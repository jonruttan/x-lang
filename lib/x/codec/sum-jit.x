; sum-jit.x -- the compiled checksums behind (Sum jit!).
;
; Loaded lazily by x/codec/sum, never on its import: this module pulls the
; JIT toolchain, and the codec stays loadable and correct on a host with no
; JIT.  The pure-x folds in sum.x are the reference and the fallback; an
; engine is adopted only after it sums the check inputs as its reference does.
;
; The loop is crc32-jit.x's: one compiled step over a scratch of words that
; folds up to sixteen bytes and calls itself, a run of steps bounded by
; %sj-budget since the lane's self-call conses its arguments.  BSD's byte is
; the register rotated right one bit within 16, plus the byte, cut to 16
; bits; System V's is the byte added to the total.
(module x/codec/sum-jit)

(import x/tool/compile compile-asm)

(import x/core/doors ptr->int ptr-ref-word ptr-set-word! str->ptr str-make)

; scratch layout (words)
(def %JP 0)        ; input address
(def %JN 1)        ; bytes to sum
(def %JI 2)        ; bytes summed
(def %JS 3)        ; the register, or the total
(def %JSTEPS 4)
(def %JBUDGET 5)
(def %JWORDS 8)

(def %sj-budget 256)

; --- the expressions (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))

(def %sj-byte (list '%mem-byte-ref-at (%M %JP) (%M %JI)))

(def %sj-bsd
  (list '& (list '+ (list '+ (list '>> (%M %JS) 1) (list '<< (list '& (%M %JS) 1) 15)) %sj-byte) 65535))

(def %sj-sysv (list '+ (%M %JS) %sj-byte))

(def %sj-expr
  (fn (_ next)
    (list 'fn '(self a)
      (pair 'do
        (List append
          ((fn (self j)
             (if (= j 16) ()
               (pair
                 (list 'if (list '< (%M %JI) (%M %JN))
                   (list 'do (%S %JS next) (%S %JI (list '+ (%M %JI) 1)))
                   0)
                 (self (+ j 1)))))
           0)
          (list
            (list 'if (list '>= (%M %JI) (%M %JN)) 0
              (list 'if (list '>= (%M %JSTEPS) (%M %JBUDGET)) 0
                (list 'do (%S %JSTEPS (list '+ (%M %JSTEPS) 1)) (list 'self 'a))))))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; which: bsd or sysv.
; check: (fn (_ fold) -> #t) -- runs the reference's check inputs through a
;        candidate fold and answers whether every register agreed.
;
; Answers (fn (_ p n s)): the register after the n bytes at p from register
; s, a drop-in for sum.x's pure fold.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def sum-jit-make
  (fn (_ which check)
    (def step (compile-asm (%sj-expr (if (eq? which (lit bsd)) %sj-bsd %sj-sysv))))
    (def buf (str-make (* 8 %JWORDS)))
    (def ptr (str->ptr buf))
    (def addr (ptr->int ptr))
    (def poke (fn (_ i v) (ptr-set-word! ptr (* i 8) v)))
    (def peek (fn (_ i) (ptr-ref-word ptr (* i 8))))
    (def fold
      (fn (_ p n s)
        ; the scratch region is held here, so the address stays good
        (do buf
            (poke %JP (ptr->int p))
            (poke %JN n)
            (poke %JI 0)
            (poke %JS s)
            ((fn (self)
               (when (< (peek %JI) n)
                 (do (poke %JSTEPS 0)
                     (poke %JBUDGET %sj-budget)
                     (step addr)
                     (self)))))
            (peek %JS))))
    (unless (check fold)
      (Err raise (lit state) "sum-jit: engine disagrees with the pure-x checksum" ()))
    fold))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit sum) (lit jit-make) sum-jit-make)

(doc (provide x/codec/sum-jit sum-jit-make)
  "The compiled checksums of sum(1) (JIT, ARM64 and x86-64 backends) behind (Sum jit!): one loop over the bytes for each, adopted only after it sums the check inputs as its pure-x fold does.")
