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
(def and
  (op args e
    (if (null? args) #t (%and-loop args e))))

(def %or-loop
  (fn (self args e)
    (if (null? (rest args))
      (eval (first args) e)
      (let ((%v (eval (first args) e)))
        (if %v %v (self (rest args) e))))))
(def or
  (op args e
    (if (null? args) () (%or-loop args e))))

(def time
  (op args
    e
    (let ((t0 (clock)))
      (let ((result (eval (first args) e)))
        (display (- (clock) t0))
        (display " us\n")
        result))))
