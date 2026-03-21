; char.x -- Character predicates and case conversion

; --- Classification ---

(note "Classification")

(doc (def char-alphabetic?
  (fn ((param c CHAR "Character to test"))
    (let ((n (char->integer c)))
      (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122))))))
  (returns BOOL "True if c is a letter A-Z or a-z")
  "Test whether a character is alphabetic.")

(doc (def char-numeric?
  (fn ((param c CHAR "Character to test"))
    (let ((n (char->integer c))) (and (>= n 48) (<= n 57)))))
  (returns BOOL "True if c is a digit 0-9")
  "Test whether a character is a digit.")

(doc (def char-whitespace?
  (fn ((param c CHAR "Character to test"))
    (let ((n (char->integer c)))
      (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12)))))
  (returns BOOL "True if c is whitespace")
  "Test whether a character is whitespace (space, tab, newline, CR, FF).")

(doc (def char-upper-case?
  (fn ((param c CHAR "Character to test"))
    (let ((n (char->integer c))) (and (>= n 65) (<= n 90)))))
  (returns BOOL "True if c is uppercase A-Z")
  "Test whether a character is uppercase.")

(doc (def char-lower-case?
  (fn ((param c CHAR "Character to test"))
    (let ((n (char->integer c))) (and (>= n 97) (<= n 122)))))
  (returns BOOL "True if c is lowercase a-z")
  "Test whether a character is lowercase.")

; --- Case conversion ---

(note "Case conversion")

(doc (def char-upcase
  (fn ((param c CHAR "Character to convert"))
    (if (char-lower-case? c)
      (integer->char (- (char->integer c) 32))
      c)))
  (returns CHAR "Uppercase version of c, or c unchanged")
  "Convert a character to uppercase.")

(doc (def char-downcase
  (fn ((param c CHAR "Character to convert"))
    (if (char-upper-case? c)
      (integer->char (+ (char->integer c) 32))
      c)))
  (returns CHAR "Lowercase version of c, or c unchanged")
  "Convert a character to lowercase.")

; --- Comparisons ---

(note "Comparisons")

(doc (def char=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (= (char->integer a) (char->integer b))))
  (returns BOOL "True if characters are equal")
  "Test whether two characters are equal.")

(doc (def char<? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (< (char->integer a) (char->integer b))))
  (returns BOOL "True if a comes before b")
  "Test whether a character is less than another by code point.")

(doc (def char>? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (> (char->integer a) (char->integer b))))
  (returns BOOL "True if a comes after b")
  "Test whether a character is greater than another by code point.")

(doc (def char<=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (<= (char->integer a) (char->integer b))))
  (returns BOOL "True if a is equal to or comes before b")
  "Test whether a character is less than or equal to another.")

(doc (def char>=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (>= (char->integer a) (char->integer b))))
  (returns BOOL "True if a is equal to or comes after b")
  "Test whether a character is greater than or equal to another.")

; --- Case-insensitive comparisons ---

(note "Case-insensitive comparisons")

(doc (def char-ci=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (char=? (char-downcase a) (char-downcase b))))
  (returns BOOL "True if characters are equal ignoring case")
  "Case-insensitive character equality.")

(doc (def char-ci<? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (char<? (char-downcase a) (char-downcase b))))
  (returns BOOL "True if a < b ignoring case")
  "Case-insensitive character less-than.")

(doc (def char-ci>? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (char>? (char-downcase a) (char-downcase b))))
  (returns BOOL "True if a > b ignoring case")
  "Case-insensitive character greater-than.")

(doc (def char-ci<=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (char<=? (char-downcase a) (char-downcase b))))
  (returns BOOL "True if a <= b ignoring case")
  "Case-insensitive character less-than-or-equal.")

(doc (def char-ci>=? (fn ((param a CHAR "First character") (param b CHAR "Second character")) (char>=? (char-downcase a) (char-downcase b))))
  (returns BOOL "True if a >= b ignoring case")
  "Case-insensitive character greater-than-or-equal.")

(provide x/char
  char-alphabetic? char-numeric? char-whitespace?
  char-upper-case? char-lower-case? char-upcase char-downcase
  char=? char<? char>? char<=? char>=?
  char-ci=? char-ci<? char-ci>? char-ci<=? char-ci>=?)
