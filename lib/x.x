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
      (fold f (f init (first lst)) (rest lst)))))

  (def reduce (fn (f lst)
    (fold f (first lst) (rest lst))))

  ; --- List generators ---
  (def range (fn (start end)
    (if (>= start end) ()
      (pair start (range (+ start 1) end)))))

  (def zip (fn (a b)
    (if (or (null? a) (null? b)) ()
      (pair (list (first a) (first b))
            (zip (rest a) (rest b))))))

  ; --- List predicates ---
  (def any? (fn (pred lst)
    (if (null? lst) ()
      (if (pred (first lst)) t
        (any? pred (rest lst))))))

  (def every? (fn (pred lst)
    (if (null? lst) t
      (if (not (pred (first lst))) ()
        (every? pred (rest lst))))))

  (lit x-lib-version)
)
