; char.x -- Char: character classification, case conversion, comparison.
;
; Plain functions homed on the Char class. Relocated past object.x (needs
; def-class); the pre-object string layer uses the char->integer C primitive,
; not these, so nothing before object.x references the Char class.

(import x/type/object)
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))
(def %integer->char (prim-ref (lit int) (lit ->char)))


(def-class Char ()
  (static
    ; --- Code point (the char<->int casts; reader-hot consumers fetch the
    ; prim directly via (prim-ref (lit char) (lit ->int)) / (lit int) (lit ->char)) ---
    (method ->int (self (param c CHAR "Character"))
      (doc "The integer code point of a character." (returns INT "Code point (0-255 for ASCII/byte chars)"))
      (%char->integer c))
    (method from-int (self (param n INT "Integer code point"))
      (doc "The character for an integer code point." (returns CHAR "The character"))
      (%integer->char n))
    ; --- Classification ---
    (method alphabetic? (self (param c CHAR "Character to test"))
      (doc "Test whether a character is alphabetic." (returns BOOL "True if c is a letter A-Z or a-z"))
      (let ((n (%char->integer c)))
        (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122)))))
    (method numeric? (self (param c CHAR "Character to test"))
      (doc "Test whether a character is a digit." (returns BOOL "True if c is a digit 0-9"))
      (let ((n (%char->integer c))) (and (>= n 48) (<= n 57))))
    (method whitespace? (self (param c CHAR "Character to test"))
      (doc "Test whether a character is whitespace (space, tab, newline, CR, FF)." (returns BOOL "True if c is whitespace"))
      (let ((n (%char->integer c)))
        (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12))))
    (method upper-case? (self (param c CHAR "Character to test"))
      (doc "Test whether a character is uppercase." (returns BOOL "True if c is uppercase A-Z"))
      (let ((n (%char->integer c))) (and (>= n 65) (<= n 90))))
    (method lower-case? (self (param c CHAR "Character to test"))
      (doc "Test whether a character is lowercase." (returns BOOL "True if c is lowercase a-z"))
      (let ((n (%char->integer c))) (and (>= n 97) (<= n 122))))
    ; --- Case conversion ---
    (method upcase (self (param c CHAR "Character to convert"))
      (doc "Convert a character to uppercase." (returns CHAR "Uppercase version of c, or c unchanged"))
      (if (Char lower-case? c) (%integer->char (- (%char->integer c) 32)) c))
    (method downcase (self (param c CHAR "Character to convert"))
      (doc "Convert a character to lowercase." (returns CHAR "Lowercase version of c, or c unchanged"))
      (if (Char upper-case? c) (%integer->char (+ (%char->integer c) 32)) c))
    ; --- Comparisons (by code point) ---
    (method =? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Test whether two characters are equal." (returns BOOL "True if characters are equal"))
      (= (%char->integer a) (%char->integer b)))
    (method <? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Test whether a character is less than another by code point." (returns BOOL "True if a comes before b"))
      (< (%char->integer a) (%char->integer b)))
    (method >? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Test whether a character is greater than another by code point." (returns BOOL "True if a comes after b"))
      (> (%char->integer a) (%char->integer b)))
    (method <=? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Test whether a character is less than or equal to another." (returns BOOL "True if a is equal to or comes before b"))
      (<= (%char->integer a) (%char->integer b)))
    (method >=? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Test whether a character is greater than or equal to another." (returns BOOL "True if a is equal to or comes after b"))
      (>= (%char->integer a) (%char->integer b)))
    ; --- Case-insensitive comparisons ---
    (method ci=? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Case-insensitive character equality." (returns BOOL "True if characters are equal ignoring case"))
      (Char =? (Char downcase a) (Char downcase b)))
    (method ci<? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Case-insensitive character less-than." (returns BOOL "True if a < b ignoring case"))
      (Char <? (Char downcase a) (Char downcase b)))
    (method ci>? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Case-insensitive character greater-than." (returns BOOL "True if a > b ignoring case"))
      (Char >? (Char downcase a) (Char downcase b)))
    (method ci<=? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Case-insensitive character less-than-or-equal." (returns BOOL "True if a <= b ignoring case"))
      (Char <=? (Char downcase a) (Char downcase b)))
    (method ci>=? (self (param a CHAR "First character") (param b CHAR "Second character"))
      (doc "Case-insensitive character greater-than-or-equal." (returns BOOL "True if a >= b ignoring case"))
      (Char >=? (Char downcase a) (Char downcase b)))))

; Value dispatch (subject-last): a character calls Char's static methods --
; (#\a upcase) -> (Char upcase #\a); (#\a ->int) -> (Char ->int #\a).
(def %type-of (prim-ref (lit type) (lit of)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-call (prim-ref (lit type) (lit push-call)))
(%type-push-call (%type-by-atom (%type-of (%integer->char 0))) (%class-call-handler Char))

(doc (provide x/type/char Char)
  (note "ASCII only. Classification, case conversion, and comparison homed on the Char class.")
  "Character operations as the Char class.")
