; rational.x -- Rational number type (exact fractions)
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


;
; Rational values are stored as (numerator . denominator) pairs,
; auto-reduced via GCD on construction. The tokenizer matches
; [+-]?[0-9]+/[0-9]+ and outscores the integer tokenizer.
;
; Promotion chain: integer -> rational -> float
; Forward-declare reader and type handle

(def %rational-read ())
(def %rational ())
; --- GCD (Euclidean algorithm) ---

(def %gcd
  (fn (self a b)
    (if (%int= b 0) a
      (self b (%int- a (%int* b (%int/ a b)))))))

(def %abs (fn (_ n) (if (%int< n 0) (%int- 0 n) n)))
; --- Find '/' position in string ---

(def %rat-find-slash
  (fn (self s i len)
    (if (>= i len) ()
      (if (= (%cvt (str-ref s i) %int) 47)
        i
        (self s (%int+ i 1) len)))))
; --- Constructor: auto-reduce and normalize sign ---

(def %make-rational
  (fn (_ n d)
    (if (%int= d 0) (error "division by zero")
      (let ((g (%gcd (%abs n) (%abs d))))
        (let ((rn (%int/ n g)) (rd (%int/ d g)))
          ; Normalize: denominator always positive
          (if (%int< rd 0)
            (%make-instance %rational (pair (%int- 0 rn) (%int- 0 rd)))
            ; Reduce to integer if denominator is 1
            (if (%int= rd 1) rn
              (%make-instance %rational (pair rn rd)))))))))
; --- Tokenizer state machine: [+-]?[0-9]+/[0-9]+ ---
; After '/' — must see at least one digit

(def %rat-denom ())

(set! %rat-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

(def %rat-first-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      ())))
; Integer digits before '/'

(def %rat-numer ())

(set! %rat-numer
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %rat-numer
      (if (= chr 47) %rat-first-denom ()))))
; --- Rational type ---

(set! %rational
  (%make-type
    "RATIONAL"
    (list
      (pair
        'write
        (fn (_ self)
          (display (first (first self)))
          (display "/")
          (display (rest (first self)))))
      (pair
        'analyse
        (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57))
            %rat-numer
            (if (= chr 45)
              (fn (_ buf sc c0)
                (if (and (>= c0 48) (<= c0 57))
                  %rat-numer
                  ()))
              (if (= chr 43)
                (fn (_ buf sc c0)
                  (if (and (>= c0 48) (<= c0 57))
                    %rat-numer
                    ()))
                ())))))
      (pair 'read (fn (_ . args) (%rational-read (first args))))
      (pair
        'from
        (list
          (pair (%type-of 42) (fn (_ value) (%make-rational value 1)))
          (pair
            (%type-of "")
            (fn (_ value)
              (let ((pos (%rat-find-slash value 0 (str-length value))))
                (if pos
                  (%make-rational
                    (%cvt (substring value 0 pos) %int)
                    (%cvt
                      (substring value (%int+ pos 1) (str-length value)) %int))
                  ()))))))
      (pair
        'to
        (list
          (pair (%type-of 42)
            (fn (_ self) (%int/ (first (first self)) (rest (first self)))))
          (pair %float
            (fn (_ self)
              (%f-div
                (%make-instance %float (%int->float (first (first self))))
                (%make-instance %float (%int->float (rest (first self)))))))
          (pair (%type-of "")
            (fn (_ self)
              (%str-append
                (%str-append (%cvt (first (first self)) %string) "/")
                (%cvt (rest (first self)) %string)))))))))
; --- Predicates ---

(note "Predicates")

; Private predicates/accessors; the public API is the Rational class.
(def %rational? (fn (_ x) (if (%type? x %rational) #t (%int-number? x))))
(def %numer-of
  (fn (_ x) (if (%type? x %rational) (first (first x)) x)))
(def %denom-of
  (fn (_ x) (if (%type? x %rational) (rest (first x)) 1)))

; --- Arithmetic ---

(note "Arithmetic")

(def %rat-numer-of %numer-of)
(def %rat-denom-of %denom-of)

(def %rat-add
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int+ (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))

(def %rat-sub
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int- (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))

(def %rat-mul
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bn) (%int* ad bd)))))

(def %rat-div
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bd) (%int* ad bn)))))
; --- Comparisons ---

(note "Comparison")

(def %rat-lt
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int< (%int* an bd) (%int* bn ad)))))

; Truncating modulo, matching int % and float fmod: a - b*trunc(a/b).
; trunc(a/b) = C integer division of the cross products.
(def %rat-mod
  (fn (_ a b)
    (let ((q (%int/ (%int* (%rat-numer-of a) (%rat-denom-of b))
                    (%int* (%rat-denom-of a) (%rat-numer-of b)))))
      (%rat-sub a (%rat-mul b (%make-rational q 1))))))

(def %rat-eq
  (fn (_ a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int= (%int* an bd) (%int* bn ad)))))
; --- Type ops + the / promotion policy ---

(note "Operator Overrides")

; Float absorbs rationals under the from-relation: declare the conversion on
; float's from-alist (the same late-registration precedent float.x uses for
; bignum). rational -> float = numerator/denominator in float space.
(def %float-from-cell (%type-from-cell (%type-by-atom %float)))
(set-first! %float-from-cell
  (pair
    (pair %rational
      (fn (_ self)
        (%f-div
          (%make-instance %float (%int->float (first (first self))))
          (%make-instance %float (%int->float (rest (first self)))))))
    (first %float-from-cell)))

(def %rat? (fn (_ x) (%type? x %rational)))

(def %ensure-rat
  (fn (_ x) (if (%rat? x) x (%make-rational x 1))))

; Generic-operator handlers: the C binaries dispatch rational operands here.
; The non-rational side is an int (float absorbs rationals via from; bignum
; and rational do not declare each other, so that mix falls through -- as
; before this conversion).
(def %rational-ts (%type-by-atom %rational))
(%type-push-op %rational-ts '+ (fn (_ a b) (%rat-add (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '- (fn (_ a b) (%rat-sub (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '* (fn (_ a b) (%rat-mul (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '/ (fn (_ a b) (%rat-div (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '< (fn (_ a b) (%rat-lt (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '= (fn (_ a b) (%rat-eq (%ensure-rat a) (%ensure-rat b))))
(%type-push-op %rational-ts '% (fn (_ a b) (%rat-mod (%ensure-rat a) (%ensure-rat b))))

; Integer division that produces rational when not exact
(def %exact-div
  (fn (_ a b)
    (if (= (%int- a (%int* b (%int/ a b))) 0)
      (%int/ a b)
      (%make-rational a b))))

; / policy: this module OWNS the variadic / (one policy owner per operator --
; bignum owns + - * overflow promotion). Both-plain-int division promotes to
; rational when inexact; anything typed flows through the dispatching C binary
; (rational/float/bignum handlers take it from there). Unary (/ x) = (/ 1 x).
(def %rat-div-policy
  (fn (_ a b)
    (if (if (%int-number? a) (%int-number? b) #f)
      (%exact-div a b)
      (%int/ a b))))

(doc / "Divide numbers; integer division produces rationals when not exact."
  (param args NUMBER "Numbers to divide")
  (returns NUMBER "Quotient"))
(set! /
  (fn (_ . args)
    (if (null? args) 1
      (if (null? (rest args))
        (%rat-div-policy 1 (first args))
        (fold %rat-div-policy (first args) (rest args))))))

; --- Reader ---

(set! %rational-read
  (fn (_ . args)
    (let ((tok (%buffer-token (first args))))
      (let ((pos (%rat-find-slash tok 0 (str-length tok))))
        (if pos
          (%make-rational
            (%cvt (substring tok 0 pos) %int)
            (%cvt
              (substring tok (%int+ pos 1) (str-length tok)) %int))
          ())))))

(import x/type/class)

(def-class Rational ()
  (static
    (method rational? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a rational number or integer."
        (returns BOOL "True if x is rational or integer"))
      (%rational? x))
    (method exact? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an exact number."
        (returns BOOL "True if x is exact (rational or integer)"))
      (%rational? x))
    (method numerator (self (param x RATIONAL|INT "Rational or integer"))
      (doc "Return the numerator of a rational number."
        (returns INT "Numerator of the rational, or the integer itself"))
      (%numer-of x))
    (method denominator (self (param x RATIONAL|INT "Rational or integer"))
      (doc "Return the denominator of a rational number."
        (returns INT "Denominator of the rational, or 1 for integers"))
      (%denom-of x))
    (method + (self (param a RATIONAL|INT "First operand") (param b RATIONAL|INT "Second operand"))
      (doc "Add two rationals (ints coerce)." (returns RATIONAL|INT "Sum, reduced to lowest terms"))
      (%rat-add (%ensure-rat a) (%ensure-rat b)))
    (method - (self (param a RATIONAL|INT "First operand") (param b RATIONAL|INT "Second operand"))
      (doc "Subtract two rationals (ints coerce)." (returns RATIONAL|INT "Difference, reduced to lowest terms"))
      (%rat-sub (%ensure-rat a) (%ensure-rat b)))
    (method * (self (param a RATIONAL|INT "First operand") (param b RATIONAL|INT "Second operand"))
      (doc "Multiply two rationals (ints coerce)." (returns RATIONAL|INT "Product, reduced to lowest terms"))
      (%rat-mul (%ensure-rat a) (%ensure-rat b)))
    (method / (self (param a RATIONAL|INT "Dividend") (param b RATIONAL|INT "Divisor"))
      (doc "Divide two rationals (ints coerce)." (returns RATIONAL|INT "Quotient, reduced to lowest terms"))
      (%rat-div (%ensure-rat a) (%ensure-rat b)))
    (method < (self (param a RATIONAL|INT "Left operand") (param b RATIONAL|INT "Right operand"))
      (doc "Test whether a is less than b (ints coerce)." (returns BOOL "True if a < b"))
      (%rat-lt (%ensure-rat a) (%ensure-rat b)))
    (method = (self (param a RATIONAL|INT "Left operand") (param b RATIONAL|INT "Right operand"))
      (doc "Test whether a equals b (ints coerce)." (returns BOOL "True if a equals b"))
      (%rat-eq (%ensure-rat a) (%ensure-rat b)))))

; Make a rational VALUE dispatch its calls to the Rational class (subject-last):
; (1/2 numerator) -> (Rational numerator 1/2); (1/2 - 1/3) -> (Rational - 1/2 1/3).
(def %type-push-call (prim-ref 'type 'push-call))
(%type-push-call (%type-by-atom %rational) (%class-call-handler Rational))

; Join the pact last, once the module is fully usable: tower members
; announce themselves so pairwise registrations fire in any load order.
(import x/sys/pact)
(Pact join 'rational %rational)

(doc (provide x/num/rational Rational)
  (note "Literal syntax: 1/3, -2/7. The generic operators dispatch rational")
  (note "operands through the type ops; / promotes inexact int division.")
  (example "(+ 1/3 1/6)" "1/2")
  "Exact rational number arithmetic, homed on the Rational class.")
