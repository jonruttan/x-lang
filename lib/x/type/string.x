; string.x -- String utilities
(import x/type/char)
(import x/core/list)
(import x/core/syntax)
(import x/codec/utf8)

; list->str: list of code-point CHARACTERs -> UTF-8 string.
;
; The C primitive of this name is the dumb byte-packer (one low byte per char),
; exposed here as bytes->str. We redefine list->str on top of it to be code-point
; aware: each character is UTF-8 encoded to its 1-4 bytes via the shared codec
; (x/codec/utf8), the bytes are concatenated, then byte-packed. This is the exact
; inverse of str->list, so (list->str (str->list s)) round-trips any UTF-8 string.
; Keeping the encoding here (not in C) is the "no UTF-8 in C" split: C packs
; bytes; the x-lang layer owns the byte<->code-point transform.
(def list->str
  (fn (_ chars)
    (bytes->str
      (map integer->char
        (fold (fn (_ acc ch) (append acc (utf8-encode (char->integer ch))))
              () chars)))))

(note "Construction")

(doc (def str
  (fn (_ . args)
    (fold str-append "" args)))
  (returns STRING "Concatenated result")
  (example "(str \"hello\" \" \" \"world\")" "\"hello world\"")
  "Concatenate all arguments into a single string.")

(note "Predicates")

(doc (def str-empty? (fn (_ (param s STRING "String to test")) (= (str-length s) 0)))
  (returns BOOL "True if string has zero length")
  "Test whether a string is empty.")

(note "Building")

(doc (def make-str
  (fn (_ (param k NUMBER "Length of the string")
       . rest)
    (def ch (if (null? rest) (" " 0) (first rest)))
    (list->str (repeat ch k))))
  (returns STRING "A string of k copies of ch (default space)")
  "Create a string of k copies of a character.")

(doc (def str-join
  (fn (_ (param sep STRING "Separator to insert between elements")
       (param lst LIST "List of strings"))
    (match
      ((null? lst) "")
      ((null? (rest lst)) (first lst))
      (#t
        (fold
          (fn (_ acc s) (str-append acc (str-append sep s)))
          (first lst)
          (rest lst))))))
  (returns STRING "Joined string")
  "Join a list of strings with a separator.")

(doc (def str-repeat
  (fn (self (param s STRING "String to repeat")
       (param n INT "Number of repetitions"))
    (if (<= n 0)
      ""
      (str-append s (self s (- n 1))))))
  (returns STRING "Repeated string")
  "Repeat a string n times.")

(doc (def str-pad-left
  (fn (self (param s STRING "String to pad")
       (param n INT "Desired minimum length")
       (param ch CHAR "Padding character"))
    (if (not (< (str-length s) n)) s
      (self (str-append (list->str (list ch)) s) n ch))))
  (returns STRING "Padded string of at least length n")
  "Left-pad a string with ch to at least length n.")

(note "Searching")

; Shared helper: test if sub matches s at position pos
(def %str-match-at?
  (fn (_ s sub pos)
    (def sub-len (str-length sub))
    (if (> (+ pos sub-len) (str-length s)) #f
      (str=? (substring s pos (+ pos sub-len)) sub))))

(doc (def str-contains?
  (fn (_ (param sub STRING "Substring to search for")
       (param s STRING "String to search in"))
    (def s-len (str-length s))
    (def sub-len (str-length sub))
    (def go
      (fn (self i)
        (if (> (+ i sub-len) s-len) #f
          (if (%str-match-at? s sub i) #t (self (+ i 1))))))
    (if (= sub-len 0) #t (go 0))))
  (returns BOOL "True if sub appears in s")
  "Test whether a string contains a substring.")

(doc (def str-starts?
  (fn (_ (param pfx STRING "Prefix to check")
       (param s STRING "String to test"))
    (%str-match-at? s pfx 0)))
  (returns BOOL "True if s starts with pfx")
  "Test whether a string starts with a prefix.")

(doc (def str-ends?
  (fn (_ (param sfx STRING "Suffix to check")
       (param s STRING "String to test"))
    (def s-len (str-length s))
    (def sfx-len (str-length sfx))
    (if (> sfx-len s-len) #f
      (%str-match-at? s sfx (- s-len sfx-len)))))
  (returns BOOL "True if s ends with sfx")
  "Test whether a string ends with a suffix.")

(note "Transformation")

(doc (def str-reverse
  (fn (_ (param s STRING "String to reverse"))
    (list->str (reverse (str->list s)))))
  (returns STRING "Reversed string")
  "Reverse a string by Unicode code point.")

; --- Conversion ---

(note "Conversion")

; Strings are stored as UTF-8 byte arrays, so str-length and str-ref (and
; substring) are byte-level.  str->list decodes those bytes into Unicode code
; points using the shared UTF-8 codec (x/codec/utf8) -- the single home for the
; byte<->code-point transform, also used by the Utf8 protocol class.

(doc (def str->list
  (fn (_ (param s STRING "String to convert"))
    (def len (str-length s))
    (let go ((i 0) (acc ()))
      (if (>= i len)
        (reverse acc)
        (do
          (def d (utf8-decode s i))
          (go (rest d) (pair (integer->char (first d)) acc)))))))
  (returns LIST "List of characters (one per Unicode code point)")
  "Convert a string to a list of characters, decoding UTF-8 code points.")

; --- Case conversion ---

(note "Case conversion")

(doc (def str-upcase
  (fn (_ (param s STRING "String to convert"))
    (list->str (map char-upcase (str->list s)))))
  (returns STRING "Uppercased string")
  "Convert all characters in a string to uppercase.")

(doc (def str-downcase
  (fn (_ (param s STRING "String to convert"))
    (list->str (map char-downcase (str->list s)))))
  (returns STRING "Lowercased string")
  "Convert all characters in a string to lowercase.")

; --- Ordering ---

(note "Ordering")

(doc (def str<?
  (fn (_ (param a STRING "First string")
       (param b STRING "Second string"))
    (let go ((i 0))
      (cond
        ((= i (str-length a)) (< i (str-length b)))
        ((= i (str-length b)) #f)
        ((char<? (str-ref a i) (str-ref b i)) #t)
        ((char>? (str-ref a i) (str-ref b i)) #f)
        (#t (go (+ i 1)))))))
  (returns BOOL "True if a is lexicographically less than b")
  "Lexicographic string less-than comparison.")

(doc (def str>? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (str<? b a)))
  (returns BOOL "True if a is lexicographically greater than b")
  "Lexicographic string greater-than comparison.")

(doc (def str<=? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (not (str>? a b))))
  (returns BOOL "True if a <= b lexicographically")
  "Lexicographic string less-than-or-equal comparison.")

(doc (def str>=? (fn (_ (param a STRING "First string") (param b STRING "Second string")) (not (str<? a b))))
  (returns BOOL "True if a >= b lexicographically")
  "Lexicographic string greater-than-or-equal comparison.")

; --- Case-insensitive comparison ---

(note "Case-insensitive comparison")

(doc (def str-ci=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (str=? (str-downcase a) (str-downcase b))))
  (returns BOOL "True if strings are equal ignoring case")
  "Case-insensitive string equality.")

(doc (def str-ci<?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (str<? (str-downcase a) (str-downcase b))))
  (returns BOOL "True if a < b ignoring case")
  "Case-insensitive string less-than.")

(doc (def str-ci>?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (str>? (str-downcase a) (str-downcase b))))
  (returns BOOL "True if a > b ignoring case")
  "Case-insensitive string greater-than.")

(doc (def str-ci<=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (str<=? (str-downcase a) (str-downcase b))))
  (returns BOOL "True if a <= b ignoring case")
  "Case-insensitive string less-than-or-equal.")

(doc (def str-ci>=?
  (fn (_ (param a STRING "First string") (param b STRING "Second string"))
    (str>=? (str-downcase a) (str-downcase b))))
  (returns BOOL "True if a >= b ignoring case")
  "Case-insensitive string greater-than-or-equal.")

; --- Trimming ---

(note "Trimming")

(doc (def str-trim-left
  (fn (_ (param s STRING "String to trim"))
    (let go ((i 0))
      (if (= i (str-length s)) ""
        (if (char-whitespace? (str-ref s i))
          (go (+ i 1))
          (substring s i (str-length s)))))))
  (returns STRING "String with leading whitespace removed")
  "Remove leading whitespace from a string.")

(doc (def str-trim-right
  (fn (_ (param s STRING "String to trim"))
    (let go ((i (- (str-length s) 1)))
      (if (< i 0) ""
        (if (char-whitespace? (str-ref s i))
          (go (- i 1))
          (substring s 0 (+ i 1)))))))
  (returns STRING "String with trailing whitespace removed")
  "Remove trailing whitespace from a string.")

(doc (def str-trim
  (fn (_ (param s STRING "String to trim"))
    (str-trim-left (str-trim-right s))))
  (returns STRING "String with both leading and trailing whitespace removed")
  "Remove whitespace from both ends of a string.")

; --- Splitting ---

(note "Splitting")

(doc (def str-split
  (fn (_ (param sep STRING "Separator string; empty splits into characters")
       (param s STRING "String to split"))
    (def sep-len (str-length sep))
    (def s-len (str-length s))
    (if (= sep-len 0) (map (fn (_ c) (list->str (list c))) (str->list s))
      (let go ((start 0) (i 0) (acc ()))
        (if (> (+ i sep-len) s-len)
          (reverse (pair (substring s start s-len) acc))
          (if (str=? (substring s i (+ i sep-len)) sep)
            (go (+ i sep-len) (+ i sep-len)
                (pair (substring s start i) acc))
            (go start (+ i 1) acc)))))))
  (returns LIST "List of substrings")
  "Split a string by a separator.")

(doc (provide x/type/string
  str make-str str-pad-left str-empty? str-join str-repeat str-contains?
  str-starts? str-ends? str-reverse str->list
  str-upcase str-downcase
  str<? str>? str<=? str>=?
  str-ci=? str-ci<? str-ci>? str-ci<=? str-ci>=?
  str-trim-left str-trim-right str-trim str-split)
  (example "(str-split \",\" \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "String manipulation, searching, and transformation.")
