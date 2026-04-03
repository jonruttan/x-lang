; predicates.x -- Type predicates
;
; Defines type-checking predicates using C's type-of primitive.
; Uses only C primitives (match, eq?, type-of, type?).

; Ensure do is available
(match
  ((guard (e ()) (eval (lit do))) ())
  (#t (include "lib/x/boot/operatives.x")))

(def null? (fn (_ x) (eq? x ())))

(def %type-pair (type-of (pair 1 2)))
(def %type-int (type-of 0))
(def %type-str (type-of ""))
(def %type-sym (type-of (lit a)))
(def %type-char (type-of (integer->char 0)))
(def %type-proc (type-of (fn (_ ) ())))
(def %type-prim (type-of eq?))

(def pair? (fn (_ x) (type? x %type-pair)))
(def number? (fn (_ x) (type? x %type-int)))
(def str? (fn (_ x) (type? x %type-str)))
(def symbol? (fn (_ x) (type? x %type-sym)))
(def char? (fn (_ x) (type? x %type-char)))
(def procedure?
  (fn (_ x)
    (match
      ((type? x %type-proc) #t)
      ((type? x %type-prim) #t)
      (#t #f))))
