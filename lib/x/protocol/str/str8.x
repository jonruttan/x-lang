; str/str8.x -- Str8: the 8-bit (byte) string class + the full string suite
(import x/protocol/seq)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))
(def %str-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))
; display-to-str renders any value the way display would -- used by (Str8 str ...)
; to coerce non-string arguments (and the target string interpolation expands to).
(def %display-to-str (prim-ref (lit io) (lit display-to-str)))

; str: the foundational string constructor. A TYPE constructor, so it's a bare
; global like `list` (your "types are foundational, classes aren't" line). The
; Str8 class method (Str8 str ...) and $"..." interpolation delegate to it.
(def str (fn (_ . args) (fold (fn (_ acc x) (%str-append acc (%display-to-str x))) "" args)))



; Str8 treats a STRING as its raw bytes (8-bit chars, 0-255), with no encoding
; protocol. It provides the whole string suite as static methods:
; (Str8 append a b), (Str8 ref i s), (Str8 length s), (Str8 upcase s), ...
;
; Three string PROTOCOLS:
;   Str8     -- always 8-bit bytes (this class)
;   StrUTF8  -- always UTF-8 code points (subclass; overrides the primitives)
;   Str      -- the AMBIENT protocol (currently = Str8); see provide below
;
; The suite is written ONCE here, expressed entirely through SELF primitives:
;   (self length s)        -- element count
;   (self ref i s)       -- i-th element (CHARACTER)
;   (self sub start len s)  -- substring of `len` elements from `start`
;   (self =? a b) (self ->list s) (self ->str l)
; so a subclass that overrides only those gets the whole suite in its own
; protocol. Str8's primitives bottom out in the str-byte-* C primitives, which
; are ALWAYS byte-level and IGNORE any handler pushed on the ambient string
; call -- so Str8 is allocation-light and safe to use inside readers/tokenizers
; that must not touch the ambient (s i).

; N5 (implicit conversion): index/count seats coerce to INT once at entry;
; an already-INT arg costs one type-handle eq?, anything else converts, and
; only an unconvertible value errors (list.x's %list->int is the pattern).
(def %str8-type-of (prim-ref (lit type) (lit of)))
(def %str8-int-type (%str8-type-of 0))
(def %str8-cvt (prim-ref (lit convert) (lit to)))
(def %str8->int (fn (_ n what)
  (if (if (null? n) #f (eq? (%str8-type-of n) %str8-int-type)) n
    (let ((k (%str8-cvt n %str8-int-type)))
      (if (if (null? k) #f (eq? (%str8-type-of k) %str8-int-type)) k (error what))))))

(def-class Str8 (extends Seq)
  (static
    ; --- primitives (8-bit byte view; handler-immune via str-byte-*) ---
    (method length (self (param v STRING "String to measure"))
      (doc "Number of bytes in v (the 8-bit element count)."
        (returns INT "Byte length of v")
        (example "(Str8 length \"abc\")" "3"))
      (%str-byte-len v))
    (method ref    (self (param i INT "Byte position (0-based; negative counts from the end)") (param v STRING "String to index"))
      (doc "The i-th byte of v as a CHARACTER (code 0-255); negative i counts from the end. Errors when i is nil or out of range."
        (returns CHAR "Byte at position i")
        (example "(Str8 ref 0 \"abc\")" "#\\a"))
      ; %str-byte-ref reads s[i] unchecked (heap over-read past the string), so
      ; the byte-length compare here is the x-lang guard. Nested ifs, not `or`:
      ; this runs per element inside the suite's loops. The entry coercion
      ; makes a piped index-search miss (nil, unconvertible) fail loudly; only
      ; the negative case pays the second byte-len fetch.
      (def j (%str8->int i "Str8 ref: index not convertible to INT"))
      (if (< j 0)
        (if (< (+ j (%str-byte-len v)) 0) (error "Str8 ref: index out of range")
          (%str-byte-ref v (+ j (%str-byte-len v))))
        (if (< j (%str-byte-len v)) (%str-byte-ref v j)
          (error "Str8 ref: index out of range"))))
    (method sub    (self (param st INT "Start byte offset (0-based)") (param len INT "Number of bytes") (param v STRING "Source string"))
      (doc "Substring of len bytes starting at byte offset st; st and len clamp to v's bounds (like StrUTF8 sub)."
        (returns STRING "The len-byte slice of v from st")
        (example "(Str8 sub 1 3 \"hello\")" "\"ell\""))
      ; %str-byte-sub reads unchecked (heap over-read past the string), so the
      ; clamping here is the x-lang guard, mirroring StrUTF8 sub's clamp.
      (def st2 (%str8->int st "Str8 sub: start not convertible to INT"))
      (def len2 (%str8->int len "Str8 sub: length not convertible to INT"))
      (let ((n (%str-byte-len v)))
        (let ((s0 (if (< st2 0) 0 (if (< st2 n) st2 n))))
          (%str-byte-sub v s0
            (if (< len2 0) 0 (if (< len2 (- n s0)) len2 (- n s0)))))))
    (method slice  (self (param st INT "Start offset (0-based, inclusive)") (param end INT "End offset (exclusive)") (param v STRING "Source string"))
      (doc "Substring [st, end) -- the slice convention (start/end-exclusive), delegating to sub (start/length). Dispatches through (self sub), so StrUTF8 slices code points."
        (returns STRING "The [st, end) slice of v")
        (example "(Str8 slice 1 4 \"hello\")" "\"ell\""))
      (self sub st (- end st) v))
    (method index  (self (param i INT "Byte position (0-based)") (param v STRING "String to index"))
      (doc "Alias for ref (the adjudicated element-access name): the i-th byte of v as a CHARACTER."
        (returns CHAR "Byte at position i")
        (example "(Str8 index 0 \"abc\")" "#\\a"))
      (self ref i v))  ; alias: index = ref

    ; cursor primitives (drive Seq's ->list/for-each/fold/count).
    ; The cursor is a BYTE offset for every subclass, so done? bounds against the
    ; raw byte length -- NOT (self length), which a code-point subclass overrides
    ; via count -> done?, an infinite recursion. start/done? are inherited
    ; unchanged by StrUTF8; only step advances differently.
    (method start (self v)     0)
    (method done? (self cur v) (>= cur (%str-byte-len v)))
    (method step  (self cur v) (pair (self ref cur v) (+ cur 1)))

    ; encode: one byte element is its own low byte. Makes
    ; (Str8 ->str (Str8 ->list s)) an identity on the byte view.
    (method char->bytes (self el) (list (& (%char->integer el) 255)))

    ; --- equality (byte equality; correct code-point equality for UTF-8 too) ---
    (method =? (self (param a STRING "First string") (param b STRING "Second string"))
      (doc "True if a and b have equal length and equal bytes."
        (returns BOOL "#t when a and b are byte-equal")
        (example "(Str8 =? \"ab\" \"ab\")" "#t"))
      (if (= (self length a) (self length b))
        (let go ((i 0) (n (self length a)))
          (if (= i n) #t
            (if (= (%char->integer (self ref i a))
                   (%char->integer (self ref i b)))
              (go (+ i 1) n) #f)))
        #f))

    ; does sub occur in s at element position pos?
    (method match-at? (self sub pos s)
      (def sub-len (self length sub))
      (if (> (+ pos sub-len) (self length s)) #f
        (self =? (self sub pos sub-len s) sub)))

    ; --- construction ---
    (method append (self . (param args STRING "Strings to concatenate"))
      (doc "Concatenate all argument strings, left to right."
        (returns STRING "The arguments joined end to end")
        (example "(Str8 append \"ab\" \"cd\" \"ef\")" "\"abcdef\""))
      (fold %str-append "" args))
    (method str (self . (param args ANY "Values to render and concatenate"))
      (doc "Concatenate values into one string, coercing each via display (so non-strings render too). The target of $\"...{expr}...\" interpolation."
        (returns STRING "The rendered values joined end to end")
        (example "(Str8 str \"x=\" 5 \"!\")" "\"x=5!\""))
      (apply str args))                            ; delegate to the foundational global
    (method iter (self (param s STRING "String to iterate"))
      (doc "An iterator over the string's characters." (returns ITER "Character iterator"))
      (Iter new s))
    (method make   (self (param k INT "Number of elements") . (param rest CHAR "Fill character (default space)"))
      (doc "A string of k copies of the fill character (space if omitted)."
        (returns STRING "k-element string of the fill character")
        (example "(Str8 make 3 (\" \" 0))" "\"   \""))
      (def ch (if (null? rest) #\space (first rest)))
      (self ->str (List repeat k ch)))

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
          ((Char <? (self ref i a) (self ref i b)) #t)
          ((Char >? (self ref i a) (self ref i b)) #f)
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
        (#t (fold (fn (_ acc s) (%str-append acc (%str-append sep s)))
                  (first lst) (rest lst)))))
    (method repeat (self (param n INT "Number of copies") (param s STRING "String to repeat"))
      (doc "Concatenate n copies of s (empty string when n <= 0)."
        (returns STRING "s repeated n times")
        (example "(Str8 repeat 3 \"ab\")" "\"ababab\""))
      (def k (%str8->int n "Str8 repeat: count not convertible to INT"))
      (def go (fn (self j) (if (<= j 0) "" (%str-append s (self (- j 1))))))
      (go k))

    ; --- padding (to n ELEMENTS: bytes for Str8, code points for Str --
    ; NOT display columns; wcwidth-style column tables are a known gap) ---
    (method pad-left (self (param n INT "Target element count") (param ch CHAR "Padding character") (param s STRING "String to pad"))
      (doc "Left-pad s with ch until it is at least n ELEMENTS long (bytes for Str8, code points for Str) -- element count, not display columns."
        (returns STRING "s padded on the left to n elements (unchanged if already >= n)")
        (example "(Str8 pad-left 5 (\"0\" 0) \"42\")" "\"00042\""))
      (def k (%str8->int n "Str8 pad-left: count not convertible to INT"))
      (def len (self length s))
      (if (not (< len k)) s
        (%str-append (self make (- k len) ch) s)))

    (method pad-right (self (param n INT "Target element count") (param ch CHAR "Padding character") (param s STRING "String to pad"))
      (doc "Right-pad s with ch until it is at least n ELEMENTS long (bytes for Str8, code points for Str) -- pad-left's missing twin."
        (returns STRING "s padded on the right to n elements (unchanged if already >= n)")
        (example "(Str8 pad-right 5 (\"0\" 0) \"42\")" "\"42000\""))
      (def k (%str8->int n "Str8 pad-right: count not convertible to INT"))
      (def len (self length s))
      (if (not (< len k)) s
        (%str-append s (self make (- k len) ch))))

    ; --- searching ---
    (method contains? (self (param sub STRING "Substring to search for") (param s STRING "String to search in"))
      (doc "True if sub occurs anywhere within s (empty sub always matches)."
        (returns BOOL "#t when s contains sub")
        (example "(Str8 contains? \"ll\" \"hello\")" "#t"))
      (def s-len (self length s))
      (def sub-len (self length sub))
      (def go (fn (loop i)
        (if (> (+ i sub-len) s-len) #f
          (if (self match-at? sub i s) #t (loop (+ i 1))))))
      (if (= sub-len 0) #t (go 0)))
    (method starts? (self (param pfx STRING "Prefix to test for") (param s STRING "String to check"))
      (doc "True if s begins with the prefix pfx."
        (returns BOOL "#t when s starts with pfx")
        (example "(Str8 starts? \"he\" \"hello\")" "#t"))
      (self match-at? pfx 0 s))
    (method ends?   (self (param sfx STRING "Suffix to test for") (param s STRING "String to check"))
      (doc "True if s ends with the suffix sfx."
        (returns BOOL "#t when s ends with sfx")
        (example "(Str8 ends? \"lo\" \"hello\")" "#t"))
      (def s-len (self length s))
      (def sfx-len (self length sfx))
      (if (> sfx-len s-len) #f (self match-at? sfx (- s-len sfx-len) s)))

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
      (self ->str (map (fn (_ c) (Char upcase c)) (self ->list s))))
    (method downcase (self (param s STRING "String to convert"))
      (doc "Lowercase the ASCII letters of s; other characters pass through."
        (returns STRING "s with A-Z mapped to a-z")
        (example "(Str8 downcase \"ABC\")" "\"abc\""))
      (self ->str (map (fn (_ c) (Char downcase c)) (self ->list s))))

    ; --- trimming (whitespace is ASCII; element scanning is correct) ---
    (method trim-left (self (param s STRING "String to trim"))
      (doc "Remove leading whitespace from s."
        (returns STRING "s with leading whitespace removed")
        (example "(Str8 trim-left \"  hi\")" "\"hi\""))
      (let go ((i 0) (n (self length s)))
        (if (= i n) ""
          (if (Char whitespace? (self ref i s))
            (go (+ i 1) n)
            (self sub i (- n i) s)))))
    (method trim-right (self (param s STRING "String to trim"))
      (doc "Remove trailing whitespace from s."
        (returns STRING "s with trailing whitespace removed")
        (example "(Str8 trim-right \"hi  \")" "\"hi\""))
      (let go ((i (- (self length s) 1)))
        (if (< i 0) ""
          (if (Char whitespace? (self ref i s))
            (go (- i 1))
            (self sub 0 (+ i 1) s)))))
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
            (reverse (pair (self sub start (- s-len start) s) acc))
            (if (self =? (self sub i sep-len s) sep)
              (go (+ i sep-len) (+ i sep-len)
                  (pair (self sub start (- i start) s) acc))
              (go start (+ i 1) acc))))))))

(doc (provide x/protocol/str/str8 Str8 str)
  (note "The 8-bit byte view. Use (Str8 length s), (Str8 upcase s), etc.; (help Str8) lists every method, (help Str8 method) shows one.")
  "Str8: the 8-bit byte string protocol (a Seq subclass) with the full string method suite.")
