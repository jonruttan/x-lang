; decimal.x -- Arbitrary-precision decimal floating-point
; lint-known: %bigint %bigint? %big-limbs %bigint-digits-per-limb
; lint-known: %make-complex complex?
; (The first row is num/bigint.x's -- its handle, its predicate, and the
; base-10 limb storage %dec-ndigits counts through; the second is
; num/complex.x's.  The tower supplies both in load order, decimal.x
; imports bigint outright, and the complex references are filed with the
; pact so they run only when complex loaded.)
;
; Decimal values are stored as (significand . exponent) where:
;   significand = an exact integer -- native INT, promoting to BIGINT
;   exponent    = a native INT
; and the value is significand * 10^exponent.  The constructor CANONICALIZES
; by stripping trailing zeros from the significand (raising the exponent to
; match), so one value has exactly one storage form: 1.50d and 1.5d are the
; same pair, zero is (0 . 0), and `=` is a pair compare rather than a walk.
;
; WHAT ROUNDS AND WHAT DOES NOT.  + - * % are EXACT -- the significand grows
; to whatever the answer needs, which is the whole point of the type and the
; reason (+ 0.1d 0.2d) is 0.3d where the double is 0.30000000000000004.
; / cannot be (1/3 has no finite decimal), so division is the operation that
; rounds: to (Decimal precision) significant digits, half-even.  sqrt, ln,
; exp and log10 round for the same reason.  Nothing else does, and no
; operation silently loses digits to a context the caller did not set.
;
; Promotion chain: int -> bigint -> rational -> float -> decimal -> complex.
; Decimal sits above float because the widening is EXACT: every finite IEEE
; double is a finite decimal (m * 2^-k = m * 5^k * 10^-k), so a mixed pair
; promotes without inventing digits.  Complex still absorbs decimal, as it
; absorbs every real.
(import x/num/bigint)
(import x/num/float)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-from-cell (prim-ref 'type 'from-cell))
(def %type-push-op (prim-ref 'type 'push-op))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref 'type 'make-instance))
(def %make-type (prim-ref 'type 'make))
(def %type-of (prim-ref 'type 'of))
(def %type? (prim-ref 'type '?))
; Fetch the char/int cast from the catalog (ns `char` utility members de-registered, R5).
(def %char->integer (prim-ref 'char '->int))

; Forward-declare the handle and the reader (set below, after make-type).
(def %decimal ())
(def %dec-read ())

; --- Context ---
; The significant digits / and sqrt round to.  34 is decimal128's
; coefficient width: wide enough that a double's 17 round-trip digits pass
; through a division untouched, narrow enough that a quotient terminates.
(def %dec-prec 34)
; Positional printing budget: how many zeros of padding a plain rendering
; may carry before the scientific form takes over.  1e-25d spelled out is
; 24 leading zeros and unreadable; 0.00001d is not.
(def %dec-plain-pad 20)

(note "Exact integer helpers")

; --- Exact integer helpers ---
; The ambient + - * are bigint's overflow-promoting variadics, so the
; significand grows past the native word on its own.  %int/ %int% %int<
; %int= are the DISPATCHING C binaries: they route a bigint operand through
; bigint's type ops and never overflow (division cannot).  That split is
; deliberate -- a plain %int* here would wrap silently at 2^63.

(def %dec-abs (fn (_ n) (if (%int< n 0) (%int- 0 n) n)))

; base^n by squaring, n >= 0.  Powers of 10 scale significands, 2 and 5
; decompose a double's binary exponent (see %dec-from-float).
(def %dec-powi
  (fn (self b n)
    (if (%int= n 0) 1
      (if (%int= (%int% n 2) 0)
        (let ((h (self b (%int/ n 2)))) (* h h))
        (* b (self b (%int- n 1)))))))

(def %dec-pow10 (fn (_ n) (%dec-powi 10 n)))

; The most decimal digits a divisor can carry and still be ONE bigint limb.
; That is the line between bigint's single-limb fast path -- a linear walk --
; and its general multi-limb long division, and it is the difference between
; a rounding that costs 7ms and one that costs 129.  Every power-of-ten
; division in this file goes a bite at a time for that reason.
(def %dec-bite (%int- %bigint-digits-per-limb 1))
(def %dec-bite-div (%dec-pow10 %dec-bite))

; v / 10^d, truncating toward zero, in bites.
(def %dec-drop
  (fn (self v d)
    (if (not (%int< 0 d)) v
      (if (%int< %dec-bite d)
        (self (%int/ v %dec-bite-div) (%int- d %dec-bite))
        (%int/ v (%dec-pow10 d))))))

; Decimal digit count of |n| -- 1 for zero.
;
; NOT through the string door, though that is the one line it would take:
; every series term below asks for this several times, and rendering a
; bigint allocates a string per limb.  A native int divides down in at most
; nineteen steps; a bigint is (limbs - 1) FULL limbs of
; %bigint-digits-per-limb plus whatever its top limb carries, which one
; walk of the limb list gives up.  Reaching into bigint's storage for that
; is the same reach float.x makes for %bigint-base, and for the same
; reason: base 10^k limbs are a DECIMAL fact about the neighbour, not an
; implementation detail that could quietly become binary.
(def %dec-ndigits
  (fn (_ n)
    (let ()
      (def %count
        (fn (self v acc)
          (if (%int< v 10) acc (self (%int/ v 10) (%int+ acc 1)))))
      (if (%bigint? n)
        (let ()
          (def %walk
            (fn (self l k)
              (if (null? (rest l))
                (%int+ (%int* k %bigint-digits-per-limb) (%count (first l) 1))
                (self (rest l) (%int+ k 1)))))
          (%walk (%big-limbs n) 0))
        (%count (%dec-abs n) 1)))))

(note "Construction")

; --- Construction ---

; The last decimal digit of |n|, without a division: base 10^k limbs put it
; in the LOW limb, where it is a native modulo.  %make-dec asks this of
; every value the module builds, and the common answer -- "not a zero,
; nothing to strip" -- must not cost a bigint long division to hear.
(def %dec-low-digit
  (fn (_ n)
    (%int% (if (%bigint? n) (first (%big-limbs n)) (%dec-abs n)) 10)))

; Canonical form: strip trailing zeros, raising the exponent to match.
; Zero collapses to (0 . 0) so it has one spelling, not one per scale.
(def %dec-strip
  (fn (self sig exp)
    (if (%int= sig 0) (pair 0 0)
      (if (%int= (%dec-low-digit sig) 0)
        (self (%int/ sig 10) (%int+ exp 1))
        (pair sig exp)))))

(def %make-dec
  (fn (_ sig exp) (%make-instance %decimal (%dec-strip sig exp))))

(def %dec-sig (fn (_ x) (first (first x))))
(def %dec-exp (fn (_ x) (rest (first x))))

; The smaller of two exponents -- the scale an exact pairwise operation
; lands on.
(def %dec-min-exp
  (fn (_ a b)
    (let ((ea (%dec-exp a)) (eb (%dec-exp b)))
      (if (%int< ea eb) ea eb))))

; Both significands restated at that common exponent: (sa . sb).  The
; scaling is exact, which is why + - and % need no precision at all.
(def %dec-align
  (fn (_ a b)
    (let ((ea (%dec-exp a)) (eb (%dec-exp b)))
      (if (%int< ea eb)
        (pair (%dec-sig a) (* (%dec-sig b) (%dec-pow10 (%int- eb ea))))
        (pair (* (%dec-sig a) (%dec-pow10 (%int- ea eb))) (%dec-sig b))))))

(note "Rounding")

; --- Rounding ---

; Round the MAGNITUDE m (m >= 0) to PREC significant digits, half-even,
; returning (significand . exponent).  STICKY says nonzero digits were
; already dropped below m -- division's remainder -- which matters at an
; exact half and nowhere else: without it (/ 1d 3d) and a true tie are
; indistinguishable at the last digit.  PREC may be zero or negative
; (rounding away every digit); the answer is then 0 at the right scale.
;
; IN LIMB-SIZED BITES, and that is a measurement rather than a taste.  The
; obvious spelling -- q = m / 10^(d-prec), r the remainder -- divides a
; double-width significand by a fifty-digit power of ten, which is bigint's
; general multi-limb long division, and it timed at 129ms per call where the
; multiply feeding it took 3.5.  Every series term rounds once, so that one
; line was the entire cost of a logarithm.
;
; A divisor BELOW bigint's base is a single limb, and single-limb division
; is the fast path: one linear walk.  So the discarded digits come off a
; limb's worth at a time, each bite a fast division, and the sticky bit
; accumulates as it goes.  The deciding digit is the last one peeled.
(def %dec-round-mag
  (fn (_ m exp prec sticky)
    (let ((d (%dec-ndigits m)))
      (if (not (%int< prec d)) (pair m exp)
        ; Dropping more digits than there are: everything left of the
        ; deciding position is below half a unit, so the answer is zero.
        (if (%int< prec 0) (pair 0 (%int+ exp (%int- d prec)))
          (let ()
            ; Like %dec-drop, but tracking whether any bite left a remainder:
            ; that is the sticky bit, and it is free here where recovering it
            ; afterwards would cost a full-width multiply.
            (def %peel
              (fn (self v left st)
                (if (%int= left 0) (pair v st)
                  (let ((c (if (%int< %dec-bite left) %dec-bite left)))
                    (let ((div (if (%int= c %dec-bite) %dec-bite-div
                                 (%dec-pow10 c))))
                      (self (%int/ v div) (%int- left c)
                        (if st #t (not (%int= (%int% v div) 0)))))))))
            (def peeled (%peel m (%int- (%int- d prec) 1) sticky))
            (def t (first peeled))
            (def rd (%int% t 10))
            (def q (%int/ t 10))
            (pair
              (if (%int< 5 rd) (+ q 1)
                (if (%int= 5 rd)
                  (if (rest peeled) (+ q 1)
                    (if (%int= (%int% q 2) 0) q (+ q 1)))
                  q))
              (%int+ exp (%int- d prec)))))))))

; The adjusted exponent: the power of ten the value sits on, so |x| lies in
; [10^adj, 10^(adj+1)).  Two different adjusted exponents settle an ordering
; outright, and a series term whose adj has fallen a working precision below
; the accumulator's can no longer move it -- which is how every series below
; knows it is finished.  Zero has none; callers test the significand first.
(def %dec-adj
  (fn (_ x) (%int+ (%dec-exp x) (%int- (%dec-ndigits (%dec-sig x)) 1))))

; Restate x at exactly NEXP, rounding half-even when that drops digits.
; The exponent form is what quantize/round-to-places wants; the digit-count
; form above is what division wants.  One rounder serves both: dropping to
; NEXP is keeping (digits - (nexp - exp)) of them.
(def %dec-rescale
  (fn (_ x nexp)
    (let ((exp (%dec-exp x)) (sig (%dec-sig x)))
      (if (not (%int< exp nexp))
        (%make-dec (* sig (%dec-pow10 (%int- exp nexp))) nexp)
        (let ((m (%dec-abs sig)))
          (let ((r (%dec-round-mag m exp
                     (%int- (%dec-ndigits m) (%int- nexp exp)) #f)))
            (%make-dec
              (if (%int< sig 0) (%int- 0 (first r)) (first r))
              (rest r))))))))

; Round to at most N significant digits.  Keeping N of them is landing on
; the exponent adj - n + 1, so this is %dec-rescale with the target read
; off the value rather than passed in.  The already-short case returns x
; UNTOUCHED, which is not just a shortcut: rescaling up would pad the
; significand with zeros %make-dec then strips one at a time, and the
; series below call this on every term.
(def %dec-round-to
  (fn (_ x n)
    (if (not (%int< n (%dec-ndigits (%dec-sig x)))) x
      (%dec-rescale x (%int+ (%int- (%dec-adj x) n) 1)))))

(note "Arithmetic")

; --- Arithmetic ---

(def %dec-add
  (fn (_ a b)
    (let ((p (%dec-align a b)))
      (%make-dec (+ (first p) (rest p)) (%dec-min-exp a b)))))

(def %dec-sub
  (fn (_ a b)
    (let ((p (%dec-align a b)))
      (%make-dec (- (first p) (rest p)) (%dec-min-exp a b)))))

(def %dec-mul
  (fn (_ a b)
    (%make-dec
      (* (%dec-sig a) (%dec-sig b))
      (%int+ (%dec-exp a) (%dec-exp b)))))

(def %dec-neg
  (fn (_ x) (%make-dec (%int- 0 (%dec-sig x)) (%dec-exp x))))

; The one operation that rounds.  Scale the dividend so the quotient lands
; with at least one digit past the precision -- k = prec + 1 + digits(b) -
; digits(a), clamped at 0 -- then round that guard digit away half-even with
; the division's remainder as the sticky bit.  The clamp is safe: k goes
; negative only when a already outruns b by more than prec + 1 digits, and
; the quotient is then long enough on its own.
; The division proper, to P significant digits.  P is a parameter rather
; than a read of %dec-prec because the series below divide at a WORKING
; precision -- guard digits the caller never sees -- and threading it is
; the honest way to say so: a set!/restore of the module's precision would
; leave the wrong value behind the first time something raised mid-series.
(def %dec-div-at
  (fn (_ a b p)
    (let ((sa (%dec-sig a)) (sb (%dec-sig b)))
      (if (%int= sb 0)
        (Err raise 'value "Decimal /: division by zero" b)
        (if (%int= sa 0) (%make-dec 0 0)
          (let ((k (%int+ (%int+ p 1)
                     (%int- (%dec-ndigits sb) (%dec-ndigits sa)))))
            (let ((k2 (if (%int< k 0) 0 k)))
              (let ((n (* (%dec-abs sa) (%dec-pow10 k2)))
                    (m (%dec-abs sb)))
                (let ((r (%dec-round-mag (%int/ n m)
                           (%int- (%int- (%dec-exp a) (%dec-exp b)) k2)
                           p
                           (not (%int= (%int% n m) 0)))))
                  (%make-dec
                    (if (if (%int< sa 0) (not (%int< sb 0)) (%int< sb 0))
                      (%int- 0 (first r))
                      (first r))
                    (rest r)))))))))))

(def %dec-div (fn (_ a b) (%dec-div-at a b %dec-prec)))

; Truncating remainder -- a - b*trunc(a/b) -- matching int %, float fmod and
; rational %.  Exact: both sides align onto one scale and the quotient is an
; integer division there, so no precision is consulted.
(def %dec-mod
  (fn (_ a b)
    (let ((p (%dec-align a b)))
      (let ((na (first p)) (nb (rest p)))
        (if (%int= nb 0)
          (Err raise 'value "Decimal %: division by zero" b)
          (%make-dec
            (%int- na (* nb (%int/ na nb)))
            (%dec-min-exp a b)))))))

(note "Comparison")

; --- Comparison ---

; -1, 0 or 1.  Signs decide first, then ADJUSTED EXPONENTS (exp + digits,
; the power of ten the value sits on): |x| lives in [10^adj, 10^(adj+1)),
; so two different adjusted exponents settle the order without scaling
; anything.  Only a tie there pays for an alignment -- which is what makes
; (< 1e-1000d 1e1000d) a digit count rather than a 2000-digit subtraction.
(def %dec-cmp
  (fn (_ a b)
    (let ((sa (%dec-sig a)) (sb (%dec-sig b)))
      (match
        ((if (%int= sa 0) (%int= sb 0) #f) 0)
        ((%int= sa 0) (if (%int< sb 0) 1 -1))
        ((%int= sb 0) (if (%int< sa 0) -1 1))
        ((if (%int< sa 0) (not (%int< sb 0)) #f) -1)
        ((if (%int< sb 0) (not (%int< sa 0)) #f) 1)
        (#t
          (let ((adja (%dec-adj a)) (adjb (%dec-adj b)))
            (let ((mag
                    (if (%int= adja adjb)
                      (let ((p (%dec-align a b)))
                        (let ((ma (%dec-abs (first p)))
                              (mb (%dec-abs (rest p))))
                          (if (%int< ma mb) -1 (if (%int= ma mb) 0 1))))
                      (if (%int< adja adjb) -1 1))))
              (if (%int< sa 0) (%int- 0 mag) mag))))))))

(def %dec-lt (fn (_ a b) (%int< (%dec-cmp a b) 0)))

; Canonical storage buys this: equal values ARE the same pair, so equality
; is two integer compares and never an alignment.
(def %dec-eq
  (fn (_ a b)
    (if (%int= (%dec-sig a) (%dec-sig b))
      (%int= (%dec-exp a) (%dec-exp b))
      #f)))

(note "Roots and powers")

; --- Roots and powers ---

; Integer square root by Newton, descending from an over-estimate
; (10^ceil(d/2) >= sqrt(n) because n < 10^d), so the iteration lands on
; floor(sqrt(n)) and stops the first time it stops shrinking.
(def %dec-isqrt
  (fn (_ n)
    (if (%int< n 2) n
      (let ()
        (def %go
          (fn (self x)
            (let ((y (%int/ (+ x (%int/ n x)) 2)))
              (if (%int< y x) (self y) x))))
        (%go (%dec-pow10 (%int/ (%int+ (%dec-ndigits n) 1) 2)))))))

; sqrt to (Decimal precision) significant digits.  Scale the significand up
; by an EVEN power of ten large enough that the integer root carries about
; 2*prec + 2 digits, take the integer root there, then round the surplus
; away with "the root was not exact" as the sticky bit.
(def %dec-sqrt
  (fn (_ x)
    (let ((sig (%dec-sig x)) (exp (%dec-exp x)))
      (if (%int< sig 0)
        (Err raise 'value "Decimal sqrt: no real root of a negative" x)
        (if (%int= sig 0) (%make-dec 0 0)
          (let ((want (%int- (%int+ (* 2 %dec-prec) 2) (%dec-ndigits sig))))
            (let ((s0 (if (%int< want 0) 0 want)))
              ; The shift must leave exp - s even: the halved exponent is
              ; the root's, and half of an odd number is not a scale.
              (let ((s (if (%int= (%int% (%int- exp s0) 2) 0) s0 (%int+ s0 1))))
                (let ((n (* sig (%dec-pow10 s))))
                  (let ((r (%dec-isqrt n)))
                    (let ((rr (%dec-round-mag r (%int/ (%int- exp s) 2)
                                %dec-prec (not (%int= (* r r) n)))))
                      (%make-dec (first rr) (rest rr)))))))))))))

; x^n for an integer n, by squaring.  A non-negative exponent is EXACT (it
; is repeated multiplication and nothing else); a negative one is one
; division, so it rounds exactly once rather than per squaring.
(def %dec-pow
  (fn (_ x n)
    (if (%int< n 0)
      (%dec-div (%make-dec 1 0) (%dec-pow x (%int- 0 n)))
      (let ()
        (def %go
          (fn (self acc b e)
            (if (%int= e 0) acc
              (self
                (if (%int= (%int% e 2) 0) acc (%dec-mul acc b))
                (%dec-mul b b)
                (%int/ e 2)))))
        (%go (%make-dec 1 0) x n)))))

(note "Logarithms and the exponential")

; --- Logarithms and the exponential ---
;
; There is no libm here.  Float's sin/log/exp are one dlsym away because a
; double is what libm computes in; an arbitrary-precision decimal is not,
; so these three ARE the implementation rather than a call to one.
;
; The shape all three share: reduce the argument into a window where a
; series converges quickly, run the series at prec + guard digits, undo the
; reduction, round ONCE at the end.  The guard digits are what let every
; truncation inside the series sit far enough below the answer's last digit
; that it cannot move it.
(def %dec-guard 10)

; --- The series run in FIXED POINT, not in decimals ---
;
; A term is an INTEGER at a fixed scale: v stands for v * 10^S, with the same
; S for every term of one series.  At that scale addition is integer
; addition -- no alignment, no exponent arithmetic, no construction, no
; canonicalisation, no rounding -- and a term that reaches zero has fallen
; off the bottom of the working precision, which is the stopping condition
; for free.  Only multiplication does any work: the product sits at 2S and
; comes back to S by dropping -S digits, one %dec-drop.
;
; Measured, at 34 digits: a decimal-valued term cost ~19ms (a multiply, two
; roundings, a divide, an add, each building and canonicalising a fresh
; instance); the same term in fixed point costs a multiply, a drop, a small
; divide and an integer add.
;
; THE SCALE IS THE ACCURACY ARGUMENT, and the two series choose differently.
; atanh scales RELATIVE to its argument (S = adj(z) - w + 1), so a z near
; zero -- ln of an x near 1 -- keeps a full w digits instead of being
; measured against a 1 it is nowhere near.  exp scales ABSOLUTELY (S = -w)
; because its accumulator starts at 1 and stays within a factor of e of it.
; Undoing exp's reduction is the one place fixed point is wrong -- squaring
; k times grows the VALUE, which a fixed scale would have to store digit by
; digit -- so the squarings happen back in decimals, where the exponent
; carries the magnitude and the significand stays w digits.

; X as an integer at scale S, so the result stands for (result * 10^S).
; Exact whenever S is at or below x's own exponent, which is how both series
; pick it; a value finer than the scale asks for is truncated, never
; invented.
(def %dec-to-fx
  (fn (_ x s)
    (let ((d (%int- (%dec-exp x) s)))
      (if (%int< d 0)
        (%dec-drop (%dec-sig x) (%int- 0 d))
        (* (%dec-sig x) (%dec-pow10 d))))))

; atanh(z) = z + z^3/3 + z^5/5 + ... at W digits, for |z| < 1.  Both
; logarithms ride this one series: ln m is 2*atanh((m-1)/(m+1)), and the
; ln 10 that the exponent needs is built from atanh(1/3) and atanh(1/9).
; It converges on |z|^2, which is the whole reason for the folding below --
; at |z| < 0.54 it is 80-odd terms where the unfolded 2*atanh(9/11) is 250.
(def %dec-atanh
  (fn (_ z w)
    (if (%int= (%dec-sig z) 0) z
      (let ()
        ; Scale relative to z, so zf lands with w digits whatever z's size.
        (def s (%int+ (%int- (%dec-adj z) w) 1))
        (def dn (%int- 0 s))
        (def zf (%dec-to-fx z s))
        (def z2 (%dec-drop (* zf zf) dn))
        ; Terms are all of one sign (z^2 is positive), so the accumulator
        ; only grows: no cancellation, and a term that divides down to zero
        ; is a true stopping condition rather than a hope.
        (def %go
          (fn (self term n acc)
            (let ((t2 (%dec-drop (* term z2) dn)))
              (let ((add (%int/ t2 n)))
                (if (%int= add 0) acc
                  (self t2 (%int+ n 2) (+ acc add)))))))
        (%make-dec (%go zf 3 zf) s)))))

; ln 10, to at least W digits, computed once per precision.
;
; It cannot come from the reduction below -- 10 reduces to 1 * 10^1, whose
; logarithm is the very thing being asked for -- so it gets its own
; identity: ln 10 = 3 ln 2 + ln 1.25, with ln 2 = 2 atanh(1/3) and
; ln 1.25 = 2 atanh(1/9).  Both arguments are small, so the pair costs
; about 70 terms between them where the direct 2 atanh(9/11) costs 250.
(def %dec-ln10-cell (pair 0 ()))

(def %dec-ln10
  (fn (_ w)
    (if (if (%int< (first %dec-ln10-cell) w) #f #t)
      (rest %dec-ln10-cell)
      (let ()
        (def one (%make-dec 1 0))
        (def v
          (%dec-round-to
            (%dec-add
              (%dec-mul (%make-dec 6 0)
                (%dec-atanh (%dec-div-at one (%make-dec 3 0) w) w))
              (%dec-mul (%make-dec 2 0)
                (%dec-atanh (%dec-div-at one (%make-dec 9 0) w) w)))
            w))
        (%set-first! %dec-ln10-cell w)
        (%set-rest! %dec-ln10-cell v)
        v))))

; The natural logarithm at W digits (the caller rounds to the precision).
;
; x = m * 10^e, with m folded into [0.3, 3) rather than the obvious [1, 10).
; That window is chosen to keep ln m and e*ln 10 from cancelling: inside it
; e is ZERO, so an x near 1 -- where the two would cancel completely, and
; where the answer's leading digits would be the guard digits -- never meets
; ln 10 at all.  Outside it |e*ln 10| is at least 2.3 while |ln m| is at
; most 1.1, so the sum can lose about one digit and no more.  (m - 1) is
; exact besides: subtraction here never rounds.
(def %dec-ln-at
  (fn (_ x w)
    (let ((sig (%dec-sig x)))
      (if (not (%int< 0 sig))
        (Err raise 'value "Decimal ln: no logarithm of zero or a negative" x)
        (let ((nd (%dec-ndigits sig)) (adj (%dec-adj x)))
          (let ((m0 (%make-dec sig (%int- 1 nd))))
            (let ((low (%dec-lt m0 (%make-dec 3 0))))
              (let ((m (if low m0 (%make-dec sig (%int- 0 nd))))
                    (e (if low adj (%int+ adj 1)))
                    (one (%make-dec 1 0)))
                (let ((z (%dec-div-at
                           (%dec-sub m one) (%dec-add m one) w)))
                  (let ((lm (%dec-mul (%make-dec 2 0) (%dec-atanh z w))))
                    ; e is zero for every x already inside the window, and
                    ; ln 10 is a 70-term series -- so an argument near 1,
                    ; the common one, never pays for a constant it would
                    ; only multiply by nothing.
                    (if (%int= e 0) lm
                      (%dec-add lm
                        (%dec-mul (%make-dec e 0) (%dec-ln10 w))))))))))))))

(def %dec-ln
  (fn (_ x)
    (%dec-round-to
      (%dec-ln-at x (%int+ %dec-prec %dec-guard))
      %dec-prec)))

; log10 = ln x / ln 10, with one exception that is not an optimisation:
; canonical storage has already stripped an exact power of ten down to a
; significand of 1, so its exponent IS the answer, exactly, and no series
; can improve on an integer.  (Decimal log10 1000d) is 3d, not 3 followed
; by thirty-three zeros and a doubt.
(def %dec-log10
  (fn (_ x)
    (let ((sig (%dec-sig x)))
      (if (not (%int< 0 sig))
        (Err raise 'value "Decimal log10: no logarithm of zero or a negative" x)
        (if (%int= sig 1) (%make-dec (%dec-exp x) 0)
          (let ((w (%int+ %dec-prec %dec-guard)))
            (%dec-round-to
              (%dec-div-at (%dec-ln-at x w) (%dec-ln10 w) w)
              %dec-prec)))))))

; The exponential.  Named -of because %dec-exp is this file's EXPONENT
; accessor and one of the two had to give way; the accessor is read twenty
; times a line here and the function three.
;
; exp(x) = exp(x / 2^k)^(2^k), with k large enough that |r| < 1 and the
; Taylor series is 40 terms rather than unbounded.  Dividing a decimal by a
; power of two is EXACT -- 1/2 is 5/10 -- so the reduction costs digits and
; no accuracy at all, which is why it is a multiplication by 5^k here and
; not a division.  k = 4(adj+1) is enough because 16^(adj+1) > 10^(adj+1),
; and it is added to the working precision because each of the k squarings
; that undo it doubles the relative error.
(def %dec-exp-of
  (fn (_ x)
    (if (%int= (%dec-sig x) 0) (%make-dec 1 0)
      (let ()
        (def adj (%dec-adj x))
        (def k (if (%int< adj 0) 0 (%int* 4 (%int+ adj 1))))
        (def w (%int+ (%int+ %dec-prec %dec-guard) k))
        (def r
          (if (%int= k 0) x
            (%dec-mul x (%make-dec (%dec-powi 5 k) (%int- 0 k)))))
        (def rf (%dec-to-fx r (%int- 0 w)))
        (def one (%dec-pow10 w))
        ; sum r^n/n!, each term built from the last: term(n) = term(n-1)*r/n.
        (def %go
          (fn (self term n acc)
            (let ((t2 (%int/ (%dec-drop (* term rf) w) n)))
              (if (%int= t2 0) acc
                (self t2 (%int+ n 1) (+ acc t2))))))
        ; Back in decimals for the squarings: each one DOUBLES the value's
        ; magnitude, and only an exponent can carry that without paying a
        ; digit for it.
        (def %sq
          (fn (self v i)
            (if (%int= i 0) v
              (self (%dec-round-to (%dec-mul v v) w) (%int- i 1)))))
        (%dec-round-to
          (%sq (%make-dec (%go one 1 one) (%int- 0 w)) k)
          %dec-prec)))))

(note "Conversion")

; --- Text ---

; [+-]?DIGITS[.DIGITS][eE[+-]DIGITS] with an optional trailing d -- the
; literal's own text, so the reader and (Decimal from "...") share one
; parser.  The fractional digits are not a separate quantity: they are the
; significand's low end, and each one costs the exponent a step.
;
; The scanners are LOCAL defs (scoped by the let, per the tower's
; def-in-a-let idiom): nothing outside a parse has any use for "index of
; the exponent marker", and the %-global namespace is flat and shared.
(def %dec-parse
  (fn (_ text)
    (let ()
      (def %chr (fn (_ s i) (%char->integer (%str-ref s i))))
      ; Index of the first byte C in [i, len), or ().
      (def %find
        (fn (self s i len c)
          (if (not (%int< i len)) ()
            (if (%int= (%chr s i) c) i (self s (%int+ i 1) len c)))))
      ; Index of the exponent marker, either case.
      (def %find-exp
        (fn (self s i len)
          (if (not (%int< i len)) ()
            (let ((c (%chr s i)))
              (if (if (%int= c 101) #t (%int= c 69)) i
                (self s (%int+ i 1) len))))))
      ; Digits [start, end) as an exact integer, nine at a time: a
      ; nine-digit chunk always fits a native int, and the ambient * and +
      ; promote the accumulator once it outgrows one.
      (def %digits
        (fn (self s start end acc)
          (if (not (%int< start end)) acc
            (let ((n (if (%int< (%int+ start 9) end) 9 (%int- end start))))
              (self s (%int+ start n) end
                (+ (* acc (%dec-pow10 n))
                   (%str->number (%substring s start (%int+ start n)))))))))
      ; Is [i, len) a non-empty run of digits?  The gate that keeps
      ; (Decimal from "abc") a RAISE: %str->number answers 0 for text it
      ; cannot read, and a numeric door that turns garbage into zero is
      ; the silent kind of wrong.
      (def %digits?
        (fn (self s i len)
          (if (not (%int< i len)) #f
            (if (%int< (%chr s i) 48) #f
              (if (%int< 57 (%chr s i)) #f
                (if (%int= (%int+ i 1) len) #t
                  (self s (%int+ i 1) len)))))))
      ; [+-]?digits as a native int, for the exponent field.
      (def %parse-exp
        (fn (_ s i len)
          (if (not (%int< i len)) 0
            (let ((c (%chr s i)))
              (if (%int= c 45)
                (%int- 0 (%str->number (%substring s (%int+ i 1) len)))
                (if (%int= c 43)
                  (%str->number (%substring s (%int+ i 1) len))
                  (%str->number (%substring s i len))))))))
      (let ((len0 (%str-length text)))
        (let ((len
                (if (%int< 0 len0)
                  (let ((c (%chr text (%int- len0 1))))
                    (if (if (%int= c 100) #t (%int= c 68)) (%int- len0 1) len0))
                  len0)))
          (let ((c0 (if (%int< 0 len) (%chr text 0) 0)))
            (let ((neg (%int= c0 45))
                  (start (if (if (%int= c0 45) #t (%int= c0 43)) 1 0)))
              (let ((epos (%find-exp text start len)))
                (let ((mend (if (null? epos) len epos))
                      (xval (if (null? epos) 0
                              (%parse-exp text (%int+ epos 1) len))))
                  (let ((dot (%find text start mend 46)))
                    (let ((iend (if (null? dot) mend dot))
                          (fstart (if (null? dot) mend (%int+ dot 1))))
                      ; Well-formed is: digits on at least one side of an
                      ; optional single point, nothing but digits on either,
                      ; and -- when there is an e -- digits after its
                      ; optional sign.  12. and .5 pass; "", "abc", "1.2.3"
                      ; and "1e" do not.
                      (if (not
                            (if (if (%digits? text start iend)
                                  (if (%int= fstart mend) #t
                                    (%digits? text fstart mend))
                                  (if (%int= start iend)
                                    (%digits? text fstart mend) #f))
                              (if (null? epos) #t
                                (let ((xs (%int+ epos 1)))
                                  (let ((c (if (%int< xs len) (%chr text xs) 0)))
                                    (%digits? text
                                      (if (if (%int= c 45) #t (%int= c 43))
                                        (%int+ xs 1) xs)
                                      len))))
                              #f))
                        (Err raise 'value
                          "Decimal from: not a decimal number" text)
                        (let ((sig (%digits text fstart mend
                                     (%digits text start iend 0))))
                          (%make-dec
                            (if neg (%int- 0 sig) sig)
                            (%int- xval (%int- mend fstart))))))))))))))))

; The value's text WITHOUT the d suffix: what (Decimal ->str) answers and
; what a host language prints.  `write` adds the suffix, because a printed
; 1.5 would read back as a FLOAT.  Local helpers, for %dec-parse's reason.
(def %dec->str
  (fn (_ x)
    (let ()
      (def %zeros
        (fn (self n acc)
          (if (%int= n 0) acc (self (%int- n 1) (%str-append acc "0")))))
      ; d.ddde<adjusted> -- the round-tripping spelling for values whose
      ; positional form would be mostly zeros.
      (def %sci
        (fn (_ s n exp)
          (%str-append
            (if (%int= n 1) s
              (%str-append (%substring s 0 1)
                (%str-append "." (%substring s 1 n))))
            (%str-append "e" (%cvt (%int+ exp (%int- n 1)) %string)))))
      (let ((sig (%dec-sig x)) (exp (%dec-exp x)))
        (let ((s (%cvt (%dec-abs sig) %string)))
          (let ((n (%str-length s)))
            (%str-append
              (if (%int< sig 0) "-" "")
              (match
                ((%int= exp 0) s)
                ((%int< 0 exp)
                 (if (%int< %dec-plain-pad exp)
                   (%sci s n exp)
                   (%str-append s (%zeros exp ""))))
                ((%int< (%int- 0 exp) n)
                 (%str-append (%substring s 0 (%int+ n exp))
                   (%str-append "." (%substring s (%int+ n exp) n))))
                ((%int< %dec-plain-pad (%int- (%int- 0 exp) n))
                 (%sci s n exp))
                (#t
                 (%str-append "0."
                   (%str-append
                     (%zeros (%int- (%int- 0 exp) n) "") s)))))))))))

; --- Numeric conversion ---

; Truncation toward zero, matching (Float ->int).
(def %dec->int
  (fn (_ x)
    (let ((sig (%dec-sig x)) (exp (%dec-exp x)))
      (if (%int< exp 0)
        (%int/ sig (%dec-pow10 (%int- 0 exp)))
        (* sig (%dec-pow10 exp))))))

; A double, EXACTLY.  The stored bit pattern gives (mantissa, binary
; exponent); a negative binary exponent is not a rounding problem but an
; identity -- m * 2^-k = m * 5^k * 10^-k -- so the decimal that comes back
; is the double's true value, all 55 digits of 0.1 included, not a
; 17-digit shortest-round-trip approximation of it.
(def %dec-from-float
  (fn (_ f)
    (let ((bits (first f)))
      (let ((em (& (>> bits 52) 2047))
            (mant (& bits (%int- (<< 1 52) 1))))
        (if (%int= em 2047)
          (Err raise 'value "Decimal from: a float inf/NaN has no decimal" f)
          (let ((m (if (%int= em 0) mant (%int+ mant (<< 1 52))))
                (e2 (if (%int= em 0) -1074 (%int- em 1075))))
            (let ((d (if (%int< e2 0)
                       (%make-dec (* m (%dec-powi 5 (%int- 0 e2))) e2)
                       (%make-dec (* m (%dec-powi 2 e2)) 0))))
              (if (%int< bits 0) (%dec-neg d) d))))))))

(note "Predicates")

; --- Predicates ---
; Private; the public API is (Decimal decimal? x).

(def %dec? (fn (_ x) (%type? x %decimal)))

; Door: coerce through the conversion catalog, so the other side may be an
; int, bigint, float, rational or numeric string.  A miss is a raise, never
; a nil into (first) -- the C core is unchecked, so the guard lives here.
(def %ensure-dec
  (fn (_ x)
    (if (%dec? x) x
      (let ((d (%cvt x %decimal)))
        (if (%dec? d) d
          (Err raise 'type "Decimal: operand not convertible to DECIMAL" x))))))

(note "Type registration")

; --- Tokenizer state machine: [+-]?DIGITS[.DIGITS][eE[+-]DIGITS]d ---
;
; The states are module-level defs, not inline closures, for the reason
; every other tower stage records: the COMPILED analyser in
; boot/tower-compiled.x captures them as free variables once, and an
; anonymous closure there is rooted by nothing after %compile-fvars is
; cleared (#49).
;
; Only the terminal `d` scores, and the score covers the suffix, so 1.5d
; (4 chars) outbids float's 1.5 (3) on the same run.  Without the suffix
; nothing here scores at all and the float reader keeps the token.

(def %dec-exp-digits ())
(set! %dec-exp-digits
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-exp-digits
      (if (= chr 100) (%score-set score 1 buffer) ()))))

(def %dec-exp-first
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-exp-digits ())))

(def %dec-exp-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-exp-digits
      (if (or (= chr 45) (= chr 43)) %dec-exp-first ()))))

(def %dec-frac ())
(set! %dec-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-frac
      (if (= chr 100) (%score-set score 1 buffer)
        (if (or (= chr 101) (= chr 69)) %dec-exp-sign ())))))

(def %dec-first-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-frac ())))

(def %dec-int ())
(set! %dec-int
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-int
      (if (= chr 100) (%score-set score 1 buffer)
        (if (= chr 46) %dec-first-frac
          (if (or (= chr 101) (= chr 69)) %dec-exp-sign ()))))))

; A lone sign must see a digit next, so `-` and `+` stay operators.
(def %dec-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %dec-int ())))

(set! %decimal
  (%make-type
    "DECIMAL"
    (list
      (pair 'write
        (fn (_ self) (display (%dec->str self) "d")))
      (pair 'analyse
        (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) %dec-int
            (if (or (= chr 45) (= chr 43)) %dec-sign ()))))
      (pair 'read (fn (_ . args) (%dec-read (first args))))
      (pair 'from
        (list
          (pair (%type-of 42) (fn (_ value) (%make-dec value 0)))
          ; A bigint instance IS an exact integer: it can be the
          ; significand as it stands, no limb walk in between.
          (pair %bigint (fn (_ value) (%make-dec value 0)))
          (pair (%type-of "") (fn (_ value) (%dec-parse value)))
          (pair %float (fn (_ value) (%dec-from-float value)))))
      (pair 'to
        (list
          (pair (%type-of 42) (fn (_ self) (%dec->int self)))
          (pair (%type-of "") (fn (_ self) (%dec->str self)))
          ; Out through the text door on purpose: strtod is correctly
          ; rounded, and re-deriving that here would be a worse copy.
          (pair %float (fn (_ self) (%cvt (%dec->str self) %float))))))))

; --- Reader (set after make-type so the closure captures the real handle) ---
(set! %dec-read
  (fn (_ . args) (%dec-parse (%buffer-token (first args)))))

(note "Operator Overrides")

; --- Type ops: the generic operators dispatch decimal operands here ---
; Handlers receive raw operands; %ensure-dec coerces the other side through
; the from-alist, so an int, bigint, float or numeric string all land.

(def %decimal-type (%type-by-atom %decimal))
(%type-push-op %decimal-type '+ (fn (_ a b) (%dec-add (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '- (fn (_ a b) (%dec-sub (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '* (fn (_ a b) (%dec-mul (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '/ (fn (_ a b) (%dec-div (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '% (fn (_ a b) (%dec-mod (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '< (fn (_ a b) (%dec-lt (%ensure-dec a) (%ensure-dec b))))
(%type-push-op %decimal-type '= (fn (_ a b) (%dec-eq (%ensure-dec a) (%ensure-dec b))))

; --- Cohort predicates ---
; number? and real? are extended IN PLACE by each tower module.  Decimal
; CHAINS rather than restating the cohort: it loads last, so the predicate
; it wraps already knows every type that came before it, and a module added
; later wraps this one in turn.

(def %dec-was-number? number?)
(def %dec-was-real? real?)

(doc number? "Test whether a value is any numeric type (now including decimals)."
  (param x ANY "Value to test")
  (returns BOOL "True if x is a number"))
(set! number? (fn (_ x) (if (%dec? x) #t (%dec-was-number? x))))

(doc real? "Test whether a value is a real number (now including decimals)."
  (param x ANY "Value to test")
  (returns BOOL "True if x is a real number"))
(set! real? (fn (_ x) (if (%dec? x) #t (%dec-was-real? x))))

(import x/sys/pact)

; --- Pairwise registrations ---
; Neither side alone can install these: each needs the other module's
; handle AND this one's operations.  Filed with the pact, they run here
; when that module loaded first, at its join when it loads later, and
; never when it never loads.

(Pact when (list 'rational)
  (fn (_ rat)
    ; rational -> decimal ROUNDS -- 1/3 has no finite decimal -- so it goes
    ; through the divider and lands on the current precision, exactly as
    ; rational -> float lands on 53 bits.  (numerator . denominator) is
    ; rational.x's payload.
    (let ((cell (%type-from-cell %decimal-type)))
      (%set-first! cell
        (pair
          (pair rat
            (fn (_ value)
              (%dec-div
                (%make-dec (first (first value)) 0)
                (%make-dec (rest (first value)) 0))))
          (first cell))))))

(Pact when (list 'complex)
  (fn (_ cx)
    ; Complex absorbs every real, decimal included, so the edge is declared
    ; on COMPLEX's from-alist: the absorbing side owns the entry.  The
    ; converter is %make-complex with a zero imaginary part -- which
    ; collapses straight back to the real, exactly as the float and
    ; rational entries do; the declaration is what the lattice reads.
    (let ((cell (%type-from-cell (%type-by-atom cx))))
      (%set-first! cell
        (pair (pair %decimal (fn (_ value) (%make-complex value 0)))
          (first cell))))
    ; complex? was bound to the number? of complex.x's load moment, so it
    ; cannot see a type registered after it.  Re-point the alias at the
    ; live predicate rather than leaving two answers in the tree.
    (set! complex? number?)))

(import x/type/class)

(def-class Decimal ()
  (static
    (method decimal? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an arbitrary-precision decimal."
        (returns BOOL "True if x is a decimal"))
      (%dec? x))
    ; --- Context ---
    (method precision (self)
      (doc "The significant digits division and sqrt round to."
        (returns INT "Current precision")
        (sample "(Decimal precision)" "34"))
      %dec-prec)
    (method precision! (self (param n INT "Significant digits, at least 1"))
      (doc "Set the significant digits division and sqrt round to. Addition, subtraction and multiplication stay exact and are unaffected."
        (returns INT "The new precision"))
      (if (%int< n 1)
        (Err raise 'value "Decimal precision!: precision must be at least 1" n)
        (do (set! %dec-prec n) n)))
    ; --- Conversions ---
    (method from (self (param x ANY "An int, bigint, float, rational, numeric string, or decimal (identity)"))
      (doc "Construct a decimal from any convertible value, through the conversion catalog. A float converts EXACTLY; a rational rounds to the current precision. Raises kind-'type when nothing converts."
        (returns DECIMAL "Decimal instance")
        (sample "(Decimal ->str (Decimal from \"1.25\"))" "\"1.25\""))
      (%ensure-dec x))
    (method make (self (param sig INT "Significand (int or bigint)")
                       (param exp INT "Power-of-ten exponent"))
      (doc "Construct the decimal sig * 10^exp directly, without going through text."
        (returns DECIMAL "Decimal instance")
        (sample "(Decimal ->str (Decimal make 125 -2))" "\"1.25\""))
      (%make-dec sig exp))
    (method significand (self (param x DECIMAL "Decimal value"))
      (doc "The decimal's significand, with trailing zeros already stripped."
        (returns INT "Significand as an exact integer"))
      (%dec-sig (%ensure-dec x)))
    (method exponent (self (param x DECIMAL "Decimal value"))
      (doc "The decimal's power-of-ten exponent."
        (returns INT "Exponent"))
      (%dec-exp (%ensure-dec x)))
    (method ->int (self (param x DECIMAL "Decimal value"))
      (doc "Convert a decimal to an exact integer by truncation toward zero."
        (returns INT "Truncated integer value"))
      (%dec->int (%ensure-dec x)))
    (method ->str (self (param x DECIMAL "Decimal value"))
      (doc "The decimal's text, without the d suffix that `write` adds for round-tripping."
        (returns STRING "Decimal text"))
      (%dec->str (%ensure-dec x)))
    (method ->float (self (param x DECIMAL "Decimal value"))
      (doc "Convert a decimal to the nearest IEEE 754 double. Lossy by definition; the rounding is strtod's."
        (returns FLOAT "Nearest double"))
      (%cvt (%dec->str (%ensure-dec x)) %float))
    ; --- Arithmetic (operands coerce via the from-alist) ---
    (method + (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Add two decimals, exactly (other numerics coerce)." (returns DECIMAL "Sum"))
      (%dec-add (%ensure-dec a) (%ensure-dec b)))
    (method - (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Subtract two decimals, exactly (other numerics coerce)." (returns DECIMAL "Difference"))
      (%dec-sub (%ensure-dec a) (%ensure-dec b)))
    (method * (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Multiply two decimals, exactly (other numerics coerce)." (returns DECIMAL "Product"))
      (%dec-mul (%ensure-dec a) (%ensure-dec b)))
    (method / (self (param a NUMBER "Dividend") (param b NUMBER "Divisor"))
      (doc "Divide two decimals, rounded half-even to the current precision (other numerics coerce)."
        (returns DECIMAL "Quotient"))
      (%dec-div (%ensure-dec a) (%ensure-dec b)))
    (method % (self (param a NUMBER "Dividend") (param b NUMBER "Divisor"))
      (doc "Truncating remainder of decimal division, exactly (other numerics coerce)."
        (returns DECIMAL "Remainder, with the dividend's sign"))
      (%dec-mod (%ensure-dec a) (%ensure-dec b)))
    (method < (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a is less than b (other numerics coerce)." (returns BOOL "True if a < b"))
      (%dec-lt (%ensure-dec a) (%ensure-dec b)))
    (method = (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a equals b (other numerics coerce)." (returns BOOL "True if a equals b"))
      (%dec-eq (%ensure-dec a) (%ensure-dec b)))
    (method compare (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Three-way comparison of two decimals (other numerics coerce)."
        (returns INT "-1 if a < b, 0 if equal, 1 if a > b"))
      (%dec-cmp (%ensure-dec a) (%ensure-dec b)))
    (method neg (self (param x NUMBER "Decimal value"))
      (doc "Negate a decimal." (returns DECIMAL "The negated value"))
      (%dec-neg (%ensure-dec x)))
    (method abs (self (param x NUMBER "Decimal value"))
      (doc "The absolute value of a decimal." (returns DECIMAL "Magnitude"))
      (let ((d (%ensure-dec x))) (if (%int< (%dec-sig d) 0) (%dec-neg d) d)))
    (method zero? (self (param x NUMBER "Decimal value"))
      (doc "Test whether a decimal is zero." (returns BOOL "True if x is zero"))
      (%int= (%dec-sig (%ensure-dec x)) 0))
    ; --- Rounding ---
    (method round (self (param x NUMBER "Decimal value")
                        (param places INT "Decimal places to keep; negative rounds to tens, hundreds, ..."))
      (doc "Round a decimal to a number of decimal places, half-even."
        (returns DECIMAL "Rounded value")
        (sample "(Decimal ->str (Decimal round 2.675d 2))" "\"2.68\""))
      (%dec-rescale (%ensure-dec x) (%int- 0 places)))
    (method rescale (self (param x NUMBER "Decimal value") (param exp INT "Target power-of-ten exponent"))
      (doc "Restate a decimal at a given exponent, rounding half-even when that drops digits. The exponent-facing form of `round`, for a caller that thinks in scales."
        (returns DECIMAL "Value at the requested exponent"))
      (%dec-rescale (%ensure-dec x) exp))
    (method trunc (self (param x NUMBER "Decimal value"))
      (doc "Truncate a decimal toward zero, as an integral decimal."
        (returns DECIMAL "Integer part"))
      (%make-dec (%dec->int (%ensure-dec x)) 0))
    (method floor (self (param x NUMBER "Decimal value"))
      (doc "The largest integral decimal not greater than x."
        (returns DECIMAL "Floor of x"))
      (let ((d (%ensure-dec x)))
        (let ((t (%make-dec (%dec->int d) 0)))
          (if (%dec-lt t d) t (if (%dec-eq t d) t (%dec-sub t (%make-dec 1 0)))))))
    (method ceil (self (param x NUMBER "Decimal value"))
      (doc "The smallest integral decimal not less than x."
        (returns DECIMAL "Ceiling of x"))
      (let ((d (%ensure-dec x)))
        (let ((t (%make-dec (%dec->int d) 0)))
          (if (%dec-lt d t) t (if (%dec-eq t d) t (%dec-add t (%make-dec 1 0)))))))
    ; --- Roots and powers ---
    (method sqrt (self (param x NUMBER "Non-negative decimal"))
      (doc "The square root of a decimal, rounded half-even to the current precision."
        (returns DECIMAL "Square root of x"))
      (%dec-sqrt (%ensure-dec x)))
    (method pow (self (param x NUMBER "Base") (param n INT "Integer exponent"))
      (doc "Raise a decimal to an integer power. A non-negative exponent is exact; a negative one divides once, at the current precision."
        (returns DECIMAL "x raised to the power n"))
      (%dec-pow (%ensure-dec x) n))
    ; --- Logarithms and the exponential ---
    ; Computed by series at the current precision plus guard digits, then
    ; rounded once -- there is no libm for a decimal this wide.
    (method exp (self (param x NUMBER "Exponent"))
      (doc "Raise e to a power, to the current precision."
        (returns DECIMAL "e raised to the power x")
        (sample "(Decimal ->str (Decimal exp 0d))" "\"1\""))
      (%dec-exp-of (%ensure-dec x)))
    (method ln (self (param x NUMBER "Positive decimal"))
      (doc "The natural logarithm of a decimal, to the current precision. Raises kind-'value for zero or a negative."
        (returns DECIMAL "Natural logarithm of x")
        (sample "(Decimal ->str (Decimal ln 1d))" "\"0\""))
      (%dec-ln (%ensure-dec x)))
    (method log10 (self (param x NUMBER "Positive decimal"))
      (doc "The base-10 logarithm of a decimal, to the current precision. An exact power of ten answers its exponent exactly. Raises kind-'value for zero or a negative."
        (returns DECIMAL "log10(x)")
        (sample "(Decimal ->str (Decimal log10 1000d))" "\"3\""))
      (%dec-log10 (%ensure-dec x)))))

; Value dispatch (subject-last): (1.5d decimal?) -> (Decimal decimal? 1.5d).
(def %type-push-call (prim-ref 'type 'push-call))
(%type-push-call %decimal-type (%class-call-handler Decimal))

; Join the pact last, once the module is fully usable: any registration
; waiting on decimal fires against the finished class and type ops.
(Pact join 'decimal %decimal)

(doc (provide x/num/decimal Decimal)
  (note "Literal syntax: 1.5d, -0.001d, 3d, 1.5e-8d. The generic operators")
  (note "dispatch decimal operands through the type ops; mixed operands")
  (note "resolve by the from-relation, and a double widens EXACTLY.")
  (note "+ - * % are exact; / sqrt ln exp log10 round half-even to")
  (note "(Decimal precision).  The transcendentals are series, not libm --")
  (note "correct to the last digit; the series run in fixed point, so a")
  (note "34-digit ln costs about a tenth of a second, not ten.")
  (example "(Decimal ->str (+ 0.1d 0.2d))" "\"0.3\"")
  "Arbitrary-precision decimal floating-point, homed on the Decimal class.")
