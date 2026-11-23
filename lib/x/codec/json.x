; codec/json.x -- Json: parse and emit JSON text.
;
; The value mapping (both directions):
;   JSON object <-> Dict (string keys -- the reason this codec waited for x/type/dict)
;   array  <-> list          string <-> string      true/false <-> #t/#f
;   null   <-> the symbol `null` (nil would collide with the empty array)
;   number <-> integer, or FLOAT when the text carries . / e (built at runtime
;              via the conversion catalogue -- this SOURCE file stays float-literal-free
;              so it loads under plain x-core)
;
; Parsing is recursive descent over TOKENS.  A Lexer (x/reader/lexer) reads
; the text into blank runs, punctuation, strings, numbers and words, its
; analyser states compiled where the assembler lane is open, and each step
; of the descent takes the tokens it starts at and answers
; (value . tokens after).  A string no backslash is in is one slice of its
; token; any other is read by a second lexer into plain runs and escapes.
; \uXXXX decodes to a code point (surrogate pairs combined) and re-encodes
; as UTF-8; raw UTF-8 bytes pass through untouched both ways.
;
; A text is read a piece at a time and the heap collected between pieces,
; so a text of any length costs the values it answers and one piece's
; tokens: see %json-piece.
;
; Bytes and positions are machine integers, and the parser and the emitter
; compare and step them through the int doors: under the numeric tower the
; generic = < + and - dispatch on their operands' types.
;
; Emission escapes properly -- the gap that kept lib/x/logo/json.x app-only:
; " \ and control bytes come out as \" \\ \n \r \t \b \f or \u00XX.

(module x/codec/json)
(import x/type/class)
(import x/type/dict)
(import x/type/list)
(import x/num/float)
(import x/sys/gc)
(import x/reader/lexer)

; Fetch the byte-level string prims from the catalogue (ns `str` de-registered, R5).
(import x/core/doors char->int int& int* int+ int- int< int= int>> io-display-to-str str-append str-byte-len str-byte-ref str-byte-sub)
; display-to-str renders any number the way the printer would (int/bigint/float).
; The conversion dispatcher: (%json-cvt "2.5" %float) parses AND boxes a float
; via the float type's from-alist (%float is the documented convert type
; handle, bound when x/num/float loads above).
(def %json-cvt (prim-ref 'convert 'to))
; char->int for byte values of CHARACTERs coming from str-byte-ref callers.

(def %json-bs (str-byte-sub "\\x" 0 1))   ; a one-byte backslash string
(def %json-quote (str-byte-sub "\"x" 0 1)) ; a one-byte double-quote string

; str-byte-ref returns a CHARACTER; the parser wants byte INTs.
(def %json-byte (fn (_ s i) (char->int (str-byte-ref s i))))

; --- tokens ----------------------------------------------------------------
; Two lexers, made at the first parse.  The first reads a text: blank runs,
; the punctuation, a string, a number, a word.  A string no backslash is in
; reads as ps, so its value is one slice of the token; any other string
; reads as s, and the second lexer reads its raw text into quotes, plain
; runs and two-byte escapes.  Blank runs are kept as tokens, so the byte a
; token starts at is the length of the text before it.
(def %json-lexer-cell (pair () ()))
(def %json-lexer
  (fn (_)
    (if (null? (first %json-lexer-cell))
      (let ((blank " \t\r\n")
            (letters (list (pair 97 122) (pair 65 90)))
            ; a byte past 127 is a negative code where the machine's char is
            ; signed and a code of 128 to 255 where it is not: both are listed
            (unquoted (list (pair 1 33) (pair 35 91) (pair 93 127) (pair -128 -1) (pair 128 255))))
        (%set-first! %json-lexer-cell
          (pair
            (Lexer make (list
              (Lexer run 'ws blank blank)
              (Lexer table 'p (list "{" "}" "[" "]" "," ":" "-"))
              (Lexer pattern 'ps (list (list "\"" 1 1) (list unquoted 0 ()) (list "\"" 1 1)))
              (Lexer quoted 's 34 34 92)
              (Lexer number 'n ())
              (Lexer run 'w letters letters)
              (Lexer any 'bad)))
            (Lexer make (list
              (Lexer table 'q (list "\""))
              (Lexer run 'p unquoted unquoted)
              (Lexer escape 'e 92))))))
      ())
    (first %json-lexer-cell)))

; A token is (TAG TEXT), a number's (TAG TEXT LABEL).

; A text is read a piece at a time, and the heap is collected before each
; piece after the first: a read and the walk over its tokens leave garbage
; behind every token, and nothing collects it during one call.  Only the
; piece in hand is held, so a text of any length costs the values it
; answers and one piece's tokens.  A piece may end inside a token, so its
; last token is left for the next piece to read whole, and so is everything
; from a quote the lexer read alone, which is a string the piece cut.  A
; piece that keeps no token is read again at twice the size.  A piece that
; is not the last ends in the token `more`, where the next is read.
(def %json-piece 32768)
(def %json-more (list 'more ""))

; The text being parsed, its length, where the next piece starts, where the
; piece in hand started, and that piece's tokens.
(def %json-src (pair () ()))
(def %json-len (pair 0 ()))
(def %json-pos (pair 0 ()))
(def %json-base (pair 0 ()))
(def %json-all (pair () ()))

; The tokens of ts pushed onto acc, with the bytes they span, up to where
; the piece's end may have cut.
(def %json-keep
  (fn (self ts acc k)
    (match
      ((null? ts) (pair acc k))
      ((null? (rest ts)) (pair acc k))
      ((if (eq? (first (first ts)) 'bad) (str=? (first (rest (first ts))) %json-quote) #f)
        (pair acc k))
      (#t (self (rest ts) (pair (first ts) acc)
            (int+ k (str-byte-len (first (rest (first ts))))))))))

; The next piece's tokens, nil at the text's end.
(def %json-read
  (fn (_)
    (def s (first %json-src))
    (def n (first %json-len))
    (def l (first (%json-lexer)))
    (def hold
      (fn (_ ts i next)
        (%set-first! %json-base i)
        (%set-first! %json-pos next)
        (%set-first! %json-all ts)
        ts))
    (if (int< 0 (first %json-pos)) (Heap collect) ())
    (let go ((i (first %json-pos)) (size %json-piece))
      (if (not (int< (int+ i size) n))
        (hold (l read-str (str-byte-sub s i (int- n i))) i n)
        (let ((got (%json-keep (l read-str (str-byte-sub s i size)) () 0)))
          (if (int= (rest got) 0)
            (go i (int* size 2))
            (hold (%reverse (pair %json-more (first got))) i (int+ i (rest got)))))))))

; The byte the first token of ts starts at, counted through the piece in
; hand; the text's end for no token.
(def %json-at
  (fn (_ ts)
    (if (null? ts) (first %json-len)
      (let go ((all (first %json-all)) (n (first %json-base)))
        (if (if (null? all) #t (eq? all ts)) n
          (go (rest all) (int+ n (str-byte-len (first (rest (first all)))))))))))

(def %json-err
  (fn (_ what ts)
    (def at (%json-at ts))
    (%set-first! %json-all ())
    (%set-first! %json-src ())
    (Err raise 'value (str-append "Json parse: " (str-append what
      (str-append " at byte " (%number->str at)))) ())))

; ts past a blank run, the next piece read where this one ends.
(def %json-skip
  (fn (self ts)
    (if (null? ts) ts
      (let ((tag (first (first ts))))
        (match
          ((eq? tag 'ws) (self (rest ts)))
          ((eq? tag 'more) (self (%json-read)))
          (#t ts))))))

; ts itself, the next piece read where this one ends.
(def %json-fill
  (fn (_ ts)
    (if (null? ts) ts (if (eq? (first (first ts)) 'more) (%json-read) ts))))

; The byte of the punctuation ts starts with, 0 when it starts with none.
(def %json-punct
  (fn (_ ts)
    (if (null? ts) 0 (if (eq? (first (first ts)) 'p) (%json-byte (first (rest (first ts))) 0) 0))))

(def %json-word
  (fn (_ ts)
    (def w (first (rest (first ts))))
    (match
      ((str=? w "true") #t)
      ((str=? w "false") #f)
      ((str=? w "null") 'null)
      (#t (%json-err "unknown literal" ts)))))

; --- numbers ---------------------------------------------------------------
; The lexer labels a number: 1 an integer, 2 one with a fraction or an
; exponent, 3 a hex integer, which JSON has none of.  A float is built via
; the conversion catalogue -- runtime, no float literals here.

; JSON allows an exponent with no point (1e3); the float reader needs one,
; so an exponent with no point before it gets ".0" before its e.
(def %json-pointed
  (fn (_ text)
    (def n (str-byte-len text))
    (def epos
      (let go ((j 0))
        (if (not (int< j n)) ()
          (let ((b (%json-byte text j)))
            (match
              ((int= b 46) ())
              ((int= b 101) j)
              ((int= b 69) j)
              (#t (go (int+ j 1))))))))
    (if (null? epos) text
      (str-append (str-append (str-byte-sub text 0 epos) ".0")
        (str-byte-sub text epos (int- n epos))))))

(def %json-hex?
  (fn (_ text)
    (if (int< (str-byte-len text) 2) #f
      (let ((b (%json-byte text 1))) (if (int= b 120) #t (int= b 88))))))

; An integer's value from its digits.  One of fifteen digits or fewer is a
; machine integer, stepped a digit at a time; a longer one goes to the
; numeric reader, which answers a big integer.
(def %json-int
  (fn (_ text sign)
    (def n (str-byte-len text))
    (if (int< 15 n) (%str->number (str-append sign text))
      (let go ((j 0) (acc 0))
        (if (int< j n)
          (go (int+ j 1) (int+ (int* acc 10) (int- (%json-byte text j) 48)))
          (if (str=? sign "") acc (int- 0 acc)))))))

; The number ts starts with, SIGN before its text; AT is where it began.
(def %json-number
  (fn (_ ts0 at sign)
    (def ts (%json-fill ts0))
    (if (if (null? ts) #t (not (eq? (first (first ts)) 'n))) (%json-err "malformed number" at)
      (let ((text (first (rest (first ts)))) (label (first (rest (rest (first ts))))))
        ; %json-cvt, not the bits door (Float str->bits): that returns the raw IEEE bit
        ; pattern; the convert path boxes a real FLOAT value.
        (def v
          (match
            ((%json-hex? text) ())
            ((int= label 1) (%json-int text sign))
            (#t (%json-cvt (str-append sign (%json-pointed text))
                  (eval (lit float) (module x/num/float))))))
        (if (null? v) (%json-err "malformed number" at) (pair v (rest ts)))))))

; --- strings ---------------------------------------------------------------
; The value of one hex digit's byte, or nil.
(def %json-hex-digit
  (fn (_ b)
    (match
      ((if (not (int< b 48)) (not (int< 57 b)) #f) (int- b 48))
      ((if (not (int< b 97)) (not (int< 102 b)) #f) (int- b 87))
      ((if (not (int< b 65)) (not (int< 70 b)) #f) (int- b 55))
      (#t ()))))

; The four hex digits a \u is followed by: the start of the plain run after it.
(def %json-hex4
  (fn (_ ts at)
    (if (if (null? ts) #t
          (if (eq? (first (first ts)) 'p) (int< (str-byte-len (first (rest (first ts)))) 4) #t))
      (%json-err "truncated \\u escape" at)
      (let ((text (first (rest (first ts)))))
        (let go ((j 0) (acc 0))
          (if (int< j 4)
            (let ((v (%json-hex-digit (%json-byte text j))))
              (if (null? v) (%json-err "malformed \\u escape" at)
                (go (int+ j 1) (int+ (int* acc 16) v))))
            acc))))))

; The tokens after those four digits: what is left of the run, then the rest.
(def %json-after4
  (fn (_ ts)
    (def text (first (rest (first ts))))
    (def n (str-byte-len text))
    (if (int= n 4) (rest ts)
      (pair (list 'p (str-byte-sub text 4 (int- n 4))) (rest ts)))))

; The UTF-8 bytes of code point cp, as a string.
(def %json-utf8
  (fn (_ cp)
    (def tail (fn (_ shift) (int+ 128 (int& (int>> cp shift) 63))))
    (bytes->str
      (match
        ((int< cp 128) (list cp))
        ((int< cp 2048) (list (int+ 192 (int>> cp 6)) (tail 0)))
        ((int< cp 65536) (list (int+ 224 (int>> cp 12)) (tail 6) (tail 0)))
        (#t (list (int+ 240 (int>> cp 18)) (tail 12) (tail 6) (tail 0)))))))

; Whether ts starts with a \u escape.
(def %json-u?
  (fn (_ ts)
    (if (null? ts) #f
      (if (eq? (first (first ts)) 'e) (int= (%json-byte (first (rest (first ts))) 1) 117) #f))))

; \uXXXX (with surrogate-pair combining), ts the tokens after the escape
; -> (utf8-string . tokens after it)
(def %json-unicode
  (fn (_ ts at)
    (def hi (%json-hex4 ts at))
    (def more (%json-after4 ts))
    (if (if (not (int< hi 55296)) (not (int< 56319 hi)) #f)          ; D800-DBFF: lead surrogate
      (if (if (int= (str-byte-len (first (rest (first ts)))) 4) (%json-u? more) #f)
        (let ((lo (%json-hex4 (rest more) at)))
          (if (if (not (int< lo 56320)) (not (int< 57343 lo)) #f)    ; DC00-DFFF: tail surrogate
            (pair (%json-utf8 (int+ 65536 (int+ (int* 1024 (int- hi 55296)) (int- lo 56320))))
                  (%json-after4 (rest more)))
            (%json-err "lone lead surrogate" at)))
        (%json-err "lone lead surrogate" at))
      (if (if (not (int< hi 56320)) (not (int< 57343 hi)) #f)
        (%json-err "lone tail surrogate" at)
        (pair (%json-utf8 hi) more)))))

; The text one escape byte stands for.
(def %json-escape
  (fn (_ b at)
    (match
      ((int= b 34) %json-quote)
      ((int= b 92) %json-bs)
      ((int= b 47) "/")
      ((int= b 110) (bytes->str (list 10)))   ; \n
      ((int= b 116) (bytes->str (list 9)))    ; \t
      ((int= b 114) (bytes->str (list 13)))   ; \r
      ((int= b 98) (bytes->str (list 8)))     ; \b
      ((int= b 102) (bytes->str (list 12)))   ; \f
      (#t (%json-err "unknown escape" at)))))

; The value of a string token that holds escapes; AT is where it stands.
(def %json-string
  (fn (_ raw at)
    (let go ((ts ((rest (%json-lexer)) read-str raw)) (acc ""))
      (if (null? ts) acc
        (let ((tag (first (first ts))))
          (match
            ((eq? tag 'p) (go (rest ts) (str-append acc (first (rest (first ts))))))
            ((eq? tag 'q) (go (rest ts) acc))
            ((%json-u? ts)
              (let ((u (%json-unicode (rest ts) at)))
                (go (rest u) (str-append acc (first u)))))
            (#t (go (rest ts)
                  (str-append acc (%json-escape (%json-byte (first (rest (first ts))) 1) at))))))))))

; The string ts starts with, or nil when it starts with none.
(def %json-str
  (fn (_ ts)
    (def tag (first (first ts)))
    (def text (first (rest (first ts))))
    (match
      ((eq? tag 'ps) (str-byte-sub text 1 (int- (str-byte-len text) 2)))
      ((eq? tag 's) (%json-string text ts))
      ; a quote the lexer read alone opens a string nothing closes
      ((if (eq? tag 'bad) (str=? text %json-quote) #f) (%json-err "unterminated string" ()))
      (#t ()))))

; --- values ----------------------------------------------------------------
; Each step takes the tokens it starts at and answers (value . tokens after).
(def %json-parse-value ())

(def %json-parse-array
  (fn (self ts0 acc)
    (def ts (%json-skip ts0))
    (if (null? ts) (%json-err "unterminated array" ts)
      (if (int= (%json-punct ts) 93)                              ; ]
        (pair (%reverse acc) (rest ts))
        (let ((v (%json-parse-value ts)))
          (let ((k (%json-skip (rest v))))
            (if (null? k) (%json-err "unterminated array" k)
              (let ((b (%json-punct k)))
                (match
                  ((int= b 44) (self (rest k) (pair (first v) acc)))            ; ,
                  ((int= b 93) (pair (%reverse (pair (first v) acc)) (rest k))) ; ]
                  (#t (%json-err "expected , or ] in array" k)))))))))))

(def %json-parse-object
  (fn (self ts0 d)
    (def ts (%json-skip ts0))
    (match
      ((null? ts) (%json-err "unterminated object" ts))
      ((int= (%json-punct ts) 125) (pair d (rest ts)))            ; }
      (#t
        (let ((key (%json-str ts)))
          (if (null? key) (%json-err "expected a string key" ts)
            (let ((c (%json-skip (rest ts))))
              (if (not (int= (%json-punct c) 58))                 ; :
                (%json-err "expected : after key" c)
                (let ((v (%json-parse-value (rest c))))
                  (do (d set! key (first v))
                      (let ((k (%json-skip (rest v))))
                        (if (null? k) (%json-err "unterminated object" k)
                          (let ((b (%json-punct k)))
                            (match
                              ((int= b 44) (self (rest k) d))
                              ((int= b 125) (pair d (rest k)))
                              (#t (%json-err "expected , or } in object" k))))))))))))))))

(set! %json-parse-value
  (fn (_ ts0)
    (def ts (%json-skip ts0))
    (if (null? ts) (%json-err "unexpected end of input" ts)
      (let ((b (%json-punct ts)))
        (match
          ((int= b 123) (%json-parse-object (rest ts) (Dict make)))
          ((int= b 91) (%json-parse-array (rest ts) ()))
          ((int= b 45) (%json-number (rest ts) ts "-"))
          ((not (int= b 0)) (%json-err "unexpected byte" ts))
          (#t
            (let ((tag (first (first ts))))
              (let ((v (match
                         ((eq? tag 'n) (%json-number ts ts ""))
                         ((eq? tag 'w) (pair (%json-word ts) (rest ts)))
                         (#t (let ((s (%json-str ts)))
                               (if (null? s) (%json-err "unexpected byte" ts)
                                 (pair s (rest ts))))))))
                v))))))))

; --- emission ---------------------------------------------------------------
(def %json-hexdig "0123456789abcdef")
(def %json-hex1 (fn (_ n) (str-byte-sub %json-hexdig (& n 15) 1)))

; Escape one control byte as \u00XX (the shortcut escapes are handled inline).
(def %json-ctl
  (fn (_ b)
    (str-append %json-bs
      (str-append "u00" (str-append (%json-hex1 (>> b 4)) (%json-hex1 b))))))

(def %json-emit-string
  (fn (_ s)
    (def len (str-byte-len s))
    (def %esc
      (fn (_ b)
        (match
          ((int= b 34) (str-append %json-bs %json-quote))
          ((int= b 92) (str-append %json-bs %json-bs))
          ((int= b 10) (str-append %json-bs "n"))
          ((int= b 9) (str-append %json-bs "t"))
          ((int= b 13) (str-append %json-bs "r"))
          ((int= b 8) (str-append %json-bs "b"))
          ((int= b 12) (str-append %json-bs "f"))
          (#t (%json-ctl b)))))
    (def %needs?
      (fn (_ b) (if (int= b 34) #t (if (int= b 92) #t (int< b 32)))))
    (let go ((i 0) (seg 0) (acc %json-quote))
      (if (not (int< i len))
        (str-append acc
          (str-append (str-byte-sub s seg (int- i seg)) %json-quote))
        (let ((b (%json-byte s i)))
          (if (%needs? b)
            (go (int+ i 1) (int+ i 1)
                (str-append acc
                  (str-append (str-byte-sub s seg (int- i seg)) (%esc b))))
            (go (int+ i 1) seg acc)))))))

(def %json-emit ())

; Pieces prepend, ONE concat per container (#333): the per-element
; append re-copied the container's whole accumulated text -- and nested
; containers re-copied their children's finished text at every level.
(def %json-emit-array
  (fn (_ lst)
    (let go ((xs lst) (acc (list "[")) (sep ""))
      (if (null? xs) (%str-concat (%reverse (pair "]" acc)))
        (go (rest xs)
            (pair (%json-emit (first xs)) (pair sep acc))
            ",")))))

(def %json-emit-object
  (fn (_ d)
    (let go ((es (d ->alist)) (acc (list "{")) (sep ""))
      (if (null? es) (%str-concat (%reverse (pair "}" acc)))
        (let ((k (first (first es))))
          (let ((ks (match
                      ((str? k) k)
                      ((symbol? k) (symbol->str k))
                      (#t (Err raise 'type "Json emit: object keys must be strings or symbols" ())))))
            (go (rest es)
                (pair (%json-emit (rest (first es)))
                  (pair ":" (pair (%json-emit-string ks) (pair sep acc))))
                ",")))))))

(set! %json-emit
  (fn (_ v)
    (match
      ((eq? v #t) "true")
      ((eq? v #f) "false")
      ((null? v) "[]")
      ((str? v) (%json-emit-string v))
      ((Num int? v) (io-display-to-str v))
      ((symbol? v)
        (if (str=? (symbol->str v) "null") "null"
          (%json-emit-string (symbol->str v))))
      ((pair? v) (%json-emit-array v))
      ((Dict dict? v) (%json-emit-object v))
      ; the tower's numbers by type name: a rational and a complex have no JSON form
      (#t (let ((tn (Type name v)))
            (match
              ((str=? tn "FLOAT") (io-display-to-str v))
              ((str=? tn "BIGINT") (io-display-to-str v))
              ((str=? tn "RATIONAL") (Err raise 'type "Json emit: no JSON form for a rational (convert to a float first)" ()))
              ((str=? tn "COMPLEX") (Err raise 'type "Json emit: no JSON form for a complex number" ()))
              (#t (Err raise 'type "Json emit: unsupported value type" ()))))))))

(def-class Json ()
  (doc "JSON text codec: parse to Dict/list/string/number/#t/#f/null values, emit with proper escaping."
    (note "JSON objects are Dicts (string keys); arrays are lists; null is the SYMBOL null (nil would collide with []).")
    (note "Decimal and exponent numbers parse as floats (via the conversion catalogue); plain digit runs parse as integers.")
    (example "((Json parse \"{\\\"a\\\": [1, true]}\") get \"a\")" "(1 #t)")
    (see parse) (see emit))
  (static
    (method parse (self (param s STRING "JSON text"))
      (doc "Parse JSON text into x-lang values; malformed input errors with a byte position."
        (returns ANY "Dict / list / string / number / #t / #f / 'null")
        (example "(Json parse \"[1, 2.5, null]\")" "(1 2.5 'null)"))
      (%set-first! %json-src s)
      (%set-first! %json-len (str-byte-len s))
      (%set-first! %json-pos 0)
      (def v (%json-parse-value (%json-read)))
      (if (null? (%json-skip (rest v)))
        (do (%set-first! %json-all ()) (%set-first! %json-src ()) (first v))
        (%json-err "trailing content" (rest v))))
    (method emit (self (param v ANY "Value to serialize"))
      (doc "Serialize a value as compact JSON text, escaping \" \\ and control bytes."
        (returns STRING "JSON text")
        (example "(Json emit (list 1 \"a\\\"b\" 'null))" "\"[1,\\\"a\\\\\\\"b\\\",null]\""))
      (%json-emit v))))

(doc (provide x/codec/json Json)
  (note "parse: recursive descent over the tokens a Lexer reads, a piece of the text at a time; \\uXXXX decodes (surrogate pairs combined); raw UTF-8 passes through.")
  (note "emit: the escaping the app-side logo/json.x never had -- \" \\ and control bytes always escape.")
  (example "(Json emit (Json parse \"{\\\"k\\\":[1,2]}\"))" "\"{\\\"k\\\":[1,2]}\"")
  "Json: parse and emit JSON text (objects are Dicts, arrays are lists).")
