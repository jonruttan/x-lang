; logic.x -- Boolean and logic

(doc (def boolean? (fn (_ (param x ANY "Value to test")) (or (eq? x #t) (eq? x #f))))
  (returns BOOLEAN "True if x is #t or #f")
  "Test whether a value is a boolean.")

(doc (def default-to (fn (_ (param d ANY "Default value") (param x ANY "Value to check")) (if (null? x) d x)))
  (returns ANY "x if non-nil, otherwise d")
  "Return x if non-nil, otherwise return the default d.")

(doc (def until
  (fn (_ (param pred CALLABLE "Predicate to stop on")
       (param f CALLABLE "Transformation function")
       (param x ANY "Initial value"))
    (if (pred x) x (until pred f (f x)))))
  (returns ANY "First value satisfying pred")
  "Repeatedly apply f to x until pred is satisfied, then return the value.")

(doc (def equal?
  (fn (_ (param a ANY "First value") (param b ANY "Second value"))
    (match
      ((and (number? a) (number? b)) (= a b))
      ((and (str? a) (str? b)) (str=? a b))
      (#t (eq? a b)))))
  (returns BOOLEAN "True if a and b are structurally equal")
  "Structural equality: compares numbers by value, strings by content, else by identity.")

; --- Derived comparisons ---

(doc (def > (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand")) (< b a)))
  (returns BOOLEAN "True if a is greater than b")
  "Test whether a is greater than b.")

(doc (def <= (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand")) (or (< a b) (= a b))))
  (returns BOOLEAN "True if a is less than or equal to b")
  "Test whether a is less than or equal to b.")

(doc (def >= (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand")) (or (< b a) (= a b))))
  (returns BOOLEAN "True if a is greater than or equal to b")
  "Test whether a is greater than or equal to b.")

(doc (provide x/core/logic boolean? default-to until equal? > <= >=)
  "Boolean logic, structural equality, and derived comparisons.")
