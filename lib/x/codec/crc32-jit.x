; crc32-jit.x -- the compiled CRC-32 behind (Crc32 jit!).
;
; Loaded lazily by x/codec/crc32, never on its import: this module pulls the
; JIT toolchain, and the codec stays loadable and correct on a host with no
; JIT.  The pure-x fold in crc32.x is the reference and the fallback; the
; engine is adopted only after it sums the check inputs as the reference does.
;
; One compiled step over a scratch of words: the input's address, its count,
; how much is summed, the register, the steps taken and allowed, then the
; table of 256.  A step folds up to sixteen bytes, each the table's entry for
; the register's low byte against the next byte, against the register shifted
; down eight, then calls itself.  The lane's self-call conses its arguments,
; so a run of steps is bounded: the step returns after %cj-budget of them and
; the driver here runs it again.
(module x/codec/crc32-jit)

(import x/tool/compile compile-asm)

(def %cj-make-str (prim-ref (lit str) (lit make)))
(def %cj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %cj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %cj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %cj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %cj-oref (prim-ref (lit obj) (lit ref)))

; scratch layout (words)
(def %CP 0)        ; input address
(def %CN 1)        ; bytes to sum
(def %CI 2)        ; bytes summed
(def %CC 3)        ; the register
(def %CSTEPS 4)
(def %CBUDGET 5)
(def %CT 8)        ; the table, 256 words

(def %cj-budget 256)

; --- the expression (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))

(def %cj-expr
  (list 'fn '(self a)
    (pair 'do
      (List append
        ((fn (self j)
           (if (= j 16) ()
             (pair
               (list 'if (list '< (%M %CI) (%M %CN))
                 (list 'do
                   (%S %CC (list '^
                             (%MA (list '+ %CT (list '& (list '^ (%M %CC) (list '%mem-byte-ref-at (%M %CP) (%M %CI))) 255)))
                             (list '>> (%M %CC) 8)))
                   (%S %CI (list '+ (%M %CI) 1)))
                 0)
               (self (+ j 1)))))
         0)
        (list
          (list 'if (list '>= (%M %CI) (%M %CN)) 0
            (list 'if (list '>= (%M %CSTEPS) (%M %CBUDGET)) 0
              (list 'do (%S %CSTEPS (list '+ (%M %CSTEPS) 1)) (list 'self 'a)))))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; table: crc32.x's table, a vector whose slot i+1 holds byte i's entry.
; check: (fn (_ fold) -> #t) -- runs the reference's check inputs through a
;        candidate fold and answers whether every register agreed.
;
; Answers (fn (_ p n c)): the register after the n bytes at p from register
; c, a drop-in for crc32.x's pure fold.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def crc32-jit-make
  (fn (_ table check)
    (def step (compile-asm %cj-expr))
    (def buf (%cj-make-str (* 8 (+ %CT 256))))
    (def ptr (%cj-str->ptr buf))
    (def addr (%cj-ptr->int ptr))
    (def poke (fn (_ i v) (%cj-pset ptr (* i 8) v)))
    (def peek (fn (_ i) (%cj-pref ptr (* i 8))))
    ((fn (self i) (when (< i 256) (do (poke (+ %CT i) (%cj-oref table (+ i 1))) (self (+ i 1))))) 0)
    (def fold
      (fn (_ p n c)
        ; the scratch region is held here, so the address stays good
        (do buf
            (poke %CP (%cj-ptr->int p))
            (poke %CN n)
            (poke %CI 0)
            (poke %CC c)
            ((fn (self)
               (when (< (peek %CI) n)
                 (do (poke %CSTEPS 0)
                     (poke %CBUDGET %cj-budget)
                     (step addr)
                     (self)))))
            (peek %CC))))
    (unless (check fold)
      (Err raise (lit state) "crc32-jit: engine disagrees with the pure-x CRC-32" ()))
    fold))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit crc32) (lit jit-make) crc32-jit-make)

(doc (provide x/codec/crc32-jit crc32-jit-make)
  "The compiled CRC-32 (JIT, ARM64 and x86-64 backends) behind (Crc32 jit!): one loop over the bytes, adopted only after it sums the check inputs as the pure-x fold does.")
