; float.x -- Floating-point type with IEEE 754 bit-pattern storage
; lint-known: %bigint-base
; (defined in num/bigint.x; the tower supplies it in load order)
(import x/type/class)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

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
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
(def %ffi-call (prim-ref 'ffi 'call))



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
  (fn (_ bits)
    ; d->s renders int-valued doubles bare ("1"), which re-reads as an
    ; INT -- keep the point so floats round-trip (#45 R4). Skip anything
    ; already carrying a point, an exponent, or inf/nan.
    (let ((s (%ffi-call "d->s" () bits)))
      (if (Str8 contains? "." s) s
        (if (Str8 contains? "e" s) s
          (if (Str8 contains? "n" s) s
            (Str8 append s ".0")))))))

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
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
; Must see at least one digit after '.'

(def %float-first-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (%score-set score 1 buffer) %float-frac)
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
        'write
        (fn (_ self) (display (%float->str (first self)))))
      (pair
        'analyse
        (fn (_ buffer score chr)
          ; Entry: digit [0-9], or '-' followed by a digit

          (if (and (>= chr 48) (<= chr 57))
            %float-int-digits
            (if (= chr 45) %float-neg-int ()))))
      (pair 'read (fn (_ . args) (%float-read (first args))))
      (pair
        'from
        (list
          (pair
            (%type-of 42)
            (fn (_ value) (%make-instance %float (%int->float value))))
          (pair
            (%type-of "")
            (fn (_ value) (%make-instance %float (%str->float value))))
))
      (pair
        'to
        (list
          (pair (%type-of 42) (fn (_ self) (%float->int (first self))))
          (pair
            (%type-of "")
            (fn (_ self) (%float->str (first self)))))))))

(note "Predicates")

; --- Predicates and constructors ---

(def %float? (fn (_ x) (%type? x %float)))

; Door: coerce to float through the catalog; a miss is a raise, never nil
; into (first)/d+d (the C core is unchecked -- guards live in x-lang).
(def %to-float
  (fn (_ x what)
    (if (%float? x) x
      (let ((f (%cvt x %float)))
        (if (%float? f) f (Err raise 'type what x))))))

(def %float-of
  (fn (_ x) (%to-float x "Float from: not convertible to FLOAT")))

(def %int-of
  (fn (_ x)
    (match
      ((%float? x) (%float->int (first x)))
      ((%int-number? x) x)
      (#t (Err raise 'type "Float ->int: not a float" x)))))

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

; fmod through the dlsym'd %libm handle (dd->d), like every other math
; function -- NOT an inline C convention.  The retired d%d convention was
; the binary's ONLY link-time libm reference; with it gone the link drops
; -lm entirely (%libm above already loads libm itself at runtime).
(def %ffmod (%dlsym %libm "fmod"))
(def %f-mod
  (fn (_ a b)
    (%make-instance %float (%ffi-call "dd->d" %ffmod (first a) (first b)))))

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

(def %pi (%fatan2 (%float-of 0) (%float-of -1)))

(def %e (%fexp (%float-of 1)))

(def %ensure-float
  (fn (_ x) (%to-float x "Float: operand not convertible to FLOAT")))

; --- Type ops: the generic operators dispatch float operands here ---
; %ensure-float goes through the cvt from-alist, so the other side may be an
; int, string, bigint, or rational (all declared). The old %safe wrapper chain
; is gone: bigint owns the + - * int-overflow policy, rational owns /, and the
; binary C operators dispatch everything typed.

(def %float-ts (%type-by-atom %float))
(%type-push-op %float-ts '+ (fn (_ a b) (%f-add (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts '- (fn (_ a b) (%f-sub (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts '* (fn (_ a b) (%f-mul (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts '/ (fn (_ a b) (%f-div (%ensure-float a) (%ensure-float b))))
; Without this op, (% 1.2 1.4) fell through to x_prim_mod's integer
; fallback -- value-word % value-word on two float PAYLOAD POINTERS --
; and returned garbage ((gcd 1.2 1.4) famously yielded 8).
(%type-push-op %float-ts '% (fn (_ a b) (%f-mod (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts '< (fn (_ a b) (%f-lt (%ensure-float a) (%ensure-float b))))
(%type-push-op %float-ts '= (fn (_ a b) (%f-eq (%ensure-float a) (%ensure-float b))))

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

; --- Bigint -> float conversion (registered late, after f+/f* are defined) ---
; A pairwise registration: it needs bigint's handle (the from-alist key) and
; float's arithmetic (the converter body), so neither module alone can install
; it. Filed with the pact, it runs right here when bigint loaded first, at
; bigint's join when bigint loads later, and never when bigint never loads.
; (The old `(if (not (null? %bigint))` guard raised Unbound SYMBOL whenever
; bigint was absent -- an unbound global is not nil.)
(import x/sys/pact)
(Pact when (list 'bigint)
  (fn (_ big)
    ; %bigint-base and `reverse` (x/core/list) are bigint.x's load-time
    ; bindings; the pact guarantees bigint fully loaded before this fires.
    (let ((from-cell (%type-from-cell (%type-by-atom %float))))
      (%set-first! from-cell
        (pair
          (pair big
            (fn (_ value)
              (def sign (first (first value)))
              (def limbs (%reverse (rest (first value))))
              (def fbase (%float-of %bigint-base))
              (def fzero (%float-of 0))
              ; Horner's method on reversed (now MSB-first) limbs
              (def %go
                (fn (self ls acc)
                  (if (null? ls) acc
                    (self (rest ls) (%f-add (%f-mul acc fbase) (%float-of (first ls)))))))
              (def mag (%go limbs fzero))
              (if (%int= sign -1) (%f-sub fzero mag) mag)))
          (first from-cell))))))

(import x/type/class)

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
    (method bits->str (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Render a raw IEEE 754 bit pattern as its decimal string -- FFI plumbing; value-level work wants (Float from) / the printer." (returns STRING "Decimal string representation"))
      (%float->str bits))
    (method bits->int (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Truncate a raw IEEE 754 bit pattern to a machine integer -- FFI plumbing; value-level work wants (Float ->int)." (returns INT "Truncated integer value"))
      (%float->int bits))
    (method int->bits (self (param n INT "Integer value"))
      (doc "The IEEE 754 bit pattern of an integer's double value -- FFI plumbing, NOT a float constructor; (Float from) builds instances." (returns INT "IEEE 754 double bit pattern"))
      (%int->float n))
    (method str->bits (self (param s STRING "Decimal string to parse"))
      (doc "The IEEE 754 bit pattern of a decimal string's double value -- FFI plumbing, NOT a parser-to-instance; (Float from) builds instances (the old from-str name claimed FLOAT and returned bits, #66)." (returns INT "IEEE 754 double bit pattern"))
      (%str->float s))
    (method from (self (param x ANY "An exact number (int, bigint, rational), a numeric string, or a float (identity)"))
      (doc "Construct a float from any convertible value, through the conversion catalog -- the generic value door (was exact->inexact, #357). Raises kind-'type when nothing converts." (returns FLOAT "Float instance"))
      (%float-of x))
    (method ->int (self (param x FLOAT "Float value (machine ints pass through)"))
      (doc "Convert an inexact float to an exact integer by truncation." (returns INT "Truncated integer value"))
      (%int-of x))
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
      (%fatan2 y x))

    ; --- The math tail (#363) ---
    ; Cold paths: dlsym per call (the kill pattern), keeping float.x inside
    ; its %-globals budget; the hot trig/exp family above keeps its
    ; load-time-cached resolves.
    (method log2 (self (param x FLOAT "Positive float"))
      (doc "Compute the base-2 logarithm of a float."
        (returns FLOAT "log2(x)")
        (sample "(Float log2 8.0)" "3.0"))
      (%make-instance %float (%ffi-call "d->d" (%dlsym %libm "log2") (first x))))
    (method log10 (self (param x FLOAT "Positive float"))
      (doc "Compute the base-10 logarithm of a float."
        (returns FLOAT "log10(x)")
        (sample "(Float log10 1000.0)" "3.0"))
      (%make-instance %float (%ffi-call "d->d" (%dlsym %libm "log10") (first x))))
    (method hypot (self (param x FLOAT "First leg") (param y FLOAT "Second leg"))
      (doc "Compute sqrt(x^2 + y^2) without intermediate overflow (libm hypot)."
        (returns FLOAT "The hypotenuse")
        (sample "(Float hypot 3.0 4.0)" "5.0"))
      (%make-instance %float (%ffi-call "dd->d" (%dlsym %libm "hypot") (first x) (first y))))

    ; --- Constants (#363) ---
    ; %pi and %e were already computed at load (atan2/exp); tau derives
    ; per call through the float adder.
    (method pi (self)
      (doc "The circle constant pi, 3.14159265..."
        (returns FLOAT "pi")
        (sample "(Float pi)" "3.14159265358979"))
      %pi)
    (method e (self)
      (doc "Euler's number e, 2.71828182..."
        (returns FLOAT "e")
        (sample "(Float e)" "2.71828182845905"))
      %e)
    (method tau (self)
      (doc "The turn constant tau = 2*pi, 6.28318530..."
        (returns FLOAT "tau")
        (sample "(Float tau)" "6.28318530717959"))
      (%f-add %pi %pi))

    ; --- IEEE-special predicates (#363) ---
    ; Bit tests on the stored pattern: exponent all-ones ((<< 2047 52),
    ; 0x7FF0000000000000) marks the specials; the 52 mantissa bits split
    ; NaN from infinity. The masks are DERIVED, not written out: a 17+-
    ; digit decimal literal parses as a BIGINT wherever num/bigint has
    ; capped the int reader, and & refuses bigints. All three are TOTAL
    ; predicates: #f, never a raise, off-domain.
    (method nan? (self (param x ANY "Value to test"))
      (doc "Is x a float NaN? #f for every non-float (an int is never NaN)."
        (returns BOOL "#t only for a NaN float")
        (sample "(Float nan? (/ 0.0 0.0))" "#t"))
      (if (%float? x)
        (let ((em (<< 2047 52)))
          (if (= (& (first x) em) em)
            (not (= (& (first x) (- (<< 1 52) 1)) 0))
            #f))
        #f))
    (method inf? (self (param x ANY "Value to test"))
      (doc "Is x a float infinity, either sign? #f for every non-float."
        (returns BOOL "#t only for an infinite float")
        (sample "(Float inf? (/ 1.0 0.0))" "#t"))
      (if (%float? x)
        (let ((em (<< 2047 52)))
          (if (= (& (first x) em) em)
            (= (& (first x) (- (<< 1 52) 1)) 0)
            #f))
        #f))
    (method finite? (self (param x ANY "Value to test"))
      (doc "Is x a finite number? #t for machine INTs and finite floats; #f for float inf/NaN and for everything else (rational/bigint instances answer through their own classes)."
        (returns BOOL "#t for machine ints and finite floats")
        (sample "(Float finite? 42)" "#t"))
      (match
        ((%float? x)
         (let ((em (<< 2047 52)))
           (not (= (& (first x) em) em))))
        ((number? x) #t)
        (#t #f)))))

; Value dispatch (subject-last): (3.14 float?) -> (Float float? 3.14).
(def %type-push-call (prim-ref 'type 'push-call))
(%type-push-call (%type-by-atom %float) (%class-call-handler Float))

; Join the pact last, once the module is fully usable: any registration
; waiting on float fires against the finished class and type ops.
(Pact join 'float %float)

(doc (provide x/num/float Float)
  (note "Literal syntax: 3.14. The generic operators dispatch float operands")
  (note "through the type ops; mixed operands resolve by the from-relation.")
  (example "(+ 1 3.14)" "4.14")
  "IEEE 754 floating-point arithmetic, homed on the Float class.")
