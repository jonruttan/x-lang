; math.x -- Num: integer math utilities and number predicates, as static methods.
;
; Loads AFTER object.x in the boot sequence (it needs def-class); nothing loaded
; before the object system calls these. Value-passing call sites use
; (method-ref Num inc) etc.

(import x/type/object)

(def-class Num ()
  (static
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
    (method min (self (param a NUMBER "First number") (param b NUMBER "Second number"))
      (doc "Return the smaller of two numbers." (returns NUMBER "The smaller of a and b"))
      (if (< a b) a b))
    (method max (self (param a NUMBER "First number") (param b NUMBER "Second number"))
      (doc "Return the larger of two numbers." (returns NUMBER "The larger of a and b"))
      (if (> a b) a b))
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
      (doc "Test whether a number is zero." (returns BOOLEAN "True if n is zero"))
      (= n 0))
    (method positive? (self (param n NUMBER "Number to test"))
      (doc "Test whether a number is positive." (returns BOOLEAN "True if n is positive"))
      (> n 0))
    (method negative? (self (param n NUMBER "Number to test"))
      (doc "Test whether a number is negative." (returns BOOLEAN "True if n is negative"))
      (< n 0))
    (method even? (self (param n NUMBER "Integer to test"))
      (doc "Test whether an integer is even." (returns BOOLEAN "True if n is even"))
      (= (% n 2) 0))
    (method odd? (self (param n NUMBER "Integer to test"))
      (doc "Test whether an integer is odd." (returns BOOLEAN "True if n is odd"))
      (not (= (% n 2) 0)))
    ; --- GCD / LCM ---
    (method gcd (self . args)
      (doc "Compute the greatest common divisor. Variadic: (Num gcd a b c ...) folds pairwise."
        (returns NUMBER "Greatest common divisor of all arguments"))
      (def %gcd2
        (fn (self a b) (if (Num zero? b) a (self b (% a b)))))
      (if (null? args) 0
        (fold (fn (_ acc x) (%gcd2 (Num abs acc) (Num abs x)))
              (first args) (rest args))))
    (method lcm (self . args)
      (doc "Compute the least common multiple. Variadic: (Num lcm a b c ...) folds pairwise."
        (returns NUMBER "Least common multiple of all arguments"))
      (def %lcm2
        (fn (_ a b)
          (if (Num zero? b) 0 (Num abs (* (/ a (Num gcd a b)) b)))))
      (if (null? args) 1
        (fold (fn (_ acc x) (%lcm2 (Num abs acc) (Num abs x)))
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

(doc (provide x/core/math Num)
  (example "(Num clamp 0 10 15)" "10")
  "Integer arithmetic utilities and number predicates, homed on the Num class.")
