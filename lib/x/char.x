; char.x -- Character predicates and case conversion

; --- Classification ---

(def char-alphabetic?
  (fn (c)
    (let ((n (char->integer c)))
      (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122))))))

(def char-numeric?
  (fn (c)
    (let ((n (char->integer c))) (and (>= n 48) (<= n 57)))))

(def char-whitespace?
  (fn (c)
    (let ((n (char->integer c)))
      (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12)))))

(def char-upper-case?
  (fn (c)
    (let ((n (char->integer c))) (and (>= n 65) (<= n 90)))))

(def char-lower-case?
  (fn (c)
    (let ((n (char->integer c))) (and (>= n 97) (<= n 122)))))

; --- Case conversion ---

(def char-upcase
  (fn (c)
    (if (char-lower-case? c)
      (integer->char (- (char->integer c) 32))
      c)))

(def char-downcase
  (fn (c)
    (if (char-upper-case? c)
      (integer->char (+ (char->integer c) 32))
      c)))

; --- Comparisons ---

(def char=? (fn (a b) (= (char->integer a) (char->integer b))))
(def char<? (fn (a b) (< (char->integer a) (char->integer b))))
(def char>? (fn (a b) (> (char->integer a) (char->integer b))))
(def char<=? (fn (a b) (<= (char->integer a) (char->integer b))))
(def char>=? (fn (a b) (>= (char->integer a) (char->integer b))))

; --- Case-insensitive comparisons ---

(def char-ci=? (fn (a b) (char=? (char-downcase a) (char-downcase b))))
(def char-ci<? (fn (a b) (char<? (char-downcase a) (char-downcase b))))
(def char-ci>? (fn (a b) (char>? (char-downcase a) (char-downcase b))))
(def char-ci<=? (fn (a b) (char<=? (char-downcase a) (char-downcase b))))
(def char-ci>=? (fn (a b) (char>=? (char-downcase a) (char-downcase b))))
