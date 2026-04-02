; complex.x -- Complex number type
(import x/num/float)
(import x/num/rational)
(import x/core/numeric)
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
      (make-instance %complex (pair re im)))))
; --- Save current (real-number-aware) operators ---

(def %real+ +)
(def %real- -)
(def %real* *)
(def %real/ /)
(def %real= =)
(def %real< <)
; --- Accessors ---

(def %complex? (fn (_ x) (type? x %complex)))

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
      (if (= (convert (str-ref s i) %int) ch)
        i
        (self s (%int+ i 1) len ch)))))

(def %cx-parse-num
  (fn (_ s)
    (if (%cx-find-char s 0 (str-length s) 46)
      (make-instance %float (str->float s))
      (convert s %int))))

(set! %cx-read
  (fn (_ . args)
    (let ((tok (buffer-token (first args))))
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
  (make-type
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
      (pair (lit first-chars) "0123456789")
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) %cx-real-int ())))
      (pair (lit read) (fn (_ . args) (%cx-read (first args))))
      (pair
        (lit from)
        (list
          (pair (type-of 42) (fn (_ value) (%make-complex value 0)))
          (pair %float (fn (_ value) (%make-complex value 0)))
          (pair %rational (fn (_ value) (%make-complex value 0)))))
      (pair
        (lit to)
        (list
          (pair (type-of "")
            (fn (_ self) (write-to-str self))))))))
; --- Arithmetic ---

(note "Arithmetic")

(doc (def complex+
  (fn (_ (param a COMPLEX|NUMBER "First operand")
       (param b COMPLEX|NUMBER "Second operand"))
    (%make-complex
      (%real+ (%complex-re a) (%complex-re b))
      (%real+ (%complex-im a) (%complex-im b)))))
  (returns COMPLEX|NUMBER "Sum, collapsed to real if imaginary part is zero")
  "Add two complex numbers.")

(doc (def complex-
  (fn (_ (param a COMPLEX|NUMBER "First operand")
       (param b COMPLEX|NUMBER "Second operand"))
    (%make-complex
      (%real- (%complex-re a) (%complex-re b))
      (%real- (%complex-im a) (%complex-im b)))))
  (returns COMPLEX|NUMBER "Difference, collapsed to real if imaginary part is zero")
  "Subtract two complex numbers.")

(doc (def complex*
  (fn (_ (param a COMPLEX|NUMBER "First operand")
       (param b COMPLEX|NUMBER "Second operand"))
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (%make-complex
        (%real- (%real* ar br) (%real* ai bi))
        (%real+ (%real* ar bi) (%real* ai br))))))
  (returns COMPLEX|NUMBER "Product, collapsed to real if imaginary part is zero")
  "Multiply two complex numbers.")

(doc (def complex/
  (fn (_ (param a COMPLEX|NUMBER "Dividend")
       (param b COMPLEX|NUMBER "Divisor"))
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (let ((denom (%real+ (%real* br br) (%real* bi bi))))
        (%make-complex
          (%real/ (%real+ (%real* ar br) (%real* ai bi)) denom)
          (%real/ (%real- (%real* ai br) (%real* ar bi)) denom))))))
  (returns COMPLEX|NUMBER "Quotient, collapsed to real if imaginary part is zero")
  "Divide two complex numbers.")

(doc (def complex=
  (fn (_ (param a COMPLEX|NUMBER "Left operand")
       (param b COMPLEX|NUMBER "Right operand"))
    (if (%real= (%complex-re a) (%complex-re b))
      (%real= (%complex-im a) (%complex-im b))
      ())))
  (returns BOOLEAN "True if both real and imaginary parts are equal")
  "Test whether two complex numbers are equal.")
; --- R5RS constructors and accessors ---

(note "Constructors and Accessors")

(doc (def make-rectangular
  (fn (_ (param re NUMBER "Real part")
       (param im NUMBER "Imaginary part"))
    (%make-complex re im)))
  (returns COMPLEX|NUMBER "Complex number, or real if imaginary part is zero")
  "Construct a complex number from rectangular coordinates.")

(doc (def make-polar
  (fn (_ (param mag NUMBER "Magnitude")
       (param ang NUMBER "Angle in radians"))
    (let ((fang (exact->inexact ang)) (fmag (exact->inexact mag)))
      (%make-complex
        (f* fmag (fcos fang))
        (f* fmag (fsin fang))))))
  (returns COMPLEX|NUMBER "Complex number from polar coordinates")
  "Construct a complex number from polar coordinates (magnitude and angle).")

(doc real-part "Return the real part of a complex number, or the number itself for reals."
  (param z COMPLEX|NUMBER "Complex or real number")
  (returns NUMBER "Real part"))
(def real-part %complex-re)

(doc imag-part "Return the imaginary part of a complex number, or 0 for reals."
  (param z COMPLEX|NUMBER "Complex or real number")
  (returns NUMBER "Imaginary part"))
(def imag-part %complex-im)

(doc (def magnitude
  (fn (_ (param z COMPLEX|NUMBER "Complex or real number"))
    (if (%complex? z)
      (let ((re (exact->inexact (%complex-re z)))
            (im (exact->inexact (%complex-im z))))
        (fsqrt (f+ (f* re re) (f* im im))))
      (if (%real< z 0)
        (exact->inexact (%real- 0 z))
        (exact->inexact z)))))
  (returns FLOAT "Absolute value (distance from origin)")
  "Return the magnitude (absolute value) of a complex or real number.")

(doc (def angle
  (fn (_ (param z COMPLEX|NUMBER "Complex or real number"))
    (if (%complex? z)
      (fatan2
        (exact->inexact (%complex-im z))
        (exact->inexact (%complex-re z)))
      (if (%real< z 0) %pi (exact->inexact 0)))))
  (returns FLOAT "Angle in radians")
  "Return the angle (argument) of a complex number in radians.")
; --- Operator promotion: add complex layer ---

(note "Operator Overrides")

(def %ensure-complex (fn (_ x) (if (%complex? x) x (%make-complex x 0))))

; Use numeric tower factories for +, *
(set! + (%make-fold-op %complex? complex+ %ensure-complex %real+ 0))
(set! * (%make-fold-op %complex? complex* %ensure-complex %real* 1))

; = uses factory
(set! = (%make-cmp-op %complex? complex= %ensure-complex %real=))

; / and - need unary special cases
(set! /
  (fn (_ . args)
    (if (null? args) 1
      (if (null? (rest args))
        (if (%complex? (first args))
          (complex/ (%make-complex 1 0) (first args))
          (%real/ 1 (first args)))
        (fold
          (fn (_ acc x)
            (if (%complex? acc) (complex/ acc (%ensure-complex x))
              (if (%complex? x) (complex/ (%ensure-complex acc) x)
                (%real/ acc x))))
          (first args) (rest args))))))

(set! -
  (fn (_ . args)
    (if (null? args) 0
      (if (null? (rest args))
        (if (%complex? (first args))
          (complex- (%make-complex 0 0) (first args))
          (%real- (first args)))
        (fold
          (fn (_ acc x)
            (if (%complex? acc) (complex- acc (%ensure-complex x))
              (if (%complex? x) (complex- (%ensure-complex acc) x)
                (%real- acc x))))
          (first args) (rest args))))))
; --- Predicates ---

(note "Predicates")

(doc number? "Test whether a value is any numeric type (integer, rational, float, or complex)."
  (param x ANY "Value to test")
  (returns BOOLEAN "True if x is a number"))
(set! number?
  (fn (_ x)
    (if (%complex? x) #t
      (if (%rat? x) #t
        (if (float? x) #t
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
      (if (float? x) #t
        (%int-number? x)))))

(doc (provide x/num/complex
  complex? complex+ complex- complex* complex/ complex=
  make-rectangular make-polar real-part imag-part magnitude angle)
  (note "Literal syntax: a+bi, a-bi (e.g. 3+4i, 0+1i, 2-3i)")
  (note "Extends arithmetic operators (+, -, *, /, =) with complex promotion.")
  (example "3+4i" "3+4i")
  (example "(+ 1 2i)" "1+2i")
  (example "(magnitude 3+4i)" "5.0")
  "Complex number arithmetic with rectangular and polar forms.")
