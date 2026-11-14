; unlzma-jit.x -- the compiled decoder behind Unlzma.
;
; Loaded lazily by x/codec/unlzma, as x/codec/bunzip2-jit is by Bunzip2:
; this module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x decoder in unlzma.x is the
; reference and the fallback; this engine replaces its decode loop, the
; decisions from the top of one to the end or to an input that might run
; out inside the next, and is adopted only after it agrees with the
; reference on the check streams, whole and fed in pieces.  The header, the
; range coder's first five bytes and the regions stay in x.
;
; The loop is one compiled function over a scratch of words, a state machine
; whose phase is its first argument.  Every move between phases is a
; self-call in tail position, which compiles as a jump, so a whole stream is
; one call.  One phase decodes a bit: its second argument is the
; probability's index and its third the phase to go to after, which reads
; the bit from the scratch.  Literals, lengths, the slot tree and the
; distance's low bits are loops of that phase.
;
; Each byte goes to the window and to the output at once, so the window is
; never flushed.  The loop returns to its driver here when a decision might
; not fit: less than a match's 273 bytes of room left in the output, or in
; the window while the window is still growing towards the header's
; dictionary size.  The driver grows that region and runs the loop again.
; It returns as well when fewer bytes are unread than a decision might
; read, for a stream fed a piece at a time.  An input that runs out inside
; a decision leaves an error status and feeds zero bytes until the loop is
; back at the top of one.
(module x/codec/unlzma-jit)

(import x/tool/compile compile-asm)
(import x/type/vector)
(import x/num/u32 u32-srl)

(import x/core/doors mem-copy obj-ref obj-set! ptr->int ptr-ref-word ptr-set-word! str->ptr str-make)

; scratch layout (words)
(def %IN 0)         ; the input's address, its length, how much is read
(def %INLEN 1)
(def %INCNT 2)
(def %CODE 3)       ; the range coder
(def %RANGE 4)
(def %PROBS 5)      ; the probabilities' address and count
(def %NPROBS 6)
(def %DICT 7)       ; the window's address, size, how much is allocated, the
(def %DICTSIZE 8)   ; write position, how far it has ever been written, and
(def %DICTCAP 9)    ; the bytes of every whole window behind it
(def %DICTPOS 10)
(def %DICTHIGH 11)
(def %GLOBALPOS 12)
(def %OUT 13)       ; the output's address, size and count
(def %OUTCAP 14)
(def %OUTCNT 15)
(def %LC 16)
(def %POSMASK 17)
(def %LITMASK 18)
(def %STATE 19)
(def %REP0 20)
(def %REP1 21)
(def %REP2 22)
(def %REP3 23)
(def %PREV 24)
(def %DSTSIZE 25)   ; the output size the header declares, or -1
(def %ST 26)        ; 0 running, 1 done, 2 output room, 3 window room, 4 input
                    ; wanted, <0 error
(def %POSST 27)     ; the decision's position state
(def %BIT 28)       ; the bit the bit phase decoded
(def %V 29)
(def %BOUND 30)
(def %TMP 31)
(def %B 32)         ; the byte being put
(def %W 33)         ; where a distance reads in the window
(def %BASE 34)      ; a literal's probabilities, its symbol so far, the
(def %LM 35)        ; byte one distance back and its bit
(def %MB 36)
(def %MBIT 37)
(def %LBASE 38)     ; a length: its coder, the phase after, the length
(def %LRET 39)
(def %LEN 40)
(def %TBASE 41)     ; a tree walk: its base, levels left and in all, the
(def %TLEV 42)      ; symbol so far, what to add, the phase after, the result
(def %TORIG 43)
(def %TM 44)
(def %TADD 45)
(def %TRET 46)
(def %RES 47)
(def %SLOT 48)      ; a distance: its slot, the low bits' base, place, tree
(def %DBASE 49)     ; index, the distance so far and the bits left
(def %DI 50)
(def %DM 51)
(def %DACC 52)
(def %DBITS 53)
(def %D 54)
(def %INWAIT 55)    ; the fewest unread bytes a decision starts with
(def %TOPCNT 56)    ; the output's count at the top of the decision
(def %NEXT 64)      ; 12: what the state becomes after a literal
(def %WORDS 76)

; The coder's 32-bit patterns, in hex because hex reads the bits; see
; unlzma.x.  A probability is 11 bits and moves by a 32nd of the way to its
; bound; the coder takes a byte once range is under 2^24.
(def %M32 0xFFFFFFFF)
(def %TOP 16777216)

; The most bytes one decision writes: a match of 273.
(def %MAXLEN 273)

; What an error status means, as the pure decoder says it.
(def %uj-error
  (fn (_ st)
    (match
      ((= st -1) (pair (lit short) "the stream ends inside a symbol"))
      ((= st -2) (pair (lit data) "a distance reaches past the window"))
      ((= st -3) (pair (lit data) "a distance names bytes the stream never wrote"))
      ((= st -4) (pair (lit data) "a distance is not a number of bytes"))
      (#t (pair (lit data) "an unknown engine status")))))

; --- expression builders (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))
(def %fail (fn (_ st) (list 'if (list '< (%M %ST) 0) 0 (%S %ST st))))

; The phases, by number.
(def %P-TOP 0)
(def %P-BIT 1)
(def %P-IS-MATCH 2)
(def %P-PLAIN 3)
(def %P-PLAIN-BIT 4)
(def %P-MATCHED 5)
(def %P-MATCHED-BIT 6)
(def %P-LITERAL 7)
(def %P-IS-REP 8)
(def %P-G0 9)
(def %P-REP0-LONG 10)
(def %P-G1 11)
(def %P-G2 12)
(def %P-REP-LEN 13)
(def %P-REP-LEN-DONE 14)
(def %P-COPY 15)
(def %P-LEN 16)
(def %P-LEN-CHOICE 17)
(def %P-LEN-CHOICE-2 18)
(def %P-LEN-DONE 19)
(def %P-TREE 20)
(def %P-TREE-BIT 21)
(def %P-MATCH-LEN 22)
(def %P-SLOT 23)
(def %P-DLOW 24)
(def %P-DLOW-BIT 25)
(def %P-DIRECT 26)
(def %P-DIST 27)

(def %go (fn (_ ph) (list 'self 'a ph 0 0)))
(def %bit (fn (_ idx ret) (list 'self 'a %P-BIT idx ret)))

; The word's own shift is arithmetic, and on a 4-byte word a 32-bit pattern
; reads its top bit as a sign: a logical shift masks the bits shifted in, and
; an unsigned comparison compares the halves first, as unlzma.x's %ult does.
; On an 8-byte word the patterns are the numbers and both are the plain op.
(def %srl
  (fn (_ e k)
    (if (< 4 %word-size) (list '>> e k) (list '& (list '>> e k) (u32-srl %M32 k)))))

(def %ult
  (fn (_ a b)
    (if (< 4 %word-size) (list '< a b)
      (list 'or (list '< (%srl a 1) (%srl b 1))
                (list 'and (list '= (%srl a 1) (%srl b 1)) (list '< (list '& a 1) (list '& b 1)))))))

(def %top-bit?
  (fn (_ e) (if (< 4 %word-size) (list '= (list '>> e 31) 1) (list '< e 0))))

; A byte into the coder once range has shrunk past 2^24; at the end of the
; input, the error status and a zero byte.
(def %normalize
  (list 'if (%ult (%M %RANGE) %TOP)
    (list 'do
      (list 'if (list '< (%M %INCNT) (%M %INLEN))
        (list 'do (%S %TMP (list '%mem-byte-ref-at (%M %IN) (%M %INCNT)))
                  (%S %INCNT (list '+ (%M %INCNT) 1)))
        (list 'do (%fail -1) (%S %TMP 0)))
      (%S %RANGE (list '& (list '<< (%M %RANGE) 8) %M32))
      (%S %CODE (list '& (list '| (list '<< (%M %CODE) 8) (%M %TMP)) %M32)))
    0))

; Where a distance of rep0 reads, into W, wrapping to the window's end; or
; the error status.
(def %back
  (list 'do
    (%S %W (list '- (%M %DICTPOS) (%M %REP0)))
    (list 'if (list '< (%M %W) 0)
      (list 'do
        (%S %W (list '+ (%M %W) (%M %DICTSIZE)))
        (list 'if (list '< (%M %W) 0) (%fail -2)
          (list 'if (list '< (%M %DICTHIGH) (list '+ (%M %W) 1)) (%fail -3) 0)))
      0)))

(def %at-back (list '%mem-byte-ref-at (%M %DICT) (%M %W)))

; A byte into the window and onto the output; at the window's end the write
; position goes back to its start.
(def %put
  (fn (_ b)
    (list 'do
      (%S %B b)
      (list '%mem-byte-set-at! (%M %DICT) (%M %DICTPOS) (%M %B))
      (list '%mem-byte-set-at! (%M %OUT) (%M %OUTCNT) (%M %B))
      (%S %OUTCNT (list '+ (%M %OUTCNT) 1))
      (%S %PREV (%M %B))
      (%S %TMP (list '+ (%M %DICTPOS) 1))
      (list 'if (list '< (%M %DICTHIGH) (%M %TMP)) (%S %DICTHIGH (%M %TMP)) 0)
      (list 'if (list '= (%M %TMP) (%M %DICTSIZE))
        (list 'do (%S %DICTPOS 0) (%S %GLOBALPOS (list '+ (%M %GLOBALPOS) (%M %DICTSIZE))))
        (%S %DICTPOS (%M %TMP))))))

; A tree walk of levels bits from base, its symbol less 2^levels plus add
; into RES, then phase ret.
(def %tree
  (fn (_ base levels add ret)
    (list 'do (%S %TBASE base) (%S %TLEV levels) (%S %TORIG levels) (%S %TM 1)
              (%S %TADD add) (%S %TRET ret) (%go %P-TREE))))

; A length from the coder at base, into LEN, then phase ret.
(def %length
  (fn (_ base ret) (list 'do (%S %LBASE base) (%S %LRET ret) (%go %P-LEN))))

(def %lit-state? (list '< (%M %STATE) 7))

; The phases' bodies, in number order, a builder a subject.  L reads
; unlzma.x's probability layout by name.

; 0-2: the top of a decision, the bit, and the decision's first bit read.
(def %uj-head
  (fn (_ L)
    (list
      ; top: the end, the input, room, then the decision's first bit
      (list 'if (list '< (%M %ST) 0) 0
        (list 'if (list 'and (list '< -1 (%M %DSTSIZE))
                             (list '< (list '- (%M %DSTSIZE) 1) (list '+ (%M %GLOBALPOS) (%M %DICTPOS))))
          (list 'do (%S %ST 1) 0)
          (list 'if (list '< (list '- (%M %INLEN) (%M %INCNT)) (%M %INWAIT))
            (list 'do (%S %ST 4) 0)
            (list 'if (list '< (%M %OUTCAP) (list '+ (%M %OUTCNT) %MAXLEN))
              (list 'do (%S %ST 2) 0)
              (list 'if (list 'and (list '< (%M %DICTCAP) (%M %DICTSIZE))
                                   (list '< (%M %DICTCAP) (list '+ (%M %DICTPOS) %MAXLEN)))
                (list 'do (%S %ST 3) 0)
                (list 'do
                  (%S %TOPCNT (%M %OUTCNT))
                  (%S %POSST (list '& (list '+ (%M %DICTPOS) (%M %GLOBALPOS)) (%M %POSMASK)))
                  (%bit (list '+ (L (lit is-match)) (list '+ (list '<< (%M %STATE) 4) (%M %POSST)))
                        %P-IS-MATCH)))))))
      ; bit: one bit against the probability at index i, which it moves
      (list 'do
        %normalize
        (%S %V (list '%mem-ref-at (%M %PROBS) 'i))
        (%S %BOUND (list '* (%M %V) (%srl (%M %RANGE) 11)))
        (list 'if (%ult (%M %CODE) (%M %BOUND))
          (list 'do (%S %RANGE (%M %BOUND))
                    (list '%mem-set-at! (%M %PROBS) 'i (list '+ (%M %V) (list '>> (list '- 2048 (%M %V)) 5)))
                    (%S %BIT 0))
          (list 'do (%S %RANGE (list '- (%M %RANGE) (%M %BOUND)))
                    (%S %CODE (list '- (%M %CODE) (%M %BOUND)))
                    (list '%mem-set-at! (%M %PROBS) 'i (list '- (%M %V) (list '>> (%M %V) 5)))
                    (%S %BIT 1)))
        (list 'self 'a 'r 0 0))
      ; is-match: a literal, or a match
      (list 'if (list '= (%M %BIT) 0)
        (list 'do
          (%S %BASE (list '+ (L (lit literal))
                      (list '* 768 (list '+ (list '<< (list '& (list '+ (%M %DICTPOS) (%M %GLOBALPOS)) (%M %LITMASK))
                                                      (%M %LC))
                                            (list '>> (%M %PREV) (list '- 8 (%M %LC)))))))
          (%S %LM 1)
          (list 'if %lit-state? (%go %P-PLAIN)
            (list 'do %back
              (list 'if (list '< (%M %ST) 0) (%go %P-TOP)
                (list 'do (%S %MB %at-back) (%go %P-MATCHED))))))
        (%bit (list '+ (L (lit is-rep)) (%M %STATE)) %P-IS-REP)))))

; 3-7: a literal.
(def %uj-literal
  (fn (_)
    (list
      ; plain: the literal's bits, under the bits so far
      (list 'if (list '< (%M %LM) 256) (%bit (list '+ (%M %BASE) (%M %LM)) %P-PLAIN-BIT) (%go %P-LITERAL))
      (list 'do (%S %LM (list '+ (list '* (%M %LM) 2) (%M %BIT))) (%go %P-PLAIN))
      ; matched: the bits of the byte one distance back as well, until they differ
      (list 'if (list '< (%M %LM) 256)
        (list 'do
          (%S %MB (list '& (list '<< (%M %MB) 1) 511))
          (%S %MBIT (list '& (%M %MB) 256))
          (%bit (list '+ (%M %BASE) (list '+ 256 (list '+ (%M %MBIT) (%M %LM)))) %P-MATCHED-BIT))
        (%go %P-LITERAL))
      (list 'do
        (%S %LM (list '+ (list '* (%M %LM) 2) (%M %BIT)))
        (list 'if (list '= (%M %MBIT) (list '<< (%M %BIT) 8)) (%go %P-MATCHED) (%go %P-PLAIN)))
      ; literal: the state moves on and the byte is put
      (list 'do
        (%S %STATE (%MA (list '+ %NEXT (%M %STATE))))
        (%put (list '& (%M %LM) 255))
        (%go %P-TOP)))))

; 8-15: a fresh distance or a repeated one, the repeated ones, and the copy.
(def %uj-matches
  (fn (_ L)
    (list
      ; is-rep: a fresh distance, or one of the last four
      (list 'if (list '= (%M %BIT) 0)
        (list 'do
          (%S %REP3 (%M %REP2))
          (%S %REP2 (%M %REP1))
          (%S %REP1 (%M %REP0))
          (%S %STATE (list 'if %lit-state? 0 3))
          (%length (L (lit len-coder)) %P-MATCH-LEN))
        (%bit (list '+ (L (lit is-rep-g0)) (%M %STATE)) %P-G0))
      ; g0: rep0, or a further one
      (list 'if (list '= (%M %BIT) 0)
        (%bit (list '+ (L (lit is-rep-0-long)) (list '+ (list '<< (%M %STATE) 4) (%M %POSST))) %P-REP0-LONG)
        (%bit (list '+ (L (lit is-rep-g1)) (%M %STATE)) %P-G1))
      ; rep0-long: a single byte, or a length
      (list 'if (list '= (%M %BIT) 0)
        (list 'do
          (%S %STATE (list 'if %lit-state? 9 11))
          %back
          (list 'if (list '< (%M %ST) 0) (%go %P-TOP)
            (list 'do (%put %at-back) (%go %P-TOP))))
        (%go %P-REP-LEN))
      ; g1: rep1, or a further one
      (list 'if (list '= (%M %BIT) 0)
        (list 'do (%S %D (%M %REP1)) (%S %REP1 (%M %REP0)) (%S %REP0 (%M %D)) (%go %P-REP-LEN))
        (%bit (list '+ (L (lit is-rep-g2)) (%M %STATE)) %P-G2))
      ; g2: rep2 or rep3, moved to the front
      (list 'do
        (list 'if (list '= (%M %BIT) 0)
          (list 'do (%S %D (%M %REP2)) (%S %REP2 (%M %REP1)))
          (list 'do (%S %D (%M %REP3)) (%S %REP3 (%M %REP2)) (%S %REP2 (%M %REP1))))
        (%S %REP1 (%M %REP0))
        (%S %REP0 (%M %D))
        (%go %P-REP-LEN))
      ; rep-len: a repeated distance's length
      (list 'do
        (%S %STATE (list 'if %lit-state? 8 11))
        (%length (L (lit rep-len-coder)) %P-REP-LEN-DONE))
      (list 'do (%S %LEN (list '+ (%M %LEN) 2)) (%go %P-COPY))
      ; copy: LEN bytes from rep0 back
      (list 'if (list '< (%M %LEN) 1) (%go %P-TOP)
        (list 'do %back
          (list 'if (list '< (%M %ST) 0) (%go %P-TOP)
            (list 'do (%put %at-back) (%S %LEN (list '- (%M %LEN) 1)) (%go %P-COPY))))))))

; 16-21: a length, and the tree walk lengths and slots share.
(def %uj-lengths
  (fn (_ L)
    (list
      ; len: its tier
      (%bit (list '+ (%M %LBASE) (L (lit len-choice))) %P-LEN-CHOICE)
      (list 'if (list '= (%M %BIT) 0)
        (%tree (list '+ (%M %LBASE) (list '+ (L (lit len-low)) (list '<< (%M %POSST) 3))) 3 0 %P-LEN-DONE)
        (%bit (list '+ (%M %LBASE) (L (lit len-choice-2))) %P-LEN-CHOICE-2))
      (list 'if (list '= (%M %BIT) 0)
        (%tree (list '+ (%M %LBASE) (list '+ (L (lit len-mid)) (list '<< (%M %POSST) 3))) 3 8 %P-LEN-DONE)
        (%tree (list '+ (%M %LBASE) (L (lit len-high))) 8 16 %P-LEN-DONE))
      (list 'do (%S %LEN (%M %RES)) (list 'self 'a (%M %LRET) 0 0))
      ; tree: a bit a level
      (list 'if (list '< (%M %TLEV) 1)
        (list 'do
          (%S %RES (list '+ (list '- (%M %TM) (list '<< 1 (%M %TORIG))) (%M %TADD)))
          (list 'self 'a (%M %TRET) 0 0))
        (%bit (list '+ (%M %TBASE) (%M %TM)) %P-TREE-BIT))
      (list 'do
        (%S %TM (list '+ (list '* (%M %TM) 2) (%M %BIT)))
        (%S %TLEV (list '- (%M %TLEV) 1))
        (%go %P-TREE)))))

; 22-25: a fresh distance's slot and its low bits.
(def %uj-distances
  (fn (_ L)
    (list
      ; match-len: the length known, the distance's slot
      (%tree (list '+ (L (lit pos-slot)) (list '<< (list 'if (list '< (%M %LEN) 4) (%M %LEN) 3) 6)) 6 0 %P-SLOT)
      ; slot: the distance outright, from a tree of its own, or coded bits
      ; and the align tree
      (list 'do
        (%S %SLOT (%M %RES))
        (list 'if (list '< (%M %SLOT) 4)
          (list 'do (%S %DACC (%M %SLOT)) (%go %P-DIST))
          (list 'do
            (%S %DBITS (list '- (list '>> (%M %SLOT) 1) 1))
            (%S %DACC (list '| 2 (list '& (%M %SLOT) 1)))
            (list 'if (list '< (%M %SLOT) 14)
              (list 'do
                (%S %DACC (list '<< (%M %DACC) (%M %DBITS)))
                (%S %DBASE (list '- (list '+ (L (lit spec-pos)) (%M %DACC)) (list '+ (%M %SLOT) 1)))
                (%S %DI 1) (%S %DM 1)
                (%go %P-DLOW))
              (list 'do (%S %DBITS (list '- (%M %DBITS) 4)) (%go %P-DIRECT))))))
      ; dlow: the low bits, a bit a step
      (list 'if (list '< (%M %DBITS) 1) (%go %P-DIST)
        (%bit (list '+ (%M %DBASE) (%M %DM)) %P-DLOW-BIT))
      (list 'do
        (%S %DM (list '+ (list '* (%M %DM) 2) (%M %BIT)))
        (list 'if (list '= (%M %BIT) 1) (%S %DACC (list '| (%M %DACC) (%M %DI))) 0)
        (%S %DI (list '<< (%M %DI) 1))
        (%S %DBITS (list '- (%M %DBITS) 1))
        (%go %P-DLOW)))))

; 26-27: a distance's coded bits and its end.
(def %uj-distance-end
  (fn (_ L)
    (list
      ; direct: the middle bits, the range halved for each, then the align tree
      (list 'if (list '< (%M %DBITS) 1)
        (list 'do
          (%S %DACC (list '& (list '<< (%M %DACC) 4) %M32))
          (%S %DBASE (L (lit align)))
          (%S %DI 1) (%S %DM 1) (%S %DBITS 4)
          (%go %P-DLOW))
        (list 'do
          %normalize
          (%S %RANGE (%srl (%M %RANGE) 1))
          (list 'if (%ult (%M %CODE) (%M %RANGE)) (%S %TMP 0)
            (list 'do (%S %CODE (list '- (%M %CODE) (%M %RANGE))) (%S %TMP 1)))
          (%S %DACC (list '& (list '| (list '<< (%M %DACC) 1) (%M %TMP)) %M32))
          (%S %DBITS (list '- (%M %DBITS) 1))
          (%go %P-DIRECT)))
      ; dist: the end marker, a refusal, or the copy
      (list 'do
        (%S %STATE (list '+ (%M %STATE) 7))
        (%S %REP0 (list '& (list '+ (%M %DACC) 1) %M32))
        (list 'if (list '= (%M %REP0) 0)
          (list 'if (list '< (%M %ST) 0) 0 (list 'do (%S %ST 1) 0))
          (list 'if (%top-bit? (%M %REP0)) (list 'do (%fail -4) (%go %P-TOP))
            (list 'do (%S %LEN (list '+ (%M %LEN) 2)) (%go %P-COPY))))))))

(def %uj-phases
  (fn (_ L)
    (List append (%uj-head L)
      (List append (%uj-literal)
        (List append (%uj-matches L)
          (List append (%uj-lengths L)
            (List append (%uj-distances L) (%uj-distance-end L))))))))

; The phases chosen by halving their numbers, so a move costs a few tests.
(def %uj-dispatch
  (fn (self bodies lo hi)
    (if (= lo hi) (List ref lo bodies)
      ((fn (_ mid)
         (list 'if (list '< 'ph (+ mid 1)) (self bodies lo mid) (self bodies (+ mid 1) hi)))
       (>> (+ lo hi) 1)))))

(def %uj-expr
  (fn (_ L)
    (def bodies (%uj-phases L))
    (list 'fn '(self a ph i r) (%uj-dispatch bodies 0 (- (List length bodies) 1)))))

; --- build: compile, wire the driver, and PROVE it against the reference ---
;
; state:  unlzma.x's slot numbers for its decoder, as an alist: the
;         input, the coder, the probabilities, the window, the output, the
;         header's numbers, the state machine's, the flush mark, the input
;         a decision waits for, and done.  The decoder holds its regions and
;         every number; the run reads them in and writes them back.
; layout: its probability layout, as an alist of offsets by name.
; next:   its vector of what the state becomes after a literal.
; check:  (fn (_ run) -> #t) -- runs the reference's check streams through a
;         candidate and answers whether every output agreed with its own.
;
; Answers a drop-in for unlzma.x's run, (fn (_ d)), which carries d's
; decisions on as unlzma.x's %pure-run does.  Or
; raises: on a host with no assembler backend, a toolchain error, or any
; disagreement.  The caller guards; a raise means "stay pure-x".
(def unlzma-jit-make
  (fn (_ state layout next check)
    (def %step (compile-asm (%uj-expr (fn (_ name) (rest (Assoc entry name layout))))))
    (Heap collect)
    (def %buf (str-make (* %word-size %WORDS)))
    (def %ptr (str->ptr %buf))
    (def %addr (ptr->int %ptr))
    (def %poke (fn (_ i v) (ptr-set-word! %ptr (* i %word-size) v)))
    (def %peek (fn (_ i) (ptr-ref-word %ptr (* i %word-size))))
    (def %slot (fn (_ name) (rest (Assoc entry name state))))
    ((fn (self i) (when (< i 12) (do (%poke (+ %NEXT i) (Vector ref i next)) (self (+ i 1))))) 0)
    ; The scratch's words that are the decoder's numbers, each by its slot:
    ; read in before a run and written back after, so the decoder carries a
    ; stream from one run to the next and the scratch holds nothing between.
    (def %words
      (List map (fn (_ p) (pair (first p) (%slot (rest p))))
        (list (pair %INLEN (lit inlen)) (pair %INCNT (lit incnt)) (pair %CODE (lit code))
              (pair %RANGE (lit range)) (pair %NPROBS (lit nprobs)) (pair %DICTSIZE (lit dictsize))
              (pair %DICTCAP (lit dictcap)) (pair %DICTPOS (lit dictpos)) (pair %DICTHIGH (lit dicthigh))
              (pair %GLOBALPOS (lit globalpos)) (pair %OUTCAP (lit outcap)) (pair %OUTCNT (lit outcnt))
              (pair %LC (lit lc)) (pair %POSMASK (lit posmask)) (pair %LITMASK (lit litmask))
              (pair %STATE (lit state)) (pair %REP0 (lit rep0)) (pair %REP1 (lit rep1))
              (pair %REP2 (lit rep2)) (pair %REP3 (lit rep3)) (pair %PREV (lit prev))
              (pair %DSTSIZE (lit dstsize)) (pair %INWAIT (lit inwait)))))
    (def %s-in (%slot (lit in)))
    (def %s-probs (%slot (lit probs)))
    (def %s-dictr (%slot (lit dictr)))
    (def %s-dict (%slot (lit dict)))
    (def %s-out (%slot (lit out)))
    (def %s-outp (%slot (lit outp)))
    (def %s-flush (%slot (lit dictflush)))
    (def %s-outcnt (%slot (lit outcnt)))
    (def %s-done (%slot (lit done)))
    ; a region of cap bytes holding the first n of old
    (def %regrow
      (fn (_ old n cap)
        (def r (str-make cap))
        (when (< 0 n) (mem-copy (str->ptr r) (str->ptr old) n))
        r))
    (def %double (fn (self c n) (if (< c n) (self (* c 2) n) c)))
    ; The scratch's numbers back into d; the window is all on the output.
    (def %save!
      (fn (_ d)
        (List for-each (fn (_ p) (obj-set! d (rest p) (%peek (first p)))) %words)
        (obj-set! d %s-flush (%peek %DICTPOS))))
    ; The loop run from the top of a decision until it is done or wants
    ; input, its regions grown when it returns for room.  Each byte went to
    ; the output as it went to the window, so the window is all flushed.
    (def %drive
      (fn (self d)
        (%poke %ST 0)
        (%step %addr %P-TOP 0 0)
        (def st (%peek %ST))
        (match
          ((or (= st 1) (= st 4))
            (do (%save! d)
                (when (= st 1) (obj-set! d %s-done #t))))
          ((= st 2)
            (do (def cap (%double (* 2 (%peek %OUTCAP)) (+ (%peek %OUTCNT) %MAXLEN)))
                (def o (%regrow (obj-ref d %s-out) (%peek %OUTCNT) cap))
                (obj-set! d %s-out o)
                (obj-set! d %s-outp (str->ptr o))
                (%poke %OUT (ptr->int (str->ptr o)))
                (%poke %OUTCAP cap)
                (self d)))
          ((= st 3)
            (do (def want (%double (* 2 (%peek %DICTCAP)) (+ (%peek %DICTPOS) %MAXLEN)))
                (def cap (if (< (%peek %DICTSIZE) want) (%peek %DICTSIZE) want))
                (def w (%regrow (obj-ref d %s-dictr) (%peek %DICTHIGH) cap))
                (obj-set! d %s-dictr w)
                (obj-set! d %s-dict (str->ptr w))
                (%poke %DICT (ptr->int (str->ptr w)))
                (%poke %DICTCAP cap)
                (self d)))
          ; the output only up to the top of the decision that failed, the
          ; bytes it put on the way past the error not counted
          (#t (do (%save! d)
                  (obj-set! d %s-outcnt (%peek %TOPCNT))
                  (def e (%uj-error st))
                  (Err raise (lit value) (Str8 append "Unlzma: " (rest e)) (list (pair (lit lzma) (first e)))))))))
    (def %run
      (fn (_ d)
        (List for-each (fn (_ p) (%poke (first p) (obj-ref d (rest p)))) %words)
        (%poke %IN (ptr->int (obj-ref d %s-in)))
        (%poke %PROBS (ptr->int (obj-ref d %s-probs)))
        (%poke %DICT (ptr->int (obj-ref d %s-dict)))
        (%poke %OUT (ptr->int (obj-ref d %s-outp)))
        (%drive d)))
    (unless (check %run)
      (Err raise (lit state) "unlzma-jit: engine disagrees with the pure-x decoder" ()))
    ; the scratch is held by the driver's closure
    (fn (_ d) (do %buf (%run d)))))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit unlzma) (lit jit-make) unlzma-jit-make)

(doc (provide x/codec/unlzma-jit unlzma-jit-make)
  (example "(do (import x/codec/unlzma-jit) (procedure? (prim-ref (lit unlzma) (lit jit-make))))" "#t")
  "The compiled decoder behind Unlzma (JIT, ARM64, x86-64 and 32-bit ARM backends): the whole decode loop, one compiled state machine, built and adopted only after agreeing with the pure-x decoder.")
