; # Computational Expressions in C
;
; ## x.x -- x Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do (def x-lib-version "0.1.0")

  ; --- Functional combinators ---
  (def identity (fn (x) x))

  (def const (fn (x) (fn (y) x)))

  (def compose (fn (f g) (fn (x) (f (g x)))))

  (def curry (fn (f x) (fn (y) (f x y))))

  ; --- List folds ---
  (def fold (fn (f init lst)
    (if (null? lst) init
      (fold f (f init (car lst)) (cdr lst)))))

  (def reduce (fn (f lst)
    (fold f (car lst) (cdr lst))))

  ; --- List generators ---
  (def range (fn (start end)
    (if (>= start end) ()
      (cons start (range (+ start 1) end)))))

  (def zip (fn (a b)
    (if (or (null? a) (null? b)) ()
      (cons (list (car a) (car b))
            (zip (cdr a) (cdr b))))))

  ; --- List predicates ---
  (def any? (fn (pred lst)
    (if (null? lst) ()
      (if (pred (car lst)) t
        (any? pred (cdr lst))))))

  (def every? (fn (pred lst)
    (if (null? lst) t
      (if (not (pred (car lst))) ()
        (every? pred (cdr lst))))))

  (quote x-lib-version)
)
