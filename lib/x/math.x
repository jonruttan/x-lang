; math.x -- Math and number predicates
(import x/logic)
(import x/list)

; --- Arithmetic ---

(note "Arithmetic")

(doc (def inc (fn (_ (param n NUMBER "Number to increment")) (+ n 1)))
  (returns NUMBER "n + 1")
  "Add one to a number.")

(doc (def dec (fn (_ (param n NUMBER "Number to decrement")) (- n 1)))
  (returns NUMBER "n - 1")
  "Subtract one from a number.")

(doc (def negate (fn (_ (param n NUMBER "Number to negate")) (- 0 n)))
  (returns NUMBER "The additive inverse of n")
  "Return the negation of a number.")

(doc (def abs (fn (_ (param n NUMBER "Number")) (if (< n 0) (- 0 n) n)))
  (returns NUMBER "Absolute value of n")
  "Return the absolute value of a number.")

(doc (def min (fn (_ (param a NUMBER "First number") (param b NUMBER "Second number")) (if (< a b) a b)))
  (returns NUMBER "The smaller of a and b")
  "Return the smaller of two numbers.")

(doc (def max (fn (_ (param a NUMBER "First number") (param b NUMBER "Second number")) (if (> a b) a b)))
  (returns NUMBER "The larger of a and b")
  "Return the larger of two numbers.")

(doc (def clamp (fn (_ (param lo NUMBER "Lower bound") (param hi NUMBER "Upper bound") (param n NUMBER "Value to clamp")) (min hi (max lo n))))
  (returns NUMBER "n clamped to [lo, hi]")
  "Clamp a number to the range [lo, hi].")

(doc (def min-by (fn (_ (param f CALLABLE "Projection function") (param a ANY "First value") (param b ANY "Second value")) (if (< (f a) (f b)) a b)))
  (returns ANY "The value whose projection is smaller")
  "Return the value with the smaller result under f.")

(doc (def max-by (fn (_ (param f CALLABLE "Projection function") (param a ANY "First value") (param b ANY "Second value")) (if (> (f a) (f b)) a b)))
  (returns ANY "The value whose projection is larger")
  "Return the value with the larger result under f.")

; --- Number predicates ---

(note "Number predicates")

(doc (def zero? (fn (_ (param n NUMBER "Number to test")) (= n 0)))
  (returns BOOLEAN "True if n is zero")
  "Test whether a number is zero.")

(doc (def positive? (fn (_ (param n NUMBER "Number to test")) (> n 0)))
  (returns BOOLEAN "True if n is positive")
  "Test whether a number is positive.")

(doc (def negative? (fn (_ (param n NUMBER "Number to test")) (< n 0)))
  (returns BOOLEAN "True if n is negative")
  "Test whether a number is negative.")

(doc (def even? (fn (_ (param n NUMBER "Integer to test")) (= (% n 2) 0)))
  (returns BOOLEAN "True if n is even")
  "Test whether an integer is even.")

(doc (def odd? (fn (_ (param n NUMBER "Integer to test")) (not (= (% n 2) 0))))
  (returns BOOLEAN "True if n is odd")
  "Test whether an integer is odd.")

; --- GCD / LCM ---

(note "GCD / LCM")

(doc (def gcd
  (fn (_ . args)
    (def %gcd2
      (fn (_ a b) (if (zero? b) a (%gcd2 b (% a b)))))
    (if (null? args) 0
      (fold (fn (_ acc x) (%gcd2 (abs acc) (abs x)))
            (first args) (rest args)))))
  (returns NUMBER "Greatest common divisor of all arguments")
  "Compute the greatest common divisor. Variadic: (gcd a b c ...) folds pairwise.")

(doc (def lcm
  (fn (_ . args)
    (def %lcm2
      (fn (_ a b)
        (if (zero? b) 0 (abs (* (/ a (gcd a b)) b)))))
    (if (null? args) 1
      (fold (fn (_ acc x) (%lcm2 (abs acc) (abs x)))
            (first args) (rest args)))))
  (returns NUMBER "Least common multiple of all arguments")
  "Compute the least common multiple. Variadic: (lcm a b c ...) folds pairwise.")

; --- Exponentiation ---

(note "Exponentiation")

(doc (def expt
  (fn (_ (param base NUMBER "Base") (param exp NUMBER "Non-negative integer exponent"))
    (if (= exp 0) 1
      (if (even? exp)
        (expt (* base base) (/ exp 2))
        (* base (expt base (- exp 1)))))))
  (returns NUMBER "base raised to the power exp")
  "Compute base raised to a non-negative integer exponent by repeated squaring.")

(doc (provide x/math inc dec negate abs min max clamp min-by max-by
  zero? positive? negative? even? odd? gcd lcm expt)
  (example "(clamp 0 10 15)" "10")
  "Integer arithmetic utilities.")
