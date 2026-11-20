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
; Parsing is recursive descent over BYTES (the str-byte-* prims, handler-
; immune); each step returns (value . next-pos). Strings copy contiguous
; segments with one byte-sub per escape boundary, so escape-free strings are
; a single slice. \uXXXX decodes to a code point (surrogate pairs combined)
; and re-encodes as UTF-8; raw UTF-8 bytes pass through untouched both ways.
;
; Parsing leaves garbage behind every byte, and nothing collects it during
; one call, so parse collects as it goes: each string, number and word
; parsed adds its length to a debt, and the heap is collected when the debt
; passes %json-window bytes of text.  A text of any length then costs the
; values it answers and a window's garbage.
;
; Bytes and positions are machine integers, and the parser and the emitter
; compare and step them through the int doors: under the numeric tower the
; generic = < + and - dispatch on their operands' types, at a cost that a
; walk over every byte of a text pays for every byte.
;
; Emission escapes properly -- the gap that kept lib/x/logo/json.x app-only:
; " \ and control bytes come out as \" \\ \n \r \t \b \f or \u00XX.

(module x/codec/json)
(import x/type/class)
(import x/type/dict)
(import x/type/list)
(import x/num/float)
(import x/sys/gc)

; Fetch the byte-level string prims from the catalogue (ns `str` de-registered, R5).
(import x/core/doors char->int int* int+ int- int< int= io-display-to-str str-append str-byte-len str-byte-ref str-byte-sub)
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

(def %json-ws?
  (fn (_ b) (match
              ((int= b 32) #t)
              ((int= b 9) #t)
              ((int= b 10) #t)
              (#t (int= b 13)))))

(def %json-skip-ws
  (fn (self s i len)
    (if (int< i len)
      (if (%json-ws? (%json-byte s i)) (self s (int+ i 1) len) i)
      i)))

(def %json-err
  (fn (_ what i)
    (Err raise 'value (str-append "Json parse: " (str-append what
      (str-append " at byte " (%number->str i)))) ())))

; Expect the literal word w (true/false/null) at i; value already known.
(def %json-word
  (fn (_ s i len w v)
    (def n (str-byte-len w))
    (if (int< len (int+ i n)) (%json-err "truncated literal" i)
      (if (str=? (str-byte-sub s i n) w)
        (pair v (int+ i n))
        (%json-err "unknown literal" i)))))

; --- numbers ---------------------------------------------------------------
; Scan the number's extent, then classify: . / e / E anywhere makes it a
; float (built via the conversion catalogue -- runtime, no float literals here).
(def %json-num-byte?
  (fn (_ b)
    (match
      ((if (not (int< b 48)) (not (int< 57 b)) #f) #t)   ; 0-9
      ((int= b 45) #t) ((int= b 43) #t)        ; - +
      ((int= b 46) #t)                      ; .
      ((int= b 101) #t) ((int= b 69) #t)       ; e E
      (#t #f))))

(def %json-parse-number
  (fn (_ s i len)
    (def %end
      (let go ((j i))
        (if (int< j len) (if (%json-num-byte? (%json-byte s j)) (go (int+ j 1)) j) j)))
    (def %text (str-byte-sub s i (int- %end i)))
    (def %floaty
      (let go ((j i))
        (if (not (int< j %end)) #f
          (let ((b (%json-byte s j)))
            (match
              ((int= b 46) #t)
              ((int= b 101) #t)
              ((int= b 69) #t)
              (#t (go (int+ j 1))))))))
    ; JSON allows an exponent with no point (1e3); the float reader needs
    ; one, so an exponent with no point before it gets ".0" before its e.
    (def %epos
      (let go ((j i))
        (if (not (int< j %end)) ()
          (let ((b (%json-byte s j)))
            (match
              ((int= b 46) ())
              ((int= b 101) (int- j i))
              ((int= b 69) (int- j i))
              (#t (go (int+ j 1))))))))
    (def %read-text
      (if (null? %epos) %text
        (str-append (str-append (str-byte-sub %text 0 %epos) ".0")
          (str-byte-sub %text %epos (int- (int- %end i) %epos)))))
    ; %json-cvt, not the bits door (Float str->bits): that returns the raw IEEE bit
    ; pattern; the convert path boxes a real FLOAT value.
    (def %v (if %floaty (%json-cvt %read-text (eval (lit float) (module x/num/float))) (%str->number %text)))
    (if (null? %v) (%json-err "malformed number" i) (pair %v %end))))

; --- strings ---------------------------------------------------------------
(def %json-hexdig "0123456789abcdef")

; 4 hex digits at i -> integer (%str->number radix 16), error on short input.
(def %json-hex4
  (fn (_ s i len)
    (if (int< len (int+ i 4)) (%json-err "truncated \\u escape" i)
      (let ((v (%str->number (str-byte-sub s i 4) 16)))
        (if (null? v) (%json-err "malformed \\u escape" i) v)))))

; \uXXXX (with surrogate-pair combining) -> (utf8-string . next-pos)
(def %json-unicode
  (fn (_ s i len)
    (def hi (%json-hex4 s i len))
    (if (if (not (int< hi 55296)) (not (int< 56319 hi)) #f)          ; D800-DBFF: lead surrogate
      (if (if (int< len (int+ i 6)) #t
            (not (str=? (str-byte-sub s (int+ i 4) 2) (str-append %json-bs "u"))))
        (%json-err "lone lead surrogate" i)
        (let ((lo (%json-hex4 s (int+ i 6) len)))
          (if (if (not (int< lo 56320)) (not (int< 57343 lo)) #f)    ; DC00-DFFF: tail surrogate
            (pair (bytes->str (StrUtf8 encode
                    (int+ 65536 (int+ (int* 1024 (int- hi 55296)) (int- lo 56320)))))
                  (int+ i 10))
            (%json-err "lone lead surrogate" i))))
      (if (if (not (int< hi 56320)) (not (int< 57343 hi)) #f)
        (%json-err "lone tail surrogate" i)
        (pair (bytes->str (StrUtf8 encode hi)) (int+ i 4))))))

; One escape char after the backslash -> (string . next-pos)
(def %json-escape
  (fn (_ s i len)
    (if (not (int< i len)) (%json-err "truncated escape" i)
      (let ((b (%json-byte s i)))
        (match
          ((int= b 34) (pair %json-quote (int+ i 1)))
          ((int= b 92) (pair %json-bs (int+ i 1)))
          ((int= b 47) (pair "/" (int+ i 1)))
          ((int= b 110) (pair (bytes->str (list 10)) (int+ i 1)))   ; \n
          ((int= b 116) (pair (bytes->str (list 9)) (int+ i 1)))    ; \t
          ((int= b 114) (pair (bytes->str (list 13)) (int+ i 1)))   ; \r
          ((int= b 98) (pair (bytes->str (list 8)) (int+ i 1)))     ; \b
          ((int= b 102) (pair (bytes->str (list 12)) (int+ i 1)))   ; \f
          ((int= b 117) (%json-unicode s (int+ i 1) len))           ; \uXXXX
          (#t (%json-err "unknown escape" i)))))))

; String body after the opening quote. seg marks the start of the pending
; contiguous run; acc accumulates finished pieces -- escape-free strings
; finish as one byte-sub.
(def %json-parse-string
  (fn (self s i len seg acc)
    (if (not (int< i len)) (%json-err "unterminated string" i)
      (let ((b (%json-byte s i)))
        (match
          ((int= b 34)
            (pair (str-append acc (str-byte-sub s seg (int- i seg))) (int+ i 1)))
          ((int= b 92)
            (let ((esc (%json-escape s (int+ i 1) len)))
              (self s (rest esc) len (rest esc)
                (str-append acc
                  (str-append (str-byte-sub s seg (int- i seg)) (first esc))))))
          (#t (self s (int+ i 1) len seg acc)))))))

; --- values ----------------------------------------------------------------
(def %json-parse-value ())

; The bytes of text parsed between collections.
(def %json-window 8192)
(def %json-debt (pair 0 ()))
(def %json-owe!
  (fn (_ k)
    (let ((d (int+ (first %json-debt) k)))
      (if (int< d %json-window) (%set-first! %json-debt d)
        (do (%set-first! %json-debt 0) (Heap collect))))))

(def %json-parse-array
  (fn (self s i len acc)
    (def j (%json-skip-ws s i len))
    (if (not (int< j len)) (%json-err "unterminated array" j)
      (if (int= (%json-byte s j) 93)                              ; ]
        (pair (%reverse acc) (int+ j 1))
        (let ((v (%json-parse-value s j len)))
          (let ((k (%json-skip-ws s (rest v) len)))
            (if (not (int< k len)) (%json-err "unterminated array" k)
              (match
                ((int= (%json-byte s k) 44)                       ; ,
                  (self s (int+ k 1) len (pair (first v) acc)))
                ((int= (%json-byte s k) 93)                       ; ]
                  (pair (%reverse (pair (first v) acc)) (int+ k 1)))
                (#t (%json-err "expected , or ] in array" k))))))))))

(def %json-parse-object
  (fn (self s i len d)
    (def j (%json-skip-ws s i len))
    (match
      ((not (int< j len)) (%json-err "unterminated object" j))
      ((int= (%json-byte s j) 125)
        ; }
        (pair d (int+ j 1)))
      ((not (int= (%json-byte s j) 34)) (%json-err "expected a string key" j))
      (#t
        (let ((key (%json-parse-string s (int+ j 1) len (int+ j 1) "")))
          (%json-owe! (int- (rest key) j))
          (let ((c (%json-skip-ws s (rest key) len)))
            (if (if (not (int< c len)) #t (not (int= (%json-byte s c) 58)))   ; :
              (%json-err "expected : after key" c)
              (let ((v (%json-parse-value s (int+ c 1) len)))
                (do (d set! (first key) (first v))
                    (let ((k (%json-skip-ws s (rest v) len)))
                      (if (not (int< k len)) (%json-err "unterminated object" k)
                        (match
                          ((int= (%json-byte s k) 44) (self s (int+ k 1) len d))
                          ((int= (%json-byte s k) 125) (pair d (int+ k 1)))
                          (#t (%json-err "expected , or } in object" k))))))))))))))

(set! %json-parse-value
  (fn (_ s i len)
    (def j (%json-skip-ws s i len))
    (if (not (int< j len)) (%json-err "unexpected end of input" j)
      (let ((b (%json-byte s j)))
        (match
          ((int= b 123) (%json-parse-object s (int+ j 1) len (Dict make)))
          ((int= b 91) (%json-parse-array s (int+ j 1) len ()))
          (#t
            ; a string, a number or a word: its length is owed once it is parsed
            (let ((v (match
                       ((int= b 34) (%json-parse-string s (int+ j 1) len (int+ j 1) ""))
                       ((int= b 116) (%json-word s j len "true" #t))
                       ((int= b 102) (%json-word s j len "false" #f))
                       ((int= b 110) (%json-word s j len "null" 'null))
                       ((int= b 45) (%json-parse-number s j len))
                       ((if (not (int< b 48)) (not (int< 57 b)) #f) (%json-parse-number s j len))
                       (#t (%json-err "unexpected byte" j)))))
              (%json-owe! (int- (rest v) j))
              v)))))))

; --- emission ---------------------------------------------------------------
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
      (def len (str-byte-len s))
      (def v (%json-parse-value s 0 len))
      (if (int< (%json-skip-ws s (rest v) len) len)
        (%json-err "trailing content" (rest v))
        (first v)))
    (method emit (self (param v ANY "Value to serialize"))
      (doc "Serialize a value as compact JSON text, escaping \" \\ and control bytes."
        (returns STRING "JSON text")
        (example "(Json emit (list 1 \"a\\\"b\" 'null))" "\"[1,\\\"a\\\\\\\"b\\\",null]\""))
      (%json-emit v))))

(doc (provide x/codec/json Json)
  (note "parse: recursive descent over bytes; \\uXXXX decodes (surrogate pairs combined); raw UTF-8 passes through.")
  (note "emit: the escaping the app-side logo/json.x never had -- \" \\ and control bytes always escape.")
  (example "(Json emit (Json parse \"{\\\"k\\\":[1,2]}\"))" "\"{\\\"k\\\":[1,2]}\"")
  "Json: parse and emit JSON text (objects are Dicts, arrays are lists).")
