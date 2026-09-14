; logic.x -- Boolean and logic

(doc (def boolean? (fn (_ (param x ANY "Value to test")) (or (eq? x #t) (eq? x #f))))
  (returns BOOL "True if x is #t or #f")
  "Test whether a value is a boolean.")

; default-to and until live on the Fn class (combinators).

; Deep structural equality. eq? is a raw scalar compare (it reads slot 0, which is
; the value for an atom but the car for a pair), so it cannot compare compounds --
; that is what equal? is for. Pairs are compared element-wise here (recursively);
; the final branches only see non-number/non-string atoms and boxed objects.
; self is the recursion.
;
; %equal-others: the extension hook for compound types this file cannot know
; about (logic.x loads before the object system). A later module installs a
; handler (fn (_ equal? a b) -> #t/#f), chaining the previous one -- vector.x
; installs elementwise vector equality this way. The default says #f: identity
; already failed by the time the hook runs. Class INSTANCES deliberately stay
; identity-compared (they have object identity); a value-semantics instance
; type can install its own handler here.
(def %equal-others (pair (fn (_ eq a b) #f) ()))

(doc (def equal?
  (fn (self (param a ANY "First value") (param b ANY "Second value"))
    (match
      ((and (number? a) (number? b)) (= a b))
      ((and (str? a) (str? b)) (str=? a b))
      ((and (pair? a) (pair? b)) (and (self (first a) (first b)) (self (rest a) (rest b))))
      ((or (pair? a) (pair? b)) #f)
      ((eq? a b) #t)
      (#t ((first %equal-others) self a b)))))
  (returns BOOL "True if a and b are structurally equal")
  (note "Vectors compare elementwise (handler installed by x/type/vector); class instances compare by identity.")
  "Structural equality: numbers by value, strings by content, pairs and vectors element-wise (deep), else identity.")

; The library's own handle on structural equality.  `equal?` is a bare global,
; so a session may rebind it, and lang bundles do -- x-sweet ships
; `(def equal? eq?)` as part of its Scheme shim.  Every container that compares
; by content reads that name: Dict's bucket search, Assoc find, List index-of,
; includes?, uniq and uniq-by, and a record's =?.  A rebinding does not make
; them fail, it makes them answer a different question for the rest of the
; session, in code that never mentioned equality.
;
; Library internals reach for this name and user code keeps `equal?` -- the
; split protocol/str/utf8.x draws between `Str`, the rebindable ambient alias,
; and `Str8`, the fixed name its own internals use.  What is captured is the
; closure, not the behaviour: its body reads %equal-others at call time, so a
; module that extends equality through that hook (x/type/vector does) still
; reaches every one of these seats.  Only rebinding the name stops working.
(def %equal? equal?)

; --- Derived comparisons ---
;
; Each rejects a nil operand before delegating. core/arithmetic.x's guard on
; < already makes a missing operand raise instead of segfaulting, so these
; checks are not what keeps the process alive -- they are what makes the
; message name the operator the user actually typed. Without them (> 1)
; reports "<: operands must not be nil", naming a primitive the caller never
; wrote. The cost is two null? tests on a path that already pays for the
; guard inside <.
(doc (def > (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
    (if (or (null? a) (null? b)) (error ">: needs two arguments") (< b a))))
  (returns BOOL "True if a is greater than b")
  "Test whether a is greater than b.")

(doc (def <= (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
    (if (or (null? a) (null? b)) (error "<=: needs two arguments") (or (< a b) (= a b)))))
  (returns BOOL "True if a is less than or equal to b")
  "Test whether a is less than or equal to b.")

(doc (def >= (fn (_ (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
    (if (or (null? a) (null? b)) (error ">=: needs two arguments") (or (< b a) (= a b)))))
  (returns BOOL "True if a is greater than or equal to b")
  "Test whether a is greater than or equal to b.")

(doc (provide x/core/logic boolean? equal? > <= >=)
  (note "boolean? stays with the type-predicate cohort transitionally; equal?/>/<=/>= are")
  (note "keep-list operators. default-to and until live on the Fn class.")
  "Boolean logic, structural equality, and derived comparisons.")
