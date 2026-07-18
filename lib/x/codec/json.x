; codec/json.x -- Json: parse and emit JSON text.
;
; The value mapping (both directions):
;   object <-> Dict (string keys -- the reason this codec waited for x/type/dict)
;   array  <-> list          string <-> string      true/false <-> #t/#f
;   null   <-> the symbol `null` (nil would collide with the empty array)
;   number <-> integer, or FLOAT when the text carries . / e (built at runtime
;              via (Float from-str) -- this SOURCE file stays float-literal-free
;              so it loads under plain x-core)
;
; Parsing is recursive descent over BYTES (the str-byte-* prims, handler-
; immune); each step returns (value . next-pos). Strings copy contiguous
; segments with one byte-sub per escape boundary, so escape-free strings are
; a single slice. \uXXXX decodes to a code point (surrogate pairs combined)
; and re-encodes as UTF-8; raw UTF-8 bytes pass through untouched both ways.
;
; Emission escapes properly -- the gap that kept lib/x/logo/json.x app-only:
; " \ and control bytes come out as \" \\ \n \r \t \b \f or \u00XX.

(import x/type/object)
(import x/type/dict)
(import x/type/list)
(import x/num/float)

; Fetch the byte-level string prims from the catalog (ns `str` de-registered, R5).
(def %json-byte-len (prim-ref (lit str) (lit byte-len)))
(def %json-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %json-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def %json-append (prim-ref (lit str) (lit append)))
; display-to-str renders any number the way the printer would (int/bignum/float).
(def %json-display (prim-ref (lit io) (lit display-to-str)))
; The conversion dispatcher: (%json-cvt "2.5" %float) parses AND boxes a float
; via the float type's from-alist (%float is the documented convert type
; handle, bound when x/num/float loads above).
(def %json-cvt (prim-ref (lit convert) (lit to)))
; char->int for byte values of CHARACTERs coming from str-byte-ref callers.
(def %json-char->int (prim-ref (lit char) (lit ->int)))

(def %json-bs (%json-byte-sub "\\x" 0 1))   ; a one-byte backslash string
(def %json-quote (%json-byte-sub "\"x" 0 1)) ; a one-byte double-quote string

; str-byte-ref returns a CHARACTER; the parser wants byte INTs.
(def %json-byte (fn (_ s i) (%json-char->int (%json-byte-ref s i))))

(def %json-ws?
  (fn (_ b) (if (= b 32) #t (if (= b 9) #t (if (= b 10) #t (= b 13))))))

(def %json-skip-ws
  (fn (self s i len)
    (if (< i len)
      (if (%json-ws? (%json-byte s i)) (self s (+ i 1) len) i)
      i)))

(def %json-err
  (fn (_ what i)
    (error (%json-append "Json parse: " (%json-append what
      (%json-append " at byte " (number->str i)))))))

; Expect the literal word w (true/false/null) at i; value already known.
(def %json-word
  (fn (_ s i len w v)
    (def n (%json-byte-len w))
    (if (> (+ i n) len) (%json-err "truncated literal" i)
      (if (str=? (%json-byte-sub s i n) w)
        (pair v (+ i n))
        (%json-err "unknown literal" i)))))

; --- numbers ---------------------------------------------------------------
; Scan the number's extent, then classify: . / e / E anywhere makes it a
; float (built via Float from-str -- runtime, no float literals here).
(def %json-num-byte?
  (fn (_ b)
    (match
      ((if (>= b 48) (<= b 57) #f) #t)   ; 0-9
      ((= b 45) #t) ((= b 43) #t)        ; - +
      ((= b 46) #t)                      ; .
      ((= b 101) #t) ((= b 69) #t)       ; e E
      (#t #f))))

(def %json-parse-number
  (fn (_ s i len)
    (def %end
      (let go ((j i))
        (if (< j len) (if (%json-num-byte? (%json-byte s j)) (go (+ j 1)) j) j)))
    (def %text (%json-byte-sub s i (- %end i)))
    (def %floaty
      (let go ((j i))
        (if (>= j %end) #f
          (let ((b (%json-byte s j)))
            (if (= b 46) #t (if (= b 101) #t (if (= b 69) #t (go (+ j 1)))))))))
    ; %json-cvt, not (Float from-str): from-str returns the raw IEEE bit
    ; pattern; the convert path boxes a real FLOAT value.
    (def %v (if %floaty (%json-cvt %text %float) (str->number %text)))
    (if (null? %v) (%json-err "malformed number" i) (pair %v %end))))

; --- strings ---------------------------------------------------------------
(def %json-hexdig "0123456789abcdef")

; 4 hex digits at i -> integer (str->number radix 16), error on short input.
(def %json-hex4
  (fn (_ s i len)
    (if (> (+ i 4) len) (%json-err "truncated \\u escape" i)
      (let ((v (str->number (%json-byte-sub s i 4) 16)))
        (if (null? v) (%json-err "malformed \\u escape" i) v)))))

; \uXXXX (with surrogate-pair combining) -> (utf8-string . next-pos)
(def %json-unicode
  (fn (_ s i len)
    (def hi (%json-hex4 s i len))
    (if (if (>= hi 55296) (<= hi 56319) #f)          ; D800-DBFF: lead surrogate
      (if (if (> (+ i 6) len) #t
            (not (str=? (%json-byte-sub s (+ i 4) 2) (%json-append %json-bs "u"))))
        (%json-err "lone lead surrogate" i)
        (let ((lo (%json-hex4 s (+ i 6) len)))
          (if (if (>= lo 56320) (<= lo 57343) #f)    ; DC00-DFFF: tail surrogate
            (pair (bytes->str (StrUTF8 encode
                    (+ 65536 (+ (* 1024 (- hi 55296)) (- lo 56320)))))
                  (+ i 10))
            (%json-err "lone lead surrogate" i))))
      (if (if (>= hi 56320) (<= hi 57343) #f)
        (%json-err "lone tail surrogate" i)
        (pair (bytes->str (StrUTF8 encode hi)) (+ i 4))))))

; One escape char after the backslash -> (string . next-pos)
(def %json-escape
  (fn (_ s i len)
    (if (>= i len) (%json-err "truncated escape" i)
      (let ((b (%json-byte s i)))
        (match
          ((= b 34) (pair %json-quote (+ i 1)))
          ((= b 92) (pair %json-bs (+ i 1)))
          ((= b 47) (pair "/" (+ i 1)))
          ((= b 110) (pair (bytes->str (list 10)) (+ i 1)))   ; \n
          ((= b 116) (pair (bytes->str (list 9)) (+ i 1)))    ; \t
          ((= b 114) (pair (bytes->str (list 13)) (+ i 1)))   ; \r
          ((= b 98) (pair (bytes->str (list 8)) (+ i 1)))     ; \b
          ((= b 102) (pair (bytes->str (list 12)) (+ i 1)))   ; \f
          ((= b 117) (%json-unicode s (+ i 1) len))           ; \uXXXX
          (#t (%json-err "unknown escape" i)))))))

; String body after the opening quote. seg marks the start of the pending
; contiguous run; acc accumulates finished pieces -- escape-free strings
; finish as one byte-sub.
(def %json-parse-string
  (fn (self s i len seg acc)
    (if (>= i len) (%json-err "unterminated string" i)
      (let ((b (%json-byte s i)))
        (match
          ((= b 34)
            (pair (%json-append acc (%json-byte-sub s seg (- i seg))) (+ i 1)))
          ((= b 92)
            (let ((esc (%json-escape s (+ i 1) len)))
              (self s (rest esc) len (rest esc)
                (%json-append acc
                  (%json-append (%json-byte-sub s seg (- i seg)) (first esc))))))
          (#t (self s (+ i 1) len seg acc)))))))

; --- values ----------------------------------------------------------------
(def %json-parse-value ())

(def %json-parse-array
  (fn (self s i len acc)
    (def j (%json-skip-ws s i len))
    (if (>= j len) (%json-err "unterminated array" j)
      (if (= (%json-byte s j) 93)                              ; ]
        (pair (reverse acc) (+ j 1))
        (let ((v (%json-parse-value s j len)))
          (let ((k (%json-skip-ws s (rest v) len)))
            (if (>= k len) (%json-err "unterminated array" k)
              (match
                ((= (%json-byte s k) 44)                       ; ,
                  (self s (+ k 1) len (pair (first v) acc)))
                ((= (%json-byte s k) 93)                       ; ]
                  (pair (reverse (pair (first v) acc)) (+ k 1)))
                (#t (%json-err "expected , or ] in array" k))))))))))

(def %json-parse-object
  (fn (self s i len d)
    (def j (%json-skip-ws s i len))
    (if (>= j len) (%json-err "unterminated object" j)
      (if (= (%json-byte s j) 125)                             ; }
        (pair d (+ j 1))
        (if (not (= (%json-byte s j) 34))
          (%json-err "expected a string key" j)
          (let ((key (%json-parse-string s (+ j 1) len (+ j 1) "")))
            (let ((c (%json-skip-ws s (rest key) len)))
              (if (if (>= c len) #t (not (= (%json-byte s c) 58)))   ; :
                (%json-err "expected : after key" c)
                (let ((v (%json-parse-value s (+ c 1) len)))
                  (do (d put! (first key) (first v))
                      (let ((k (%json-skip-ws s (rest v) len)))
                        (if (>= k len) (%json-err "unterminated object" k)
                          (match
                            ((= (%json-byte s k) 44) (self s (+ k 1) len d))
                            ((= (%json-byte s k) 125) (pair d (+ k 1)))
                            (#t (%json-err "expected , or } in object" k)))))))))))))))

(set! %json-parse-value
  (fn (_ s i len)
    (def j (%json-skip-ws s i len))
    (if (>= j len) (%json-err "unexpected end of input" j)
      (let ((b (%json-byte s j)))
        (match
          ((= b 34) (%json-parse-string s (+ j 1) len (+ j 1) ""))
          ((= b 123) (%json-parse-object s (+ j 1) len (Dict make)))
          ((= b 91) (%json-parse-array s (+ j 1) len ()))
          ((= b 116) (%json-word s j len "true" #t))
          ((= b 102) (%json-word s j len "false" #f))
          ((= b 110) (%json-word s j len "null" (lit null)))
          ((= b 45) (%json-parse-number s j len))
          ((if (>= b 48) (<= b 57) #f) (%json-parse-number s j len))
          (#t (%json-err "unexpected byte" j)))))))

; --- emission ---------------------------------------------------------------
(def %json-hex1 (fn (_ n) (%json-byte-sub %json-hexdig (& n 15) 1)))

; Escape one control byte as \u00XX (the shortcut escapes are handled inline).
(def %json-ctl
  (fn (_ b)
    (%json-append %json-bs
      (%json-append "u00" (%json-append (%json-hex1 (>> b 4)) (%json-hex1 b))))))

(def %json-emit-string
  (fn (_ s)
    (def len (%json-byte-len s))
    (def %esc
      (fn (_ b)
        (match
          ((= b 34) (%json-append %json-bs %json-quote))
          ((= b 92) (%json-append %json-bs %json-bs))
          ((= b 10) (%json-append %json-bs "n"))
          ((= b 9) (%json-append %json-bs "t"))
          ((= b 13) (%json-append %json-bs "r"))
          ((= b 8) (%json-append %json-bs "b"))
          ((= b 12) (%json-append %json-bs "f"))
          (#t (%json-ctl b)))))
    (def %needs?
      (fn (_ b) (if (= b 34) #t (if (= b 92) #t (< b 32)))))
    (let go ((i 0) (seg 0) (acc %json-quote))
      (if (>= i len)
        (%json-append acc
          (%json-append (%json-byte-sub s seg (- i seg)) %json-quote))
        (let ((b (%json-byte s i)))
          (if (%needs? b)
            (go (+ i 1) (+ i 1)
                (%json-append acc
                  (%json-append (%json-byte-sub s seg (- i seg)) (%esc b))))
            (go (+ i 1) seg acc)))))))

(def %json-emit ())

(def %json-emit-array
  (fn (_ lst)
    (let go ((xs lst) (acc "[") (sep ""))
      (if (null? xs) (%json-append acc "]")
        (go (rest xs)
            (%json-append acc (%json-append sep (%json-emit (first xs))))
            ",")))))

(def %json-emit-object
  (fn (_ d)
    (let go ((es (d ->alist)) (acc "{") (sep ""))
      (if (null? es) (%json-append acc "}")
        (let ((k (first (first es))))
          (let ((ks (match
                      ((str? k) k)
                      ((symbol? k) (symbol->str k))
                      (#t (error "Json emit: object keys must be strings or symbols")))))
            (go (rest es)
                (%json-append acc
                  (%json-append sep
                    (%json-append (%json-emit-string ks)
                      (%json-append ":" (%json-emit (rest (first es)))))))
                ",")))))))

(set! %json-emit
  (fn (_ v)
    (match
      ((eq? v #t) "true")
      ((eq? v #f) "false")
      ((null? v) "[]")
      ((str? v) (%json-emit-string v))
      ((number? v) (%json-display v))
      ((symbol? v)
        (if (str=? (symbol->str v) "null") "null"
          (%json-emit-string (symbol->str v))))
      ((pair? v) (%json-emit-array v))
      ((Dict dict? v) (%json-emit-object v))
      ; tower instances are not number?-true; dispatch the rest by type name
      (#t (let ((tn (Type name v)))
            (match
              ((str=? tn "FLOAT") (%json-display v))
              ((str=? tn "BIGNUM") (%json-display v))
              ((str=? tn "RATIONAL") (error "Json emit: no JSON form for a rational (convert to a float first)"))
              ((str=? tn "COMPLEX") (error "Json emit: no JSON form for a complex number"))
              (#t (error "Json emit: unsupported value type"))))))))

(def-class Json ()
  (doc "JSON text codec: parse to Dict/list/string/number/#t/#f/null values, emit with proper escaping."
    (note "Objects are Dicts (string keys); arrays are lists; null is the SYMBOL null (nil would collide with []).")
    (note "Decimal and exponent numbers parse as floats (via Float from-str); plain digit runs parse as integers.")
    (example "((Json parse \"{\\\"a\\\": [1, true]}\") get \"a\")" "(1 #t)")
    (see parse) (see emit))
  (static
    (method parse (self (param s STRING "JSON text"))
      (doc "Parse JSON text into x-lang values; malformed input errors with a byte position."
        (returns ANY "Dict / list / string / number / #t / #f / (lit null)")
        (example "(Json parse \"[1, 2.5, null]\")" "the list (1 2.5 null)"))
      (def len (%json-byte-len s))
      (def v (%json-parse-value s 0 len))
      (if (< (%json-skip-ws s (rest v) len) len)
        (%json-err "trailing content" (rest v))
        (first v)))
    (method emit (self (param v ANY "Value to serialize"))
      (doc "Serialize a value as compact JSON text, escaping \" \\ and control bytes."
        (returns STRING "JSON text")
        (example "(Json emit (list 1 \"a\\\"b\" (lit null)))" "\"[1,\\\"a\\\\\\\"b\\\",null]\""))
      (%json-emit v))))

(doc (provide x/codec/json Json)
  (note "parse: recursive descent over bytes; \\uXXXX decodes (surrogate pairs combined); raw UTF-8 passes through.")
  (note "emit: the escaping the app-side logo/json.x never had -- \" \\ and control bytes always escape.")
  (example "(Json emit (Json parse \"{\\\"k\\\":[1,2]}\"))" "\"{\\\"k\\\":[1,2]}\"")
  "Json: parse and emit JSON text (objects are Dicts, arrays are lists).")
