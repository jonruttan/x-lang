; fmt.x -- Fmt: comment-preserving s-expression formatter.
;
; Data-driven pretty printer for x-lang s-expressions. The formatting logic
; lives in %-private functions -- the three core printers (%fmt-expr / %fmt-list
; / %fmt-body) are mutually recursive via forward-decl + set!, so they call each
; other directly (no per-node class dispatch). The Fmt class is the API.
(import x/type/str)
(import x/type/object)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))
; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))

; --- Construct table helpers ---

(def %fmt-build-lookup (fn (self entries acc)
  (if (null? entries) acc
    (let ((entry (first entries)))
        (self (rest entries)
          (pair (pair (first entry) (rest entry)) acc))))))

(def %fmt-build-table (fn (_ constructs)
  (%fmt-build-lookup constructs ())))

(def %fmt-find (fn (self key table)
  (unless (null? table)
    (if (str=? (%cvt key %string)
                  (%cvt (first (first table)) %string))
      (first table)
      (self key (rest table))))))

(def %fmt-lookup (fn (_ name table)
  (def entry (%fmt-find name table))
  (unless (null? entry) (rest entry))))

(def %fmt-get-prop (fn (self key props)
  (unless (null? props)
    (if (pair? (first props))
      (if (eq? (first (first props)) key)
        (rest (first props))
        (self key (rest props)))
      (self key (rest props))))))

; --- Predicates ---

(def %fmt-comment? (fn (_ tok)
  (when (pair? tok) (eq? (first tok) '%comment))))

; --- Width estimation ---

; Column math counts CODE POINTS via the bare (s) call -- str-length is
; BYTES and misaligns any non-ASCII source. True display columns
; (double-width CJK, zero-width combining marks) need a wcwidth-style
; table: known gap (#44 N3); code points are correct for everything else.
(def %fmt-cp-len (fn (_ s) (s)))

(def %fmt-width (fn (_ form)
  (if (%fmt-comment? form) 80
    (%fmt-cp-len (%write-to-str form)))))

; --- Pretty printer ---

(def %spaces (fn (_ n) (display (Str repeat n " "))))

; Forward declarations (mutually recursive)
(def %fmt-expr ())
(def %fmt-list ())
(def %fmt-body ())

(set! %fmt-body (fn (_ forms col)
  (unless (null? forms)
    (if (not (pair? forms))
      (do (display "\n") (%spaces col)
          (display ". ") (%fmt-expr forms col))
      (do (display "\n") (%spaces col)
          (%fmt-expr (first forms) col)
          (%fmt-body (rest forms) col))))))

; Layout strategies
(def %fmt-head-1 (fn (_ head rest-forms col)
  (if (null? rest-forms) (write (pair head rest-forms))
    (let ((head-width (+ 2 (%fmt-cp-len (%cvt head %string)))))
        (display "(") (write head) (display " ")
        (%fmt-expr (first rest-forms) (+ col head-width))
        (%fmt-body (rest rest-forms) (+ col 2))
        (display ")")))))

(def %fmt-head-kw (fn (_ head rest-forms col)
  (let ((head-width (+ 2 (%fmt-cp-len (%cvt head %string)))))
      (display "(") (write head) (display " ")
      (%fmt-expr (first rest-forms) (+ col head-width))
      (%fmt-body (rest rest-forms) (+ col 2))
      (display ")"))))

(def %fmt-body-only (fn (_ head rest-forms col)
  (do (display "(") (write head)
      (%fmt-body rest-forms (+ col 2))
      (display ")"))))

(def %fmt-default (fn (_ head rest-forms col)
  (do (display "(")
      (%fmt-expr head (+ col 1))
      (%fmt-body rest-forms (+ col 2))
      (display ")"))))

(set! %fmt-list (fn (_ form col table)
  (def head (first form))
  (def rest-forms (rest form))
  (if (< (%fmt-width form) 60)
    (write form)
    (let ((props (when (symbol? head) (%fmt-lookup head table))))
      (let ((fmt-type (unless (null? props) (%fmt-get-prop 'fmt props))))
        (if (eq? fmt-type 'head-1)  (%fmt-head-1 head rest-forms col)
        (if (eq? fmt-type 'head-kw) (%fmt-head-kw head rest-forms col)
        (if (eq? fmt-type 'body)    (%fmt-body-only head rest-forms col)
          (%fmt-default head rest-forms col)))))))))

(set! %fmt-expr (fn (_ form col)
  (if (%fmt-comment? form)
    (display (first (rest form)))
    (if (pair? form) (%fmt-list form col ())
      (write form)))))

(def %fmt-tokens (fn (_ tokens table)
  (def %go (fn (self toks first-token)
    (unless (null? toks)
      (let ((tok (first toks)))
          (unless first-token
            (unless (%fmt-comment? tok)
              (display "\n")))
          (if (pair? tok) (%fmt-list tok 0 table) (%fmt-expr tok 0))
          (unless (%fmt-comment? tok)
            (display "\n"))
          (self (rest toks) ())))))
  (%go tokens #t)))

; --- The Fmt class: the API ---
(def-class Fmt ()
  (doc "Comment-preserving, data-driven pretty printer for x-lang s-expressions."
    (note "Build a formatter table from construct declarations with (Fmt build-table ...), then (Fmt tokens toks table) prints them. A form under 60 chars wide prints as-is; wider ones indent per the table's `fmt` property (head-1 / head-kw / body / default).")
    (example "(Fmt width (list 10 20))" "7"))
  (static
    (method build-table (self (param constructs LIST "Construct declarations (from XEON)"))
      (doc "Build a formatter lookup table from construct declarations."
        (returns ALIST "Lookup table mapping names to property lists"))
      (%fmt-build-table constructs))

    (method lookup (self (param name SYMBOL "Form name to look up")
                         (param table ALIST "Table from (Fmt build-table)"))
      (doc "Look up formatting properties for a construct name."
        (returns LIST "Property list, or nil"))
      (%fmt-lookup name table))

    (method get-prop (self (param key SYMBOL "Property key")
                           (param props LIST "Property list from (Fmt lookup)"))
      (doc "Get a specific property from a construct property list."
        (returns ANY "Property value, or nil"))
      (%fmt-get-prop key props))

    (method comment? (self (param tok ANY "Token to test"))
      (doc "Test whether a token is a comment token."
        (returns BOOL "True if tok is a (%comment ...) token"))
      (%fmt-comment? tok))

    (method width (self (param form ANY "Form to measure"))
      (doc "Estimate the display width of a form in CODE POINTS (via write-to-str; a comment counts as 80). Code points approximate display columns except for double-width/combining glyphs (wcwidth is a known gap)."
        (returns INT "Estimated width in code points"))
      (%fmt-width form))

    (method expr (self (param form ANY "Expression to format")
                       (param col INT "Current indentation column"))
      (doc "Format any expression, writing the result to output."
        (returns ANY "nil (output via display)"))
      (%fmt-expr form col))

    (method list (self (param form LIST "List form to format")
                       (param col INT "Current indentation column")
                       (param table ALIST "Formatter table"))
      (doc "Format a list form with indentation-aware pretty printing, writing the result."
        (returns ANY "nil (output via display)"))
      (%fmt-list form col table))

    (method body (self (param forms LIST "Body forms")
                       (param col INT "Current indentation column"))
      (doc "Format a sequence of body forms, one per line, writing the result."
        (returns ANY "nil (output via display)"))
      (%fmt-body forms col))

    (method tokens (self (param tokens LIST "Token list from the tokenizer")
                         (param table ALIST "Formatter table from (Fmt build-table)"))
      (doc "Format a list of top-level tokens with the given construct table, writing the result."
        (returns ANY "nil (output via display)"))
      (%fmt-tokens tokens table))))

(doc (provide x/tool/fmt Fmt)
  (note "Formatting logic is %-private (the mutually-recursive printers call each other directly); the Fmt class is the API.")
  "Comment-preserving s-expression formatter on the Fmt class.")
