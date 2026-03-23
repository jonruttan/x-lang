; string.x -- String utilities
(import x/data/char)
(import x/core/list)
(import x/core/derived)

(note "Construction")

(doc (def str
  (fn (_ . args)
    (fold string-append "" args)))
  (returns STRING "Concatenated result")
  (example "(str \"hello\" \" \" \"world\")" "\"hello world\"")
  "Concatenate all arguments into a single string.")

(note "Predicates")

(doc (def string-empty? (fn (_ (param s STRING "String to test")) (= (string-length s) 0)))
  (returns BOOL "True if string has zero length")
  "Test whether a string is empty.")

(note "Building")

(doc (def make-string
  (fn (_ (param k NUMBER "Length of the string")
       . rest)
    (def ch (if (null? rest) (" " 0) (first rest)))
    (list->string (repeat ch k))))
  (returns STRING "A string of k copies of ch (default space)")
  "Create a string of k copies of a character.")

(doc (def string-join
  (fn (_ (param sep STRING "Separator to insert between elements")
       (param lst LIST "List of strings"))
    (match
      ((null? lst) "")
      ((null? (rest lst)) (first lst))
      (#t
        (fold
          (fn (_ acc s) (string-append acc (string-append sep s)))
          (first lst)
          (rest lst))))))
  (returns STRING "Joined string")
  "Join a list of strings with a separator.")

(doc (def string-repeat
  (fn (_ (param s STRING "String to repeat")
       (param n INT "Number of repetitions"))
    (if (<= n 0)
      ""
      (string-append s (string-repeat s (- n 1))))))
  (returns STRING "Repeated string")
  "Repeat a string n times.")

(doc (def string-pad-left
  (fn (_ (param s STRING "String to pad")
       (param n INT "Desired minimum length")
       (param ch CHAR "Padding character"))
    (if (not (< (string-length s) n)) s
      (string-pad-left (string-append (list->string (list ch)) s) n ch))))
  (returns STRING "Padded string of at least length n")
  "Left-pad a string with ch to at least length n.")

(note "Searching")

; Shared helper: test if sub matches s at position pos
(def %string-match-at?
  (fn (_ s sub pos)
    (def sub-len (string-length sub))
    (if (> (+ pos sub-len) (string-length s)) #f
      (string=? (substring s pos (+ pos sub-len)) sub))))

(doc (def string-contains?
  (fn (_ (param sub STRING "Substring to search for")
       (param s STRING "String to search in"))
    (def s-len (string-length s))
    (def sub-len (string-length sub))
    (def go
      (fn (_ i)
        (if (> (+ i sub-len) s-len) #f
          (if (%string-match-at? s sub i) #t (go (+ i 1))))))
    (if (= sub-len 0) #t (go 0))))
  (returns BOOL "True if sub appears in s")
  "Test whether a string contains a substring.")

(doc (def string-starts?
  (fn (_ (param pfx STRING "Prefix to check")
       (param s STRING "String to test"))
    (%string-match-at? s pfx 0)))
  (returns BOOL "True if s starts with pfx")
  "Test whether a string starts with a prefix.")

(doc (def string-ends?
  (fn (_ (param sfx STRING "Suffix to check")
       (param s STRING "String to test"))
    (def s-len (string-length s))
    (def sfx-len (string-length sfx))
    (if (> sfx-len s-len) #f
      (%string-match-at? s sfx (- s-len sfx-len)))))
  (returns BOOL "True if s ends with sfx")
  "Test whether a string ends with a suffix.")

(note "Transformation")

(doc (def string-reverse
  (fn (_ (param s STRING "String to reverse"))
    (def len (string-length s))
    (def go
      (fn (_ i acc)
        (if (< i 0)
          acc
          (go (- i 1) (string-append acc (substring s i (+ i 1)))))))
    (go (- len 1) "")))
  (returns STRING "Reversed string")
  "Reverse a string.")

; --- Conversion ---

(note "Conversion")

(doc (def string->list
  (fn (_ (param s STRING "String to convert"))
    (let go ((i (- (string-length s) 1)) (acc ()))
      (if (< i 0) acc (go (- i 1) (pair (string-ref s i) acc))))))
  (returns LIST "List of characters")
  "Convert a string to a list of characters.")

; --- Case conversion ---

(note "Case conversion")

(doc (def string-upcase
  (fn (_ (param s STRING "String to convert"))
    (list->string (map char-upcase (string->list s)))))
  (returns STRING "Uppercased string")
  "Convert all characters in a string to uppercase.")

(doc (def string-downcase
  (fn (_ (param s STRING "String to convert"))
    (list->string (map char-downcase (string->list s)))))
  (returns STRING "Lowercased string")
  "Convert all characters in a string to lowercase.")

; --- Ordering ---

(note "Ordering")

(doc (def string<?
  (fn (_ (param a STRING "First string")
       (param b STRING "Second string"))
    (let go ((i 0))
      (cond
        ((= i (string-length a)) (< i (string-length b)))
        ((= i (string-length b)) #f)
        ((char<? (string-ref a i) (string-ref b i)) #t)
        ((char>? (string-ref a i) (string-ref b i)) #f)
        (#t (go (+ i 1)))))))
  (returns BOOL "True if a is lexicographically less than b")
  "Lexicographic string less-than comparison.")

(doc (def string>? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (string<? b a)))
  (returns BOOL "True if a is lexicographically greater than b")
  "Lexicographic string greater-than comparison.")

(doc (def string<=? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (not (string>? a b))))
  (returns BOOL "True if a <= b lexicographically")
  "Lexicographic string less-than-or-equal comparison.")

(doc (def string>=? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (not (string<? a b))))
  (returns BOOL "True if a >= b lexicographically")
  "Lexicographic string greater-than-or-equal comparison.")

; --- Case-insensitive comparison ---

(note "Case-insensitive comparison")

(doc (def string-ci=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (string=? (string-downcase a) (string-downcase b))))
  (returns BOOL "True if strings are equal ignoring case")
  "Case-insensitive string equality.")

(doc (def string-ci<?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (string<? (string-downcase a) (string-downcase b))))
  (returns BOOL "True if a < b ignoring case")
  "Case-insensitive string less-than.")

(doc (def string-ci>?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (string>? (string-downcase a) (string-downcase b))))
  (returns BOOL "True if a > b ignoring case")
  "Case-insensitive string greater-than.")

(doc (def string-ci<=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (string<=? (string-downcase a) (string-downcase b))))
  (returns BOOL "True if a <= b ignoring case")
  "Case-insensitive string less-than-or-equal.")

(doc (def string-ci>=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (string>=? (string-downcase a) (string-downcase b))))
  (returns BOOL "True if a >= b ignoring case")
  "Case-insensitive string greater-than-or-equal.")

; --- Trimming ---

(note "Trimming")

(doc (def string-trim-left
  (fn (_ (param s STRING "String to trim"))
    (let go ((i 0))
      (if (= i (string-length s)) ""
        (if (char-whitespace? (string-ref s i))
          (go (+ i 1))
          (substring s i (string-length s)))))))
  (returns STRING "String with leading whitespace removed")
  "Remove leading whitespace from a string.")

(doc (def string-trim-right
  (fn (_ (param s STRING "String to trim"))
    (let go ((i (- (string-length s) 1)))
      (if (< i 0) ""
        (if (char-whitespace? (string-ref s i))
          (go (- i 1))
          (substring s 0 (+ i 1)))))))
  (returns STRING "String with trailing whitespace removed")
  "Remove trailing whitespace from a string.")

(doc (def string-trim
  (fn (_ (param s STRING "String to trim"))
    (string-trim-left (string-trim-right s))))
  (returns STRING "String with both leading and trailing whitespace removed")
  "Remove whitespace from both ends of a string.")

; --- Splitting ---

(note "Splitting")

(doc (def string-split
  (fn (_ (param sep STRING "Separator string; empty splits into characters")
       (param s STRING "String to split"))
    (def sep-len (string-length sep))
    (def s-len (string-length s))
    (if (= sep-len 0) (map (fn (_ c) (list->string (list c))) (string->list s))
      (let go ((start 0) (i 0) (acc ()))
        (if (> (+ i sep-len) s-len)
          (reverse (pair (substring s start s-len) acc))
          (if (string=? (substring s i (+ i sep-len)) sep)
            (go (+ i sep-len) (+ i sep-len)
                (pair (substring s start i) acc))
            (go start (+ i 1) acc)))))))
  (returns LIST "List of substrings")
  "Split a string by a separator.")

(doc (provide x/data/string
  str make-string string-pad-left string-empty? string-join string-repeat string-contains?
  string-starts? string-ends? string-reverse string->list
  string-upcase string-downcase
  string<? string>? string<=? string>=?
  string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
  string-trim-left string-trim-right string-trim string-split)
  (example "(string-split \",\" \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "String manipulation, searching, and transformation.")
