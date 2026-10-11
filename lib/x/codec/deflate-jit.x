; deflate-jit.x -- the compiled matcher and token writer behind Deflate.
;
; Loaded lazily by x/codec/deflate, as x/codec/inflate-jit is by Inflate:
; this module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x encoder in deflate.x is the
; reference and the fallback; this engine replaces its two hot parts --
; finding the matches, and writing a block's tokens under its codes -- and
; is adopted only after the streams it writes for the codec's check inputs
; are byte for byte the reference's.  The codes, the headers and stored
; blocks stay in x.
;
; The matcher is one compiled loop over the whole input: every loop in it
; is a self-call in tail position, which the compiler makes a jump.  The
; writer is one compiled step over a scratch holding the writer's bit
; state and the block's tables.  A step writes one token -- a literal, or a
; length and a distance with their extra bits -- whole bytes out as they
; fill, then calls itself; it returns after %dj-budget tokens, and the
; driver here grows the output and runs it again.  A token is at most 48
; bits, so a run writes at most %dj-budget * 6 bytes, which the driver makes
; room for before each run: the step never checks its room.
(module x/codec/deflate-jit)

(import x/tool/compile compile-asm)

(def %dj-make-str (prim-ref (lit str) (lit make)))
(def %dj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %dj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %dj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %dj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %dj-oref (prim-ref (lit obj) (lit ref)))
(def %dj-oset! (prim-ref (lit obj) (lit set!)))

; scratch layout (words): the writer's state, then the tables.
(def %OUT 0)       ; output address
(def %CNT 1)       ; bytes written
(def %BB 2)        ; bits not yet a byte
(def %BC 3)        ; and how many
(def %LENS 4)      ; token tables' addresses: a match's length or 0,
(def %VALS 5)      ; its distance or the literal
(def %T 6)         ; the next token
(def %T1 7)        ; the block's end
(def %STEPS 8)
(def %BUDGET 9)
(def %LEN 10)
(def %VAL 11)
(def %LCD 12)      ; a length's code, 0..28
(def %DCD 13)      ; a distance's code, 0..29
(def %TMP 14)
(def %LC 16)       ; literal/length codes, reversed for writing, 286
(def %LL 302)      ; and their lengths
(def %DC 588)      ; distance codes, 30
(def %DL 618)      ; and their lengths
(def %LCODE 648)   ; a match length's code, by length 0..258
(def %LB 907)      ; length bases and extra bits, by code 0..28
(def %LE 936)
(def %DCODE 965)   ; a distance's code: by d-1 to 255, by 256+((d-1)>>7) past
(def %DB 1477)     ; distance bases and extra bits, by code 0..29
(def %DE 1507)
(def %WORDS 1537)

; --- expression builders (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))

; A whole byte of the bit buffer out, if it holds eight bits.
(def %dj-flush
  (list 'if (list '>= (%M %BC) 8)
    (list 'do
      (list '%mem-byte-set-at! (%M %OUT) (%M %CNT) (list '& (%M %BB) 255))
      (%S %CNT (list '+ (%M %CNT) 1))
      (%S %BB (list '>> (%M %BB) 8))
      (%S %BC (list '- (%M %BC) 8)))
    0))

; The low n bits of value written, least significant first (3.1.1).  The
; buffer holds under eight bits before, and n is at most fifteen, so two
; flushes leave it under eight again.
(def %dj-put
  (fn (_ value n)
    (list 'do
      (%S %TMP n)
      (%S %BB (list '| (%M %BB) (list '<< value (%M %BC))))
      (%S %BC (list '+ (%M %BC) (%M %TMP)))
      %dj-flush
      %dj-flush)))

; A token: a literal's code, or a length's code and extra bits, then its
; distance's code and extra bits.
(def %dj-token
  (list 'do
    (%S %LEN (list '%mem-ref-at (%M %LENS) (%M %T)))
    (%S %VAL (list '%mem-ref-at (%M %VALS) (%M %T)))
    (list 'if (list '= (%M %LEN) 0)
      (%dj-put (%MA (list '+ %LC (%M %VAL))) (%MA (list '+ %LL (%M %VAL))))
      (list 'do
        (%S %LCD (%MA (list '+ %LCODE (%M %LEN))))
        (%dj-put (%MA (list '+ %LC (list '+ 257 (%M %LCD)))) (%MA (list '+ %LL (list '+ 257 (%M %LCD)))))
        (%dj-put (list '- (%M %LEN) (%MA (list '+ %LB (%M %LCD)))) (%MA (list '+ %LE (%M %LCD))))
        (%S %DCD
          (list 'if (list '<= (%M %VAL) 256)
            (%MA (list '+ %DCODE (list '- (%M %VAL) 1)))
            (%MA (list '+ %DCODE (list '+ 256 (list '>> (list '- (%M %VAL) 1) 7))))))
        (%dj-put (%MA (list '+ %DC (%M %DCD))) (%MA (list '+ %DL (%M %DCD))))
        (%dj-put (list '- (%M %VAL) (%MA (list '+ %DB (%M %DCD)))) (%MA (list '+ %DE (%M %DCD))))))))

(def %dj-step-expr
  (list 'fn '(self a)
    (list 'if (list '>= (%M %T) (%M %T1)) 0
      (list 'do
        %dj-token
        (%S %T (list '+ (%M %T) 1))
        (list 'if (list '>= (%M %STEPS) (%M %BUDGET)) 0
          (list 'do (%S %STEPS (list '+ (%M %STEPS) 1)) (list 'self 'a)))))))

; Tokens a call may write before it returns: each one is a frame.
(def %dj-budget 256)

; --- The matcher: one compiled loop over the input ---
;
; deflate.x's %tokenize! step for step -- the three-byte hash, the chain
; walked up to 32 candidates, a candidate tried only when its byte at the
; best length so far agrees, the longest match taken, the positions inside
; a match of up to 16 bytes entered -- so the tokens are the same ones.
; Every loop is a self-call in tail position, which compiles as a jump: the
; whole input is one call.  PH says where the loop is:
;
;   0  at position I: a literal near the end, or hash, enter and walk
;   1  the walk at candidate C
;   2  comparing candidate C with position I, K bytes agreed
;   3  the walk done: the token
;   4  entering the positions inside a match, I up to the match's end
;
; Its scratch (words): the input's address and length, the hash and chain
; tables' addresses (words holding a position plus one, 0 for none), the
; token tables' addresses and the token count, then the walk's best length
; and distance, the candidates left, the longest match possible here, the
; match's end, and two temporaries.  Answers the token count.
(def %MP 0) (def %MN 1) (def %MHEAD 2) (def %MPREV 3) (def %MLENS 4) (def %MVALS 5)
(def %MT 6) (def %MBLEN 7) (def %MBDIST 8) (def %MSTEPS 9) (def %MLIMIT 10)
(def %ME 11) (def %MH 12) (def %MOLD 13) (def %MWORDS 14)

(def %dm-byte (fn (_ at) (list '%mem-byte-ref-at (%M %MP) at)))

; The hash of the three bytes at position e, as deflate.x's %hash.
(def %dm-hash
  (fn (_ e)
    (list '& (list '+ (list '* (%dm-byte e) 1089)
                      (list '+ (list '* (%dm-byte (list '+ e 1)) 33) (%dm-byte (list '+ e 2))))
          32767)))

; Position e entered: its chain link is what the hash headed.
(def %dm-insert
  (fn (_ e)
    (list 'do
      (%S %MH (%dm-hash e))
      (list '%mem-set-at! (%M %MPREV) (list '& e 32767) (list '%mem-ref-at (%M %MHEAD) (%M %MH)))
      (list '%mem-set-at! (%M %MHEAD) (%M %MH) (list '+ e 1)))))

; A token: length len (0 for a literal) and val.
(def %dm-token
  (fn (_ len val)
    (list 'do
      (list '%mem-set-at! (%M %MLENS) (%M %MT) len)
      (list '%mem-set-at! (%M %MVALS) (%M %MT) val)
      (%S %MT (list '+ (%M %MT) 1)))))

; The next candidate on C's chain, and one fewer left.
(def %dm-next
  (list 'do
    (%S %MSTEPS (list '- (%M %MSTEPS) 1))
    (list 'self 'a 1 'i (list '- (list '%mem-ref-at (%M %MPREV) (list '& 'c 32767)) 1) 0)))

(def %dm-expr
  (list 'fn '(self a ph i c k)
    (list 'if (list '= 'ph 0)
      (list 'if (list '>= 'i (%M %MN)) (%M %MT)
        (list 'if (list '< (list '- (%M %MN) 'i) 3)
          (list 'do (%dm-token 0 (%dm-byte 'i)) (list 'self 'a 0 (list '+ 'i 1) 0 0))
          (list 'do
            (%S %MH (%dm-hash 'i))
            (%S %MOLD (list '%mem-ref-at (%M %MHEAD) (%M %MH)))
            (list '%mem-set-at! (%M %MPREV) (list '& 'i 32767) (%M %MOLD))
            (list '%mem-set-at! (%M %MHEAD) (%M %MH) (list '+ 'i 1))
            (%S %MBLEN 2)
            (%S %MBDIST 0)
            (%S %MSTEPS 32)
            (%S %MLIMIT (list 'if (list '< (list '- (%M %MN) 'i) 258) (list '- (%M %MN) 'i) 258))
            (list 'self 'a 1 'i (list '- (%M %MOLD) 1) 0))))
    (list 'if (list '= 'ph 1)
      (list 'if (list 'or (list '< 'c 0) (list '> (list '- 'i 'c) 32768) (list '= (%M %MSTEPS) 0)
                          (list '> (%M %MBLEN) 128) (list '>= (%M %MBLEN) (%M %MLIMIT)))
        (list 'self 'a 3 'i 0 0)
        (list 'if (list '= (%dm-byte (list '+ 'c (%M %MBLEN))) (%dm-byte (list '+ 'i (%M %MBLEN))))
          (list 'self 'a 2 'i 'c 0)
          %dm-next))
    (list 'if (list '= 'ph 2)
      (list 'if (list 'if (list '< 'k (%M %MLIMIT)) (list '= (%dm-byte (list '+ 'c 'k)) (%dm-byte (list '+ 'i 'k))) 0)
        (list 'self 'a 2 'i 'c (list '+ 'k 1))
        (list 'do
          (list 'if (list '> 'k (%M %MBLEN))
            (list 'do (%S %MBLEN 'k) (%S %MBDIST (list '- 'i 'c)))
            0)
          %dm-next))
    (list 'if (list '= 'ph 3)
      (list 'if (list '< (%M %MBLEN) 3)
        (list 'do (%dm-token 0 (%dm-byte 'i)) (list 'self 'a 0 (list '+ 'i 1) 0 0))
        (list 'do
          (%dm-token (%M %MBLEN) (%M %MBDIST))
          (%S %ME (list '+ 'i (%M %MBLEN)))
          (list 'if (list '> (%M %MBLEN) 16)
            (list 'self 'a 0 (%M %ME) 0 0)
            (list 'self 'a 4 (list '+ 'i 1) 0 0))))
      (list 'if (list '< 'i (%M %ME))
        (list 'do
          (list 'if (list '>= (list '- (%M %MN) 'i) 3) (%dm-insert 'i) 0)
          (list 'self 'a 4 (list '+ 'i 1) 0 0))
        (list 'self 'a 0 (%M %ME) 0 0))))))))

(def %dj-mem-set (prim-ref (lit mem) (lit set)))

; --- The counter: a block's frequencies, one compiled loop ---
;
; deflate.x's %count!: each token's literal/length symbol and distance code
; tallied, the bytes it covers added to b.  Its scratch (words): the token
; tables' addresses and the block's end, two temporaries, then the length
; and distance code tables (as the writer's) and the two tallies.
(def %CLENS 0) (def %CVALS 1) (def %CT1 2) (def %CLEN 3) (def %CVAL 4)
(def %CLCODE 8) (def %CDCODE 267) (def %CLF 779) (def %CDF 1065) (def %CWORDS 1095)

(def %dc-bump (fn (_ at) (list '%mem-set-at! 'a at (list '+ (%MA at) 1))))

; --- Adler-32 (RFC 1950 8): one compiled loop, the two sums its arguments,
; each reduced a byte at a time.  Its scratch (words): the bytes' address
; and their count.
(def %AP 0) (def %AN 1)
(def %da-x1 (list '% (list '+ 'x (list '%mem-byte-ref-at (%M %AP) 'i)) 65521))
(def %da-expr
  (list 'fn '(self a i x y)
    (list 'if (list '>= 'i (%M %AN)) (list '| (list '<< 'y 16) 'x)
      (list 'self 'a (list '+ 'i 1) %da-x1 (list '% (list '+ 'y %da-x1) 65521)))))

(def %dc-expr
  (list 'fn '(self a t b)
    (list 'if (list '>= 't (%M %CT1)) 'b
      (list 'do
        (%S %CLEN (list '%mem-ref-at (%M %CLENS) 't))
        (%S %CVAL (list '%mem-ref-at (%M %CVALS) 't))
        (list 'if (list '= (%M %CLEN) 0)
          (list 'do
            (%dc-bump (list '+ %CLF (%M %CVAL)))
            (list 'self 'a (list '+ 't 1) (list '+ 'b 1)))
          (list 'do
            (%dc-bump (list '+ %CLF (list '+ 257 (%MA (list '+ %CLCODE (%M %CLEN))))))
            (%dc-bump (list '+ %CDF
                        (list 'if (list '<= (%M %CVAL) 256)
                          (%MA (list '+ %CDCODE (list '- (%M %CVAL) 1)))
                          (%MA (list '+ %CDCODE (list '+ 256 (list '>> (list '- (%M %CVAL) 1) 7)))))))
            (list 'self 'a (list '+ 't 1) (list '+ 'b (%M %CLEN)))))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; state:    deflate.x's slot numbers for its writer, as an alist
;           (outp outcap outcnt bitbuf bitcnt).
; tables:   deflate.x's vectors (length-code lbase lext distance-code dbase
;           dext), slot k holding entry k-1.
; room:     deflate.x's (fn (_ w n)), room for n more output bytes.
; put-code: deflate.x's (fn (_ w codes lengths sym)), for the end code.
; check:    (fn (_ eng) -> #t) -- whether an engine (MATCH PUT COUNT ADLER)
;           writes and sums what the reference does on the check inputs.
;
; Answers (MATCH PUT COUNT ADLER), drop-ins for deflate.x's four:
; (fn (_ src n lens vals)) for %match-x, (fn (_ w lens vals t t1 lcodes llen
; dcodes dlen)) for %put-tokens!, (fn (_ lens vals t t1 lfreq dfreq b)) for
; %count!, and (fn (_ p n)) for %adler-x.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def deflate-jit-make
  (fn (_ state tables room put-code check)
    (def %step (compile-asm %dj-step-expr))
    (def %matcher (compile-asm %dm-expr))
    (def %mbuf (%dj-make-str (* %MWORDS 8)))
    (def %mptr (%dj-str->ptr %mbuf))
    (def %maddr (%dj-ptr->int %mptr))
    (def %mpoke (fn (_ i v) (%dj-pset %mptr (* i 8) v)))
    ; A zeroed table of n words, held by the caller for as long as its
    ; address is in use.
    (def %words
      (fn (_ n)
        (def r (%dj-make-str (* n 8)))
        (%dj-mem-set (%dj-str->ptr r) 0 (* n 8))
        r))
    (def %match
      (fn (_ src n lens vals)
        (def head (%words 32768))
        (def prev (%words 32768))
        (%mpoke %MP (%dj-ptr->int src))
        (%mpoke %MN n)
        (%mpoke %MHEAD (%dj-ptr->int (%dj-str->ptr head)))
        (%mpoke %MPREV (%dj-ptr->int (%dj-str->ptr prev)))
        (%mpoke %MLENS (%dj-ptr->int lens))
        (%mpoke %MVALS (%dj-ptr->int vals))
        (%mpoke %MT 0)
        (%matcher %maddr 0 0 0 0)))
    (def %buf (%dj-make-str (* %WORDS 8)))
    (def %ptr (%dj-str->ptr %buf))
    (def %addr (%dj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%dj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%dj-pref %ptr (* i 8))))
    (def %slot (fn (_ name) (rest (Assoc entry name state))))
    ; Slots 1..n of vector v into words base..base+n-1.
    (def %load!
      (fn (_ v base n)
        ((fn (self k) (if (> k n) () (do (%poke (+ base (- k 1)) (%dj-oref v k)) (self (+ k 1))))) 1)))
    ((fn (self ts bases)
       (if (null? ts) ()
         (do (%load! (first ts) (first bases) (%dj-oref (first ts) 0))
             (self (rest ts) (rest bases)))))
     tables (list %LCODE %LB %LE %DCODE %DB %DE))
    (def %put
      (fn (_ w lens vals t t1 lcodes llen dcodes dlen)
        (%load! lcodes %LC 286)
        (%load! llen %LL 286)
        (%load! dcodes %DC 30)
        (%load! dlen %DL 30)
        (%poke %LENS (%dj-ptr->int lens))
        (%poke %VALS (%dj-ptr->int vals))
        (%poke %T t)
        (%poke %T1 t1)
        (%poke %BB (%dj-oref w (%slot (lit bitbuf))))
        (%poke %BC (%dj-oref w (%slot (lit bitcnt))))
        ((fn (self)
           (room w (* %dj-budget 8))
           (%poke %OUT (%dj-ptr->int (%dj-oref w (%slot (lit outp)))))
           (%poke %CNT (%dj-oref w (%slot (lit outcnt))))
           (%poke %STEPS 0)
           (%poke %BUDGET (- %dj-budget 1))
           (%step %addr)
           (%dj-oset! w (%slot (lit outcnt)) (%peek %CNT))
           (if (< (%peek %T) t1) (self) ())))
        (%dj-oset! w (%slot (lit bitbuf)) (%peek %BB))
        (%dj-oset! w (%slot (lit bitcnt)) (%peek %BC))
        (put-code w lcodes llen 256)))
    (def %counter (compile-asm %dc-expr))
    (def %cbuf (%dj-make-str (* %CWORDS 8)))
    (def %cptr (%dj-str->ptr %cbuf))
    (def %caddr (%dj-ptr->int %cptr))
    (def %cpoke (fn (_ i v) (%dj-pset %cptr (* i 8) v)))
    (def %cpeek (fn (_ i) (%dj-pref %cptr (* i 8))))
    ((fn (self k) (if (> k 259) () (do (%cpoke (+ %CLCODE (- k 1)) (%dj-oref (first tables) k)) (self (+ k 1))))) 1)
    (def %dcode-table (first (rest (rest (rest tables)))))
    ((fn (self k) (if (> k 512) () (do (%cpoke (+ %CDCODE (- k 1)) (%dj-oref %dcode-table k)) (self (+ k 1))))) 1)
    (def %count
      (fn (_ lens vals t t1 lfreq dfreq b)
        ((fn (self i) (if (< i 316) (do (%cpoke (+ %CLF i) 0) (self (+ i 1))) ())) 0)
        (%cpoke %CLENS (%dj-ptr->int lens))
        (%cpoke %CVALS (%dj-ptr->int vals))
        (%cpoke %CT1 t1)
        (def b1 (%counter %caddr t b))
        ; The tallies added to the caller's, which hold the end code's.
        ((fn (self i)
           (if (< i 286)
             (do (if (= (%cpeek (+ %CLF i)) 0) ()
                   (%dj-oset! lfreq (+ i 1) (+ (%dj-oref lfreq (+ i 1)) (%cpeek (+ %CLF i)))))
                 (self (+ i 1)))
             ()))
         0)
        ((fn (self i)
           (if (< i 30)
             (do (if (= (%cpeek (+ %CDF i)) 0) ()
                   (%dj-oset! dfreq (+ i 1) (+ (%dj-oref dfreq (+ i 1)) (%cpeek (+ %CDF i)))))
                 (self (+ i 1)))
             ()))
         0)
        b1))
    (def %summer (compile-asm %da-expr))
    (def %abuf (%dj-make-str 16))
    (def %aptr (%dj-str->ptr %abuf))
    (def %aaddr (%dj-ptr->int %aptr))
    (def %adler
      (fn (_ p n)
        (%dj-pset %aptr (* %AP 8) (%dj-ptr->int p))
        (%dj-pset %aptr (* %AN 8) n)
        (%summer %aaddr 0 1 0)))
    (def %engine (list %match %put %count %adler))
    (if (check %engine) ()
      (Err raise (lit state) "deflate-jit: engine disagrees with the pure-x encoder" ()))
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit deflate) (lit jit-make) deflate-jit-make)

(doc (provide x/codec/deflate-jit deflate-jit-make)
  "The compiled matcher and token writer behind Deflate (JIT, ARM64 and x86-64 backends); built and adopted only after writing what the pure-x encoder writes.")
