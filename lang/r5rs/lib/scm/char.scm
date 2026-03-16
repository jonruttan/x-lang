; --- Character comparisons (R5RS §6.3.4) ---

(define
  (char=? a b)
  (= (char->integer a) (char->integer b)))
(define
  (char<? a b)
  (< (char->integer a) (char->integer b)))
(define
  (char>? a b)
  (> (char->integer a) (char->integer b)))
(define
  (char<=? a b)
  (<= (char->integer a) (char->integer b)))
(define
  (char>=? a b)
  (>= (char->integer a) (char->integer b)))

; --- Character classification (R5RS §6.3.4) ---

(define
  (char-alphabetic? c)
  (let ((n (char->integer c)))
    (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122)))))
(define
  (char-numeric? c)
  (let ((n (char->integer c))) (and (>= n 48) (<= n 57))))
(define
  (char-whitespace? c)
  (let ((n (char->integer c)))
    (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12))))
(define
  (char-upper-case? c)
  (let ((n (char->integer c))) (and (>= n 65) (<= n 90))))
(define
  (char-lower-case? c)
  (let ((n (char->integer c))) (and (>= n 97) (<= n 122))))

; --- Character case conversion ---

(define
  (char-upcase c)
  (if (char-lower-case? c)
    (integer->char (- (char->integer c) 32))
    c))
(define
  (char-downcase c)
  (if (char-upper-case? c)
    (integer->char (+ (char->integer c) 32))
    c))

; --- Case-insensitive character comparison ---

(define
  (char-ci=? a b)
  (char=? (char-downcase a) (char-downcase b)))
(define
  (char-ci<? a b)
  (char<? (char-downcase a) (char-downcase b)))
(define
  (char-ci>? a b)
  (char>? (char-downcase a) (char-downcase b)))
(define
  (char-ci<=? a b)
  (char<=? (char-downcase a) (char-downcase b)))
(define
  (char-ci>=? a b)
  (char>=? (char-downcase a) (char-downcase b)))
