; rational.x -- Rational number type (exact fractions)
(import x/float)
;
; Rational values are stored as (numerator . denominator) pairs,
; auto-reduced via GCD on construction. The tokenizer matches
; [+-]?[0-9]+/[0-9]+ and outscores the integer tokenizer.
;
; Promotion chain: integer -> rational -> float
; Forward-declare reader and type handle

(def %rational-read ())
(def %rational ())
; --- GCD (Euclidean algorithm) ---

(def %gcd
  (fn (_ a b)
    (if (%int= b 0) a
      (%gcd b (%int- a (%int* b (%int/ a b)))))))

(def %abs (fn (_ n) (if (%int< n 0) (%int- 0 n) n)))
; --- Find '/' position in string ---

(def %rat-find-slash
  (fn (_ s i len)
    (if (>= i len) ()
      (if (= (convert (string-ref s i) %int) 47)
        i
        (%rat-find-slash s (%int+ i 1) len)))))
; --- Constructor: auto-reduce and normalize sign ---

(def %make-rational
  (fn (_ n d)
    (if (%int= d 0) (error "division by zero")
      (let ((g (%gcd (%abs n) (%abs d))))
        (let ((rn (%int/ n g)) (rd (%int/ d g)))
          ; Normalize: denominator always positive
          (if (%int< rd 0)
            (make-instance %rational (pair (%int- 0 rn) (%int- 0 rd)))
            ; Reduce to integer if denominator is 1
            (if (%int= rd 1) rn
              (make-instance %rational (pair rn rd)))))))))
; --- Tokenizer state machine: [+-]?[0-9]+/[0-9]+ ---
; After '/' — must see at least one digit

(def %rat-denom ())

(set! %rat-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

(def %rat-first-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      ())))
; Integer digits before '/'

(def %rat-numer ())

(set! %rat-numer
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %rat-numer
      (if (= chr 47) %rat-first-denom ()))))
; --- Rational type ---

(set! %rational
  (make-type
    "RATIONAL"
    (list
      (pair
        (lit write)
        (fn (_ self)
          (display (first (first self)))
          (display "/")
          (display (rest (first self)))))
      (pair (lit first-chars) "0123456789-+")
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57))
            %rat-numer
            (if (= chr 45)
              (fn (_ buffer score chr)
                (if (and (>= chr 48) (<= chr 57))
                  %rat-numer
                  ()))
              (if (= chr 43)
                (fn (_ buffer score chr)
                  (if (and (>= chr 48) (<= chr 57))
                    %rat-numer
                    ()))
                ())))))
      (pair (lit read) (fn (_ . args) (%rational-read (first args))))
      (pair
        (lit from)
        (list
          (pair (type-of 42) (fn (_ value) (%make-rational value 1)))
          (pair
            (type-of "")
            (fn (_ value)
              (let ((pos (%rat-find-slash value 0 (string-length value))))
                (if pos
                  (%make-rational
                    (convert (substring value 0 pos) %int)
                    (convert
                      (substring value (%int+ pos 1) (string-length value)) %int))
                  ()))))))
      (pair
        (lit to)
        (list
          (pair (type-of 42)
            (fn (_ self) (%int/ (first (first self)) (rest (first self)))))
          (pair %float
            (fn (_ self)
              (f/
                (make-instance %float (int->float (first (first self))))
                (make-instance %float (int->float (rest (first self)))))))
          (pair (type-of "")
            (fn (_ self)
              (string-append
                (string-append (convert (first (first self)) %string) "/")
                (convert (rest (first self)) %string)))))))))
; --- Predicates ---

(note "Predicates")

(doc (def rational? (fn (_ (param x ANY "Value to test")) (if (type? x %rational) #t (%int-number? x))))
  (returns BOOLEAN "True if x is rational or integer")
  "Test whether a value is a rational number or integer.")

(doc (def exact? (fn (_ (param x ANY "Value to test")) (if (type? x %rational) #t (%int-number? x))))
  (returns BOOLEAN "True if x is exact (rational or integer)")
  "Test whether a value is an exact number.")
; --- Accessors ---

(note "Accessors")

(doc (def numerator
  (fn (_ (param x RATIONAL|INTEGER "Rational or integer"))
    (if (type? x %rational) (first (first x)) x)))
  (returns INTEGER "Numerator of the rational, or the integer itself")
  "Return the numerator of a rational number.")

(doc (def denominator
  (fn (_ (param x RATIONAL|INTEGER "Rational or integer"))
    (if (type? x %rational) (rest (first x)) 1)))
  (returns INTEGER "Denominator of the rational, or 1 for integers")
  "Return the denominator of a rational number.")
; --- Arithmetic ---

(note "Arithmetic")

; Use public accessors — no private duplicates
(def %rat-numer-of numerator)
(def %rat-denom-of denominator)

(doc (def rat+
  (fn (_ (param a RATIONAL|INTEGER "First operand")
       (param b RATIONAL|INTEGER "Second operand"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int+ (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))
  (returns RATIONAL|INTEGER "Sum, reduced to lowest terms")
  "Add two rational numbers.")

(doc (def rat-
  (fn (_ (param a RATIONAL|INTEGER "First operand")
       (param b RATIONAL|INTEGER "Second operand"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int- (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))
  (returns RATIONAL|INTEGER "Difference, reduced to lowest terms")
  "Subtract two rational numbers.")

(doc (def rat*
  (fn (_ (param a RATIONAL|INTEGER "First operand")
       (param b RATIONAL|INTEGER "Second operand"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bn) (%int* ad bd)))))
  (returns RATIONAL|INTEGER "Product, reduced to lowest terms")
  "Multiply two rational numbers.")

(doc (def rat/
  (fn (_ (param a RATIONAL|INTEGER "Dividend")
       (param b RATIONAL|INTEGER "Divisor"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bd) (%int* ad bn)))))
  (returns RATIONAL|INTEGER "Quotient, reduced to lowest terms")
  "Divide two rational numbers.")
; --- Comparisons ---

(note "Comparison")

(doc (def rat<
  (fn (_ (param a RATIONAL|INTEGER "Left operand")
       (param b RATIONAL|INTEGER "Right operand"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int< (%int* an bd) (%int* bn ad)))))
  (returns BOOLEAN "True if a < b")
  "Test whether rational a is less than rational b.")

(doc (def rat=
  (fn (_ (param a RATIONAL|INTEGER "Left operand")
       (param b RATIONAL|INTEGER "Right operand"))
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int= (%int* an bd) (%int* bn ad)))))
  (returns BOOLEAN "True if a equals b")
  "Test whether two rational numbers are equal.")
; --- Operator promotion: int -> rational -> float ---

(note "Operator Overrides")
; Save float-aware operators before overriding

(def %num+ +)
(def %num- -)
(def %num* *)
(def %num/ /)
(def %num< <)
(def %num= =)

(def %rat? (fn (_ x) (type? x %rational)))

; Binary operation with promotion
(def %rat-binop
  (fn (_ rat-op float-op int-op a b)
    (if (float? a) (float-op a (if (float? b) b (%ensure-float b)))
      (if (float? b) (float-op (%ensure-float a) b)
        (if (%rat? a) (if (%rat? b) (rat-op a b)
                        (rat-op a (%make-rational b 1)))
          (if (%rat? b) (rat-op (%make-rational a 1) b)
            (int-op a b)))))))

; Fold for variadic ops
(def %rat-fold
  (fn (_ rat-op float-op int-op acc lst)
    (if (null? lst) acc
      (%rat-fold rat-op float-op int-op
        (%rat-binop rat-op float-op int-op acc (first lst))
        (rest lst)))))

(doc + "Add numbers with int/rational/float promotion."
  (param args NUMBER "Numbers to add")
  (returns NUMBER "Sum"))
(set! +
  (fn (_ . args)
    (if (null? args) 0
      (%rat-fold rat+ f+ %num+ (first args) (rest args)))))

(doc * "Multiply numbers with int/rational/float promotion."
  (param args NUMBER "Numbers to multiply")
  (returns NUMBER "Product"))
(set! *
  (fn (_ . args)
    (if (null? args) 1
      (%rat-fold rat* f* %num* (first args) (rest args)))))

; Integer division that produces rational when not exact
(def %exact-div
  (fn (_ a b)
    (if (= (%int- a (%int* b (%int/ a b))) 0)
      (%int/ a b)
      (%make-rational a b))))

(doc / "Divide numbers with int/rational/float promotion. Integer division produces rationals when not exact."
  (param args NUMBER "Numbers to divide")
  (returns NUMBER "Quotient"))
(set! /
  (fn (_ . args)
    (if (null? args) 1
      (if (null? (rest args))
        (%rat-binop rat/ f/ %exact-div 1 (first args))
        (%rat-fold rat/ f/ %exact-div (first args) (rest args))))))

(doc - "Subtract numbers with int/rational/float promotion. Unary form negates."
  (param args NUMBER "Numbers to subtract")
  (returns NUMBER "Difference"))
(set! -
  (fn (_ . args)
    (if (null? args) 0
      (if (null? (rest args))
        (if (float? (first args))
          (f- (exact->inexact 0) (first args))
          (if (%rat? (first args))
            (rat- (%make-rational 0 1) (first args))
            (%num- (first args))))
        (%rat-fold rat- f- %num- (first args) (rest args))))))

(doc < "Compare numbers with int/rational/float promotion."
  (param a NUMBER "Left operand")
  (param b NUMBER "Right operand")
  (returns BOOLEAN "True if a < b"))
(set! <
  (fn (_ a b)
    (if (float? a) (f< a (%ensure-float b))
      (if (float? b) (f< (%ensure-float a) b)
        (if (%rat? a) (rat< a (if (%rat? b) b (%make-rational b 1)))
          (if (%rat? b) (rat< (%make-rational a 1) b)
            (%num< a b)))))))

(doc = "Test equality with int/rational/float promotion."
  (param a NUMBER "Left operand")
  (param b NUMBER "Right operand")
  (returns BOOLEAN "True if a equals b"))
(set! =
  (fn (_ a b)
    (if (float? a) (f= a (%ensure-float b))
      (if (float? b) (f= (%ensure-float a) b)
        (if (%rat? a) (rat= a (if (%rat? b) b (%make-rational b 1)))
          (if (%rat? b) (rat= (%make-rational a 1) b)
            (%num= a b)))))))
; Harden % against / override (/ now produces rationals)
(doc % "Integer remainder, hardened against rational / override."
  (param a INTEGER "Dividend")
  (param b INTEGER "Divisor")
  (returns INTEGER "Remainder"))
(set! % (fn (_ a b) (%int- a (%int* b (%int/ a b)))))
; --- Reader ---

(set! %rational-read
  (fn (_ . args)
    (let ((tok (buffer-token (first args))))
      (let ((pos (%rat-find-slash tok 0 (string-length tok))))
        (if pos
          (%make-rational
            (convert (substring tok 0 pos) %int)
            (convert
              (substring tok (%int+ pos 1) (string-length tok)) %int))
          ())))))

(doc (provide x/rational
  rational? exact? numerator denominator rat+ rat- rat* rat/ rat< rat=)
  (note "Literal syntax: 1/3, -2/7. Extends +,-,*,/,%,<,=.")
  (example "(+ 1/3 1/6)" "1/2")
  "Exact rational number arithmetic.")
