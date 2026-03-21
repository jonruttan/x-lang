; float.x -- Floating-point type with IEEE 754 bit-pattern storage
(import x/numeric)
;
; Float values are stored as IEEE 754 double bit patterns inside integers.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).
;
; All float conversion functions use generic ffi-call conventions,
; eliminating the need for any float-specific C primitives.
; Forward-declare reader

(def %float-read ())

(note "Conversion")

; --- FFI-based conversion functions ---
; These use generic ffi-call conventions (no function pointer needed)

(doc (def float->string
  (fn (_ (param bits INTEGER "IEEE 754 double bit pattern"))
    (ffi-call "d->s" () bits)))
  (returns STRING "Decimal string representation")
  "Convert a float bit pattern to its string representation.")

(doc (def int->float
  (fn (_ (param n INTEGER "Integer value"))
    (ffi-call "i->d" () n)))
  (returns INTEGER "IEEE 754 double bit pattern")
  "Convert an integer to a float bit pattern.")

(doc (def float->int
  (fn (_ (param bits INTEGER "IEEE 754 double bit pattern"))
    (ffi-call "d->i" () bits)))
  (returns INTEGER "Truncated integer value")
  "Convert a float bit pattern to an integer by truncation.")

; State machine for tokenizer: matches [0-9]+\.[0-9]+
; Uses intrinsic scoring — score computed from buffer length.
; After first fractional digit: continue digits or score

(def %float-frac ())

(set! %float-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %float-frac
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))
; Must see at least one digit after '.'

(def %float-first-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %float-frac)
      ())))
; Integer part: digits until '.'

(def %float-int-digits ())

(set! %float-int-digits
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %float-int-digits
      (if (= chr 46) %float-first-frac ()))))
; --- Math library for strtod (needed by convert alist) ---
; Try libm.so.6 (Linux), libm.dylib (macOS), then fall back to current process

(def %libm
  (let ((h (dlopen "libm.so.6" 1)))
    (if h h
      (let ((h (dlopen "libm.dylib" 1)))
        (if h h
          (dlopen () 1))))))

(def %strtod (dlsym %libm "strtod"))

(doc (def string->float
  (fn (_ (param s STRING "Decimal string to parse"))
    (ffi-call "s0->d" %strtod s)))
  (returns FLOAT "Parsed float value")
  "Parse a decimal string into a float.")

; Float type with tokenizer, display, and alist-based convert

(def %float
  (make-type
    "FLOAT"
    (list
      (pair
        (lit write)
        (fn (_ self) (display (float->string (first self)))))
      (pair (lit first-chars) "0123456789")
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          ; Entry: must start with digit [0-9]

          (if (and (>= chr 48) (<= chr 57)) %float-int-digits ())))
      (pair (lit read) (fn (_ . args) (%float-read (first args))))
      (pair
        (lit from)
        (list
          (pair
            (type-of 42)
            (fn (_ value) (make-instance %float (int->float value))))
          (pair
            (type-of "")
            (fn (_ value) (make-instance %float (string->float value))))))
      (pair
        (lit to)
        (list
          (pair (type-of 42) (fn (_ self) (float->int (first self))))
          (pair
            (type-of "")
            (fn (_ self) (float->string (first self)))))))))

(note "Predicates")

; --- Predicates and constructors ---

(doc (def float?
  (fn (_ (param x ANY "Value to test"))
    (type? x %float)))
  (returns BOOLEAN "True if x is a float")
  "Test whether a value is a float.")

(doc (def exact->inexact
  (fn (_ (param x INTEGER "Exact integer value"))
    (convert x %float)))
  (returns FLOAT "Float representation")
  "Convert an exact integer to an inexact float.")

(doc (def inexact->exact
  (fn (_ (param x FLOAT "Float value"))
    (float->int (first x))))
  (returns INTEGER "Truncated integer value")
  "Convert an inexact float to an exact integer by truncation.")

(note "Arithmetic")

; --- Arithmetic ---

(doc (def f+
  (fn (_ (param a FLOAT "First operand") (param b FLOAT "Second operand"))
    (make-instance
      %float
      (ffi-call "d+d" () (first a) (first b)))))
  (returns FLOAT "Sum")
  "Add two floats.")

(doc (def f-
  (fn (_ (param a FLOAT "First operand") (param b FLOAT "Second operand"))
    (make-instance
      %float
      (ffi-call "d-d" () (first a) (first b)))))
  (returns FLOAT "Difference")
  "Subtract two floats.")

(doc (def f*
  (fn (_ (param a FLOAT "First operand") (param b FLOAT "Second operand"))
    (make-instance
      %float
      (ffi-call "d*d" () (first a) (first b)))))
  (returns FLOAT "Product")
  "Multiply two floats.")

(doc (def f/
  (fn (_ (param a FLOAT "Dividend") (param b FLOAT "Divisor"))
    (make-instance
      %float
      (ffi-call "d/d" () (first a) (first b)))))
  (returns FLOAT "Quotient")
  "Divide two floats.")

(note "Comparisons")

; --- Comparisons ---

(doc (def f<
  (fn (_ (param a FLOAT "Left operand") (param b FLOAT "Right operand"))
    (ffi-call "d<d" () (first a) (first b))))
  (returns BOOLEAN "True if a < b")
  "Test whether float a is less than float b.")

(doc (def f=
  (fn (_ (param a FLOAT "Left operand") (param b FLOAT "Right operand"))
    (ffi-call "d=d" () (first a) (first b))))
  (returns BOOLEAN "True if a equals b")
  "Test whether two floats are equal.")

; Reader: called by tokenizer after successful analyse
; Uses buffer-token to extract consumed text, then strtod to parse

(set! %float-read
  (fn (_ . args)
    (make-instance
      %float
      (ffi-call "s0->d" %strtod (buffer-token (first args))))))

(note "Math Functions")

; Factory: resolve dlsym at definition time, return closure with cached pointer

(def %libm-d
  (fn (_ name)
    (let ((sym (dlsym %libm name)))
      (fn (_ x)
        (make-instance %float (ffi-call "d->d" sym (first x)))))))

(def %libm-dd
  (fn (_ name)
    (let ((sym (dlsym %libm name)))
      (fn (_ a b)
        (make-instance
          %float
          (ffi-call "dd->d" sym (first a) (first b)))))))

(doc (def fsin (%libm-d "sin"))
  (param x FLOAT "Angle in radians") (returns FLOAT "Sine of x")
  "Compute the sine of a float.")

(doc (def fcos (%libm-d "cos"))
  (param x FLOAT "Angle in radians") (returns FLOAT "Cosine of x")
  "Compute the cosine of a float.")

(doc (def ftan (%libm-d "tan"))
  (param x FLOAT "Angle in radians") (returns FLOAT "Tangent of x")
  "Compute the tangent of a float.")

(doc (def fsqrt (%libm-d "sqrt"))
  (param x FLOAT "Non-negative float") (returns FLOAT "Square root of x")
  "Compute the square root of a float.")

(doc (def fexp (%libm-d "exp"))
  (param x FLOAT "Exponent") (returns FLOAT "e raised to the power x")
  "Compute e raised to a power.")

(doc (def flog (%libm-d "log"))
  (param x FLOAT "Positive float") (returns FLOAT "Natural logarithm of x")
  "Compute the natural logarithm of a float.")

(doc (def fabs (%libm-d "fabs"))
  (param x FLOAT "Float value") (returns FLOAT "Absolute value of x")
  "Compute the absolute value of a float.")

(doc (def ffloor (%libm-d "floor"))
  (param x FLOAT "Float value") (returns FLOAT "Largest integer not greater than x")
  "Round a float down to the nearest integer.")

(doc (def fceil (%libm-d "ceil"))
  (param x FLOAT "Float value") (returns FLOAT "Smallest integer not less than x")
  "Round a float up to the nearest integer.")

(doc (def fround (%libm-d "round"))
  (param x FLOAT "Float value") (returns FLOAT "Nearest integer, ties away from zero")
  "Round a float to the nearest integer.")

(doc (def ftrunc (%libm-d "trunc"))
  (param x FLOAT "Float value") (returns FLOAT "Integer part of x")
  "Truncate a float toward zero.")

(doc (def frint (%libm-d "rint"))
  (param x FLOAT "Float value") (returns FLOAT "Nearest integer using current rounding mode")
  "Round a float to the nearest integer using the current rounding mode.")

(doc (def fasin (%libm-d "asin"))
  (param x FLOAT "Value in [-1, 1]") (returns FLOAT "Arc sine in radians")
  "Compute the arc sine of a float.")

(doc (def facos (%libm-d "acos"))
  (param x FLOAT "Value in [-1, 1]") (returns FLOAT "Arc cosine in radians")
  "Compute the arc cosine of a float.")

(doc (def fatan (%libm-d "atan"))
  (param x FLOAT "Float value") (returns FLOAT "Arc tangent in radians")
  "Compute the arc tangent of a float.")

(doc (def fpow (%libm-dd "pow"))
  (param base FLOAT "Base") (param exponent FLOAT "Exponent")
  (returns FLOAT "base raised to the power exponent")
  "Raise a float to a power.")

(doc (def fatan2 (%libm-dd "atan2"))
  (param y FLOAT "Y coordinate") (param x FLOAT "X coordinate")
  (returns FLOAT "Angle in radians")
  "Compute the arc tangent of y/x, using signs to determine the quadrant.")

; --- Constants ---

(def %pi (fatan2 (exact->inexact 0) (exact->inexact -1)))

(def %e (fexp (exact->inexact 1)))

(note "Generic Overrides")

; --- Generic arithmetic overrides ---
; Save current operators (bignum-safe if bignum.x loaded before us)
(def %safe+ +)
(def %safe- -)
(def %safe* *)
(def %safe/ /)
(def %safe< <)
(def %safe= =)
(def %ensure-float (fn (_ x) (convert x %float)))

; Use numeric tower factories for +, *, /, <, =
(set! + (%make-fold-op float? f+ %ensure-float %safe+ 0))
(set! * (%make-fold-op float? f* %ensure-float %safe* 1))
(set! / (%make-fold-op float? f/ %ensure-float %safe/ 1))
(set! < (%make-cmp-op float? f< %ensure-float %safe<))
(set! = (%make-cmp-op float? f= %ensure-float %safe=))

; - is special: unary negation case
(set! -
  (fn (_ . args)
    (if (null? args) 0
      (if (null? (rest args))
        (if (float? (first args))
          (f- (exact->inexact 0) (first args))
          (%safe- (first args)))
        (fold
          (fn (_ acc x)
            (if (float? acc) (f- acc (%ensure-float x))
              (if (float? x) (f- (%ensure-float acc) x)
                (%safe- acc x))))
          (first args) (rest args))))))

(note "R7RS Predicates")

; --- R7RS predicates ---
; %int-number? already saved by x-core.x

(doc (def integer? number?)
  "Test whether a value is an integer. Alias for the original number? predicate.")

(doc number?
  (param x ANY "Value to test")
  (returns BOOLEAN "True if x is a number")
  "Test whether a value is a number (integer or float).")

(set! number? (fn (_ x) (if (%int-number? x) #t (float? x))))

(doc (def real? number?)
  "Test whether a value is a real number. Equivalent to number?.")

(doc (def inexact? float?)
  "Test whether a value is inexact. Equivalent to float?.")

(doc (provide x/float
  float? float->string int->float float->int string->float
  exact->inexact inexact->exact
  f+ f- f* f/ f< f= fsin fcos ftan fsqrt fexp flog fabs
  ffloor fceil fround ftrunc frint fasin facos fatan fpow fatan2
  integer? real? inexact?)
  (note "Literal syntax: 3.14, 1.0e10. Extends +,-,*,/,<,= with float promotion.")
  (example "(+ 1 3.14)" "4.14")
  "IEEE 754 floating-point arithmetic.")
