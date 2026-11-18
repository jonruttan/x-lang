; distribution.x -- probability distributions as values.
;
; A distribution is a value made by a constructor of the Distribution
; class with its parameters: (Distribution normal 0 1) is the standard
; normal.  Each answers, for a number x or a probability p:
;
;   density      the probability density at x
;   cumulative   the probability of a value at or below x
;   survival     the probability of a value above x, 1 less the
;                cumulative, worked out directly where that keeps its
;                digits far out in the upper tail
;   quantile     the x at which the cumulative is p, its inverse
;
; and its mean, variance and deviation.  Every answer is a Float.
;
; Distribution is the base class.  It holds what every distribution
; shares: the survival as 1 less the cumulative, the deviation as the
; variance's root, and a quantile found by searching the cumulative.  A
; distribution is a subclass that supplies its density, cumulative, mean
; and variance, and overrides the shared methods where it has a closed
; form.  The subclasses are reached through the constructors and are not
; provided.
;
; The normal's cumulative and survival come from libm's erfc.  Its quantile
; starts from Acklam's rational approximation, good to about 1e-9, and one
; Halley step against erfc brings it to full precision.  The uniform and the
; exponential have closed forms; the exponential's use expm1 and log1p,
; which keep their digits where x or p is near 0.  The gamma's cumulative
; is the regularized incomplete gamma function, and the standardized mean's and
; the variance ratio's the regularized incomplete beta, each by a series or a
; continued fraction.
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
  (fn (_ p)
    (let ((p (float-of p)))
      (if (if (f-lt p %zero) #t (f-lt %one p))
        (Err raise (lit value) "Distribution quantile: p is outside 0 to 1" p)
        p))))

; X, a positive parameter, as a Float; any other is refused.
(def %positive
  (fn (_ who what x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) x
        (Err raise (lit value) (Str8 append "Distribution " who ": " what " must be greater than 0") x)))))

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

(def %two (float-of 2))
(def %four (float-of 4))
(def %not-a-number (f-div %zero %zero))
(def %abs (fn (_ x) (if (f-lt x %zero) (%negate x) x)))

; The spacing of floats at 1, 2^-52: a series or a fraction has converged
; when its next step changes it by less than this, relatively.
(def %epsilon (float-of "2.220446049250313e-16"))

; Lentz's continued fractions divide by their running terms; one that
; comes out smaller than this is taken as this, so no step divides by 0.
(def %tiny (float-of "1.0e-300"))
(def %not-tiny (fn (_ v) (if (f-lt (%abs v) %tiny) %tiny v)))

; The most steps a series, a fraction or a quantile search takes.  Each
; converges long before this; it bounds a step that does not.
(def %iterations 10000)

(def %lgamma (libm-fn (lit %distribution-lgamma) "d->d" "lgamma"))

; The log of the beta function, log Gamma(a) + log Gamma(b) - log Gamma(a + b).
(def %log-beta
  (fn (_ a b) (f-sub (f-add (%lgamma a) (%lgamma b)) (%lgamma (f-add a b)))))

; x^a e^(-x) / Gamma(a), the factor the incomplete gamma's series and
; fraction share.
(def %gamma-front
  (fn (_ a x) (%exp (f-sub (f-sub (f-mul a (%log x)) x) (%lgamma a)))))

; The regularized lower incomplete gamma P(a, x), for x below a + 1, by
; its series: the front times the sum of x^n / (a (a + 1) ... (a + n)).
(def %gamma-series
  (fn (_ a x)
    (let go ((n %one) (term (f-div %one a)) (sum (f-div %one a)) (i 0))
      (let ((term (f-div (f-mul term x) (f-add a n))))
        (let ((sum (f-add sum term)))
          (if (if (f-lt (%abs term) (f-mul (%abs sum) %epsilon)) #t (= i %iterations))
            (f-mul sum (%gamma-front a x))
            (go (f-add n %one) term sum (+ i 1))))))))

; The regularized upper incomplete gamma Q(a, x), for x at or above a + 1,
; by its continued fraction, evaluated by Lentz's method.
(def %gamma-fraction
  (fn (_ a x)
    (let ((b (f-add (f-sub x a) %one)))
      (let go ((i 1) (b b) (c (f-div %one %tiny)) (d (f-div %one b)) (h (f-div %one b)))
        (let ((an (f-mul (float-of (- 0 i)) (f-sub (float-of i) a)))
              (b (f-add b %two)))
          (let ((d (f-div %one (%not-tiny (f-add (f-mul an d) b))))
                (c (%not-tiny (f-add b (f-div an c)))))
            (let ((step (f-mul d c)))
              (let ((h (f-mul h step)))
                (if (if (f-lt (%abs (f-sub step %one)) %epsilon) #t (= i %iterations))
                  (f-mul h (%gamma-front a x))
                  (go (+ i 1) b c d h))))))))))

; The regularized incomplete gamma, lower P(a, x) and upper Q(a, x), for
; x greater than 0: each by the series below a + 1 and by the fraction
; from there, the other taken as 1 less it.
(def %gamma-lower
  (fn (_ a x)
    (if (f-lt x (f-add a %one)) (%gamma-series a x) (f-sub %one (%gamma-fraction a x)))))
(def %gamma-upper
  (fn (_ a x)
    (if (f-lt x (f-add a %one)) (f-sub %one (%gamma-series a x)) (%gamma-fraction a x))))

; The continued fraction of the regularized incomplete beta I_x(a, b),
; evaluated by Lentz's method; it converges fast for x below
; (a + 1) / (a + b + 2).
(def %beta-fraction
  (fn (_ a b x)
    (let ((qab (f-add a b)) (qap (f-add a %one)) (qam (f-sub a %one)))
      (let ((d0 (f-div %one (%not-tiny (f-sub %one (f-div (f-mul qab x) qap))))))
        (let go ((m 1) (c %one) (d d0) (h d0))
          (let ((mf (float-of m)))
            (let ((m2 (f-mul %two mf)))
              (let ((even (f-div (f-mul (f-mul mf (f-sub b mf)) x)
                                 (f-mul (f-add qam m2) (f-add a m2)))))
                (let ((d (f-div %one (%not-tiny (f-add %one (f-mul even d)))))
                      (c (%not-tiny (f-add %one (f-div even c)))))
                  (let ((h (f-mul h (f-mul d c)))
                        (odd (%negate (f-div (f-mul (f-mul (f-add a mf) (f-add qab mf)) x)
                                             (f-mul (f-add a m2) (f-add qap m2))))))
                    (let ((d (f-div %one (%not-tiny (f-add %one (f-mul odd d)))))
                          (c (%not-tiny (f-add %one (f-div odd c)))))
                      (let ((step (f-mul d c)))
                        (let ((h (f-mul h step)))
                          (if (if (f-lt (%abs (f-sub step %one)) %epsilon) #t (= m %iterations))
                            h
                            (go (+ m 1) c d h)))))))))))))))

; The regularized incomplete beta I_x(a, b), with Y, 1 less x, given
; apart so a caller that has it exactly keeps its digits: the fraction
; at x below (a + 1) / (a + b + 2), and 1 less the fraction of the
; mirrored I_y(b, a) above.
(def %beta-regular
  (fn (_ a b x y)
    (match
      ((if (f-lt %zero x) #f #t) %zero)
      ((if (f-lt %zero y) #f #t) %one)
      (#t
        (let ((front (%exp (f-sub (f-add (f-mul a (%log x)) (f-mul b (%log y))) (%log-beta a b)))))
          (if (f-lt x (f-div (f-add a %one) (f-add (f-add a b) %two)))
            (f-div (f-mul front (%beta-fraction a b x)) a)
            (f-sub %one (f-div (f-mul front (%beta-fraction b a y)) b))))))))

; A point between LO and HI for the quantile search: halfway, or the
; geometric middle when they are far apart, and a sixteenth of HI while
; LO is still 0, so a quantile near 0 is found in steps of its own size.
(def %middle
  (fn (_ lo hi)
    (match
      ((if (f-lt %zero lo) #f #t) (f-div hi (float-of 16)))
      ((f-lt (f-mul lo %four) hi) (fsqrt (f-mul lo hi)))
      (#t (f-mul %half (f-add lo hi))))))

; The x at which distribution D's cumulative is P, with Q its complement
; 1 less p, both strictly between 0 and 1.  The quantile lies above 0
; where the cumulative at 0 is below p, and below 0 otherwise; the search
; runs along that side, on the distance y from 0.  It grows a bracket
; from 1 by doubling, then takes Newton steps, the error over the density,
; falling back to the bracket's middle when a step would leave it.  Above
; 1/2 the error is q less the survival, which keeps the digits of the
; upper tail.
(def %invert
  (fn (_ d p q)
    (let ((upper (f-lt %half p)))
      (let ((error-at (fn (_ x) (if upper (f-sub q (d survival x)) (f-sub (d cumulative x) p)))))
        (let ((e0 (error-at %zero)))
          (if (if (f-lt e0 %zero) #f (if (f-lt %zero e0) #f #t)) %zero
            (let ((above (f-lt e0 %zero)))
              (let ((along (fn (_ y) (if above y (%negate y)))))
                (let ((miss (fn (_ y) (if above (error-at y) (%negate (error-at (%negate y)))))))
                  (let ((top (let grow ((hi %one) (i 0))
                               (if (if (f-lt (miss hi) %zero) (< i 2000) #f) (grow (f-mul hi %two) (+ i 1)) hi))))
                    (let go ((lo %zero) (hi top) (y (f-mul %half top)) (i 0))
                      (let ((e (miss y)))
                        (if (if (f-lt e %zero) #f (if (f-lt %zero e) #f #t)) (along y)
                          (let ((lo (if (f-lt e %zero) y lo)) (hi (if (f-lt e %zero) hi y)))
                            (let ((newton (f-sub y (f-div e (d density (along y))))))
                              (let ((next (if (if (f-lt lo newton) (f-lt newton hi) #f) newton (%middle lo hi))))
                                (if (if (f-lt (%abs (f-sub next y)) (f-mul (f-mul %four %epsilon) (%abs next))) #t (= i %iterations))
                                  (along next)
                                  (go lo hi next (+ i 1)))))))))))))))))))

(def-class Distribution ()
  (doc "A probability distribution as a value. A constructor makes one from its parameters, and it answers its density, cumulative, survival and quantile, and its mean, variance and deviation, each a Float."
    (note "Distribution holds what every distribution shares; each constructor answers a value of a subclass that supplies its own density, cumulative, mean and variance.")
    (example "((Distribution normal 0 1) cumulative 1.96)" "0.97500210485178")
    (example "((Distribution exponential 2) mean)" "0.5")
    (see normal) (see uniform) (see exponential) (see gamma) (see chi-squared) (see standardized-mean) (see variance-ratio)
    (see density) (see cumulative) (see survival) (see quantile))

  (static
    (method normal (self . (param parameters NUMBER "Optional (MEAN DEVIATION); 0 and 1 by default, the standard normal"))
      (doc "The normal distribution of a mean and a deviation greater than 0: density e^(-z^2/2) over the deviation times the root of 2 pi, z being x's distance from the mean in deviations."
        (returns Distribution "The distribution")
        (example "((Distribution normal 10 2) quantile 0.5)" "10.0"))
      (new-from Normal
        (list (lit mean) (if (null? parameters) %zero (float-of (first parameters)))
              (lit deviation) (if (null? parameters) %one (%positive "normal" "the deviation" (List ref 1 parameters))))))

    (method uniform (self . (param parameters NUMBER "Optional (LOWER UPPER); 0 and 1 by default"))
      (doc "The uniform distribution from a lower bound to a greater upper one: every value between them equally likely."
        (returns Distribution "The distribution")
        (example "((Distribution uniform 2 6) mean)" "4.0"))
      (let ((a (if (null? parameters) %zero (float-of (first parameters))))
            (b (if (null? parameters) %one (float-of (List ref 1 parameters)))))
        (if (f-lt a b) ()
          (Err raise (lit value) "Distribution uniform: the upper bound must be greater than the lower" (list a b)))
        (new-from Uniform (list (lit lower) a (lit upper) b))))

    (method exponential (self . (param parameters NUMBER "Optional (RATE); 1 by default"))
      (doc "The exponential distribution of a rate greater than 0: the waiting time to an event that comes at that rate, density rate times e^(-rate x) from 0 on. Its mean is 1 over the rate."
        (returns Distribution "The distribution")
        (example "((Distribution exponential 4) variance)" "0.0625"))
      (new-from Exponential
        (list (lit rate) (if (null? parameters) %one (%positive "exponential" "the rate" (first parameters))))))

    (method gamma (self (param shape NUMBER "The shape, greater than 0") . (param parameters NUMBER "Optional (RATE); 1 by default"))
      (doc "The gamma distribution of a shape and a rate, both greater than 0: density rate^shape x^(shape - 1) e^(-rate x) over Gamma(shape), from 0 on. With a whole shape it is the waiting time to that many events at the rate, and shape 1 is the exponential."
        (returns Distribution "The distribution")
        (example "((Distribution gamma 2 4) mean)" "0.5"))
      (new-from Gamma
        (list (lit shape) (%positive "gamma" "the shape" shape)
              (lit rate) (if (null? parameters) %one (%positive "gamma" "the rate" (first parameters))))))

    (method chi-squared (self (param freedom NUMBER "The degrees of freedom, greater than 0"))
      (doc "The chi-squared distribution of its degrees of freedom: with a whole number n, the sum of the squares of n independent standard normals. It is the gamma of shape freedom / 2 and rate 1/2."
        (returns Distribution "The distribution")
        (example "((Distribution chi-squared 3) mean)" "3.0"))
      (new-from Gamma
        (list (lit shape) (f-mul %half (%positive "chi-squared" "the degrees of freedom" freedom))
              (lit rate) %half)))

    (method standardized-mean (self (param freedom NUMBER "The degrees of freedom, greater than 0"))
      (doc "The distribution of a standardized mean, of its degrees of freedom: the distance of a sample's mean from the true mean, in the standard errors the sample itself estimates, with freedom one less than the sample's size. It is a standard normal over the root of an independent chi-squared divided by its freedom, and nears the standard normal as the freedom grows."
        (known-as "t distribution" "Student's t")
        (returns Distribution "The distribution")
        (example "((Distribution standardized-mean 5) cumulative 0)" "0.5"))
      (new-from StandardizedMean (list (lit freedom) (%positive "standardized-mean" "the degrees of freedom" freedom))))

    (method variance-ratio (self (param upper NUMBER "The degrees of freedom of the variance above, greater than 0")
                                 (param lower NUMBER "The degrees of freedom of the variance below, greater than 0"))
      (doc "The distribution of a variance ratio, of two degrees of freedom: the ratio of two independent chi-squareds, each divided by its freedom, which is the ratio of two sample variances of normals with one true variance."
        (known-as "F distribution")
        (returns Distribution "The distribution")
        (example "((Distribution variance-ratio 4 10) mean)" "1.25"))
      (new-from VarianceRatio
        (list (lit upper) (%positive "variance-ratio" "the upper degrees of freedom" upper)
              (lit lower) (%positive "variance-ratio" "the lower degrees of freedom" lower)))))

  ; The ends of the values the distribution takes, the quantiles at p 0
  ; and p 1: the whole line unless a subclass says otherwise.
  (method %from (self) (%negate %infinity))
  (method %to (self) %infinity)

  (method density (self (param x NUMBER "Where"))
    (doc "The probability density at x."
      (returns FLOAT "The density")
      (example "((Distribution normal) density 0)" "0.398942280401433")
      (example "((Distribution uniform 0 4) density 1)" "0.25"))
    (Err raise (lit value) "Distribution density: this distribution supplies none" self))

  (method cumulative (self (param x NUMBER "Where"))
    (doc "The probability of a value at or below x."
      (known-as "CDF")
      (returns FLOAT "A probability from 0 to 1")
      (example "((Distribution normal 0 1) cumulative 0)" "0.5")
      (example "((Distribution uniform 0 4) cumulative 3)" "0.75"))
    (Err raise (lit value) "Distribution cumulative: this distribution supplies none" self))

  (method survival (self (param x NUMBER "Where"))
    (doc "The probability of a value above x: 1 less the cumulative, worked out directly where that keeps its digits far out in the upper tail."
      (returns FLOAT "A probability from 0 to 1")
      (example "((Distribution normal 0 1) survival 1.96)" "0.0249978951482204")
      (example "((Distribution exponential 1) survival 0)" "1.0"))
    (f-sub %one (self cumulative x)))

  (method quantile (self (param p NUMBER "A probability from 0 to 1"))
    (doc "The x at which the cumulative is p, so (d cumulative (d quantile p)) is p. p 0 and 1 answer the ends of the values the distribution takes, which may be infinite; a p outside 0 to 1 is refused."
      (known-as "inverse CDF" "ppf")
      (returns FLOAT "The quantile")
      (example "((Distribution normal 0 1) quantile 0.975)" "1.95996398454005")
      (example "((Distribution exponential 1) quantile 0.5)" "0.693147180559945"))
    (let ((p (%probability p)))
      (match
        ((if (f-lt %zero p) #f #t) (self %from))
        ((if (f-lt p %one) #f #t) (self %to))
        (#t (%invert self p (f-sub %one p))))))

  (method mean (self)
    (doc "The mean, the distribution's centre of mass. It is infinite where the distribution has none."
      (returns FLOAT "The mean")
      (example "((Distribution normal 3 2) mean)" "3.0")
      (example "((Distribution uniform 2 6) mean)" "4.0"))
    (Err raise (lit value) "Distribution mean: this distribution supplies none" self))

  (method variance (self)
    (doc "The variance, the mean squared distance from the mean. It is infinite or not a number where the distribution has none."
      (returns FLOAT "The variance")
      (example "((Distribution normal 3 2) variance)" "4.0")
      (example "((Distribution exponential 2) variance)" "0.25"))
    (Err raise (lit value) "Distribution variance: this distribution supplies none" self))

  (method deviation (self)
    (doc "The deviation, the variance's square root."
      (known-as "standard deviation" "std")
      (returns FLOAT "The deviation")
      (example "((Distribution normal 3 2) deviation)" "2.0")
      (example "((Distribution uniform 0 12) deviation)" "3.46410161513775"))
    (fsqrt (self variance))))

; The normal distribution of a mean and a deviation.
(def-class Normal (extends Distribution)
  mean        ; a Float
  deviation   ; a Float, greater than 0

  (method %z (self x) (f-div (f-sub (float-of x) (field (lit mean))) (field (lit deviation))))

  (method density (self x)
    (f-div (%exp (f-mul %half (%negate (%square (self %z x)))))
           (f-mul (field (lit deviation)) %root-two-pi)))
  (method cumulative (self x) (%phi (self %z x)))
  (method survival (self x) (%phi-upper (self %z x)))
  (method quantile (self p)
    (let ((p (%probability p)))
      (match
        ((if (f-lt %zero p) #f #t) (%negate %infinity))
        ((if (f-lt p %one) #f #t) %infinity)
        (#t (f-add (field (lit mean)) (f-mul (field (lit deviation)) (%standard-quantile p)))))))
  (method mean (self) (field (lit mean)))
  (method variance (self) (%square (field (lit deviation))))
  (method deviation (self) (field (lit deviation))))

; The uniform distribution from a lower bound to an upper one.
(def-class Uniform (extends Distribution)
  lower   ; a Float
  upper   ; a Float, greater than lower

  (method %width (self) (f-sub (field (lit upper)) (field (lit lower))))

  ; 1 over the width between the bounds, 0 outside them.
  (method density (self x)
    (let ((x (float-of x)))
      (if (if (f-lt x (field (lit lower))) #t (f-lt (field (lit upper)) x)) %zero
        (f-div %one (self %width)))))
  (method cumulative (self x)
    (let ((x (float-of x)))
      (match
        ((f-lt x (field (lit lower))) %zero)
        ((f-lt (field (lit upper)) x) %one)
        (#t (f-div (f-sub x (field (lit lower))) (self %width))))))
  (method survival (self x)
    (let ((x (float-of x)))
      (match
        ((f-lt x (field (lit lower))) %one)
        ((f-lt (field (lit upper)) x) %zero)
        (#t (f-div (f-sub (field (lit upper)) x) (self %width))))))
  ; The lower bound plus p of the width.
  (method quantile (self p)
    (f-add (field (lit lower)) (f-mul (%probability p) (self %width))))
  (method mean (self) (f-mul %half (f-add (field (lit lower)) (field (lit upper)))))
  (method variance (self) (f-div (%square (self %width)) (float-of 12))))

; The exponential distribution of a rate.
(def-class Exponential (extends Distribution)
  rate    ; a Float, greater than 0

  (method density (self x)
    (let ((x (float-of x)))
      (if (f-lt x %zero) %zero
        (f-mul (field (lit rate)) (%exp (%negate (f-mul (field (lit rate)) x)))))))
  (method cumulative (self x)
    (let ((x (float-of x)))
      (if (f-lt x %zero) %zero
        (%negate (%expm1 (%negate (f-mul (field (lit rate)) x)))))))
  (method survival (self x)
    (let ((x (float-of x)))
      (if (f-lt x %zero) %one
        (%exp (%negate (f-mul (field (lit rate)) x))))))
  ; -log(1 - p) over the rate; the added 0 makes p 0 answer 0, not -0.
  (method quantile (self p)
    (let ((p (%probability p)))
      (if (f-lt p %one)
        (f-add (f-div (%negate (%log1p (%negate p))) (field (lit rate))) %zero)
        %infinity)))
  (method mean (self) (f-div %one (field (lit rate))))
  (method variance (self) (f-div %one (%square (field (lit rate)))))
  (method deviation (self) (f-div %one (field (lit rate)))))

; The gamma distribution of a shape and a rate, on 0 up.  Its cumulative
; and survival are the regularized incomplete gamma, lower and upper, at
; rate times x.  At x 0 the density is infinite for a shape below 1, the
; rate at shape 1 and 0 above.  The chi-squared is the gamma of shape
; freedom / 2 and rate 1/2.
(def-class Gamma (extends Distribution)
  shape   ; a Float, greater than 0
  rate    ; a Float, greater than 0

  (method %from (self) %zero)

  (method density (self x)
    (let ((x (float-of x)) (shape (field (lit shape))) (rate (field (lit rate))))
      (match
        ((f-lt x %zero) %zero)
        ((if (f-lt %zero x) #f #t)
          (match ((f-lt shape %one) %infinity) ((f-lt %one shape) %zero) (#t rate)))
        (#t (%exp (f-sub (f-sub (f-add (f-mul shape (%log rate)) (f-mul (f-sub shape %one) (%log x)))
                                (f-mul rate x))
                         (%lgamma shape)))))))
  (method cumulative (self x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) (%gamma-lower (field (lit shape)) (f-mul (field (lit rate)) x)) %zero)))
  (method survival (self x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) (%gamma-upper (field (lit shape)) (f-mul (field (lit rate)) x)) %one)))
  (method mean (self) (f-div (field (lit shape)) (field (lit rate))))
  (method variance (self) (f-div (field (lit shape)) (%square (field (lit rate))))))

; The standardized mean's distribution of its degrees of freedom v (the
; t distribution of statistics texts), on the whole
; line and even about 0.  Its density is (1 + x^2/v)^(-(v + 1)/2) over
; the root of v times B(v/2, 1/2).  The probability beyond |x| on one
; side is half the regularized incomplete beta I_w(v/2, 1/2) at
; w = v / (v + x^2), with 1 less w worked out as x^2 / (v + x^2).  The
; mean is 0 above 1 degree of freedom and infinite to there; the variance
; is v / (v - 2) above 2, infinite from 1 to 2 and not a number to 1.
(def-class StandardizedMean (extends Distribution)
  freedom   ; a Float, greater than 0

  ; The probability of a value beyond the distance |x| from 0, on one side.
  (method %tail (self x)
    (let ((v (field (lit freedom))) (xx (%square x)))
      (let ((sum (f-add v xx)))
        (f-mul %half (%beta-regular (f-mul %half v) %half (f-div v sum) (f-div xx sum))))))

  (method density (self x)
    (let ((x (float-of x)) (v (field (lit freedom))))
      (let ((h (f-mul %half (f-add v %one))))
        (%exp (f-sub (f-sub (f-sub (%lgamma h) (%lgamma (f-mul %half v)))
                            (f-mul %half (%log (f-mul v pi))))
                     (f-mul h (%log1p (f-div (%square x) v))))))))
  (method cumulative (self x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) (f-sub %one (self %tail x)) (self %tail x))))
  (method survival (self x)
    (let ((x (float-of x)))
      (if (f-lt %zero x) (self %tail x) (f-sub %one (self %tail x)))))
  (method mean (self) (if (f-lt %one (field (lit freedom))) %zero %infinity))
  (method variance (self)
    (let ((v (field (lit freedom))))
      (match
        ((f-lt %two v) (f-div v (f-sub v %two)))
        ((f-lt %one v) %infinity)
        (#t %not-a-number)))))

; The F distribution of two degrees of freedom, a above and b below, on
; 0 up: the ratio of two chi-squareds each over its freedom.  Its
; cumulative is the regularized incomplete beta I_w(a/2, b/2) at
; w = a x / (a x + b), and its survival the mirrored I at b / (a x + b).
; At x 0 the density is infinite for a below 2, 1 at 2 and 0 above.  The
; mean is b / (b - 2) above 2 and infinite to there; the variance is
; 2 b^2 (a + b - 2) / (a (b - 2)^2 (b - 4)) above 4 and infinite to
; there.
(def-class VarianceRatio (extends Distribution)
  upper   ; a Float, greater than 0: the freedom of the variance above
  lower   ; a Float, greater than 0: the freedom of the variance below

  (method %from (self) %zero)

  (method density (self x)
    (let ((x (float-of x)) (a (field (lit upper))) (b (field (lit lower))))
      (match
        ((f-lt x %zero) %zero)
        ((if (f-lt %zero x) #f #t)
          (match ((f-lt a %two) %infinity) ((f-lt %two a) %zero) (#t %one)))
        (#t
          (let ((ha (f-mul %half a)) (hb (f-mul %half b)))
            (%exp (f-sub (f-sub (f-add (f-add (f-mul ha (%log a)) (f-mul hb (%log b)))
                                       (f-mul (f-sub ha %one) (%log x)))
                                (f-mul (f-add ha hb) (%log (f-add b (f-mul a x)))))
                         (%log-beta ha hb))))))))
  (method cumulative (self x)
    (let ((x (float-of x)) (a (field (lit upper))) (b (field (lit lower))))
      (if (f-lt %zero x)
        (let ((sum (f-add (f-mul a x) b)))
          (%beta-regular (f-mul %half a) (f-mul %half b) (f-div (f-mul a x) sum) (f-div b sum)))
        %zero)))
  (method survival (self x)
    (let ((x (float-of x)) (a (field (lit upper))) (b (field (lit lower))))
      (if (f-lt %zero x)
        (let ((sum (f-add (f-mul a x) b)))
          (%beta-regular (f-mul %half b) (f-mul %half a) (f-div b sum) (f-div (f-mul a x) sum)))
        %one)))
  (method mean (self)
    (let ((b (field (lit lower))))
      (if (f-lt %two b) (f-div b (f-sub b %two)) %infinity)))
  (method variance (self)
    (let ((a (field (lit upper))) (b (field (lit lower))))
      (match
        ((f-lt %four b)
          (f-div (f-mul (f-mul %two (%square b)) (f-sub (f-add a b) %two))
                 (f-mul (f-mul a (%square (f-sub b %two))) (f-sub b %four))))
        (#t %infinity)))))

(doc (provide x/num/distribution Distribution)
  "Probability distributions as values: the Distribution class makes the normal, uniform, exponential, gamma, chi-squared, standardized-mean and variance-ratio distributions from their parameters, each answering its density, cumulative, survival and quantile, mean, variance and deviation."
  (example "((Distribution normal 0 1) quantile 0.5)" "0.0"))
