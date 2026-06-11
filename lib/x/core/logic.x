; logic.x -- Boolean and logic

(doc (def boolean? (fn (_ (param x ANY "Value to test")) (or (eq? x #t) (eq? x #f))))
  (returns BOOLEAN "True if x is #t or #f")
  "Test whether a value is a boolean.")

; default-to and until live on the Fn class (combinators).

; Deep structural equality. eq? is a raw scalar compare (it reads slot 0, which is
; the value for an atom but the car for a pair), so it cannot compare compounds --
; that is what equal? is for. Pairs are compared element-wise here (recursively);
; the final eq? branch only sees non-number/non-string atoms (symbols, chars,
; bools, nil), where the raw scalar compare is correct. self is the recursion.
(doc (def equal?
  (fn (self (param a ANY "First value") (param b ANY "Second value"))
    (match
      ((and (number? a) (number? b)) (= a b))
      ((and (str? a) (str? b)) (str=? a b))
      ((and (pair? a) (pair? b)) (and (self (first a) (first b)) (self (rest a) (rest b))))
      ((or (pair? a) (pair? b)) #f)
      (#t (eq? a b)))))
  (returns BOOLEAN "True if a and b are structurally equal")
  "Structural equality: numbers by value, strings by content, pairs element-wise (deep), else identity.")

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

(doc (provide x/core/logic boolean? equal? > <= >=)
  (note "boolean? stays with the type-predicate cohort transitionally; equal?/>/<=/>= are")
  (note "keep-list operators. default-to and until live on the Fn class.")
  "Boolean logic, structural equality, and derived comparisons.")
