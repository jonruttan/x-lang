; str.x -- The string library, in the ACTIVE string protocol.
;
; This is the canonical string module (it supersedes the deprecated
; x/type/string). It does NOT implement the string operations -- those live
; once, as methods, on the protocol classes:
;
;   x/protocol/str/str8   Str8     -- 8-bit bytes
;   x/protocol/str/utf8   StrUTF8  -- UTF-8 code points
;
; and `Str` names the ACTIVE protocol (Str8 at startup; rebind to StrUTF8 to
; switch the whole library to code points). Every function here is a thin
; delegator to `Str`, looked up by name at call time, so they all follow the
; active protocol automatically -- change `Str` and the entire str-* API
; changes with it. No per-function rebinding.
;
; Two element views of a STRING:
;   - BYTE view: a string is its raw 0-255 octets. str-byte-* (and str-ref /
;     str-length / substring, which are pinned to bytes) always use this. It is
;     O(1) to index, never allocates, and is what readers/tokenizers must use.
;   - CODE-POINT view: a string is its decoded Unicode code points. The bare
;     call (s i) and this str-* API use the ACTIVE protocol, which is UTF-8.
;     Code-point random access is O(n) (variable width); prefer whole-string
;     ops (str->list, map over it) when visiting every element.
;
; See `(help str-protocols)` for the full model.

(import x/protocol/str/utf8)   ; loads Str8 + StrUTF8 (+ Str alias)
(import x/core/list)

(note "Construction")

; str / make-str are variadic. (Class method ...) is operative dispatch (the
; selector is unevaluated), so apply can't splat into it -- these call the
; underlying ops directly. Concatenation is byte-append (valid for UTF-8 too);
; make uses the active protocol's element repeat.
(doc (def str (fn (_ . args) (fold str-append "" args)))
  (returns STRING "All arguments concatenated")
  (example "(str \"a\" \"b\" \"c\")" "\"abc\"")
  "Concatenate strings.")

(doc (def make-str
  (fn (_ k . rest)
    (def ch (if (null? rest) (" " 0) (first rest)))
    (Str ->str (repeat ch k))))
  (param k INT "Number of elements")
  (param rest CHAR "Optional fill character (default space)")
  (returns STRING "A string of k copies of the fill character")
  (example "(make-str 3)" "\"   \"")
  "Build a string of k repeated characters (code points under StrUTF8).")

(note "Predicates")

(doc (def str-empty? (fn (_ s) (Str empty? s)))
  (param s STRING "String to test")
  (returns BOOL "#t if s has no elements")
  (example "(str-empty? \"\")" "#t")
  "Test whether a string is empty.")

(note "Length / indexing")
; str-length, str-ref, substring are BYTE accessors (boot/string.x, bound to the
; str-byte-* C primitives). They stay byte-level regardless of the active
; protocol -- this is the raw octet view. Documented here for discoverability.

(doc str-length
  (param s STRING "String to measure")
  (returns INT "Byte length of s")
  (example "(str-length \"$¢€\")" "6")
  "Byte length (raw octets). For element count in the active protocol use (Str length s).")

(doc str-ref
  (param s STRING "String to index")
  (param i INT "Byte offset (negative counts from the end)")
  (returns CHAR "The byte at offset i, as a CHARACTER (0-255)")
  (example "(str-ref \"$¢€\" 1)" "#\\Â")
  "Byte at offset i. For the i-th code point use (StrUTF8 index s i) or the bare (s i).")

(doc substring
  (param s STRING "Source string")
  (param start INT "Start byte offset")
  (param end INT "End byte offset (exclusive)")
  (returns STRING "The bytes [start, end) of s")
  (example "(substring \"abcdef\" 1 4)" "\"bcd\"")
  "Byte substring [start, end). Always byte-level.")

(note "Joining / repeating")

(doc (def str-join (fn (_ sep lst) (Str join sep lst)))
  (param sep STRING "Separator inserted between elements")
  (param lst LIST "List of strings")
  (returns STRING "lst joined by sep")
  (example "(str-join \", \" (list \"a\" \"b\"))" "\"a, b\"")
  "Join a list of strings with a separator.")

(doc (def str-repeat (fn (_ s n) (Str repeat s n)))
  (param s STRING "String to repeat")
  (param n INT "Repetition count")
  (returns STRING "s repeated n times")
  (example "(str-repeat \"ab\" 3)" "\"ababab\"")
  "Repeat a string n times.")

(note "Padding")

(doc (def str-pad-left (fn (_ s n ch) (Str pad-left s n ch)))
  (param s STRING "String to pad")
  (param n INT "Target width, in elements of the active protocol")
  (param ch CHAR "Pad character")
  (returns STRING "s left-padded with ch to width n")
  (example "(str-pad-left \"hi\" 5 (\" \" 0))" "\"   hi\"")
  "Left-pad to n elements (code points under StrUTF8).")

(note "Searching")

(doc (def str-contains? (fn (_ sub s) (Str contains? sub s)))
  (param sub STRING "Substring to find")
  (param s STRING "String to search")
  (returns BOOL "#t if sub occurs in s")
  (example "(str-contains? \"ll\" \"hello\")" "#t")
  "Test whether s contains sub.")

(doc (def str-starts? (fn (_ pfx s) (Str starts? pfx s)))
  (param pfx STRING "Prefix")
  (param s STRING "String to test")
  (returns BOOL "#t if s starts with pfx")
  (example "(str-starts? \"he\" \"hello\")" "#t")
  "Test whether s starts with pfx.")

(doc (def str-ends? (fn (_ sfx s) (Str ends? sfx s)))
  (param sfx STRING "Suffix")
  (param s STRING "String to test")
  (returns BOOL "#t if s ends with sfx")
  (example "(str-ends? \"lo\" \"hello\")" "#t")
  "Test whether s ends with sfx.")

(note "Transformation")

(doc (def str-reverse (fn (_ s) (Str reverse s)))
  (param s STRING "String to reverse")
  (returns STRING "s reversed by element")
  (example "(str-reverse \"abc\")" "\"cba\"")
  "Reverse a string (whole code points under StrUTF8).")

(doc (def str-upcase (fn (_ s) (Str upcase s)))
  (param s STRING "String to convert")
  (returns STRING "s uppercased (ASCII letters)")
  (example "(str-upcase \"café\")" "\"CAFé\"")
  "Uppercase ASCII letters; other characters pass through.")

(doc (def str-downcase (fn (_ s) (Str downcase s)))
  (param s STRING "String to convert")
  (returns STRING "s lowercased (ASCII letters)")
  (example "(str-downcase \"CAFÉ\")" "\"cafÉ\"")
  "Lowercase ASCII letters; other characters pass through.")

(note "Conversion")

(doc (def str->list (fn (_ s) (Str ->list s)))
  (param s STRING "String to convert")
  (returns LIST "List of CHARACTERs, one per element of the active protocol")
  (example "(str->list \"$¢€\")" "(#\\$ #\\¢ #\\€)")
  "Explode a string into its characters (code points under StrUTF8).")

(note "Ordering")

; str=? is NOT redefined here: it stays the byte-level boot primitive
; (boot/string.x). It runs inside the tokenizer (e.g. the logo readers), which
; must not allocate; routing it through the object-dispatching Str would trip GC
; mid-parse. Byte equality is the same answer as code-point equality, so there is
; no semantic loss. Documented for discoverability.
(doc str=?
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a and b are equal")
  (example "(str=? \"ab\" \"ab\")" "#t")
  "String equality (byte-level; same result as code-point equality).")

(doc (def str<?  (fn (_ a b) (Str <?  a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a sorts before b")
  (example "(str<? \"abc\" \"abd\")" "#t")
  "Lexicographic less-than.")

(doc (def str>?  (fn (_ a b) (Str >?  a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a sorts after b")
  "Lexicographic greater-than.")

(doc (def str<=? (fn (_ a b) (Str <=? a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a sorts before or equal to b")
  "Lexicographic less-than-or-equal.")

(doc (def str>=? (fn (_ a b) (Str >=? a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a sorts after or equal to b")
  "Lexicographic greater-than-or-equal.")

(note "Case-insensitive ordering")

(doc (def str-ci=?  (fn (_ a b) (Str ci=?  a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if equal ignoring ASCII case")
  (example "(str-ci=? \"Hello\" \"hello\")" "#t")
  "Case-insensitive equality.")

(doc (def str-ci<?  (fn (_ a b) (Str ci<?  a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a < b ignoring ASCII case")
  "Case-insensitive less-than.")

(doc (def str-ci>?  (fn (_ a b) (Str ci>?  a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a > b ignoring ASCII case")
  "Case-insensitive greater-than.")

(doc (def str-ci<=? (fn (_ a b) (Str ci<=? a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a <= b ignoring ASCII case")
  "Case-insensitive less-than-or-equal.")

(doc (def str-ci>=? (fn (_ a b) (Str ci>=? a b)))
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a >= b ignoring ASCII case")
  "Case-insensitive greater-than-or-equal.")

(note "Trimming")

(doc (def str-trim-left  (fn (_ s) (Str trim-left s)))
  (param s STRING "String to trim")
  (returns STRING "s without leading whitespace")
  "Drop leading whitespace.")

(doc (def str-trim-right (fn (_ s) (Str trim-right s)))
  (param s STRING "String to trim")
  (returns STRING "s without trailing whitespace")
  "Drop trailing whitespace.")

(doc (def str-trim (fn (_ s) (Str trim s)))
  (param s STRING "String to trim")
  (returns STRING "s without leading or trailing whitespace")
  (example "(str-trim \"  hi  \")" "\"hi\"")
  "Drop leading and trailing whitespace.")

(note "Splitting")

(doc (def str-split (fn (_ sep s) (Str split sep s)))
  (param sep STRING "Separator; empty string splits into single characters")
  (param s STRING "String to split")
  (returns LIST "List of substrings")
  (example "(str-split \",\" \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "Split s on sep. An empty sep splits into one string per element.")

(doc (provide x/type/str
  str make-str str-empty? str-length str-ref substring
  str-join str-repeat str-pad-left
  str-contains? str-starts? str-ends?
  str-reverse str-upcase str-downcase str->list
  str=? str<? str>? str<=? str>=?
  str-ci=? str-ci<? str-ci>? str-ci<=? str-ci>=?
  str-trim-left str-trim-right str-trim str-split)
  (note "All operations follow the active protocol via the `Str` alias (Str8 by default; rebind to StrUTF8 for code points). For an explicit protocol use (Str8 ...) / (StrUTF8 ...).")
  "String library in the active protocol. Supersedes x/type/string.")
