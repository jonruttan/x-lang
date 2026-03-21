; math.x -- Math and number predicates

; --- Arithmetic ---

(note "Arithmetic")

(doc (def inc (fn ((param n NUMBER "Number to increment")) (+ n 1)))
  (returns NUMBER "n + 1")
  "Add one to a number.")

(doc (def dec (fn ((param n NUMBER "Number to decrement")) (- n 1)))
  (returns NUMBER "n - 1")
  "Subtract one from a number.")

(doc (def negate (fn ((param n NUMBER "Number to negate")) (- 0 n)))
  (returns NUMBER "The additive inverse of n")
  "Return the negation of a number.")

(doc (def abs (fn ((param n NUMBER "Number")) (if (< n 0) (- 0 n) n)))
  (returns NUMBER "Absolute value of n")
  "Return the absolute value of a number.")

(doc (def min (fn ((param a NUMBER "First number") (param b NUMBER "Second number")) (if (< a b) a b)))
  (returns NUMBER "The smaller of a and b")
  "Return the smaller of two numbers.")

(doc (def max (fn ((param a NUMBER "First number") (param b NUMBER "Second number")) (if (> a b) a b)))
  (returns NUMBER "The larger of a and b")
  "Return the larger of two numbers.")

(doc (def clamp (fn ((param lo NUMBER "Lower bound") (param hi NUMBER "Upper bound") (param n NUMBER "Value to clamp")) (min hi (max lo n))))
  (returns NUMBER "n clamped to [lo, hi]")
  "Clamp a number to the range [lo, hi].")

(doc (def min-by (fn ((param f CALLABLE "Projection function") (param a ANY "First value") (param b ANY "Second value")) (if (< (f a) (f b)) a b)))
  (returns ANY "The value whose projection is smaller")
  "Return the value with the smaller result under f.")

(doc (def max-by (fn ((param f CALLABLE "Projection function") (param a ANY "First value") (param b ANY "Second value")) (if (> (f a) (f b)) a b)))
  (returns ANY "The value whose projection is larger")
  "Return the value with the larger result under f.")

; --- Number predicates ---

(note "Number predicates")

(doc (def zero? (fn ((param n NUMBER "Number to test")) (= n 0)))
  (returns BOOLEAN "True if n is zero")
  "Test whether a number is zero.")

(doc (def positive? (fn ((param n NUMBER "Number to test")) (> n 0)))
  (returns BOOLEAN "True if n is positive")
  "Test whether a number is positive.")

(doc (def negative? (fn ((param n NUMBER "Number to test")) (< n 0)))
  (returns BOOLEAN "True if n is negative")
  "Test whether a number is negative.")

(doc (def even? (fn ((param n NUMBER "Integer to test")) (= (% n 2) 0)))
  (returns BOOLEAN "True if n is even")
  "Test whether an integer is even.")

(doc (def odd? (fn ((param n NUMBER "Integer to test")) (not (= (% n 2) 0))))
  (returns BOOLEAN "True if n is odd")
  "Test whether an integer is odd.")

; --- GCD / LCM (need fold from list.x, loaded after) ---
; These are defined as stubs here, then set! after list.x loads.
; Actually loaded in x-core.x after list.x via inline definitions.

; --- Exponentiation ---

(note "Exponentiation")

(doc (def expt
  (fn ((param base NUMBER "Base") (param exp NUMBER "Non-negative integer exponent"))
    (if (= exp 0) 1
      (if (even? exp)
        (expt (* base base) (/ exp 2))
        (* base (expt base (- exp 1)))))))
  (returns NUMBER "base raised to the power exp")
  "Compute base raised to a non-negative integer exponent by repeated squaring.")

(doc (provide x/math inc dec negate abs min max clamp min-by max-by
  zero? positive? negative? even? odd? expt)
  (example "(clamp 0 10 15)" "10")
  "Integer arithmetic utilities.")
