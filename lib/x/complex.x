; complex.x -- Complex number type
;
; Complex values are stored as (real-part . imag-part) pairs.
; Components can be any real number type (integer, rational, float).
;
; Promotion chain: integer -> rational -> float -> complex

(def %complex ())
(def %cx-read ())
; --- Constructor: collapse to real when imag is exactly integer 0 ---

(def %make-complex
  (fn (re im)
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

(def %complex? (fn (x) (type? x %complex)))

(def %complex-re
  (fn (x) (if (%complex? x) (first (first x)) x)))

(def %complex-im
  (fn (x) (if (%complex? x) (rest (first x)) 0)))
; --- Tokenizer state machine for complex literals ---
; Matches: <digits>[.<digits>][+-]<digits>[.<digits>]i
; Also: <digits>[.<digits>]i  (pure imaginary)

(def %cx-imag-frac ())
(set! %cx-imag-frac
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-frac
      (if (= chr 105)
        (score-set score 1 buffer)
        ()))))

(def %cx-imag-dot
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-frac
      ())))

(def %cx-imag-int ())
(set! %cx-imag-int
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-int
      (if (= chr 46)
        %cx-imag-dot
        (if (= chr 105)
          (score-set score 1 buffer)
          ())))))

(def %cx-sign
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-imag-int
      ())))

(def %cx-real-frac ())
(set! %cx-real-frac
  (fn (buffer score chr)
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
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %cx-real-frac
      ())))

(def %cx-real-int ())
(set! %cx-real-int
  (fn (buffer score chr)
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
  (fn (s i len ch)
    (if (>= i len) ()
      (if (= (char->integer (string-ref s i)) ch)
        i
        (%cx-find-char s (%int+ i 1) len ch)))))

(def %cx-parse-num
  (fn (s)
    (if (%cx-find-char s 0 (string-length s) 46)
      (make-instance %float (string->float s))
      (convert s %int))))

(set! %cx-read
  (fn args
    (let ((tok (buffer-token (first args))))
      (let ((len (string-length tok)))
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
        (fn (self)
          (let ((re (first (first self))) (im (rest (first self))))
            (display re)
            (if (not (%real< im 0)) (display "+"))
            (display im)
            (display "i"))))
      (pair (lit first-chars) "0123456789")
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) %cx-real-int ())))
      (pair (lit read) (fn args (%cx-read (first args))))
      (pair
        (lit from)
        (list
          (pair (type-of 42) (fn (value) (%make-complex value 0)))
          (pair %float (fn (value) (%make-complex value 0)))
          (pair %rational (fn (value) (%make-complex value 0)))))
      (pair
        (lit to)
        (list
          (pair (type-of "")
            (fn (self) (write-to-string self))))))))
; --- Arithmetic ---

(def complex+
  (fn (a b)
    (%make-complex
      (%real+ (%complex-re a) (%complex-re b))
      (%real+ (%complex-im a) (%complex-im b)))))

(def complex-
  (fn (a b)
    (%make-complex
      (%real- (%complex-re a) (%complex-re b))
      (%real- (%complex-im a) (%complex-im b)))))

(def complex*
  (fn (a b)
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (%make-complex
        (%real- (%real* ar br) (%real* ai bi))
        (%real+ (%real* ar bi) (%real* ai br))))))

(def complex/
  (fn (a b)
    (let ((ar (%complex-re a)) (ai (%complex-im a))
          (br (%complex-re b)) (bi (%complex-im b)))
      (let ((denom (%real+ (%real* br br) (%real* bi bi))))
        (%make-complex
          (%real/ (%real+ (%real* ar br) (%real* ai bi)) denom)
          (%real/ (%real- (%real* ai br) (%real* ar bi)) denom))))))

(def complex=
  (fn (a b)
    (if (%real= (%complex-re a) (%complex-re b))
      (%real= (%complex-im a) (%complex-im b))
      ())))
; --- R5RS constructors and accessors ---

(def make-rectangular
  (fn (re im) (%make-complex re im)))

(def make-polar
  (fn (mag ang)
    (let ((fang (exact->inexact ang)) (fmag (exact->inexact mag)))
      (%make-complex
        (f* fmag (fcos fang))
        (f* fmag (fsin fang))))))

(def real-part %complex-re)

(def imag-part %complex-im)

(def magnitude
  (fn (z)
    (if (%complex? z)
      (let ((re (exact->inexact (%complex-re z)))
            (im (exact->inexact (%complex-im z))))
        (fsqrt (f+ (f* re re) (f* im im))))
      (if (%real< z 0)
        (exact->inexact (%real- 0 z))
        (exact->inexact z)))))

(def angle
  (fn (z)
    (if (%complex? z)
      (fatan2
        (exact->inexact (%complex-im z))
        (exact->inexact (%complex-re z)))
      (if (%real< z 0) %pi (exact->inexact 0)))))
; --- Operator promotion: add complex layer ---

(def %complex-fold
  (fn (complex-op real-op acc lst)
    (if (null? lst) acc
      (%complex-fold complex-op real-op
        (if (%complex? acc)
          (complex-op acc (first lst))
          (if (%complex? (first lst))
            (complex-op acc (first lst))
            (real-op acc (first lst))))
        (rest lst)))))

(set! +
  (fn args
    (if (null? args) 0
      (%complex-fold complex+ %real+ (first args) (rest args)))))

(set! *
  (fn args
    (if (null? args) 1
      (%complex-fold complex* %real* (first args) (rest args)))))

(set! /
  (fn args
    (if (null? args) 1
      (if (null? (rest args))
        (if (%complex? (first args))
          (complex/ (%make-complex 1 0) (first args))
          (%real/ 1 (first args)))
        (%complex-fold complex/ %real/ (first args) (rest args))))))

(set! -
  (fn args
    (if (null? args) 0
      (if (null? (rest args))
        (if (%complex? (first args))
          (complex- (%make-complex 0 0) (first args))
          (%real- (first args)))
        (%complex-fold complex- %real- (first args) (rest args))))))

(set! =
  (fn (a b)
    (if (%complex? a)
      (complex= a (if (%complex? b) b (%make-complex b 0)))
      (if (%complex? b)
        (complex= (%make-complex a 0) b)
        (%real= a b)))))
; --- Predicates ---

(set! number?
  (fn (x)
    (if (%complex? x) #t
      (if (%rat? x) #t
        (if (float? x) #t
          (%int-number? x))))))

(def complex? number?)

(set! real?
  (fn (x)
    (if (%rat? x) #t
      (if (float? x) #t
        (%int-number? x)))))
