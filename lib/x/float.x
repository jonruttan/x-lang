; float.x -- Floating-point type with IEEE 754 bit-pattern storage
;
; Float values are stored as IEEE 754 double bit patterns inside integers.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).
;
; All float conversion functions use generic ffi-call conventions,
; eliminating the need for any float-specific C primitives.

; Forward-declare reader and convert handler
(def %float-read ())
(def %float-convert ())

; --- FFI-based conversion functions ---
; These use generic ffi-call conventions (no function pointer needed)
(def float->string (fn (bits) (ffi-call "d->s" () bits)))
(def int->float (fn (n) (ffi-call "i->d" () n)))
(def float->int (fn (bits) (ffi-call "d->i" () bits)))

; State machine for tokenizer: matches [0-9]+\.[0-9]+
; Each state returns a closure capturing match length.

; After first fractional digit: continue digits or score
(def make-float-frac (fn (len)
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (make-float-frac (+ len 1))
      (score-match score len %float-read)))))

; Must see at least one digit after '.'
(def make-float-first-frac (fn (len)
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (make-float-frac (+ len 1))
      ()))))

; Integer part: digits until '.'
(def make-float-int-digits (fn (len)
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (make-float-int-digits (+ len 1))
      (if (= chr 46)
        (make-float-first-frac (+ len 1))
        ())))))

; Float type with tokenizer, display, and convert handler
(def %float (make-type "FLOAT"
  (list
    (pair (lit write) (fn (self)
      (display (float->string (first self)))))
    (pair (lit analyse) (fn (buffer score chr)
      ; Entry: must start with digit [0-9]
      (if (and (>= chr 48) (<= chr 57))
        (make-float-int-digits 1)
        ())))
    (pair (lit convert) (fn (value)
      (%float-convert value))))))

; --- Predicates and constructors ---
(def float? (fn (x) (type? x %float)))

; Convert handler: called by (convert value %float)
; Defined after float? so the closure can capture it
(set %float-convert (fn (value)
  (if (float? value) value
    (if (number? value)
      (make-instance %float (int->float value))
      ()))))

(def exact->inexact (fn (x) (convert x %float)))
(def inexact->exact (fn (x) (float->int (first x))))

; --- Arithmetic ---
(def f+ (fn (a b)
  (make-instance %float (ffi-call "d+d" () (first a) (first b)))))
(def f- (fn (a b)
  (make-instance %float (ffi-call "d-d" () (first a) (first b)))))
(def f* (fn (a b)
  (make-instance %float (ffi-call "d*d" () (first a) (first b)))))
(def f/ (fn (a b)
  (make-instance %float (ffi-call "d/d" () (first a) (first b)))))

; --- Comparisons ---
(def f< (fn (a b) (ffi-call "d<d" () (first a) (first b))))
(def f= (fn (a b) (ffi-call "d=d" () (first a) (first b))))

; --- Math functions via dlopen ---
; Load math library from current process (linked with -lm)
(def %libm (dlopen () 1))

; string->float via strtod from libc
(def %strtod (dlsym %libm "strtod"))
(def string->float (fn (s) (ffi-call "s0->d" %strtod s)))

; Reader: called by tokenizer after successful analyse
; Buffer's char* is accessed the same way as string's, so s0->d works
(set %float-read (fn args
  (make-instance %float (ffi-call "s0->d" %strtod (first args)))))

; Factory: resolve dlsym at definition time, return closure with cached pointer
(def %libm-d  (fn (name) (let ((sym (dlsym %libm name))) (fn (x) (make-instance %float (ffi-call "d->d" sym (first x)))))))
(def %libm-dd (fn (name) (let ((sym (dlsym %libm name))) (fn (a b) (make-instance %float (ffi-call "dd->d" sym (first a) (first b)))))))

(def fsin   (%libm-d "sin"))
(def fcos   (%libm-d "cos"))
(def ftan   (%libm-d "tan"))
(def fsqrt  (%libm-d "sqrt"))
(def fexp   (%libm-d "exp"))
(def flog   (%libm-d "log"))
(def fabs   (%libm-d "fabs"))
(def ffloor (%libm-d "floor"))
(def fceil  (%libm-d "ceil"))
(def fround (%libm-d "round"))
(def ftrunc (%libm-d "trunc"))
(def frint  (%libm-d "rint"))
(def fasin  (%libm-d "asin"))
(def facos  (%libm-d "acos"))
(def fatan  (%libm-d "atan"))
(def fpow   (%libm-dd "pow"))
(def fatan2 (%libm-dd "atan2"))

; --- Constants ---
(def %pi (fatan2 (exact->inexact 0) (exact->inexact -1)))
(def %e  (fexp (exact->inexact 1)))

; --- Generic arithmetic overrides ---
; Save original integer operations
(def %int+ +)
(def %int- -)
(def %int* *)
(def %int/ /)
(def %int< <)
(def %int= =)

; Promote to float via convert handler
(def %ensure-float (fn (x) (convert x %float)))

; Helper: fold with float coercion
(def %float-fold (fn (int-op float-op acc lst)
  (if (null? lst) acc
    (%float-fold int-op float-op
      (if (float? acc)
        (float-op acc (%ensure-float (first lst)))
        (if (float? (first lst))
          (float-op (%ensure-float acc) (first lst))
          (int-op acc (first lst))))
      (rest lst)))))

; Inlined overrides — avoid or, avoid closure variable lookup
(set + (fn args
  (if (null? args) 0
    (%float-fold %int+ f+ (first args) (rest args)))))

(set * (fn args
  (if (null? args) 1
    (%float-fold %int* f* (first args) (rest args)))))

(set / (fn args
  (if (null? args) 1
    (%float-fold %int/ f/ (first args) (rest args)))))

; - is special: unary negation case
(set - (fn args
  (if (null? args) 0
    (if (null? (rest args))
      (if (float? (first args))
        (f- (exact->inexact 0) (first args))
        (%int- (first args)))
      (%float-fold %int- f- (first args) (rest args))))))

; Comparisons — inline, no or
(set < (fn (a b)
  (if (float? a)
    (f< a (%ensure-float b))
    (if (float? b)
      (f< (%ensure-float a) b)
      (%int< a b)))))

(set = (fn (a b)
  (if (float? a)
    (f= a (%ensure-float b))
    (if (float? b)
      (f= (%ensure-float a) b)
      (%int= a b)))))

; --- R7RS predicates ---
(def integer? number?)
(def %int-number? number?)
(set number? (fn (x) (if (%int-number? x) t (float? x))))
(def real? number?)
(def inexact? float?)
