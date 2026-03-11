; float.x -- Floating-point type with IEEE 754 bit-pattern storage
;
; Float values are stored as IEEE 754 double bit patterns inside integers.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).
;
; All float conversion functions use generic ffi-call conventions,
; eliminating the need for any float-specific C primitives.

; Forward-declare reader
(def %float-read ())

; --- FFI-based conversion functions ---
; These use generic ffi-call conventions (no function pointer needed)
(def float->string (fn (bits) (ffi-call "d->s" () bits)))
(def int->float (fn (n) (ffi-call "i->d" () n)))
(def float->int (fn (bits) (ffi-call "d->i" () bits)))

; State machine for tokenizer: matches [0-9]+\.[0-9]+
; Uses intrinsic scoring — score computed from buffer length.

; After first fractional digit: continue digits or score
(def %float-frac ())
(set %float-frac (fn (buffer score chr)
  (if (and (>= chr 48) (<= chr 57))
    %float-frac
    (do (buffer-unread buffer) (score-set score 1 buffer %float-read)))))

; Must see at least one digit after '.'
(def %float-first-frac (fn (buffer score chr)
  (if (and (>= chr 48) (<= chr 57))
    (do (score-set score 1 buffer %float-read) %float-frac)
    ())))

; Integer part: digits until '.'
(def %float-int-digits ())
(set %float-int-digits (fn (buffer score chr)
  (if (and (>= chr 48) (<= chr 57))
    %float-int-digits
    (if (= chr 46)
      %float-first-frac
      ()))))

; --- Math library for strtod (needed by convert alist) ---
(def %libm (dlopen () 1))
(def %strtod (dlsym %libm "strtod"))
(def string->float (fn (s) (ffi-call "s0->d" %strtod s)))

; Float type with tokenizer, display, and alist-based convert
(def %float (make-type "FLOAT"
  (list
    (pair (lit write) (fn (self)
      (display (float->string (first self)))))
    (pair (lit analyse) (fn (buffer score chr)
      ; Entry: must start with digit [0-9]
      (if (and (>= chr 48) (<= chr 57))
        %float-int-digits
        ())))
    (pair (lit from)
      (list
        (pair (type-of 42) (fn (value)
          (make-instance %float (int->float value))))
        (pair (type-of "") (fn (value)
          (make-instance %float (string->float value))))))
    (pair (lit to)
      (list
        (pair (type-of 42) (fn (self) (float->int (first self))))
        (pair (type-of "") (fn (self) (float->string (first self)))))))))

; --- Predicates and constructors ---
(def float? (fn (x) (type? x %float)))

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

; Reader: called by tokenizer after successful analyse
; Uses buffer-token to extract consumed text, then strtod to parse
(set %float-read (fn args
  (make-instance %float (ffi-call "s0->d" %strtod (buffer-token (first args))))))

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
; %int+, %int-, %int*, %int/, %int<, %int= already saved by x-core.x

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
; %int-number? already saved by x-core.x
(def integer? number?)
(set number? (fn (x) (if (%int-number? x) t (float? x))))
(def real? number?)
(def inexact? float?)
