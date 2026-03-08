; float.x -- Floating-point type with IEEE 754 bit-pattern storage
;
; Float values are stored as IEEE 754 double bit patterns inside integers.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).

; Forward-declare reader
(def %float-read ())

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

; Float type with tokenizer and display
(def %float (make-type "FLOAT"
  (list
    (pair (lit write) (fn (self)
      (display (float->string (first self)))))
    (pair (lit analyse) (fn (buffer score chr)
      ; Entry: must start with digit [0-9]
      (if (and (>= chr 48) (<= chr 57))
        (make-float-int-digits 1)
        ()))))))

; Reader: called by tokenizer after successful analyse
(set %float-read (fn args
  (make-instance %float (float-read (first args)))))

; --- Predicates and constructors ---
(def float? (fn (x) (type? x %float)))
(def exact->inexact (fn (x)
  (if (float? x) x
    (make-instance %float (int->float x)))))
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

; Promote to float if either operand is float
(def %ensure-float (fn (x)
  (if (float? x) x (exact->inexact x))))

; Override + to handle floats
(def + (fn args
  (if (null? args) 0
    (fold (fn (acc x)
      (if (or (float? acc) (float? x))
        (f+ (%ensure-float acc) (%ensure-float x))
        (%int+ acc x)))
      (first args) (rest args)))))

; Override - to handle floats
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

; Override * to handle floats
(def * (fn args
  (if (null? args) 1
    (fold (fn (acc x)
      (if (or (float? acc) (float? x))
        (f* (%ensure-float acc) (%ensure-float x))
        (%int* acc x)))
      (first args) (rest args)))))

; Override / to handle floats
(def / (fn args
  (if (null? args) 1
    (fold (fn (acc x)
      (if (or (float? acc) (float? x))
        (f/ (%ensure-float acc) (%ensure-float x))
        (%int/ acc x)))
      (first args) (rest args)))))

; Override comparisons
(def < (fn (a b)
  (if (or (float? a) (float? b))
    (f< (%ensure-float a) (%ensure-float b))
    (%int< a b))))

(def > (fn (a b)
  (if (or (float? a) (float? b))
    (f> (%ensure-float a) (%ensure-float b))
    (%int> a b))))

(def = (fn (a b)
  (if (or (float? a) (float? b))
    (f= (%ensure-float a) (%ensure-float b))
    (%int= a b))))

(def <= (fn (a b)
  (if (or (float? a) (float? b))
    (f<= (%ensure-float a) (%ensure-float b))
    (%int<= a b))))

(def >= (fn (a b)
  (if (or (float? a) (float? b))
    (f>= (%ensure-float a) (%ensure-float b))
    (%int>= a b))))

; --- R7RS predicates ---
(def integer? number?)
(def %int-number? number?)
(def number? (fn (x) (or (%int-number? x) (float? x))))
(def real? number?)
(def inexact? float?)
