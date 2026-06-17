; random.x -- pseudo- and hardware random number generation.
;
; Two entropy backends behind one interface:
;
;   (Random sw)        a fast, NON-cryptographic xorshift PRNG, pure x-lang.
;   (Random sw seed)   the same, seeded -- deterministic and reproducible.
;   (Random hw)        the kernel CSPRNG, read from /dev/urandom through the
;                      filesystem (libc open/read via the Sys FFI layer, so it
;                      is portable across platforms and non-deterministic).
;
; Both backends expose the same 31-bit `(self %bits)` source, so every public
; method (int / range / choice / shuffle / ...) is written once on top of it.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import x/sys/posix)            ; the Sys class: open-read / fd-read / close
(import x/type/list)            ; the List class: fold / nth / length / remove

(def %urandom-path "/dev/urandom")
(def %rand-mask 2147483647)     ; 2^31 - 1: keep every result in [0, 2^31)
(def %rand-default-seed 2463534242) ; a nonzero xorshift seed (Marsaglia)

(def-class Random ()
  (doc "A source of random integers with a pluggable entropy backend."
    (note "Make one with (Random sw) / (Random sw seed) for the software PRNG, or (Random hw) for the kernel CSPRNG. The software stream is NOT cryptographically secure.")
    (example "(let ((r (Random sw 42))) (r int 6))" "an integer in [0, 6)")
    (see sw) (see hw) (see int) (see shuffle))

  (kind 'sw)          ; 'sw -> xorshift PRNG,  'hw -> /dev/urandom
  (state 2463534242)  ; xorshift register (sw only); must stay nonzero
  (fd ())             ; cached /dev/urandom fd (hw only); opened on first use

  (static
    (method sw (self . opt)
      (doc "A software xorshift PRNG. Deterministic; pass a seed for a reproducible stream."
        (param opt LIST "Optional (seed) -- a nonzero integer seed")
        (returns Random "A software RNG")
        (example "(Random sw 42)" "a seeded, reproducible PRNG"))
      (let ((r (new-from self (list 'kind 'sw))))
        (if (pair? opt) (r seed! (first opt)))
        r))

    (method hw (self)
      (doc "A hardware RNG reading the kernel CSPRNG from /dev/urandom."
        (returns Random "A hardware RNG")
        (example "(Random hw)" "a /dev/urandom-backed source"))
      (new-from self (list 'kind 'hw))))

  ; --- seeding (software only) --------------------------------------------
  (method seed! (self n)
    (doc "Reseed the software PRNG. A zero seed is replaced -- xorshift needs a nonzero state."
      (param n INT "Seed value")
      (returns Random "self, for chaining"))
    (set-member! 'state (if (= n 0) %rand-default-seed (& n %rand-mask)))
    self)

  ; --- the entropy source -------------------------------------------------
  ; 31 random bits in [0, 2^31). Both backends yield the same shape so every
  ; method below is backend-agnostic. Private (% prefix); dispatched per call.
  (method %bits (self)
    (if (eq? (member 'kind) 'hw) (self %hw-bits) (self %sw-bits)))

  ; 32-bit xorshift (Marsaglia), masked to 31 bits -- mirrors lib/x/logo/math.x.
  ; Threaded through lets (no set! on a local); the masked result is the next
  ; state, so the register stays 31-bit at rest.
  (method %sw-bits (self)
    (let ((s0 (member 'state)))
      (let ((s1 (^ s0 (<< s0 13))))
        (let ((s2 (^ s1 (>> s1 17))))
          (let ((s3 (& (^ s2 (<< s2 5)) %rand-mask)))
            (set-member! 'state s3)
            s3)))))

  ; Four bytes from /dev/urandom packed big-endian, masked to 31 bits. The fd is
  ; opened once and cached on the instance (see %fd).
  (method %hw-bits (self)
    (& (List fold (fn (_ acc b) (+ (* acc 256) b)) 0 (Sys fd-read (self %fd) 4))
       %rand-mask))

  ; Lazily open and cache the /dev/urandom descriptor.
  (method %fd (self)
    (let ((fd (member 'fd)))
      (if (null? fd)
        (let ((opened (Sys open-read %urandom-path)))
          (set-member! 'fd opened)
          opened)
        fd)))

  ; --- public API ---------------------------------------------------------
  (method int (self n)
    (doc "A random integer in [0, n)."
      (param n INT "Exclusive upper bound (must be > 0)")
      (returns INT "A value in [0, n)")
      (example "((Random sw 1) int 6)" "0..5"))
    (% (self %bits) n))

  (method range (self lo hi)
    (doc "A random integer in [lo, hi)."
      (param lo INT "Inclusive lower bound")
      (param hi INT "Exclusive upper bound")
      (returns INT "A value in [lo, hi)"))
    (+ lo (self int (- hi lo))))

  (method between (self lo hi)
    (doc "A random integer in [lo, hi] -- both ends inclusive."
      (param lo INT "Inclusive lower bound")
      (param hi INT "Inclusive upper bound")
      (returns INT "A value in [lo, hi]"))
    (+ lo (self int (+ 1 (- hi lo)))))

  (method bool (self)
    (doc "A random boolean (a fair coin)."
      (returns BOOLEAN "#t or #f")
      (example "((Random sw 9) bool)" "#t or #f"))
    (= 0 (self int 2)))

  (method bytes (self n)
    (doc "A list of n random byte values (0-255)."
      (param n INT "How many bytes")
      (returns LIST "n byte values"))
    (let go ((i n) (acc ()))
      (if (= i 0) acc (go (- i 1) (pair (self int 256) acc)))))

  (method choice (self lst)
    (doc "A uniformly random element of a non-empty list."
      (param lst LIST "A non-empty list")
      (returns ANY "A random element")
      (example "((Random sw 5) choice (list 'a 'b 'c))" "one of a/b/c"))
    (List nth (self int (List length lst)) lst))

  (method shuffle (self lst)
    (doc "A new list holding the elements of lst in random order (selection shuffle)."
      (param lst LIST "A list")
      (returns LIST "A randomly ordered copy")
      (example "((Random sw 5) shuffle (list 1 2 3))" "a permutation of (1 2 3)"))
    ; Repeatedly pull a random index out of what remains. O(n^2), but needs no
    ; mutable vector (there is no vector-set!) and is plainly correct.
    (let go ((rest lst) (out ()))
      (if (null? rest) out
        (let ((i (self int (List length rest))))
          (go (List remove i 1 rest) (pair (List nth i rest) out)))))))

(doc (provide x/num/random Random)
  (note "Two backends behind one interface: (Random sw [seed]) software, (Random hw) kernel. The software stream is not cryptographically secure.")
  "Pseudo- and hardware random number generation.")
