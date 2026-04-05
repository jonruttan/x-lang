; and-or.x -- Boolean operatives
;
; Requires: operatives.x (if, let), predicates.x (null?)

(def %and-loop
  (fn (self args e)
    (if (null? (rest args))
      (eval (first args) e)
      (if (eval (first args) e)
        (self (rest args) e)
        #f))))
(doc (def and
  (op args e
    (if (null? args) #t (%and-loop args e))))
  (param args ANY "Zero or more expressions")
  (returns ANY "Last truthy value, or #f if any expression is falsy")
  (example "(and 1 2 3)" "3")
  (example "(and 1 #f 3)" "#f")
  "Short-circuit logical AND. Evaluates left to right, returns #f on first falsy value.")

(def %or-loop
  (fn (self args e)
    (if (null? (rest args))
      (eval (first args) e)
      (let ((%v (eval (first args) e)))
        (if %v %v (self (rest args) e))))))
(doc (def or
  (op args e
    (if (null? args) () (%or-loop args e))))
  (param args ANY "Zero or more expressions")
  (returns ANY "First truthy value, or () if all are falsy")
  (example "(or #f 2 3)" "2")
  (example "(or #f ())" "()")
  "Short-circuit logical OR. Evaluates left to right, returns first truthy value.")

(doc (def time
  (op args
    e
    (let ((t0 (clock)))
      (let ((result (eval (first args) e)))
        (display (- (clock) t0))
        (display " us\n")
        result))))
  (param args ANY "Expression to time")
  (returns ANY "Result of the expression")
  "Time an expression. Prints elapsed microseconds to stdout, returns the result.")

(doc (provide x/core/boolean and or time)
  "Short-circuit logical AND and OR operatives, plus timing.")
