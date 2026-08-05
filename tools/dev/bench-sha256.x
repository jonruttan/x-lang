; bench-sha256.x -- where a SHA-256 digest's time actually goes.
;
;   sh x.sh --no-pin -q -f tools/dev/bench-sha256.x -- [--parts] [--fold] [--fill] [--unroll N] [--size BYTES]
;
; Two reports, one harness -- they share the buffer layout, the round-body
; builder and the block driver, so splitting them into two files would
; mean copying all three.
;
;   (default)  compile the round loop, verify the FIPS vectors, and time
;              a digest end to end.
;   --parts    additionally time the digest's parts SEPARATELY over the
;              same block count: the compiled round loop, the interpreted
;              W fill, and the interpreted H shuffles.
;
; The --parts report is the one that matters, and it exists because
; guessing was wrong by two orders of magnitude.  The JIT work through
; #189-#195 sharpened the compiled round loop; --parts showed that loop
; to be 0.9% of a 25KB digest against 92.5% for the interpreted W fill.
; Optimising by intuition would have kept polishing the 0.9%.  Run this
; BEFORE optimising anything here, and believe it over the intuition.
;
; --unroll N emits N round bodies per recursive call, amortising the
; per-call argument boxing over N.  It is a knob for RE-MEASURING, not a
; recommendation: 1/2/4 measured 4.00s/3.92s/3.97s on a 25KB input --
; noise, because the boxing it removes is a fraction of that 0.9% -- and
; 8 trips the allocation ceiling while tripling compile time.  The
; unrolled shape is kept here, and only here, so the negative result
; stays reproducible instead of being re-derived from scratch.
;
; --fold moves the H shuffles INTO the compiled function (sentinel entry
; at t = -1, store on the exit branch): one native call per block instead
; of a call bracketed by two interpreted eight-iteration loops.  Measured
; at --size 25000: digest 963.8 -> 666.7ms (-31%), the shuffles' 266ms
; collapsing into a rounds number that does not move.  This knob is the
; measured case FOR folding; it stays a knob so the comparison itself
; stays reproducible.
;
; --fold moves the H shuffles (working-state load, H accumulate) into
; the compiled function via a t=-1 sentinel entry -- one native call per
; block (#198: 963.8 -> 666.7ms at 25KB).
;
; --fill compiles the W fill itself against the message's raw address,
; using the byte-width %mem-byte family; the FIPS padding is compiled
; arithmetic against len/total parked in scratch slots, so one function
; serves every block including the padded tail.  This was the last
; interpreted part that mattered: 666.7 -> ~71ms at 25KB (the fill part
; alone 590 -> 15ms).  The cost is compile time (~9s with fill -- the
; fill is ~2800 nodes), so the compiled digest pays off on REUSE, not on
; a one-shot hash.
;
; Input is synthetic and content-independent: SHA-256 does identical work
; per block whatever the bytes are, so a generated buffer keeps the
; benchmark reproducible and free of any build artifact.  The reference
; numbers above were taken at --size 25000.

(do
  (import x/tool/compile)
  (import x/codec/sha256)
  (import x/tool/contract)

  (Contract alloc-guard!)

  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pset (prim-ref (lit ptr) (lit set-word!)))
  (def %pref (prim-ref (lit ptr) (lit ref-word)))
  (def %clock (prim-ref (lit sys) (lit clock)))
  (def %M 4294967295)

  ; --- args: [--parts] [--fold] [--unroll N] [--size BYTES] ---
  (def %argv (Contract argv))
  (def %flag?
    (fn (self name av)
      (match ((null? av) #f) ((str=? (first av) name) #t) (#t (self name (rest av))))))
  (def %opt
    (fn (self name av dflt)
      (match
        ((null? av) dflt)
        ((and (str=? (first av) name) (pair? (rest av)))
          (%str->number (first (rest av)) 10))
        (#t (self name (rest av) dflt)))))
  (def %parts? (%flag? "--parts" %argv))
  (def %fold? (%flag? "--fold" %argv))
  (def %fill? (%flag? "--fill" %argv))
  (def %unroll (%opt "--unroll" %argv 1))
  (def %size (%opt "--size" %argv 25000))
  ; 64 rounds have to divide evenly into groups, or the loop steps past
  ; its own terminator and runs forever.
  (unless (= 0 (% 64 %unroll))
    (do (%stderr "bench-sha256: --unroll must divide 64 (1 2 4 8 16 32 64)\n")
        (Sys exit 1)))

  ; layout: 0..15 W | 16..23 a..h | 24 t1 25 t2 | 32..95 K | 96..103 H
  (def %KB 32)
  (def %HB 96)
  (def %buf (%make-str 1024))
  (def %ptr (%str->ptr %buf))
  (def %addr (%ptr->int %ptr))
  (def %poke (fn (_ i v) (%pset %ptr (* i 8) v)))
  (def %peek (fn (_ i) (%pref %ptr (* i 8))))

  ; --- round body, built as an expression at generation time ---
  (def %C  (fn (_ i) (list '%mem-ref 'a i)))
  (def %AT (fn (_ e) (list '%mem-ref-at 'a e)))
  (def %setC (fn (_ i v) (list '%mem-set! 'a i v)))
  (def %setAT (fn (_ e v) (list '%mem-set-at! 'a e v)))
  (def %rotr (fn (_ x n) (list '& (list '| (list '>> x n) (list '<< x (- 32 n))) %M)))
  (def %bs0 (fn (_ x) (list '^ (%rotr x 2)  (list '^ (%rotr x 13) (%rotr x 22)))))
  (def %bs1 (fn (_ x) (list '^ (%rotr x 6)  (list '^ (%rotr x 11) (%rotr x 25)))))
  (def %ss0 (fn (_ x) (list '^ (%rotr x 7)  (list '^ (%rotr x 18) (list '>> x 3)))))
  (def %ss1 (fn (_ x) (list '^ (%rotr x 17) (list '^ (%rotr x 19) (list '>> x 10)))))
  (def %ch  (fn (_ x y z) (list '^ (list '& x y) (list '& (list '& (list '~ x) %M) z))))
  (def %maj (fn (_ x y z) (list '^ (list '& x y) (list '^ (list '& x z) (list '& y z)))))
  (def %m32 (fn (_ e) (list '& e %M)))
  (def %A (%C 16)) (def %B (%C 17)) (def %Cc (%C 18)) (def %D (%C 19))
  (def %E (%C 20)) (def %F (%C 21)) (def %G (%C 22)) (def %H (%C 23))

  ; The round index as an EXPRESSION: unrolled round k reads (+ t k).
  ; k=0 stays plain `t`, so --unroll 1 emits no wasted add and is a true
  ; baseline rather than a baseline-plus-overhead.
  (def %te (fn (_ k) (if (= k 0) 't (list '+ 't k))))
  (def %w (fn (_ te off) (%AT (list '& (list '- te off) 15))))
  (def %extend-for
    (fn (_ te)
      (%setAT (list '& te 15)
        (%m32 (list '+ (list '+ (%ss1 (%w te 2)) (%w te 7))
                       (list '+ (%ss0 (%w te 15)) (%w te 16)))))))
  (def %round-for
    (fn (_ te)
      (list 'do
        (list 'if (list '< te 16) 0 (%extend-for te))
        (%setC 24 (%m32 (list '+ (list '+ %H (%bs1 %E))
                                  (list '+ (%ch %E %F %G)
                                        (list '+ (%AT (list '+ %KB te))
                                              (%AT (list '& te 15)))))))
        (%setC 25 (%m32 (list '+ (%bs0 %A) (%maj %A %B %Cc))))
        (%setC 23 %G) (%setC 22 %F) (%setC 21 %E)
        (%setC 20 (%m32 (list '+ %D (%C 24))))
        (%setC 19 %Cc) (%setC 18 %B) (%setC 17 %A)
        (%setC 16 (%m32 (list '+ (%C 24) (%C 25)))))))
  (def %bodies
    (fn (self k)
      (if (= k %unroll)
        (list (list 'self 'a (list '+ 't %unroll)))
        (pair (%round-for (%te k)) (self (+ k 1))))))
  ; The H shuffles as EXPRESSIONS.  Both move words within the same
  ; scratch buffer the round loop already addresses, at constant indices,
  ; so they need no JIT feature the rounds do not already use.
  ;   load:  a..h (slots 16..23) <- H (slots 96..103)
  ;   store: H <- (H + a..h) & 0xffffffff
  (def %seq8
    (fn (_ f) (pair 'do ((fn (self i) (if (= i 8) () (pair (f i) (self (+ i 1))))) 0))))
  (def %load-h-expr (%seq8 (fn (_ i) (%setC (+ 16 i) (%C (+ %HB i))))))
  (def %store-h-expr
    (%seq8 (fn (_ i) (%setC (+ %HB i) (%m32 (list '+ (%C (+ %HB i)) (%C (+ 16 i))))))))

  ; --unroll aside, the shape is either
  ;   (if (= t 64) 0 <rounds>)                       -- shuffles outside
  ; or, folded, a THREE-way loop entered at t = -1:
  ;   (if (< t 0)   (do <load>  (self a 0))          -- entry
  ;   (if (= t 64)  <store>                          -- exit
  ;                 <rounds>))
  ; One native call per block instead of a call plus two interpreted
  ; eight-iteration loops.  It costs one extra compare per round, which
  ; is charged against the cheapest 4% of the digest to remove ~28%.
  (def %rounds-expr
    (if %fold?
      (list 'fn '(self a t)
        (list 'if (list '< 't 0)
          (list 'do %load-h-expr (list 'self 'a 0))
          (list 'if (list '= 't 64) %store-h-expr (pair 'do (%bodies 0)))))
      (list 'fn '(self a t)
        (list 'if (list '= 't 64) 0 (pair 'do (%bodies 0))))))

  ; --- the W fill as a COMPILED function (--fill) ---
  ; The fill is the digest's dominant interpreted cost (66% after #198's
  ; fold), and what kept it interpreted was that the JIT could not read
  ; message BYTES.  With the %mem-byte family it can: the message
  ; arrives as a second raw address, and the FIPS padding -- 0x80 at
  ; len, zeros, the bit length big-endian in the last eight bytes -- is
  ; ordinary compiled arithmetic against len/total parked in scratch
  ; slots (26=block base, 27=len, 28=total), so ONE compiled function
  ; serves every block including the padded tail.  Straight-line, not a
  ; loop: sixteen words, each from four padded byte reads.
  (def %pad-byte
    (fn (_ k)
      (def i (if (= k 0) (%C 26) (list '+ (%C 26) k)))
      (def L (%C 27))
      (def T (%C 28))
      (list 'if (list '< i L)
        (list '%mem-byte-ref-at 'm i)
        (list 'if (list '= i L) 128
          (list 'if (list '< i (list '- T 8)) 0
            (list '& (list '>> (list '<< L 3)
                           (list '<< (list '- (list '- T 1) i) 3)) 255))))))
  (def %fill-word
    (fn (_ t)
      (%setC t
        (list '| (list '<< (%pad-byte (* t 4)) 24)
          (list '| (list '<< (%pad-byte (+ (* t 4) 1)) 16)
            (list '| (list '<< (%pad-byte (+ (* t 4) 2)) 8)
              (%pad-byte (+ (* t 4) 3))))))))
  (def %fill-expr
    (list 'fn '(_ a m)
      (pair 'do ((fn (self t) (if (= t 16) () (pair (%fill-word t) (self (+ t 1))))) 0))))

  (def %node-count
    (fn (self e) (if (pair? e) (+ (self (first e)) (self (rest e))) 1)))
  (display "fold ")(display (if %fold? "on " "off"))
  (display "  fill ")(display (if %fill? "on " "off"))
  (display "  unroll ")(display %unroll)
  (display "   nodes ")(display (%node-count %rounds-expr))(newline)
  (def %t-compile (%clock))
  (def %rounds (compile-asm %rounds-expr))
  (def %cfill (if %fill? (compile-asm %fill-expr) ()))
  (set! %t-compile (- (%clock) %t-compile))
  (display "compile        ")(display %t-compile)(display " us")(newline)

  ; --- x-lang side: K table, H init, block driver ---
  ((fn (self i)
     (match ((= i 64) ())
       (#t (do (%poke (+ %KB i) (%sha-oref %sha-k (+ i 1))) (self (+ i 1)))))) 0)
  (def %init-h
    (fn (_)
      ((fn (self i hs)
         (match ((null? hs) ())
           (#t (do (%poke (+ %HB i) (first hs)) (self (+ i 1) (rest hs)))))) 0 %sha-ih)))
  (def %fill-w
    (fn (_ s len total base)
      ((fn (self t)
         (match ((= t 16) ())
           (#t (do (%poke t (%sha-word s len total (%sha+ base (<< t 2))))
                   (self (%sha+ t 1)))))) 0)))
  (def %load-h
    (fn (_) ((fn (self i)
      (match ((= i 8) ()) (#t (do (%poke (+ 16 i) (%peek (+ %HB i))) (self (+ i 1)))))) 0)))
  (def %store-h
    (fn (_) ((fn (self i)
      (match ((= i 8) ())
        (#t (do (%poke (+ %HB i) (& (%sha+ (%peek (+ %HB i)) (%peek (+ 16 i))) %M))
                (self (+ i 1)))))) 0)))
  ; Folded, the compiled function does the shuffles itself and is entered
  ; at the -1 sentinel; unfolded, the interpreted loops bracket it.
  ; Filled, the W fill is the compiled %cfill against the message's raw
  ; address: one poke (the block base into slot 26) replaces sixteen
  ; interpreted %sha-word calls.  len/total sit in slots 27/28, poked
  ; once per digest, so the SAME compiled fill handles the padded tail.
  (def %fill-for
    (if %fill?
      (fn (_ s maddr len total base)
        (%poke 26 base)
        (%cfill %addr maddr))
      (fn (_ s maddr len total base)
        (%fill-w s len total base))))
  (def %block
    (if %fold?
      (fn (_ s maddr len total base)
        (%fill-for s maddr len total base)
        (%rounds %addr -1))
      (fn (_ s maddr len total base)
        (%fill-for s maddr len total base)
        (%load-h)
        (%rounds %addr 0)
        (%store-h))))
  (def %blocks-of (fn (_ len) (<< (%sha+ (>> (%sha+ len 8) 6) 1) 6)))
  (def %digest
    (fn (_ s)
      (def len (Str8 length s))
      (def total (%blocks-of len))
      (def maddr (if %fill? (%ptr->int (%str->ptr s)) 0))
      (when %fill? (do (%poke 27 len) (%poke 28 total)))
      (%init-h)
      ((fn (self b)
         (match ((= b total) ()) (#t (do (%block s maddr len total b) (self (%sha+ b 64)))))) 0)
      ((fn (self i acc)
         (match ((= i 8) acc)
           (#t (self (+ i 1)
                 (Str8 append acc
                   (Str pad-left 8 #\0 (%cvt (%peek (+ %HB i)) %string 16))))))) 0 "")))

  ; --- correctness before speed: a fast wrong digest is worth nothing ---
  (def %vec
    (fn (_ label s want)
      (def got (%digest s))
      (display label)(display (if (str=? got want) "ok" "WRONG"))(newline)
      (if (not (str=? got want))
        (Err raise 'state (Str8 append "bench-sha256: vector failed: " label) ()))))
  (%vec "vector abc     " "abc"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  (%vec "vector empty   " ""
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  (%vec "vector 56-byte " "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

  ; --- differential check against the library implementation ---
  ; The vectors above are three fixed inputs; --fold restructures the
  ; compiled loop (sentinel entry, shuffles inside), so it is worth
  ; checking the JIT path against lib/x/codec/sha256.x on an input none
  ; of them covers -- a multi-block message whose length is not a block
  ; multiple, which is where padding and the block walk interact.  Kept
  ; small because the pure-x side is the slow one.
  (def %xcheck-in (%make-str 1000))
  (def %xcheck-native (%digest %xcheck-in))
  (def %xcheck-lib (Sha256 hex %xcheck-in))
  (display "vs lib/codec   ")
  (display (if (str=? %xcheck-native %xcheck-lib) "ok" "DIVERGED"))(newline)
  (unless (str=? %xcheck-native %xcheck-lib)
    (Err raise 'state "bench-sha256: compiled digest disagrees with Sha256" ()))

  ; --- throughput ---
  (def %input (%make-str %size))
  (def %len (Str8 length %input))
  (def %total (%blocks-of %len))
  (def %nblocks (>> %total 6))
  (display "input          ")(display %size)
  (display " bytes, ")(display %nblocks)(display " blocks")(newline)
  (def %t-digest (%clock))
  (%digest %input)
  (set! %t-digest (- (%clock) %t-digest))
  (display "digest         ")(display %t-digest)(display " us")(newline)

  ; --- the attribution report ---
  ; Each part runs over the SAME block count as the digest above, so the
  ; three numbers are comparable to it and should roughly sum to it.  A
  ; sum well under the total means something outside these three is
  ; paying, and THAT is the next thing to look at.
  (when %parts?
    (do
      (%init-h)
      ; Under --fold the compiled function is entered at the sentinel, so
      ; this number INCLUDES the shuffles it absorbed -- which is why the
      ; shuffle line below reports "folded" rather than a time that the
      ; digest above no longer pays.
      (def %t-rounds (%clock))
      ((fn (self b)
         (match ((= b %nblocks) ())
           (#t (do (%rounds %addr (if %fold? -1 0)) (self (+ b 1)))))) 0)
      (set! %t-rounds (- (%clock) %t-rounds))

      ; %fill-for is whichever fill the digest above actually used --
      ; compiled under --fill, interpreted otherwise -- so this line is
      ; comparable to the digest either way.
      (def %maddr2 (if %fill? (%ptr->int (%str->ptr %input)) 0))
      (def %t-fill (%clock))
      ((fn (self b)
         (match ((= b %nblocks) ())
           (#t (do (%fill-for %input %maddr2 %len %total (<< b 6)) (self (+ b 1)))))) 0)
      (set! %t-fill (- (%clock) %t-fill))

      (def %t-shuffle 0)
      (unless %fold?
        (do
          (set! %t-shuffle (%clock))
          ((fn (self b)
             (match ((= b %nblocks) ()) (#t (do (%load-h) (%store-h) (self (+ b 1)))))) 0)
          (set! %t-shuffle (- (%clock) %t-shuffle))))

      (newline)
      (display "  compiled rounds   ")(display %t-rounds)(display " us")(newline)
      (display "  W fill            ")(display %t-fill)
      (display (if %fill? " us (compiled)" " us"))(newline)
      (display "  H shuffles        ")
      (if %fold? (display "folded into rounds") (do (display %t-shuffle)(display " us")))
      (newline)
      (display "  sum of parts      ")
      (display (+ %t-rounds (+ %t-fill %t-shuffle)))(display " us")(newline))))
