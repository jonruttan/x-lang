; char.x -- Char: character classification, case conversion, comparison.
;
; Plain functions homed on the Char class. Relocated past object.x (needs
; def-class); the pre-object string layer uses the char->integer C primitive,
; not these, so nothing before object.x references the Char class.
(module x/type/char)

(import x/type/class)
; Fetch the char/int casts from the catalogue (ns `char`/`int` utility members de-registered, R5).
(import x/core/doors char->int int->char type-by-atom type-of type-push-call)


(def-class Char ()
  (static
    ; --- Code point (the char<->int casts; reader-hot consumers fetch the
    ; prim directly via (prim-ref (lit char) (lit ->int)) / (lit int) (lit ->char)) ---
    (method ->int (self (param c CHARACTER "Character"))
      (doc "The integer code point of a character." (returns INTEGER "Code point (0-255 for ASCII/byte chars)")
        (example "(Char ->int #\\A)" "65"))
      (char->int c))
    (method from-int (self (param n INTEGER "Integer code point"))
      (doc "The character for an integer code point." (returns CHARACTER "The character")
        (example "(Char from-int 97)" "#\\a"))
      (int->char n))
    ; --- Classification ---
    (method alphabetic? (self (param c CHARACTER "Character to test"))
      (doc "Test whether a character is alphabetic." (returns BOOL "True if c is a letter A-Z or a-z")
        (example "(Char alphabetic? #\\q)" "#t")
        (example "(Char alphabetic? #\\7)" "#f"))
      (let ((n (char->int c)))
        ; Nested if, NOT and/or (#343): per character via the Str8
        ; upcase/downcase/trim walks.
        (if (if (>= n 65) (<= n 90) #f) #t (if (>= n 97) (<= n 122) #f))))
    (method numeric? (self (param c CHARACTER "Character to test"))
      (doc "Test whether a character is a digit." (returns BOOL "True if c is a digit 0-9")
        (example "(Char numeric? #\\7)" "#t"))
      (let ((n (char->int c))) (if (>= n 48) (<= n 57) #f)))
    (method whitespace? (self (param c CHARACTER "Character to test"))
      (doc "Test whether a character is whitespace (space, tab, newline, CR, FF)." (returns BOOL "True if c is whitespace")
        (example "(Char whitespace? #\\space)" "#t")
        (example "(Char whitespace? #\\a)" "#f"))
      (let ((n (char->int c)))
        (if (= n 32) #t (if (= n 9) #t (if (= n 10) #t (if (= n 13) #t (= n 12)))))))
    (method upper-case? (self (param c CHARACTER "Character to test"))
      (doc "Test whether a character is uppercase." (returns BOOL "True if c is uppercase A-Z")
        (example "(Char upper-case? #\\A)" "#t"))
      (let ((n (char->int c))) (if (>= n 65) (<= n 90) #f)))
    (method lower-case? (self (param c CHARACTER "Character to test"))
      (doc "Test whether a character is lowercase." (returns BOOL "True if c is lowercase a-z")
        (example "(Char lower-case? #\\A)" "#f"))
      (let ((n (char->int c))) (if (>= n 97) (<= n 122) #f)))
    ; --- Case conversion ---
    (method upcase (self (param c CHARACTER "Character to convert"))
      (doc "Convert a character to uppercase." (returns CHARACTER "Uppercase version of c, or c unchanged")
        (example "(Char upcase #\\a)" "#\\A")
        (example "(Char upcase #\\1)" "#\\1"))
      (if (Char lower-case? c) (int->char (- (char->int c) 32)) c))
    (method downcase (self (param c CHARACTER "Character to convert"))
      (doc "Convert a character to lowercase." (returns CHARACTER "Lowercase version of c, or c unchanged")
        (example "(Char downcase #\\A)" "#\\a"))
      (if (Char upper-case? c) (int->char (+ (char->int c) 32)) c))
    ; --- Comparisons (by code point) ---
    (method =? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Test whether two characters are equal." (returns BOOL "True if characters are equal")
        (example "(Char =? #\\a #\\a)" "#t"))
      (= (char->int a) (char->int b)))
    (method <? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Test whether a character is less than another by code point." (returns BOOL "True if a comes before b")
        (example "(Char <? #\\a #\\b)" "#t"))
      (< (char->int a) (char->int b)))
    (method >? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Test whether a character is greater than another by code point." (returns BOOL "True if a comes after b")
        (example "(Char >? #\\a #\\b)" "#f"))
      (> (char->int a) (char->int b)))
    (method <=? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Test whether a character is less than or equal to another." (returns BOOL "True if a is equal to or comes before b")
        (example "(Char <=? #\\a #\\a)" "#t"))
      (<= (char->int a) (char->int b)))
    (method >=? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Test whether a character is greater than or equal to another." (returns BOOL "True if a is equal to or comes after b")
        (example "(Char >=? #\\a #\\b)" "#f"))
      (>= (char->int a) (char->int b)))
    ; --- Case-insensitive comparisons ---
    (method ci=? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Case-insensitive character equality." (returns BOOL "True if characters are equal ignoring case")
        (example "(Char ci=? #\\a #\\A)" "#t"))
      (Char =? (Char downcase a) (Char downcase b)))
    (method ci<? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Case-insensitive character less-than." (returns BOOL "True if a < b ignoring case")
        (example "(Char ci<? #\\a #\\B)" "#t"))
      (Char <? (Char downcase a) (Char downcase b)))
    (method ci>? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Case-insensitive character greater-than." (returns BOOL "True if a > b ignoring case")
        (example "(Char ci>? #\\b #\\A)" "#t"))
      (Char >? (Char downcase a) (Char downcase b)))
    (method ci<=? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Case-insensitive character less-than-or-equal." (returns BOOL "True if a <= b ignoring case")
        (example "(Char ci<=? #\\A #\\a)" "#t"))
      (Char <=? (Char downcase a) (Char downcase b)))
    (method ci>=? (self (param a CHARACTER "First character") (param b CHARACTER "Second character"))
      (doc "Case-insensitive character greater-than-or-equal." (returns BOOL "True if a >= b ignoring case")
        (example "(Char ci>=? #\\a #\\B)" "#f"))
      (Char >=? (Char downcase a) (Char downcase b)))))

; Value dispatch (subject-last): a character calls Char's static methods --
; (#\a upcase) -> (Char upcase #\a); (#\a ->int) -> (Char ->int #\a).
(type-push-call (type-by-atom (type-of (int->char 0))) (class-call-handler Char))

(doc (provide x/type/char Char)
  (note "ASCII only. Classification, case conversion, and comparison homed on the Char class.")
  (example "(#\\a upcase)" "#\\A")
  "Character operations as the Char class.")
