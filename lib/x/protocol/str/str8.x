; str/str8.x -- Str8: the 8-bit (byte) string class + the full string suite
(import x/protocol/seq)

; Str8 treats a STRING as its raw bytes (8-bit chars, 0-255), with no encoding
; protocol. It provides the whole string suite as static methods:
; (Str8 append a b), (Str8 index s i), (Str8 length s), (Str8 upcase s), ...
;
; Three string PROTOCOLS:
;   Str8     -- always 8-bit bytes (this class)
;   StrUTF8  -- always UTF-8 code points (subclass; overrides the primitives)
;   Str      -- the AMBIENT protocol (currently = Str8); see provide below
;
; The suite is written ONCE here, expressed entirely through SELF primitives:
;   (self length s)        -- element count
;   (self index s i)       -- i-th element (CHARACTER)
;   (self sub s start len)  -- substring of `len` elements from `start`
;   (self =? a b) (self ->list s) (self ->str l)
; so a subclass that overrides only those gets the whole suite in its own
; protocol. Str8's primitives bottom out in the str-byte-* C primitives, which
; are ALWAYS byte-level and IGNORE any handler pushed on the ambient string
; call -- so Str8 is allocation-light and safe to use inside readers/tokenizers
; that must not touch the ambient (s i).

(def-class Str8 (extends Seq)
  (static
    ; --- primitives (8-bit byte view; handler-immune via str-byte-*) ---
    (method length (self (param v STRING "String to measure"))
      (doc "Number of bytes in v (the 8-bit element count)."
        (returns INT "Byte length of v")
        (example "(Str8 length \"abc\")" "3"))
      (str-byte-len v))
    (method index  (self (param v STRING "String to index") (param i INT "Byte position (0-based)"))
      (doc "The i-th byte of v as a CHARACTER (code 0-255)."
        (returns CHAR "Byte at position i")
        (example "(Str8 index \"abc\" 0)" "#\\a"))
      (str-byte-ref v i))
    (method sub    (self (param v STRING "Source string") (param st INT "Start byte offset (0-based)") (param len INT "Number of bytes"))
      (doc "Substring of len bytes starting at byte offset st."
        (returns STRING "The len-byte slice of v from st")
        (example "(Str8 sub \"hello\" 1 3)" "\"ell\""))
      (str-byte-sub v st len))
    (method ref    (self (param v STRING "String to index") (param i INT "Byte position (0-based)"))
      (doc "Alias for index: the i-th byte of v as a CHARACTER."
        (returns CHAR "Byte at position i")
        (example "(Str8 ref \"abc\" 0)" "#\\a"))
      (self index v i))  ; alias: ref = index

    ; cursor primitives (drive Seq's ->list/each/fold/count).
    ; The cursor is a BYTE offset for every subclass, so done? bounds against the
    ; raw byte length -- NOT (self length), which a code-point subclass overrides
    ; via count -> done?, an infinite recursion. start/done? are inherited
    ; unchanged by StrUTF8; only step advances differently.
    (method start (self v)     0)
    (method done? (self v cur) (>= cur (str-byte-len v)))
    (method step  (self v cur) (pair (self index v cur) (+ cur 1)))

    ; encode: one byte element is its own low byte. Makes
    ; (Str8 ->str (Str8 ->list s)) an identity on the byte view.
    (method char->bytes (self el) (list (& (char->integer el) 255)))

    ; --- equality (byte equality; correct code-point equality for UTF-8 too) ---
    (method =? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a and b have equal length and equal bytes."
        (returns BOOL "#t when a and b are byte-equal")
        (example "(Str8 =? \"ab\" \"ab\")" "#t"))
      (if (= (self length a) (self length b))
        (let go ((i 0) (n (self length a)))
          (if (= i n) #t
            (if (= (char->integer (self index a i))
                   (char->integer (self index b i)))
              (go (+ i 1) n) #f)))
        #f))

    ; does sub occur in s at element position pos?
    (method match-at? (self s sub pos)
      (def sub-len (self length sub))
      (if (> (+ pos sub-len) (self length s)) #f
        (self =? (self sub s pos sub-len) sub)))

    ; --- construction ---
    (method append (self . (param args STRING "Strings to concatenate"))
      (doc "Concatenate all argument strings, left to right."
        (returns STRING "The arguments joined end to end")
        (example "(Str8 append \"ab\" \"cd\" \"ef\")" "\"abcdef\""))
      (fold str-append "" args))
    (method make   (self (param k INT "Number of elements") . (param rest CHAR "Fill character (default space)"))
      (doc "A string of k copies of the fill character (space if omitted)."
        (returns STRING "k-element string of the fill character")
        (example "(Str8 make 3 (\" \" 0))" "\"   \""))
      (def ch (if (null? rest) (" " 0) (first rest)))
      (self ->str (repeat ch k)))

    ; --- predicates ---
    (method empty? (self (param s STRING "String to test"))
      (doc "True if s has no elements."
        (returns BOOL "#t when s is the empty string")
        (example "(Str8 empty? \"\")" "#t"))
      (= (self length s) 0))

    ; --- ordering (element order; byte order == code-point order for UTF-8) ---
    (method <? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a sorts before b in element (byte) order."
        (returns BOOL "#t when a is lexicographically less than b")
        (example "(Str8 <? \"abc\" \"abd\")" "#t"))
      (let go ((i 0) (la (self length a)) (lb (self length b)))
        (cond
          ((= i la) (< i lb))
          ((= i lb) #f)
          ((char<? (self index a i) (self index b i)) #t)
          ((char>? (self index a i) (self index b i)) #f)
          (#t (go (+ i 1) la lb)))))
    (method >?  (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a sorts after b in element (byte) order."
        (returns BOOL "#t when a is lexicographically greater than b")
        (example "(Str8 >? \"b\" \"a\")" "#t"))
      (self <? b a))
    (method <=? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a sorts before or equal to b in element (byte) order."
        (returns BOOL "#t when a is lexicographically <= b")
        (example "(Str8 <=? \"ab\" \"ab\")" "#t"))
      (not (self >? a b)))
    (method >=? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a sorts after or equal to b in element (byte) order."
        (returns BOOL "#t when a is lexicographically >= b")
        (example "(Str8 >=? \"ab\" \"ab\")" "#t"))
      (not (self <? a b)))

    ; --- case-insensitive comparison ---
    (method ci=?  (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "Case-insensitive equality: compares a and b after downcasing."
        (returns BOOL "#t when a and b are equal ignoring ASCII case")
        (example "(Str8 ci=? \"ABC\" \"abc\")" "#t"))
      (self =?  (self downcase a) (self downcase b)))
    (method ci<?  (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "Case-insensitive less-than: compares a and b after downcasing."
        (returns BOOL "#t when a sorts before b ignoring ASCII case")
        (example "(Str8 ci<? \"ABC\" \"abd\")" "#t"))
      (self <?  (self downcase a) (self downcase b)))
    (method ci>?  (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "Case-insensitive greater-than: compares a and b after downcasing."
        (returns BOOL "#t when a sorts after b ignoring ASCII case")
        (example "(Str8 ci>? \"ABD\" \"abc\")" "#t"))
      (self >?  (self downcase a) (self downcase b)))
    (method ci<=? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "Case-insensitive less-than-or-equal: compares a and b after downcasing."
        (returns BOOL "#t when a sorts before or equal to b ignoring ASCII case")
        (example "(Str8 ci<=? \"ABC\" \"abc\")" "#t"))
      (self <=? (self downcase a) (self downcase b)))
    (method ci>=? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "Case-insensitive greater-than-or-equal: compares a and b after downcasing."
        (returns BOOL "#t when a sorts after or equal to b ignoring ASCII case")
        (example "(Str8 ci>=? \"ABC\" \"abc\")" "#t"))
      (self >=? (self downcase a) (self downcase b)))

    ; --- joining / repeating ---
    (method join (self (param sep STRING "Separator inserted between elements") (param lst LIST "List of strings to join"))
      (doc "Join the strings in lst, placing sep between consecutive elements."
        (returns STRING "Elements of lst concatenated with sep between them")
        (example "(Str8 join \",\" (list \"a\" \"b\" \"c\"))" "\"a,b,c\""))
      (match
        ((null? lst) "")
        ((null? (rest lst)) (first lst))
        (#t (fold (fn (_ acc s) (str-append acc (str-append sep s)))
                  (first lst) (rest lst)))))
    (method repeat (self (param s STRING "String to repeat") (param n INT "Number of copies"))
      (doc "Concatenate n copies of s (empty string when n <= 0)."
        (returns STRING "s repeated n times")
        (example "(Str8 repeat \"ab\" 3)" "\"ababab\""))
      (if (<= n 0) "" (str-append s (self repeat s (- n 1)))))

    ; --- padding (to n ELEMENTS) ---
    (method pad-left (self (param s STRING "String to pad") (param n INT "Target element width") (param ch CHAR "Padding character"))
      (doc "Left-pad s with ch until it is at least n elements wide."
        (returns STRING "s padded on the left to width n (unchanged if already >= n)")
        (example "(Str8 pad-left \"42\" 5 (\"0\" 0))" "\"00042\""))
      (def len (self length s))
      (if (not (< len n)) s
        (str-append (self make (- n len) ch) s)))

    ; --- searching ---
    (method contains? (self (param sub STRING "Substring to search for") (param s STRING "String to search in"))
      (doc "True if sub occurs anywhere within s (empty sub always matches)."
        (returns BOOL "#t when s contains sub")
        (example "(Str8 contains? \"ll\" \"hello\")" "#t"))
      (def s-len (self length s))
      (def sub-len (self length sub))
      (def go (fn (loop i)
        (if (> (+ i sub-len) s-len) #f
          (if (self match-at? s sub i) #t (loop (+ i 1))))))
      (if (= sub-len 0) #t (go 0)))
    (method starts? (self (param pfx STRING "Prefix to test for") (param s STRING "String to check"))
      (doc "True if s begins with the prefix pfx."
        (returns BOOL "#t when s starts with pfx")
        (example "(Str8 starts? \"he\" \"hello\")" "#t"))
      (self match-at? s pfx 0))
    (method ends?   (self (param sfx STRING "Suffix to test for") (param s STRING "String to check"))
      (doc "True if s ends with the suffix sfx."
        (returns BOOL "#t when s ends with sfx")
        (example "(Str8 ends? \"lo\" \"hello\")" "#t"))
      (def s-len (self length s))
      (def sfx-len (self length sfx))
      (if (> sfx-len s-len) #f (self match-at? s sfx (- s-len sfx-len))))

    ; --- transformation ---
    (method reverse  (self (param s STRING "String to reverse"))
      (doc "Reverse the elements of s."
        (returns STRING "s with its elements in reverse order")
        (example "(Str8 reverse \"abc\")" "\"cba\""))
      (self ->str (reverse (self ->list s))))
    (method upcase (self (param s STRING "String to convert"))
      (doc "Uppercase the ASCII letters of s; other characters pass through."
        (returns STRING "s with a-z mapped to A-Z")
        (example "(Str8 upcase \"café\")" "\"CAFé\""))
      (self ->str (map char-upcase (self ->list s))))
    (method downcase (self (param s STRING "String to convert"))
      (doc "Lowercase the ASCII letters of s; other characters pass through."
        (returns STRING "s with A-Z mapped to a-z")
        (example "(Str8 downcase \"ABC\")" "\"abc\""))
      (self ->str (map char-downcase (self ->list s))))

    ; --- trimming (whitespace is ASCII; element scanning is correct) ---
    (method trim-left (self (param s STRING "String to trim"))
      (doc "Remove leading whitespace from s."
        (returns STRING "s with leading whitespace removed")
        (example "(Str8 trim-left \"  hi\")" "\"hi\""))
      (let go ((i 0) (n (self length s)))
        (if (= i n) ""
          (if (char-whitespace? (self index s i))
            (go (+ i 1) n)
            (self sub s i (- n i))))))
    (method trim-right (self (param s STRING "String to trim"))
      (doc "Remove trailing whitespace from s."
        (returns STRING "s with trailing whitespace removed")
        (example "(Str8 trim-right \"hi  \")" "\"hi\""))
      (let go ((i (- (self length s) 1)))
        (if (< i 0) ""
          (if (char-whitespace? (self index s i))
            (go (- i 1))
            (self sub s 0 (+ i 1))))))
    (method trim (self (param s STRING "String to trim"))
      (doc "Remove both leading and trailing whitespace from s."
        (returns STRING "s with surrounding whitespace removed")
        (example "(Str8 trim \"  hi  \")" "\"hi\""))
      (self trim-left (self trim-right s)))

    ; --- splitting (empty sep -> per element; else element search) ---
    (method split (self (param sep STRING "Separator to split on") (param s STRING "String to split"))
      (doc "Split s into a list of pieces around each occurrence of sep (empty sep splits into single elements)."
        (returns LIST "List of substrings of s between separators")
        (example "(Str8 split \",\" \"a,b,c\")" "(\"a\" \"b\" \"c\")"))
      (def sep-len (self length sep))
      (def s-len (self length s))
      (if (= sep-len 0)
        (map (fn (_ c) (self ->str (list c))) (self ->list s))
        (let go ((start 0) (i 0) (acc ()))
          (if (> (+ i sep-len) s-len)
            (reverse (pair (self sub s start (- s-len start)) acc))
            (if (self =? (self sub s i sep-len) sep)
              (go (+ i sep-len) (+ i sep-len)
                  (pair (self sub s start (- i start)) acc))
              (go start (+ i 1) acc))))))))

(doc (provide x/protocol/str/str8 Str8)
  (note "The 8-bit byte view. Use (Str8 length s), (Str8 upcase s), etc.; (help Str8) lists every method, (help Str8 method) shows one.")
  "Str8: the 8-bit byte string protocol (a Seq subclass) with the full string method suite.")
