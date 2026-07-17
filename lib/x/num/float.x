; float.x -- Floating-point type with IEEE 754 bit-pattern storage
(import x/type/object)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref (lit buf) (lit tok)))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-from-cell (prim-ref (lit type) (lit from-cell)))
(def %type-push-op (prim-ref (lit type) (lit push-op)))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %make-type (prim-ref (lit type) (lit make)))
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %dlopen (prim-ref (lit ffi) (lit dlopen)))
(def %dlsym (prim-ref (lit ffi) (lit dlsym)))
(def %ffi-call (prim-ref (lit ffi) (lit call)))



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

(def %float->str
  (fn (_ bits) (%ffi-call "d->s" () bits)))

(def %int->float
  (fn (_ n) (%ffi-call "i->d" () n)))

(def %float->int
  (fn (_ bits) (%ffi-call "d->i" () bits)))

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
; Sign: a '-' entry must see a digit next, so a lone '-' (the operator)
; and '-.' fall through to the symbol type unclaimed.

(def %float-neg-int
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) %float-int-digits ())))
; --- Math library for strtod (needed by convert alist) ---
; Try libm.so.6 (Linux), libm.dylib (macOS), then fall back to current process

(def %libm
  (let ((h (%dlopen "libm.so.6" 1)))
    (if h h
      (let ((h2 (%dlopen "libm.dylib" 1)))
        (if h2 h2
          (%dlopen () 1))))))

(def %strtod (%dlsym %libm "strtod"))

(def %str->float
  (fn (_ s) (%ffi-call "s0->d" %strtod s)))

; Float type with tokenizer, display, and alist-based convert

(def %float ())
(set! %float
  (%make-type
    "FLOAT"
    (list
      (pair
        (lit write)
        (fn (_ self) (display (%float->str (first self)))))
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          ; Entry: digit [0-9], or '-' followed by a digit

          (if (and (>= chr 48) (<= chr 57))
            %float-int-digits
            (if (= chr 45) %float-neg-int ()))))
      (pair (lit read) (fn (_ . args) (%float-read (first args))))
      (pair
        (lit from)
        (list
          (pair
            (%type-of 42)
            (fn (_ value) (%make-instance %float (%int->float value))))
          (pair
            (%type-of "")
            (fn (_ value) (%make-instance %float (%str->float value))))
))
      (pair
        (lit to)
        (list
          (pair (%type-of 42) (fn (_ self) (%float->int (first self))))
          (pair
            (%type-of "")
            (fn (_ self) (%float->str (first self)))))))))

(note "Predicates")

; --- Predicates and constructors ---

(def %float? (fn (_ x) (%type? x %float)))

(def %exact->inexact (fn (_ x) (%cvt x %float)))

(def %inexact->exact (fn (_ x) (%float->int (first x))))

(note "Arithmetic")

; --- Arithmetic ---

(def %f-add
  (fn (_ a b)
    (%make-instance %float (%ffi-call "d+d" () (first a) (first b)))))

(def %f-sub
  (fn (_ a b)
    (%make-instance %float (%ffi-call "d-d" () (first a) (first b)))))

(def %f-mul
  (fn (_ a b)
    (%make-instance %float (%ffi-call "d*d" () (first a) (first b)))))

(def %f-div
  (fn (_ a b)
    (%make-instance %float (%ffi-call "d/d" () (first a) (first b)))))

(def %f-mod
  (fn (_ a b)
    (%make-instance %float (%ffi-call "d%d" () (first a) (first b)))))

(note "Comparisons")

; --- Comparisons ---

(def %f-lt
  (fn (_ a b) (%ffi-call "d<d" () (first a) (first b))))

(def %f-eq
  (fn (_ a b) (%ffi-call "d=d" () (first a) (first b))))

; Reader: called by tokenizer after successful analyse
; Uses %buffer-token to extract consumed text, then strtod to parse

(set! %float-read
  (fn (_ . args)
    (%make-instance
      %float
      (%ffi-call "s0->d" %strtod (%buffer-token (first args))))))

(note "Math Functions")

; Factory: resolve dlsym at definition time, return closure with cached pointer

(def %libm-d
  (fn (_ name)
    (let ((sym (%dlsym %libm name)))
      (fn (_ x)
        (%make-instance %float (%ffi-call "d->d" sym (first x)))))))

(def %libm-dd
  (fn (_ name)
    (let ((sym (%dlsym %libm name)))
      (fn (_ a b)
        (%make-instance
          %float
          (%ffi-call "dd->d" sym (first a) (first b)))))))

(def %fsin (%libm-d "sin"))

(def %fcos (%libm-d "cos"))

(def %ftan (%libm-d "tan"))

(def %fsqrt (%libm-d "sqrt"))

(def %fexp (%libm-d "exp"))

(def %flog (%libm-d "log"))

(def %fabs (%libm-d "fabs"))

(def %ffloor (%libm-d "floor"))

(def %fceil (%libm-d "ceil"))

(def %fround (%libm-d "round"))

(def %ftrunc (%libm-d "trunc"))

(def %frint (%libm-d "rint"))

(def %fasin (%libm-d "asin"))

(def %facos (%libm-d "acos"))

(def %fatan (%libm-d "atan"))

(def %fpow (%libm-dd "pow"))

(def %fatan2 (%libm-dd "atan2"))

; --- Constants ---

(def %pi (%fatan2 (%exact->inexact 0) (%exact->inexact -1)))

(def %e (%fexp (%exact->inexact 1)))

(def %ensure-float (fn (_ x) (%cvt x %float)))

; --- Type ops: the generic operators dispatch float operands here ---
; %ensure-float goes through the cvt from-alist, so the other side may be an
; int, string, bignum, or rational (all declared). The old %safe wrapper chain
; is gone: bignum owns the + - * int-overflow policy, rational owns /, and the
; binary C operators dispatch everything typed.

(def %float-ts (%type-by-atom %float))
(%type-push-op %float-ts (lit +) (fn (_ a b) (%f-add (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts (lit -) (fn (_ a b) (%f-sub (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts (lit *) (fn (_ a b) (%f-mul (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts (lit /) (fn (_ a b) (%f-div (%ensure-float a) (%ensure-float b))))
; Without this op, (% 1.2 1.4) fell through to x_prim_mod's integer
; fallback -- value-word % value-word on two float PAYLOAD POINTERS --
; and returned garbage ((gcd 1.2 1.4) famously yielded 8).
(%type-push-op %float-ts (lit %) (fn (_ a b) (%f-mod (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts (lit <) (fn (_ a b) (%f-lt (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts (lit =) (fn (_ a b) (%f-eq (%ensure-float a) (%ensure-float b))))

(note "R7RS Predicates")

; --- R7RS predicates ---
; %int-number? already saved by x-core.x

; number? and real? are cohort predicates (transitional globals, like the other
; type predicates): defined/extended in place by the tower modules. complex.x
; set!-narrows real? to exclude complex instances. integer?/inexact? have no
; extenders and live only on the Float class.
(doc number?
  (param x ANY "Value to test")
  (returns BOOL "True if x is a number")
  "Test whether a value is a number (integer or float).")

(set! number? (fn (_ x) (if (%int-number? x) #t (%float? x))))

(doc (def real? (fn (_ (param x ANY "Value to test")) (number? x)))
  (returns BOOL "True if x is a real number")
  "Test whether a value is a real number (complex.x narrows this to exclude complexes).")

; --- Bignum -> float conversion (registered late, after f+/f* are defined) ---
; A pairwise registration: it needs bignum's handle (the from-alist key) and
; float's arithmetic (the converter body), so neither module alone can install
; it. Filed with the pact, it runs right here when bignum loaded first, at
; bignum's join when bignum loads later, and never when bignum never loads.
; (The old `(if (not (null? %bignum))` guard raised Unbound SYMBOL whenever
; bignum was absent -- an unbound global is not nil.)
(import x/sys/pact)
(Pact when (list (lit bignum))
  (fn (_ big)
    ; %bignum-base and `reverse` (x/core/list) are bignum.x's load-time
    ; bindings; the pact guarantees bignum fully loaded before this fires.
    (let ((from-cell (%type-from-cell (%type-by-atom %float))))
      (set-first! from-cell
        (pair
          (pair big
            (fn (_ value)
              (def sign (first (first value)))
              (def limbs (reverse (rest (first value))))
              (def fbase (%exact->inexact %bignum-base))
              (def fzero (%exact->inexact 0))
              ; Horner's method on reversed (now MSB-first) limbs
              (def %go
                (fn (self ls acc)
                  (if (null? ls) acc
                    (self (rest ls) (%f-add (%f-mul acc fbase) (%exact->inexact (first ls)))))))
              (def mag (%go limbs fzero))
              (if (%int= sign -1) (%f-sub fzero mag) mag)))
          (first from-cell))))))

(import x/type/object)

(def-class Float ()
  (static
    (method float? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a float." (returns BOOL "True if x is a float"))
      (%float? x))
    (method inexact? (self (param x ANY "Value to test"))
      (doc "Test whether a value is inexact. Equivalent to float?." (returns BOOL "True if x is a float"))
      (%float? x))
    (method integer? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an integer (the pre-float number? predicate)."
        (returns BOOL "True if x is a native integer"))
      (%int-number? x))
    (method real? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a real number (numbers minus complexes)."
        (returns BOOL "True if x is real"))
      (real? x))
    ; --- Conversions ---
    (method ->str (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Convert a float bit pattern to its string representation." (returns STRING "Decimal string representation"))
      (%float->str bits))
    (method ->int (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Convert a float bit pattern to an integer by truncation." (returns INT "Truncated integer value"))
      (%float->int bits))
    (method from-int (self (param n INT "Integer value"))
      (doc "Convert an integer to a float bit pattern." (returns INT "IEEE 754 double bit pattern"))
      (%int->float n))
    (method from-str (self (param s STRING "Decimal string to parse"))
      (doc "Parse a decimal string into a float." (returns FLOAT "Parsed float value"))
      (%str->float s))
    (method exact->inexact (self (param x INT "Exact integer value"))
      (doc "Convert an exact integer to an inexact float." (returns FLOAT "Float representation"))
      (%exact->inexact x))
    (method inexact->exact (self (param x FLOAT "Float value"))
      (doc "Convert an inexact float to an exact integer by truncation." (returns INT "Truncated integer value"))
      (%inexact->exact x))
    ; --- Arithmetic / comparison (operands coerce via the from-alist) ---
    (method + (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Add two floats (other numerics coerce)." (returns FLOAT "Sum"))
      (%f-add (%ensure-float a) (%ensure-float b)))
    (method - (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Subtract two floats (other numerics coerce)." (returns FLOAT "Difference"))
      (%f-sub (%ensure-float a) (%ensure-float b)))
    (method * (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Multiply two floats (other numerics coerce)." (returns FLOAT "Product"))
      (%f-mul (%ensure-float a) (%ensure-float b)))
    (method / (self (param a NUMBER "Dividend") (param b NUMBER "Divisor"))
      (doc "Divide two floats (other numerics coerce)." (returns FLOAT "Quotient"))
      (%f-div (%ensure-float a) (%ensure-float b)))
    (method < (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a is less than b (other numerics coerce)." (returns BOOL "True if a < b"))
      (%f-lt (%ensure-float a) (%ensure-float b)))
    (method = (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a equals b (other numerics coerce)." (returns BOOL "True if a equals b"))
      (%f-eq (%ensure-float a) (%ensure-float b)))
    ; --- libm ---
    (method sin (self (param x FLOAT "Angle in radians"))
      (doc "Compute the sine of a float." (returns FLOAT "Sine of x"))
      (%fsin x))
    (method cos (self (param x FLOAT "Angle in radians"))
      (doc "Compute the cosine of a float." (returns FLOAT "Cosine of x"))
      (%fcos x))
    (method tan (self (param x FLOAT "Angle in radians"))
      (doc "Compute the tangent of a float." (returns FLOAT "Tangent of x"))
      (%ftan x))
    (method sqrt (self (param x FLOAT "Non-negative float"))
      (doc "Compute the square root of a float." (returns FLOAT "Square root of x"))
      (%fsqrt x))
    (method exp (self (param x FLOAT "Exponent"))
      (doc "Compute e raised to a power." (returns FLOAT "e raised to the power x"))
      (%fexp x))
    (method log (self (param x FLOAT "Positive float"))
      (doc "Compute the natural logarithm of a float." (returns FLOAT "Natural logarithm of x"))
      (%flog x))
    (method abs (self (param x FLOAT "Float value"))
      (doc "Compute the absolute value of a float." (returns FLOAT "Absolute value of x"))
      (%fabs x))
    (method floor (self (param x FLOAT "Float value"))
      (doc "Round a float down to the nearest integer." (returns FLOAT "Largest integer not greater than x"))
      (%ffloor x))
    (method ceil (self (param x FLOAT "Float value"))
      (doc "Round a float up to the nearest integer." (returns FLOAT "Smallest integer not less than x"))
      (%fceil x))
    (method round (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer." (returns FLOAT "Nearest integer, ties away from zero"))
      (%fround x))
    (method trunc (self (param x FLOAT "Float value"))
      (doc "Truncate a float toward zero." (returns FLOAT "Integer part of x"))
      (%ftrunc x))
    (method rint (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer using the current rounding mode." (returns FLOAT "Nearest integer"))
      (%frint x))
    (method asin (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc sine of a float." (returns FLOAT "Arc sine in radians"))
      (%fasin x))
    (method acos (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc cosine of a float." (returns FLOAT "Arc cosine in radians"))
      (%facos x))
    (method atan (self (param x FLOAT "Float value"))
      (doc "Compute the arc tangent of a float." (returns FLOAT "Arc tangent in radians"))
      (%fatan x))
    (method pow (self (param base FLOAT "Base") (param exponent FLOAT "Exponent"))
      (doc "Raise a float to a power." (returns FLOAT "base raised to the power exponent"))
      (%fpow base exponent))
    (method atan2 (self (param y FLOAT "Y coordinate") (param x FLOAT "X coordinate"))
      (doc "Compute the arc tangent of y/x, using signs to determine the quadrant." (returns FLOAT "Angle in radians"))
      (%fatan2 y x))))

; Value dispatch (subject-last): (3.14 float?) -> (Float float? 3.14).
(def %type-push-call (prim-ref (lit type) (lit push-call)))
(%type-push-call (%type-by-atom %float) (%class-call-handler Float))

; Join the pact last, once the module is fully usable: any registration
; waiting on float fires against the finished class and type ops.
(Pact join (lit float) %float)

(doc (provide x/num/float Float)
  (note "Literal syntax: 3.14. The generic operators dispatch float operands")
  (note "through the type ops; mixed operands resolve by the from-relation.")
  (example "(+ 1 3.14)" "4.14")
  "IEEE 754 floating-point arithmetic, homed on the Float class.")
