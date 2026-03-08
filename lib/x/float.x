; float.x -- Floating-point type with IEEE 754 bit-pattern storage
;
; Float values are stored as IEEE 754 double bit patterns inside integers.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).

; Forward-declare reader and convert handler
(def %float-read ())
(def %float-convert ())

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

; Reader: called by tokenizer after successful analyse
(set %float-read (fn args
  (make-instance %float (float-read (first args)))))

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
(def f> (fn (a b) (ffi-call "d>d" () (first a) (first b))))
(def f= (fn (a b) (ffi-call "d=d" () (first a) (first b))))
(def f<= (fn (a b) (ffi-call "d<=d" () (first a) (first b))))
(def f>= (fn (a b) (ffi-call "d>=d" () (first a) (first b))))

; --- Math functions via dlopen ---
; Load math library from current process (linked with -lm)
(def %libm (dlopen () 1))

(def fsin  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "sin") (first x)))))
(def fcos  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "cos") (first x)))))
(def ftan  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "tan") (first x)))))
(def fsqrt (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "sqrt") (first x)))))
(def fexp  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "exp") (first x)))))
(def flog  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "log") (first x)))))
(def fabs  (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "fabs") (first x)))))
(def ffloor (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "floor") (first x)))))
(def fceil (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "ceil") (first x)))))
(def fround (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "round") (first x)))))
(def fpow  (fn (a b) (make-instance %float
  (ffi-call "dd->d" (dlsym %libm "pow") (first a) (first b)))))
(def fatan2 (fn (a b) (make-instance %float
  (ffi-call "dd->d" (dlsym %libm "atan2") (first a) (first b)))))
(def fasin (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "asin") (first x)))))
(def facos (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "acos") (first x)))))
(def fatan (fn (x) (make-instance %float
  (ffi-call "d->d" (dlsym %libm "atan") (first x)))))

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
(def %int> >)
(def %int= =)
(def %int<= <=)
(def %int>= >=)

; Promote to float via convert handler
(def %ensure-float (fn (x) (convert x %float)))

; Generator for binary fold-based arithmetic (+, *, /)
(def %make-float-binop (fn (int-op float-op)
  (fn args
    (if (null? args) (int-op)
      (fold (fn (acc x)
        (if (or (float? acc) (float? x))
          (float-op (%ensure-float acc) (%ensure-float x))
          (int-op acc x)))
        (first args) (rest args))))))

(def + (%make-float-binop %int+ f+))
(def * (%make-float-binop %int* f*))
(def / (%make-float-binop %int/ f/))

; - is special: unary negation case
(def - (fn args
  (if (null? args) 0
    (if (null? (rest args))
      (if (float? (first args))
        (f- (exact->inexact 0) (first args))
        (%int- (first args)))
      (fold (fn (acc x)
        (if (or (float? acc) (float? x))
          (f- (%ensure-float acc) (%ensure-float x))
          (%int- acc x)))
        (first args) (rest args))))))

; Generator for coerced comparisons
(def %make-float-cmp (fn (int-op float-op)
  (fn (a b)
    (if (or (float? a) (float? b))
      (float-op (%ensure-float a) (%ensure-float b))
      (int-op a b)))))

(def <  (%make-float-cmp %int<  f<))
(def >  (%make-float-cmp %int>  f>))
(def =  (%make-float-cmp %int=  f=))
(def <= (%make-float-cmp %int<= f<=))
(def >= (%make-float-cmp %int>= f>=))

; --- R7RS predicates ---
(def integer? number?)
(def %int-number? number?)
(def number? (fn (x) (or (%int-number? x) (float? x))))
(def real? number?)
(def inexact? float?)
