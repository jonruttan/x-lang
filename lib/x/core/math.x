; math.x -- Num: integer math utilities and number predicates, as static methods.
;
; Loads AFTER object.x in the boot sequence (it needs def-class); nothing loaded
; before the object system calls these. Value-passing call sites use
; (method-ref Num inc) etc.

(import x/type/class)

; The machine-INT type handle, for (Num int?) and the N5 count/index guards.
; Type handles are C-static atoms, so the eq? compare is pointer-stable.
(def %num-type-of (prim-ref (lit type) (lit of)))
(def %num-int-type (%num-type-of 0))

(def-class Num ()
  (static
    (method int? (self (param x ANY "Value to test"))
      (doc "Test whether x is a machine INT -- the base integer type. Floats, rationals, bignums, booleans, and nil are not (N5: counts and indexes are machine INTs)."
        (returns BOOL "#t only for machine integers")
        (example "(list (Num int? 3) (Num int? ()))" "(#t #f)"))
      (if (null? x) #f (eq? (%num-type-of x) %num-int-type)))
    ; --- Arithmetic ---
    (method inc (self (param n NUMBER "Number to increment"))
      (doc "Add one to a number." (returns NUMBER "n + 1"))
      (+ n 1))
    (method dec (self (param n NUMBER "Number to decrement"))
      (doc "Subtract one from a number." (returns NUMBER "n - 1"))
      (- n 1))
    (method negate (self (param n NUMBER "Number to negate"))
      (doc "Return the negation of a number." (returns NUMBER "The additive inverse of n"))
      (- 0 n))
    (method abs (self (param n NUMBER "Number"))
      (doc "Return the absolute value of a number." (returns NUMBER "Absolute value of n"))
      (if (< n 0) (- 0 n) n))
    (method min (self (param a NUMBER "First number") . (param more NUMBER "More numbers"))
      (doc "Return the smallest of one or more numbers." (returns NUMBER "The smallest argument")
        (example "(Num min 3 1 2)" "1"))
      (if (null? more) a
        (if (null? (rest more))
          (if (< (first more) a) (first more) a)   ; binary fast path
          (%fold (fn (_ m x) (if (< x m) x m)) a more))))
    (method max (self (param a NUMBER "First number") . (param more NUMBER "More numbers"))
      (doc "Return the largest of one or more numbers." (returns NUMBER "The largest argument")
        (example "(Num max 3 1 2)" "3"))
      (if (null? more) a
        (if (null? (rest more))
          (if (> (first more) a) (first more) a)   ; binary fast path
          (%fold (fn (_ m x) (if (> x m) x m)) a more))))
    (method quotient (self (param a INT "Dividend") (param b INT "Divisor"))
      (doc "Integer division truncating toward zero -- always an integer, where / on integers may promote to a rational under the tower." (returns INT "trunc(a/b)")
        (example "(Num quotient -7 2)" "-3"))
      (%int/ a b))
    (method remainder (self (param a INT "Dividend") (param b INT "Divisor"))
      (doc "Truncating remainder (the dividend's sign) -- the pair of quotient; identical to % on integers." (returns INT "a - b*trunc(a/b)")
        (example "(Num remainder -7 2)" "-1"))
      (%int% a b))
    (method modulo (self (param a INT "Dividend") (param b INT "Divisor"))
      (doc "Floored modulo: the result takes the DIVISOR's sign -- (Num modulo -7 3) is 2 where % gives -1." (returns INT "a - b*floor(a/b)")
        (example "(Num modulo -7 3)" "2"))
      (%int% (%int+ (%int% a b) b) b))
    (method divmod (self (param a INT "Dividend") (param b INT "Divisor"))
      (doc "Truncating quotient and remainder together." (returns LIST "(quotient remainder)")
        (example "(Num divmod 7 2)" "(3 1)"))
      (list (%int/ a b) (%int% a b)))
    (method isqrt (self (param n INT "Non-negative integer"))
      (doc "Integer square root: the largest k with k*k <= n (Newton's method); errors on a negative input." (returns INT "floor(sqrt(n))")
        (example "(Num isqrt 99)" "9"))
      (if (< n 0) (Err raise (lit value) "Num isqrt: negative input" ())
        (if (< n 2) n
          (let go ((x n))
            (let ((y (%int/ (%int+ x (%int/ n x)) 2)))
              (if (< y x) (go y) x))))))
    (method clamp (self (param lo NUMBER "Lower bound") (param hi NUMBER "Upper bound")
                        (param n NUMBER "Value to clamp"))
      (doc "Clamp a number to the range [lo, hi]." (returns NUMBER "n clamped to [lo, hi]")
        (example "(Num clamp 0 10 15)" "10"))
      (Num min hi (Num max lo n)))
    (method min-by (self (param f CALLABLE "Projection function")
                         (param a ANY "First value") (param b ANY "Second value"))
      (doc "Return the value with the smaller result under f."
        (returns ANY "The value whose projection is smaller"))
      (if (< (f a) (f b)) a b))
    (method max-by (self (param f CALLABLE "Projection function")
                         (param a ANY "First value") (param b ANY "Second value"))
      (doc "Return the value with the larger result under f."
        (returns ANY "The value whose projection is larger"))
      (if (> (f a) (f b)) a b))
    ; --- Number predicates ---
    (method zero? (self (param n NUMBER "Number to test"))
      (doc "Test whether a number is zero." (returns BOOL "True if n is zero"))
      (= n 0))
    (method positive? (self (param n NUMBER "Number to test"))
      (doc "Test whether a number is positive." (returns BOOL "True if n is positive"))
      (> n 0))
    (method negative? (self (param n NUMBER "Number to test"))
      (doc "Test whether a number is negative." (returns BOOL "True if n is negative"))
      (< n 0))
    (method even? (self (param n NUMBER "Integer to test"))
      (doc "Test whether an integer is even." (returns BOOL "True if n is even"))
      (= (% n 2) 0))
    (method odd? (self (param n NUMBER "Integer to test"))
      (doc "Test whether an integer is odd." (returns BOOL "True if n is odd"))
      (not (= (% n 2) 0)))
    ; --- GCD / LCM ---
    (method gcd (self . args)
      (doc "Compute the greatest common divisor. Variadic: (Num gcd a b c ...) folds pairwise."
        (returns NUMBER "Greatest common divisor of all arguments"))
      (def %gcd2
        (fn (self a b) (if (Num zero? b) a (self b (% a b)))))
      (if (null? args) 0
        (%fold (fn (_ acc x) (%gcd2 (Num abs acc) (Num abs x)))
              (first args) (rest args))))
    (method lcm (self . args)
      (doc "Compute the least common multiple. Variadic: (Num lcm a b c ...) folds pairwise."
        (returns NUMBER "Least common multiple of all arguments"))
      (def %lcm2
        (fn (_ a b)
          (if (Num zero? b) 0 (Num abs (* (/ a (Num gcd a b)) b)))))
      (if (null? args) 1
        (%fold (fn (_ acc x) (%lcm2 (Num abs acc) (Num abs x)))
              (first args) (rest args))))
    ; --- Exponentiation ---
    (method expt (self (param base NUMBER "Base")
                       (param exp NUMBER "Non-negative integer exponent"))
      (doc "Compute base raised to a non-negative integer exponent by repeated squaring."
        (returns NUMBER "base raised to the power exp"))
      (if (= exp 0) 1
        (if (Num even? exp)
          (recur self (* base base) (/ exp 2))
          (* base (recur self base (- exp 1))))))))

; Value dispatch (subject-last): an integer calls Num's static methods --
; (6 even?) -> (Num even? 6); (12 gcd 8) -> (Num gcd 12 8).
(def %type-of (prim-ref (lit type) (lit of)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-call (prim-ref (lit type) (lit push-call)))
(%type-push-call (%type-by-atom (%type-of 0)) (%class-call-handler Num))

(doc (provide x/core/math Num)
  (example "(Num clamp 0 10 15)" "10")
  "Integer arithmetic utilities and number predicates, homed on the Num class.")
