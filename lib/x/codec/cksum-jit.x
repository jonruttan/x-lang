; cksum-jit.x -- the compiled CRC behind (Cksum jit!).
;
; Loaded lazily by x/codec/cksum, never on its import: this module pulls the
; JIT toolchain, and the codec stays loadable and correct on a host with no
; JIT.  The pure-x fold in cksum.x is the reference and the fallback; the
; engine is adopted only after it sums the check inputs as the reference does.
;
; The loop is crc32-jit.x's: one compiled step over a scratch of words that
; folds up to sixteen bytes and calls itself, a run of steps bounded by
; %kj-budget since the lane's self-call conses its arguments.  Each byte is
; the table's entry for the register's top octet against it, against the
; register shifted up eight and cut to 32 bits.
(module x/codec/cksum-jit)

(import x/tool/compile compile-asm)

(import x/core/doors obj-ref ptr->int ptr-ref-word ptr-set-word! str->ptr str-make)

; scratch layout (words)
(def %KP 0)        ; input address
(def %KN 1)        ; bytes to sum
(def %KI 2)        ; bytes summed
(def %KC 3)        ; the register
(def %KSTEPS 4)
(def %KBUDGET 5)
(def %KMASK 6)     ; 4294967295
(def %KT 8)        ; the table, 256 words

(def %kj-budget 256)

; --- the expression (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))

(def %kj-expr
  (list 'fn '(self a)
    (pair 'do
      (List append
        ((fn (self j)
           (if (= j 16) ()
             (pair
               (list 'if (list '< (%M %KI) (%M %KN))
                 (list 'do
                   (%S %KC (list '^
                             (%MA (list '+ %KT (list '& (list '^ (list '>> (%M %KC) 24) (list '%mem-byte-ref-at (%M %KP) (%M %KI))) 255)))
                             (list '& (list '<< (%M %KC) 8) (%M %KMASK))))
                   (%S %KI (list '+ (%M %KI) 1)))
                 0)
               (self (+ j 1)))))
         0)
        (list
          (list 'if (list '>= (%M %KI) (%M %KN)) 0
            (list 'if (list '>= (%M %KSTEPS) (%M %KBUDGET)) 0
              (list 'do (%S %KSTEPS (list '+ (%M %KSTEPS) 1)) (list 'self 'a)))))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; table: cksum.x's table, a vector whose slot i+1 holds byte i's entry.
; check: (fn (_ fold) -> #t) -- runs the reference's check inputs through a
;        candidate fold and answers whether every register agreed.
;
; Answers (fn (_ p n c)): the register after the n bytes at p from register
; c, a drop-in for cksum.x's pure fold.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def cksum-jit-make
  (fn (_ table check)
    (def step (compile-asm %kj-expr))
    (def buf (str-make (* 8 (+ %KT 256))))
    (def ptr (str->ptr buf))
    (def addr (ptr->int ptr))
    (def poke (fn (_ i v) (ptr-set-word! ptr (* i 8) v)))
    (def peek (fn (_ i) (ptr-ref-word ptr (* i 8))))
    ((fn (self i) (when (< i 256) (do (poke (+ %KT i) (obj-ref table (+ i 1))) (self (+ i 1))))) 0)
    (poke %KMASK 4294967295)
    (def fold
      (fn (_ p n c)
        ; the scratch region is held here, so the address stays good
        (do buf
            (poke %KP (ptr->int p))
            (poke %KN n)
            (poke %KI 0)
            (poke %KC c)
            ((fn (self)
               (when (< (peek %KI) n)
                 (do (poke %KSTEPS 0)
                     (poke %KBUDGET %kj-budget)
                     (step addr)
                     (self)))))
            (peek %KC))))
    (unless (check fold)
      (Err raise (lit state) "cksum-jit: engine disagrees with the pure-x CRC" ()))
    fold))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit cksum) (lit jit-make) cksum-jit-make)

(doc (provide x/codec/cksum-jit cksum-jit-make)
  "The compiled CRC of POSIX cksum (JIT, ARM64 and x86-64 backends) behind (Cksum jit!): one loop over the bytes, adopted only after it sums the check inputs as the pure-x fold does.")
