; deflate-jit.x -- the compiled token writer behind Deflate.
;
; Loaded lazily by x/codec/deflate, as x/codec/inflate-jit is by Inflate:
; this module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x writer in deflate.x is the
; reference and the fallback; this engine replaces only its hot part --
; a block's tokens written under its codes -- and is adopted only after the
; streams it writes for the codec's check inputs are byte for byte the
; reference's.  Matching, the codes, the headers and stored blocks stay in x.
;
; The engine is one compiled step over a scratch holding the writer's bit
; state and the block's tables.  A step writes one token -- a literal, or a
; length and a distance with their extra bits -- whole bytes out as they
; fill, then calls itself.  The lane's self-call is a real call, not a jump,
; so a run is bounded: the step returns after %dj-budget tokens, and the
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

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; state:    deflate.x's slot numbers for its writer, as an alist
;           (outp outcap outcnt bitbuf bitcnt).
; tables:   deflate.x's vectors (length-code lbase lext distance-code dbase
;           dext), slot k holding entry k-1.
; room:     deflate.x's (fn (_ w n)), room for n more output bytes.
; put-code: deflate.x's (fn (_ w codes lengths sym)), for the end code.
; check:    (fn (_ put) -> #t) -- whether a token writer writes what the
;           reference writes on the check inputs.
;
; Answers (fn (_ w lens vals t t1 lcodes llen dcodes dlen)), a drop-in for
; deflate.x's %put-tokens!.  Or raises: on a host with no assembler
; backend, a toolchain error, or any disagreement.  The caller guards; a
; raise means "stay pure-x".
(def deflate-jit-make
  (fn (_ state tables room put-code check)
    (def %step (compile-asm %dj-step-expr))
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
    (if (check %put) ()
      (Err raise (lit state) "deflate-jit: engine disagrees with the pure-x writer" ()))
    %put))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit deflate) (lit jit-make) deflate-jit-make)

(doc (provide x/codec/deflate-jit deflate-jit-make)
  "The compiled token writer behind Deflate (JIT, ARM64 and x86-64 backends); built and adopted only after writing what the pure-x writer writes.")
