; complex.x -- Complex number type
(import x/num/float)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref (lit buf) (lit tok)))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-op (prim-ref (lit type) (lit push-op)))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))

(import x/num/rational)
(import x/type/object)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %make-type (prim-ref (lit type) (lit make)))
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref (lit io) (lit write-to-str)))


;
; Complex values are stored as (real-part . imag-part) pairs.
; Components can be any real number type (integer, rational, float).
;
; Promotion chain: integer -> rational -> float -> complex

(def %complex ())
(def %cx-read ())
; --- Constructor: collapse to real when imag is exactly integer 0 ---

(def %make-complex
  (fn (_ re im)
    (if (if (%int-number? im) (%int= im 0) ())
      re
      (%make-instance %complex (pair re im)))))
; --- Save current (real-number-aware) operators ---

(def %real+ +)
(def %real- -)
(def %real* *)
(def %real/ /)
(def %real= =)
(def %real< <)
; --- Accessors ---

(def %complex? (fn (_ x) (%type? x %complex)))

(def %complex-re
  (fn (_ x) (if (%complex? x) (first (first x)) x)))

(def %complex-im
  (fn (_ x) (if (%complex? x) (rest (first x)) 0)))
; --- Tokenizer state machine for complex literals ---
; Matches: <digits>[.<digits>][+-]<digits>[.<digits>]i
; Also: <digits>[.<digits>]i  (pure imaginary)

(def %cx-imag-frac ())
(set! %cx-imag-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-frac
      (if (= chr 105)
        (score-set score 1 buffer)
        ()))))

(def %cx-imag-dot
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-frac
      ())))

(def %cx-imag-int ())
(set! %cx-imag-int
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-int
      (if (= chr 46)
        %cx-imag-dot
        (if (= chr 105)
          (score-set score 1 buffer)
          ())))))

(def %cx-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-int
      ())))

(def %cx-real-frac ())
(set! %cx-real-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-real-frac
      (if (= chr 43)
        %cx-sign
        (if (= chr 45)
          %cx-sign
          (if (= chr 105)
            (score-set score 1 buffer)
            ()))))))

(def %cx-real-dot
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-real-frac
      ())))

(def %cx-real-int ())
(set! %cx-real-int
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-real-int
      (if (= chr 46)
        %cx-real-dot
        (if (= chr 43)
          %cx-sign
          (if (= chr 45)
            %cx-sign
            (if (= chr 105)
              (score-set score 1 buffer)
              ())))))))

; --- Reader helpers ---

(def %cx-find-char
  (fn (self s i len ch)
    (if (>= i len) ()
      (if (= (%cvt (str-ref s i) %int) ch)
        i
        (self s (%int+ i 1) len ch)))))

(def %cx-parse-num
  (fn (_ s)
    (if (%cx-find-char s 0 (str-length s) 46)
      (%make-instance %float (%str->float s))
      (%cvt s %int))))

(set! %cx-read
  (fn (_ . args)
    (let ((tok (%buffer-token (first args))))
      (let ((len (str-length tok)))
        (let ((body (substring tok 0 (%int- len 1))))
          (let ((blen (%int- len 1)))
            (let ((sign-pos (%cx-find-char body 1 blen 43)))
              (if (null? sign-pos)
                (set! sign-pos (%cx-find-char body 1 blen 45)))
              (if sign-pos
                (%make-complex
                  (%cx-parse-num (substring body 0 sign-pos))
                  (%cx-parse-num (substring body sign-pos blen)))
                (%make-complex 0 (%cx-parse-num body))))))))))

; --- Type definition ---

(set! %complex
  (%make-type
    "COMPLEX"
    (list
      (pair
        (lit write)
        (fn (_ self)
          (let ((re (first (first self))) (im (rest (first self))))
            (display re)
            (if (not (%real< im 0)) (display "+"))
            (display im)
            (display "i"))))
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) %cx-real-int ())))
      (pair (lit read) (fn (_ . args) (%cx-read (first args))))
      (pair
        (lit from)
        (list
          (pair (%type-of 42) (fn (_ value) (%make-complex value 0)))
          (pair %float (fn (_ value) (%make-complex value 0)))
          (pair %rational (fn (_ value) (%make-complex value 0)))))
      (pair
        (lit to)
        (list
          (pair (%type-of "")
            (fn (_ self) (%write-to-str self))))))))
; --- Arithmetic ---

(note "Arithmetic")

(def %cx-add
  (fn (_ a b)
    (%make-complex
      (%real+ (%complex-re a) (%complex-re b))
      (%real+ (%complex-im a) (%complex-im b)))))

(def %cx-sub
  (fn (_ a b)
    (%make-complex
      (%real- (%complex-re a) (%complex-re b))
      (%real- (%complex-im a) (%complex-im b)))))

(def %cx-mul
  (fn (_ a b)
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (%make-complex
        (%real- (%real* ar br) (%real* ai bi))
        (%real+ (%real* ar bi) (%real* ai br))))))

(def %cx-div
  (fn (_ a b)
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (let ((denom (%real+ (%real* br br) (%real* bi bi))))
        (%make-complex
          (%real/ (%real+ (%real* ar br) (%real* ai bi)) denom)
          (%real/ (%real- (%real* ai br) (%real* ar bi)) denom))))))

(def %cx-eq
  (fn (_ a b)
    (if (%real= (%complex-re a) (%complex-re b))
      (%real= (%complex-im a) (%complex-im b))
      ())))
; --- R5RS constructors and accessors ---

(note "Constructors and Accessors")

; Constructors/accessors live on the Complex class below.

(def %cx-magnitude
  (fn (_ z)
    (if (%complex? z)
      (let ((re (%exact->inexact (%complex-re z)))
            (im (%exact->inexact (%complex-im z))))
        (%fsqrt (%f-add (%f-mul re re) (%f-mul im im))))
      (if (%real< z 0)
        (%exact->inexact (%real- 0 z))
        (%exact->inexact z)))))

(def %cx-angle
  (fn (_ z)
    (if (%complex? z)
      (%fatan2
        (%exact->inexact (%complex-im z))
        (%exact->inexact (%complex-re z)))
      (if (%real< z 0) %pi (%exact->inexact 0)))))
; --- Type ops: the generic operators dispatch complex operands here ---
; Complex absorbs every real type via its from-declarations (int, float,
; rational), so the other side of a mixed pair always coerces with
; %ensure-complex. No < handler: complexes are unordered.

(note "Operator Overrides")

(def %ensure-complex (fn (_ x) (if (%complex? x) x (%make-complex x 0))))

(def %complex-ts (%type-by-atom %complex))
(%type-push-op %complex-ts (lit +) (fn (_ a b) (%cx-add (%ensure-complex a) (%ensure-complex b))))
(%type-push-op %complex-ts (lit -) (fn (_ a b) (%cx-sub (%ensure-complex a) (%ensure-complex b))))
(%type-push-op %complex-ts (lit *) (fn (_ a b) (%cx-mul (%ensure-complex a) (%ensure-complex b))))
(%type-push-op %complex-ts (lit /) (fn (_ a b) (%cx-div (%ensure-complex a) (%ensure-complex b))))
(%type-push-op %complex-ts (lit =) (fn (_ a b) (%cx-eq (%ensure-complex a) (%ensure-complex b))))

; --- Predicates ---

(note "Predicates")

(doc number? "Test whether a value is any numeric type (integer, rational, float, or complex)."
  (param x ANY "Value to test")
  (returns BOOLEAN "True if x is a number"))
(set! number?
  (fn (_ x)
    (if (%complex? x) #t
      (if (%rat? x) #t
        (if (%float? x) #t
          (%int-number? x))))))

(doc complex? "Test whether a value is any numeric type (alias for number?)."
  (param x ANY "Value to test")
  (returns BOOLEAN "True if x is a number"))
(def complex? number?)

(doc real? "Test whether a value is a real number (integer, rational, or float, but not complex)."
  (param x ANY "Value to test")
  (returns BOOLEAN "True if x is a real number"))
(set! real?
  (fn (_ x)
    (if (%rat? x) #t
      (if (%float? x) #t
        (%int-number? x)))))

(def-class Complex ()
  (static
    (method complex? (self (param x ANY "Value to test"))
      (doc "Test whether a value is any numeric type (alias for number?)."
        (returns BOOLEAN "True if x is a number"))
      (number? x))
    (method make-rectangular (self (param re NUMBER "Real part") (param im NUMBER "Imaginary part"))
      (doc "Construct a complex number from rectangular coordinates."
        (returns COMPLEX|NUMBER "Complex number, or real if imaginary part is zero"))
      (%make-complex re im))
    (method make-polar (self (param mag NUMBER "Magnitude") (param ang NUMBER "Angle in radians"))
      (doc "Construct a complex number from polar coordinates (magnitude and angle)."
        (returns COMPLEX|NUMBER "Complex number from polar coordinates"))
      (let ((fang (%exact->inexact ang)) (fmag (%exact->inexact mag)))
        (%make-complex
          (%f-mul fmag (%fcos fang))
          (%f-mul fmag (%fsin fang)))))
    (method real-part (self (param z COMPLEX|NUMBER "Complex or real number"))
      (doc "Return the real part of a complex number, or the number itself for reals."
        (returns NUMBER "Real part"))
      (%complex-re z))
    (method imag-part (self (param z COMPLEX|NUMBER "Complex or real number"))
      (doc "Return the imaginary part of a complex number, or 0 for reals."
        (returns NUMBER "Imaginary part"))
      (%complex-im z))
    (method magnitude (self (param z COMPLEX|NUMBER "Complex or real number"))
      (doc "Return the magnitude (absolute value) of a complex or real number."
        (returns FLOAT "Absolute value (distance from origin)"))
      (%cx-magnitude z))
    (method angle (self (param z COMPLEX|NUMBER "Complex or real number"))
      (doc "Return the angle (argument) of a complex number in radians."
        (returns FLOAT "Angle in radians"))
      (%cx-angle z))
    (method + (self (param a COMPLEX|NUMBER "First operand") (param b COMPLEX|NUMBER "Second operand"))
      (doc "Add two complex numbers (reals coerce)." (returns COMPLEX|NUMBER "Sum, collapsed to real if imaginary part is zero"))
      (%cx-add (%ensure-complex a) (%ensure-complex b)))
    (method - (self (param a COMPLEX|NUMBER "First operand") (param b COMPLEX|NUMBER "Second operand"))
      (doc "Subtract two complex numbers (reals coerce)." (returns COMPLEX|NUMBER "Difference, collapsed to real if imaginary part is zero"))
      (%cx-sub (%ensure-complex a) (%ensure-complex b)))
    (method * (self (param a COMPLEX|NUMBER "First operand") (param b COMPLEX|NUMBER "Second operand"))
      (doc "Multiply two complex numbers (reals coerce)." (returns COMPLEX|NUMBER "Product, collapsed to real if imaginary part is zero"))
      (%cx-mul (%ensure-complex a) (%ensure-complex b)))
    (method / (self (param a COMPLEX|NUMBER "Dividend") (param b COMPLEX|NUMBER "Divisor"))
      (doc "Divide two complex numbers (reals coerce)." (returns COMPLEX|NUMBER "Quotient, collapsed to real if imaginary part is zero"))
      (%cx-div (%ensure-complex a) (%ensure-complex b)))
    (method = (self (param a COMPLEX|NUMBER "Left operand") (param b COMPLEX|NUMBER "Right operand"))
      (doc "Test whether two complex numbers are equal (reals coerce)."
        (returns BOOLEAN "True if both real and imaginary parts are equal"))
      (%cx-eq (%ensure-complex a) (%ensure-complex b)))))

; Value dispatch (receiver-first): (1+2i real-part) -> (Complex real-part 1+2i).
(def %type-push-call (prim-ref (lit type) (lit push-call)))
(%type-push-call (%type-by-atom %complex) (%class-call-handler Complex))

(doc (provide x/num/complex Complex)
  (note "Literal syntax: a+bi, a-bi (e.g. 3+4i, 0+1i, 2-3i)")
  (note "Extends arithmetic operators (+, -, *, /, =) with complex promotion.")
  (example "3+4i" "3+4i")
  (example "(+ 1 2i)" "1+2i")
  (example "(magnitude 3+4i)" "5.0")
  "Complex number arithmetic with rectangular and polar forms.")
