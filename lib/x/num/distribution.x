; distribution.x -- probability distributions as values.
;
; A distribution is a value of its own class, made with its parameters:
; (Normal make 0 1) is the standard normal.  Each answers, for a number x
; or a probability p:
;
;   density      the probability density at x
;   cumulative   the probability of a value at or below x
;   survival     the probability of a value above x, 1 less the
;                cumulative, worked out directly so it keeps its digits far
;                out in the upper tail
;   quantile     the x at which the cumulative is p, its inverse
;
; and its mean, variance and deviation.  Every answer is a Float.
;
; The normal's cumulative and survival come from libm's erfc.  Its quantile
; starts from Acklam's rational approximation, good to about 1e-9, and one
; Halley step against erfc brings it to full precision.  The uniform and the
; exponential have closed forms; the exponential's use expm1 and log1p,
; which keep their digits where x or p is near 0.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/distribution)
(import x/type/class)
(import x/type/list)
(import x/num/float float float-of f-add f-sub f-mul f-div f-lt fsqrt pi libm-fn)

(def %erfc (libm-fn (lit %distribution-erfc) "d->d" "erfc"))
(def %exp (libm-fn (lit %distribution-exp) "d->d" "exp"))
(def %log (libm-fn (lit %distribution-log) "d->d" "log"))
(def %expm1 (libm-fn (lit %distribution-expm1) "d->d" "expm1"))
(def %log1p (libm-fn (lit %distribution-log1p) "d->d" "log1p"))

(def %zero (float-of 0))
(def %one (float-of 1))
(def %half (f-div (float-of 1) (float-of 2)))
(def %negate (fn (_ x) (f-sub %zero x)))
(def %square (fn (_ x) (f-mul x x)))
(def %root-two (fsqrt (float-of 2)))
(def %root-two-pi (fsqrt (f-mul (float-of 2) pi)))
(def %infinity (%negate (%log %zero)))

; P, a probability from 0 to 1, as a Float; any other is refused.
(def %probability
  (fn (_ who p)
    (let ((p (float-of p)))
      (if (if (f-lt p %zero) #t (f-lt %one p))
        (Err raise (lit value) (Str8 append who " quantile: p is outside 0 to 1") p)
        p))))

; X, a positive parameter, as a Float; any other is refused.
(def %positive
  (fn (_ who what x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) x
        (Err raise (lit value) (Str8 append who ": " what " must be greater than 0") x)))))

; The polynomial with coefficients CS, the highest power first, at X.
(def %horner
  (fn (_ cs x)
    (List fold (fn (_ acc c) (f-add (f-mul acc x) c)) %zero cs)))

(def %floats (fn (_ strs) (List map float-of strs)))

; Acklam's coefficients for the inverse of the standard normal's
; cumulative: A over B in the centre, C over D in the tails, below
; %acklam-low and above 1 less it.
(def %acklam-a
  (%floats (list "-3.969683028665376e+01" "2.209460984245205e+02" "-2.759285104469687e+02"
                 "1.383577518672690e+02" "-3.066479806614716e+01" "2.506628277459239e+00")))
(def %acklam-b
  (%floats (list "-5.447609879822406e+01" "1.615858368580409e+02" "-1.556989798598866e+02"
                 "6.680131188771972e+01" "-1.328068155288572e+01" "1.0")))
(def %acklam-c
  (%floats (list "-7.784894002430293e-03" "-3.223964580411365e-01" "-2.400758277161838e+00"
                 "-2.549732539343734e+00" "4.374664141464968e+00" "2.938163982698783e+00")))
(def %acklam-d
  (%floats (list "7.784695709041462e-03" "3.224671290700398e-01" "2.445134137142996e+00"
                 "3.754408661907416e+00" "1.0")))
(def %acklam-low (float-of "0.02425"))

; The standard normal's cumulative and survival at Z.
(def %phi (fn (_ z) (f-mul %half (%erfc (f-div (%negate z) %root-two)))))
(def %phi-upper (fn (_ z) (f-mul %half (%erfc (f-div z %root-two)))))

; The standard normal's quantile at P, strictly between 0 and 1: Acklam's
; approximation, then one Halley step, x less u over 1 + x u / 2, where u
; is the error in the cumulative over the density.  Above 1/2 the error
; is taken as 1 less p less the survival, the same quantity with the
; digits the upper tail keeps.
(def %standard-quantile
  (fn (_ p)
    (let ((x (match
               ((f-lt p %acklam-low)
                 (let ((q (fsqrt (f-mul (float-of -2) (%log p)))))
                   (f-div (%horner %acklam-c q) (%horner %acklam-d q))))
               ((f-lt (f-sub %one %acklam-low) p)
                 (let ((q (fsqrt (f-mul (float-of -2) (%log1p (%negate p))))))
                   (%negate (f-div (%horner %acklam-c q) (%horner %acklam-d q)))))
               (#t
                 (let ((q (f-sub p %half)))
                   (let ((r (%square q)))
                     (f-div (f-mul (%horner %acklam-a r) q) (%horner %acklam-b r))))))))
      (let ((e (if (f-lt %half p) (f-sub (f-sub %one p) (%phi-upper x)) (f-sub (%phi x) p))))
        (let ((u (f-mul (f-mul e %root-two-pi) (%exp (f-mul %half (%square x))))))
          (f-sub x (f-div u (f-add %one (f-mul (f-mul x u) %half)))))))))

(def-class Normal ()
  (doc "The normal distribution of a mean and a deviation: density e^(-z^2/2) over the deviation times the root of 2 pi, z being x's distance from the mean in deviations."
    (example "((Normal make 0 1) cumulative 0)" "0.5")
    (see make) (see density) (see cumulative) (see survival) (see quantile))

  mean        ; a Float
  deviation   ; a Float, greater than 0

  (static
    (method make (self . (param parameters LIST "Optional (MEAN DEVIATION); 0 and 1 by default, the standard normal"))
      (doc "The normal distribution of a mean and a deviation, the deviation greater than 0."
        (returns Normal "The distribution")
        (example "((Normal make 10 2) quantile 0.5)" "10.0"))
      (let ((m (if (null? parameters) %zero (float-of (first parameters))))
            (s (if (null? parameters) %one (%positive "Normal" "the deviation" (List ref 1 parameters)))))
        (new-from self (list (lit mean) m (lit deviation) s)))))

  (method %z (self x) (f-div (f-sub (float-of x) (field (lit mean))) (field (lit deviation))))

  (method density (self (param x NUMBER "Where"))
    (doc "The probability density at x."
      (returns FLOAT "The density")
      (example "((Normal make) density 0)" "0.398942280401433"))
    (f-div (%exp (f-mul %half (%negate (%square (self %z x)))))
           (f-mul (field (lit deviation)) %root-two-pi)))

  (method cumulative (self (param x NUMBER "Where"))
    (doc "The probability of a value at or below x."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Normal make 0 1) cumulative 0)" "0.5"))
    (%phi (self %z x)))

  (method survival (self (param x NUMBER "Where"))
    (doc "The probability of a value above x: 1 less the cumulative, keeping its digits far out in the upper tail."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Normal make 0 1) survival 1.96)" "0.0249978951482204"))
    (%phi-upper (self %z x)))

  (method quantile (self (param p NUMBER "A probability from 0 to 1"))
    (doc "The x at which the cumulative is p, so (d cumulative (d quantile p)) is p. p 0 and 1 answer minus and plus infinity; a p outside 0 to 1 is refused."
      (returns FLOAT "The quantile")
      (example "((Normal make 0 1) quantile 0.975)" "1.95996398454005"))
    (let ((p (%probability "Normal" p)))
      (match
        ((if (f-lt %zero p) #f #t) (%negate %infinity))
        ((if (f-lt p %one) #f #t) %infinity)
        (#t (f-add (field (lit mean)) (f-mul (field (lit deviation)) (%standard-quantile p)))))))

  (method mean (self)
    (doc "The mean, the distribution's centre."
      (returns FLOAT "The mean")
      (example "((Normal make 3 2) mean)" "3.0"))
    (field (lit mean)))

  (method variance (self)
    (doc "The variance, the deviation squared."
      (returns FLOAT "The variance")
      (example "((Normal make 3 2) variance)" "4.0"))
    (%square (field (lit deviation))))

  (method deviation (self)
    (doc "The deviation, the variance's square root."
      (returns FLOAT "The deviation")
      (example "((Normal make 3 2) deviation)" "2.0"))
    (field (lit deviation))))

(def-class Uniform ()
  (doc "The uniform distribution from a lower bound to an upper one: every value between them equally likely."
    (example "((Uniform make 0 4) cumulative 1)" "0.25")
    (see make) (see density) (see cumulative) (see survival) (see quantile))

  lower   ; a Float
  upper   ; a Float, greater than lower

  (static
    (method make (self . (param parameters LIST "Optional (LOWER UPPER); 0 and 1 by default"))
      (doc "The uniform distribution from lower to upper, upper greater than lower."
        (returns Uniform "The distribution")
        (example "((Uniform make 2 6) mean)" "4.0"))
      (let ((a (if (null? parameters) %zero (float-of (first parameters))))
            (b (if (null? parameters) %one (float-of (List ref 1 parameters)))))
        (if (f-lt a b) ()
          (Err raise (lit value) "Uniform: the upper bound must be greater than the lower" (list a b)))
        (new-from self (list (lit lower) a (lit upper) b)))))

  (method %width (self) (f-sub (field (lit upper)) (field (lit lower))))

  (method density (self (param x NUMBER "Where"))
    (doc "The probability density at x: 1 over the width between the bounds, 0 outside them."
      (returns FLOAT "The density")
      (example "((Uniform make 0 4) density 1)" "0.25"))
    (let ((x (float-of x)))
      (if (if (f-lt x (field (lit lower))) #t (f-lt (field (lit upper)) x)) %zero
        (f-div %one (self %width)))))

  (method cumulative (self (param x NUMBER "Where"))
    (doc "The probability of a value at or below x: 0 below the lower bound, 1 above the upper, and in proportion between."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Uniform make 0 4) cumulative 3)" "0.75"))
    (let ((x (float-of x)))
      (match
        ((f-lt x (field (lit lower))) %zero)
        ((f-lt (field (lit upper)) x) %one)
        (#t (f-div (f-sub x (field (lit lower))) (self %width))))))

  (method survival (self (param x NUMBER "Where"))
    (doc "The probability of a value above x, 1 less the cumulative."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Uniform make 0 4) survival 3)" "0.25"))
    (let ((x (float-of x)))
      (match
        ((f-lt x (field (lit lower))) %one)
        ((f-lt (field (lit upper)) x) %zero)
        (#t (f-div (f-sub (field (lit upper)) x) (self %width))))))

  (method quantile (self (param p NUMBER "A probability from 0 to 1"))
    (doc "The x at which the cumulative is p: the lower bound plus p of the width. A p outside 0 to 1 is refused."
      (returns FLOAT "The quantile")
      (example "((Uniform make 0 4) quantile 0.5)" "2.0"))
    (f-add (field (lit lower)) (f-mul (%probability "Uniform" p) (self %width))))

  (method mean (self)
    (doc "The mean, halfway between the bounds."
      (returns FLOAT "The mean")
      (example "((Uniform make 2 6) mean)" "4.0"))
    (f-mul %half (f-add (field (lit lower)) (field (lit upper)))))

  (method variance (self)
    (doc "The variance, the width squared over 12."
      (returns FLOAT "The variance")
      (example "((Uniform make 0 6) variance)" "3.0"))
    (f-div (%square (self %width)) (float-of 12)))

  (method deviation (self)
    (doc "The deviation, the variance's square root."
      (returns FLOAT "The deviation")
      (example "((Uniform make 0 12) deviation)" "3.46410161513775"))
    (fsqrt (self variance))))

(def-class Exponential ()
  (doc "The exponential distribution of a rate: the waiting time to an event that comes at that rate, density rate times e^(-rate x) from 0 on."
    (example "((Exponential make 2) mean)" "0.5")
    (see make) (see density) (see cumulative) (see survival) (see quantile))

  rate    ; a Float, greater than 0

  (static
    (method make (self . (param parameters LIST "Optional (RATE); 1 by default"))
      (doc "The exponential distribution of a rate greater than 0; its mean is 1 over the rate."
        (returns Exponential "The distribution")
        (example "((Exponential make 4) variance)" "0.0625"))
      (new-from self
        (list (lit rate) (if (null? parameters) %one (%positive "Exponential" "the rate" (first parameters)))))))

  (method density (self (param x NUMBER "Where"))
    (doc "The probability density at x: the rate times e^(-rate x), 0 below 0."
      (returns FLOAT "The density")
      (example "((Exponential make 2) density 0)" "2.0"))
    (let ((x (float-of x)))
      (if (f-lt x %zero) %zero
        (f-mul (field (lit rate)) (%exp (%negate (f-mul (field (lit rate)) x)))))))

  (method cumulative (self (param x NUMBER "Where"))
    (doc "The probability of a value at or below x: 1 less e^(-rate x), 0 below 0."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Exponential make 1) cumulative 0)" "0.0"))
    (let ((x (float-of x)))
      (if (f-lt x %zero) %zero
        (%negate (%expm1 (%negate (f-mul (field (lit rate)) x)))))))

  (method survival (self (param x NUMBER "Where"))
    (doc "The probability of a value above x: e^(-rate x), 1 below 0."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Exponential make 1) survival 0)" "1.0"))
    (let ((x (float-of x)))
      (if (f-lt x %zero) %one
        (%exp (%negate (f-mul (field (lit rate)) x))))))

  (method quantile (self (param p NUMBER "A probability from 0 to 1"))
    (doc "The x at which the cumulative is p: -log(1 - p) over the rate. p 1 answers infinity; a p outside 0 to 1 is refused."
      (returns FLOAT "The quantile")
      (example "((Exponential make 1) quantile 0.5)" "0.693147180559945"))
    (let ((p (%probability "Exponential" p)))
      (if (f-lt p %one)
        (f-add (f-div (%negate (%log1p (%negate p))) (field (lit rate))) %zero)
        %infinity)))

  (method mean (self)
    (doc "The mean, 1 over the rate."
      (returns FLOAT "The mean")
      (example "((Exponential make 2) mean)" "0.5"))
    (f-div %one (field (lit rate))))

  (method variance (self)
    (doc "The variance, 1 over the rate squared."
      (returns FLOAT "The variance")
      (example "((Exponential make 2) variance)" "0.25"))
    (f-div %one (%square (field (lit rate)))))

  (method deviation (self)
    (doc "The deviation, 1 over the rate."
      (returns FLOAT "The deviation")
      (example "((Exponential make 2) deviation)" "0.5"))
    (f-div %one (field (lit rate)))))

(doc (provide x/num/distribution Normal Uniform Exponential)
  "Probability distributions as values: Normal, Uniform and Exponential, each made with its parameters and answering its density, cumulative, survival and quantile, mean, variance and deviation."
  (example "((Normal make 0 1) quantile 0.5)" "0.0"))
