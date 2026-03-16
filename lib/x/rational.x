; rational.x -- Rational number type (exact fractions)
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
  (fn (a b)
    (if (%int= b 0) a
      (%gcd b (%int- a (%int* b (%int/ a b)))))))

(def %abs (fn (n) (if (%int< n 0) (%int- 0 n) n)))
; --- Find '/' position in string ---

(def %rat-find-slash
  (fn (s i len)
    (if (>= i len) ()
      (if (= (char->integer (string-ref s i)) 47)
        i
        (%rat-find-slash s (%int+ i 1) len)))))
; --- Constructor: auto-reduce and normalize sign ---

(def %make-rational
  (fn (n d)
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

(set %rat-denom
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

(def %rat-first-denom
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (score-set score 1 buffer) %rat-denom)
      ())))
; Integer digits before '/'

(def %rat-numer ())

(set %rat-numer
  (fn (buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      %rat-numer
      (if (= chr 47) %rat-first-denom ()))))
; --- Rational type ---

(set %rational
  (make-type
    "RATIONAL"
    (list
      (pair
        (lit write)
        (fn (self)
          (display (first (first self)))
          (display "/")
          (display (rest (first self)))))
      (pair (lit first-chars) "0123456789-+")
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (and (>= chr 48) (<= chr 57))
            %rat-numer
            (if (= chr 45)
              (fn (buffer score chr)
                (if (and (>= chr 48) (<= chr 57))
                  %rat-numer
                  ()))
              (if (= chr 43)
                (fn (buffer score chr)
                  (if (and (>= chr 48) (<= chr 57))
                    %rat-numer
                    ()))
                ())))))
      (pair (lit read) (fn args (%rational-read (first args))))
      (pair
        (lit from)
        (list
          (pair (type-of 42) (fn (value) (%make-rational value 1)))
          (pair
            (type-of "")
            (fn (value)
              (let ((pos (%rat-find-slash value 0 (string-length value))))
                (if pos
                  (%make-rational
                    (string->number (substring value 0 pos))
                    (string->number
                      (substring value (%int+ pos 1) (string-length value))))
                  ()))))))
      (pair
        (lit to)
        (list
          (pair (type-of 42)
            (fn (self) (%int/ (first (first self)) (rest (first self)))))
          (pair %float
            (fn (self)
              (f/
                (make-instance %float (int->float (first (first self))))
                (make-instance %float (int->float (rest (first self)))))))
          (pair (type-of "")
            (fn (self)
              (string-append
                (string-append (number->string (first (first self))) "/")
                (number->string (rest (first self)))))))))))
; --- Predicates ---

(def rational? (fn (x) (if (type? x %rational) #t (%int-number? x))))

(def exact? (fn (x) (if (type? x %rational) #t (%int-number? x))))
; --- Accessors ---

(def numerator
  (fn (x) (if (type? x %rational) (first (first x)) x)))

(def denominator
  (fn (x) (if (type? x %rational) (rest (first x)) 1)))
; --- Arithmetic ---

(def %rat-numer-of
  (fn (x) (if (type? x %rational) (first (first x)) x)))

(def %rat-denom-of
  (fn (x) (if (type? x %rational) (rest (first x)) 1)))

(def rat+
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int+ (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))

(def rat-
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational
        (%int- (%int* an bd) (%int* bn ad))
        (%int* ad bd)))))

(def rat*
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bn) (%int* ad bd)))))

(def rat/
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%make-rational (%int* an bd) (%int* ad bn)))))
; --- Comparisons ---

(def rat<
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int< (%int* an bd) (%int* bn ad)))))

(def rat=
  (fn (a b)
    (let ((an (%rat-numer-of a)) (ad (%rat-denom-of a))
          (bn (%rat-numer-of b)) (bd (%rat-denom-of b)))
      (%int= (%int* an bd) (%int* bn ad)))))
; --- Operator promotion: int -> rational -> float ---
; Save float-aware operators before overriding

(def %num+ +)
(def %num- -)
(def %num* *)
(def %num/ /)
(def %num< <)
(def %num= =)

(def %rat? (fn (x) (type? x %rational)))

; Binary operation with promotion
(def %rat-binop
  (fn (rat-op float-op int-op a b)
    (if (float? a) (float-op a (if (float? b) b (%ensure-float b)))
      (if (float? b) (float-op (%ensure-float a) b)
        (if (%rat? a) (if (%rat? b) (rat-op a b)
                        (rat-op a (%make-rational b 1)))
          (if (%rat? b) (rat-op (%make-rational a 1) b)
            (int-op a b)))))))

; Fold for variadic ops
(def %rat-fold
  (fn (rat-op float-op int-op acc lst)
    (if (null? lst) acc
      (%rat-fold rat-op float-op int-op
        (%rat-binop rat-op float-op int-op acc (first lst))
        (rest lst)))))

(set +
  (fn args
    (if (null? args) 0
      (%rat-fold rat+ f+ %int+ (first args) (rest args)))))

(set *
  (fn args
    (if (null? args) 1
      (%rat-fold rat* f* %int* (first args) (rest args)))))

; Integer division that produces rational when not exact
(def %exact-div
  (fn (a b)
    (if (= (%int- a (%int* b (%int/ a b))) 0)
      (%int/ a b)
      (%make-rational a b))))

(set /
  (fn args
    (if (null? args) 1
      (if (null? (rest args))
        (%rat-binop rat/ f/ %exact-div 1 (first args))
        (%rat-fold rat/ f/ %exact-div (first args) (rest args))))))

(set -
  (fn args
    (if (null? args) 0
      (if (null? (rest args))
        (if (float? (first args))
          (f- (exact->inexact 0) (first args))
          (if (%rat? (first args))
            (rat- (%make-rational 0 1) (first args))
            (%int- (first args))))
        (%rat-fold rat- f- %int- (first args) (rest args))))))

(set <
  (fn (a b)
    (if (float? a) (f< a (%ensure-float b))
      (if (float? b) (f< (%ensure-float a) b)
        (if (%rat? a) (rat< a (if (%rat? b) b (%make-rational b 1)))
          (if (%rat? b) (rat< (%make-rational a 1) b)
            (%int< a b)))))))

(set =
  (fn (a b)
    (if (float? a) (f= a (%ensure-float b))
      (if (float? b) (f= (%ensure-float a) b)
        (if (%rat? a) (rat= a (if (%rat? b) b (%make-rational b 1)))
          (if (%rat? b) (rat= (%make-rational a 1) b)
            (%int= a b)))))))
; Harden % against / override (/ now produces rationals)
(set % (fn (a b) (%int- a (%int* b (%int/ a b)))))
; --- Reader ---

(set %rational-read
  (fn args
    (let ((tok (buffer-token (first args))))
      (let ((pos (%rat-find-slash tok 0 (string-length tok))))
        (if pos
          (%make-rational
            (string->number (substring tok 0 pos))
            (string->number
              (substring tok (%int+ pos 1) (string-length tok))))
          ())))))
