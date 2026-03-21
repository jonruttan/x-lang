; logic.x -- Boolean and logic

(def boolean? (fn (x) (or (eq? x #t) (eq? x #f))))

(def default-to (fn (d x) (if (null? x) d x)))

(def until
  (fn (pred f x) (if (pred x) x (until pred f (f x)))))

(def equal?
  (fn (a b)
    (match
      ((and (number? a) (number? b)) (= a b))
      ((and (string? a) (string? b)) (string=? a b))
      (#t (eq? a b)))))

(provide x/logic boolean? default-to until equal?)
