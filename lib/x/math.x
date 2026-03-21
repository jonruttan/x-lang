; math.x -- Math and number predicates
; --- Arithmetic ---

(def inc (fn (n) (+ n 1)))

(def dec (fn (n) (- n 1)))

(def negate (fn (n) (- 0 n)))

(def abs (fn (n) (if (< n 0) (- 0 n) n)))

(def min (fn (a b) (if (< a b) a b)))

(def max (fn (a b) (if (> a b) a b)))

(def clamp (fn (lo hi n) (min hi (max lo n))))

(def min-by (fn (f a b) (if (< (f a) (f b)) a b)))

(def max-by (fn (f a b) (if (> (f a) (f b)) a b)))
; --- Number predicates ---

(def zero? (fn (n) (= n 0)))

(def positive? (fn (n) (> n 0)))

(def negative? (fn (n) (< n 0)))

(def even? (fn (n) (= (% n 2) 0)))

(def odd? (fn (n) (not (= (% n 2) 0))))

; --- GCD / LCM (need fold from list.x, loaded after) ---
; These are defined as stubs here, then set! after list.x loads.
; Actually loaded in x-core.x after list.x via inline definitions.

; --- Exponentiation ---

(def expt
  (fn (base exp)
    (if (= exp 0) 1
      (if (even? exp)
        (expt (* base base) (/ exp 2))
        (* base (expt base (- exp 1)))))))

(provide x/math inc dec negate abs min max clamp min-by max-by
  zero? positive? negative? even? odd? expt)
