; inflate-jit.x -- the compiled Huffman loop behind Inflate.
;
; Loaded lazily by x/codec/inflate, as x/codec/sha-jit is by the digests:
; this module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x decoder in inflate.x is the
; reference and the fallback; this engine replaces only its hot part -- a
; block's literals, lengths and distances -- and is adopted only after it
; agrees with the reference on a fixed-code and a dynamic-code stream.
;
; The engine is one compiled step over a 4096-byte scratch.  A step decodes
; one symbol and writes it, or copies up to eight bytes of a back-reference,
; then calls itself.  The lane's self-call is a real call that conses its
; arguments, not a jump, so a run of steps is bounded: the step returns
; after %ij-budget of them, and when the output has less than a match's 258
; bytes of room, and the driver here -- in x -- grows the output and runs it
; again.  It does not collect: the steps' argument lists are its caller's to
; sweep, and a collect with a caller's long list live overruns the
; collector's recursive mark.  Headers, the code tables and stored blocks
; stay in x.
;
; The canonical decode is unrolled: fifteen nested levels, one per code
; length, each reading a bit, so a symbol is one step and needs no inner
; loop.  An input that runs out leaves an error status and feeds zero bits
; until the step returns, rather than leaving the expression mid-way.
(module x/codec/inflate-jit)

(import x/tool/compile compile-asm)

(def %ij-make-str (prim-ref (lit str) (lit make)))
(def %ij-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ij-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %ij-pset (prim-ref (lit ptr) (lit set-word!)))
(def %ij-pref (prim-ref (lit ptr) (lit ref-word)))
(def %ij-oref (prim-ref (lit obj) (lit ref)))
(def %ij-oset! (prim-ref (lit obj) (lit set!)))

; scratch layout (words): the stream's state, then the code tables.
(def %IN 0)        ; input address
(def %INLEN 1)
(def %INCNT 2)
(def %BB 3)        ; bits read ahead
(def %BC 4)        ; and how many
(def %OUT 5)       ; output address
(def %CAP 6)
(def %CNT 7)
(def %ST 8)        ; 0 running, 1 block done, 2 return to the driver, <0 error
(def %CODE 9)      ; the canonical decode's running code, first and index
(def %FIRST 10)
(def %INDEX 11)
(def %SYM 12)
(def %LEN 13)
(def %DIST 14)
(def %NEED 15)     ; extra bits wanted
(def %REMAIN 16)   ; bytes of a back-reference still to copy
(def %FROM 17)
(def %STEPS 18)
(def %BUDGET 19)
(def %TMP 20)
(def %LC 32)       ; literal/length counts by code length, 0..15
(def %LS 48)       ; literal/length symbols, up to 288
(def %DC 336)      ; distance counts
(def %DS 352)      ; distance symbols, up to 30
(def %LB 384)      ; length bases and extra bits, codes 257..285
(def %LE 416)
(def %DB 448)      ; distance bases and extra bits, codes 0..29
(def %DE 480)

; What an error status means.
(def %ij-error
  (fn (_ st)
    (match
      ((= st -1) "the input ends inside the stream")
      ((= st -2) "a code no table holds")
      ((= st -3) "a length code out of range")
      ((= st -4) "a distance code out of range")
      ((= st -5) "a distance too far back")
      (#t "an unknown engine status"))))

; --- expression builders (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))

; One more input byte above the bits held, or, at the end of the input,
; the error status and eight zero bits.
(def %ij-refill
  (list 'if (list '< (%M %INCNT) (%M %INLEN))
    (list 'do
      (%S %BB (list '| (%M %BB) (list '<< (list '%mem-byte-ref-at (%M %IN) (%M %INCNT)) (%M %BC))))
      (%S %INCNT (list '+ (%M %INCNT) 1))
      (%S %BC (list '+ (%M %BC) 8)))
    (list 'do (%S %ST -1) (%S %BC (list '+ (%M %BC) 8)))))

; NEED (at most 13) bits, as a value.
(def %ij-bits
  (list 'do
    (list 'if (list '< (%M %BC) (%M %NEED)) %ij-refill 0)
    (list 'if (list '< (%M %BC) (%M %NEED)) %ij-refill 0)
    (%S %TMP (list '& (%M %BB) (list '- (list '<< 1 (%M %NEED)) 1)))
    (%S %BB (list '>> (%M %BB) (%M %NEED)))
    (%S %BC (list '- (%M %BC) (%M %NEED)))
    (%M %TMP)))

; The canonical decode at code length len, against counts at cb and
; symbols at sb: a code of this length is one of count[len] from FIRST on.
(def %ij-decode-level
  (fn (self len cb sb)
    (if (> len 15)
      (list 'do (%S %ST -2) (%S %SYM 256))
      (list 'do
        (list 'if (list '= (%M %BC) 0) %ij-refill 0)
        (%S %CODE (list '| (%M %CODE) (list '& (%M %BB) 1)))
        (%S %BB (list '>> (%M %BB) 1))
        (%S %BC (list '- (%M %BC) 1))
        (list 'if (list '< (list '- (%M %CODE) (%M (+ cb len))) (%M %FIRST))
          (%S %SYM (%MA (list '+ sb (list '+ (%M %INDEX) (list '- (%M %CODE) (%M %FIRST))))))
          (list 'do
            (%S %INDEX (list '+ (%M %INDEX) (%M (+ cb len))))
            (%S %FIRST (list '<< (list '+ (%M %FIRST) (%M (+ cb len))) 1))
            (%S %CODE (list '<< (%M %CODE) 1))
            (self (+ len 1) cb sb)))))))

(def %ij-decode
  (fn (_ cb sb)
    (list 'do (%S %CODE 0) (%S %FIRST 0) (%S %INDEX 0) (%ij-decode-level 1 cb sb))))

; The next step, or a return to the driver when the budget is spent.
(def %ij-continue
  (list 'if (list '>= (%M %STEPS) (%M %BUDGET))
    (list 'do (%S %ST 2) 0)
    (list 'do (%S %STEPS (list '+ (%M %STEPS) 1)) (list 'self 'a))))

; Up to eight bytes of a back-reference, a byte at a time: the source may
; overlap what this copy writes.
(def %ij-copy-chunk
  (pair 'do
    ((fn (self j)
       (if (= j 8) ()
         (pair
           (list 'if (list '> (%M %REMAIN) 0)
             (list 'do
               (list '%mem-byte-set-at! (%M %OUT) (%M %CNT) (list '%mem-byte-ref-at (%M %OUT) (%M %FROM)))
               (%S %CNT (list '+ (%M %CNT) 1))
               (%S %FROM (list '+ (%M %FROM) 1))
               (%S %REMAIN (list '- (%M %REMAIN) 1)))
             0)
           (self (+ j 1)))))
     0)))

; A length code's length and its distance, then the copy begun.
(def %ij-match
  (list 'do
    (%S %NEED (%MA (list '+ %LE (list '- (%M %SYM) 257))))
    (%S %LEN (list '+ (%MA (list '+ %LB (list '- (%M %SYM) 257))) %ij-bits))
    (%ij-decode %DC %DS)
    (list 'if (list '< (%M %ST) 0) 0
      (list 'if (list '> (%M %SYM) 29) (list 'do (%S %ST -4) 0)
        (list 'do
          (%S %NEED (%MA (list '+ %DE (%M %SYM))))
          (%S %DIST (list '+ (%MA (list '+ %DB (%M %SYM))) %ij-bits))
          (list 'if (list '> (%M %DIST) (%M %CNT)) (list 'do (%S %ST -5) 0)
            (list 'do
              (%S %FROM (list '- (%M %CNT) (%M %DIST)))
              (%S %REMAIN (%M %LEN))
              %ij-continue)))))))

; A symbol: a literal written, the block's end, or a match.
(def %ij-symbol
  (list 'do
    (%ij-decode %LC %LS)
    (list 'if (list '< (%M %ST) 0) 0
      (list 'if (list '< (%M %SYM) 256)
        (list 'do
          (list '%mem-byte-set-at! (%M %OUT) (%M %CNT) (%M %SYM))
          (%S %CNT (list '+ (%M %CNT) 1))
          %ij-continue)
        (list 'if (list '= (%M %SYM) 256) (list 'do (%S %ST 1) 0)
          (list 'if (list '> (%M %SYM) 285) (list 'do (%S %ST -3) 0)
            %ij-match))))))

(def %ij-step-expr
  (list 'fn '(self a)
    (list 'if (list '< (%M %ST) 0) 0
      (list 'if (list '> (%M %REMAIN) 0)
        (list 'do %ij-copy-chunk %ij-continue)
        (list 'if (list '> (list '+ (%M %CNT) 258) (%M %CAP))
          (list 'do (%S %ST 2) 0)
          %ij-symbol)))))

; Steps a call may take before it returns: each one is a frame.
(def %ij-budget 256)

; --- Adler-32 (RFC 1950 8): sixteen bytes a step, both sums reduced
; once a step, on a scratch of its own (words): the bytes' address, their
; count, how many are summed, the two sums, the steps taken and allowed.
(def %AP 0)
(def %AN 1)
(def %AI 2)
(def %AA 3)
(def %AB 4)
(def %ASTEPS 5)
(def %ABUDGET 6)
(def %ij-adler-expr
  (list 'fn '(self a)
    (pair 'do
      (List append
        ((fn (self j)
           (if (= j 16) ()
             (pair
               (list 'if (list '< (%M %AI) (%M %AN))
                 (list 'do
                   (%S %AA (list '+ (%M %AA) (list '%mem-byte-ref-at (%M %AP) (%M %AI))))
                   (%S %AB (list '+ (%M %AB) (%M %AA)))
                   (%S %AI (list '+ (%M %AI) 1)))
                 0)
               (self (+ j 1)))))
         0)
        (list
          (%S %AA (list '% (%M %AA) 65521))
          (%S %AB (list '% (%M %AB) 65521))
          (list 'if (list '>= (%M %AI) (%M %AN)) 0
            (list 'if (list '>= (%M %ASTEPS) (%M %ABUDGET)) 0
              (list 'do (%S %ASTEPS (list '+ (%M %ASTEPS) 1)) (list 'self 'a)))))))))

(def %ij-length-tables
  (list (list %LB 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258)
        (list %LE 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)
        (list %DB 1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577)
        (list %DE 0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; state: inflate.x's slot numbers for its stream state, as an alist
;        (in inlen incnt bitbuf bitcnt out outp outcap outcnt).
; room:  inflate.x's (fn (_ s n)), room for n more output bytes.
; check: (fn (_ engine) -> #t) -- runs the reference's test streams through a
;        candidate (CODES . ADLER) and answers whether every output and
;        every checksum agreed with the reference's own.
;
; Answers (CODES . ADLER): (fn (_ s lencode distcode)), a drop-in for
; inflate.x's %codes-x, and (fn (_ p n)), the Adler-32 of n bytes at p, a
; drop-in for its %adler32-x.  Or raises: on a host with no assembler
; backend, a toolchain error, or any disagreement.  The caller guards; a
; raise means "stay pure-x".
(def inflate-jit-make
  (fn (_ state room check)
    (def %step (compile-asm %ij-step-expr))
    (def %adler-step (compile-asm %ij-adler-expr))
    (def %abuf (%ij-make-str 64))
    (def %aptr (%ij-str->ptr %abuf))
    (def %aaddr (%ij-ptr->int %aptr))
    (def %apoke (fn (_ i v) (%ij-pset %aptr (* i 8) v)))
    (def %apeek (fn (_ i) (%ij-pref %aptr (* i 8))))
    (def %adler
      (fn (_ p n)
        (%apoke %AP (%ij-ptr->int p))
        (%apoke %AN n)
        (%apoke %AI 0)
        (%apoke %AA 1)
        (%apoke %AB 0)
        ((fn (self)
           (when (< (%apeek %AI) n)
             (do (%apoke %ASTEPS 0)
                 (%apoke %ABUDGET %ij-budget)
                 (%adler-step %aaddr)
                 (self)))))
        (| (<< (%apeek %AB) 16) (%apeek %AA))))
    (Heap collect)
    (def %buf (%ij-make-str 4096))
    (def %ptr (%ij-str->ptr %buf))
    (def %addr (%ij-ptr->int %ptr))
    (def %poke (fn (_ i v) (%ij-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%ij-pref %ptr (* i 8))))
    (def %slot (fn (_ name) (rest (Assoc entry name state))))
    (List for-each
      (fn (_ t)
        ((fn (self i vs) (unless (null? vs) (do (%poke i (first vs)) (self (+ i 1) (rest vs)))))
         (first t) (rest t)))
      %ij-length-tables)
    ; A code's counts and symbols, from inflate.x's (COUNTS SYMBOLS LEFT).
    (def %load-code!
      (fn (_ h cbase sbase)
        (def counts (first h))
        (def symbols (first (rest h)))
        ((fn (self len) (when (< len 16) (do (%poke (+ cbase len) (%ij-oref counts (+ len 1))) (self (+ len 1))))) 0)
        ((fn (self i n) (when (< i n) (do (%poke (+ sbase i) (%ij-oref symbols (+ i 1))) (self (+ i 1) n))))
         0 (%ij-oref symbols 0))))
    (def %codes
      (fn (_ s lencode distcode)
        (%load-code! lencode %LC %LS)
        (%load-code! distcode %DC %DS)
        (%poke %IN (%ij-ptr->int (%ij-oref s (%slot (lit in)))))
        (%poke %INLEN (%ij-oref s (%slot (lit inlen))))
        (%poke %INCNT (%ij-oref s (%slot (lit incnt))))
        (%poke %BB (%ij-oref s (%slot (lit bitbuf))))
        (%poke %BC (%ij-oref s (%slot (lit bitcnt))))
        (%poke %ST 0)
        (%poke %REMAIN 0)
        ((fn (self)
           (do (room s 258)
               (%poke %OUT (%ij-ptr->int (%ij-oref s (%slot (lit outp)))))
               (%poke %CAP (%ij-oref s (%slot (lit outcap))))
               (%poke %CNT (%ij-oref s (%slot (lit outcnt))))
               (%poke %STEPS 0)
               (%poke %BUDGET %ij-budget)
               (%poke %ST 0)
               (%step %addr)
               (%ij-oset! s (%slot (lit outcnt)) (%peek %CNT))
               (match
                 ((= (%peek %ST) 2) (self))
                 ((= (%peek %ST) 1) ())
                 (#t (Err raise (lit value)
                       (Str8 append "Inflate: " (%ij-error (%peek %ST))) ()))))))
        (%ij-oset! s (%slot (lit incnt)) (%peek %INCNT))
        (%ij-oset! s (%slot (lit bitbuf)) (%peek %BB))
        (%ij-oset! s (%slot (lit bitcnt)) (%peek %BC))
        ()))
    (unless (check (pair %codes %adler))
      (Err raise (lit state) "inflate-jit: engine disagrees with the pure-x decoder" ()))
    (pair %codes %adler)))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit inflate) (lit jit-make) inflate-jit-make)

(doc (provide x/codec/inflate-jit inflate-jit-make)
  "The compiled Huffman loop behind Inflate (JIT, ARM64 and x86-64 backends); built and adopted only after agreeing with the pure-x decoder.")
