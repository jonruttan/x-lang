; fmt.x -- Comment-preserving formatter library
;
; Data-driven pretty printer for x-lang s-expressions.
; Uses write-to-str for width estimation (C speed).
(import x/type/string)

; --- Construct table helpers ---

(def %fmt-build-lookup (fn (_ entries acc)
  (if (null? entries) acc
    (do (def entry (first entries))
        (%fmt-build-lookup (rest entries)
          (pair (pair (first entry) (rest entry)) acc))))))

(doc (def fmt-build-table (fn (_ constructs)
  (%fmt-build-lookup constructs ())))
  (param constructs LIST "Construct declarations from XEON")
  (returns ALIST "Lookup table mapping names to property lists")
  "Build a formatter lookup table from construct declarations.")

(def %fmt-find (fn (_ key table)
  (if (null? table) ()
    (if (str=? (convert key %string)
                  (convert (first (first table)) %string))
      (first table)
      (%fmt-find key (rest table))))))

(doc (def fmt-lookup (fn (_ name table)
  (def entry (%fmt-find name table))
  (if (null? entry) () (rest entry))))
  (param name SYMBOL "Form name to look up")
  (param table ALIST "Formatter table from fmt-build-table")
  (returns LIST "Property list or nil")
  "Look up formatting properties for a construct name.")

(doc (def fmt-get-prop (fn (_ key props)
  (if (null? props) ()
    (if (pair? (first props))
      (if (eq? (first (first props)) key)
        (rest (first props))
        (fmt-get-prop key (rest props)))
      (fmt-get-prop key (rest props))))))
  (param key SYMBOL "Property key to find")
  (param props LIST "Property list from fmt-lookup")
  (returns ANY "Property value or nil")
  "Get a specific property from a construct property list.")

; --- Predicates ---

(doc (def fmt-comment? (fn (_ tok)
  (if (pair? tok) (eq? (first tok) (lit %comment)) ())))
  (param tok ANY "Token to test")
  (returns BOOLEAN "True if tok is a comment token")
  "Test whether a token is a comment.")

; --- Width estimation ---

(doc (def fmt-width (fn (_ form)
  (if (fmt-comment? form) 80
    (str-length (write-to-str form)))))
  (param form ANY "Form to measure")
  (returns INTEGER "Estimated display width in characters")
  "Estimate the display width of a form using write-to-str.")

; --- Pretty printer ---

(def %spaces (fn (_ n) (display (str-repeat " " n))))

; Forward declarations
(def fmt-expr ())
(def fmt-list ())
(def fmt-body ())

(set! fmt-body (fn (_ forms col)
  (if (null? forms) ()
    (if (not (pair? forms))
      (do (display "\n") (%spaces col)
          (display ". ") (fmt-expr forms col))
      (do (display "\n") (%spaces col)
          (fmt-expr (first forms) col)
          (fmt-body (rest forms) col))))))

; Layout strategies
(def %fmt-head-1 (fn (_ head rest-forms col)
  (if (null? rest-forms) (write (pair head rest-forms))
    (do (display "(") (write head) (display " ")
        (def head-width (+ 2 (str-length (convert head %string))))
        (fmt-expr (first rest-forms) (+ col head-width))
        (fmt-body (rest rest-forms) (+ col 2))
        (display ")")))))

(def %fmt-head-kw (fn (_ head rest-forms col)
  (do (display "(") (write head) (display " ")
      (def head-width (+ 2 (str-length (convert head %string))))
      (fmt-expr (first rest-forms) (+ col head-width))
      (fmt-body (rest rest-forms) (+ col 2))
      (display ")"))))

(def %fmt-body-only (fn (_ head rest-forms col)
  (do (display "(") (write head)
      (fmt-body rest-forms (+ col 2))
      (display ")"))))

(def %fmt-default (fn (_ head rest-forms col)
  (do (display "(")
      (fmt-expr head (+ col 1))
      (fmt-body rest-forms (+ col 2))
      (display ")"))))

(doc (set! fmt-list (fn (_ form col table)
  (def head (first form))
  (def rest-forms (rest form))
  (if (< (fmt-width form) 60)
    (write form)
    (do (def props (if (symbol? head) (fmt-lookup head table) ()))
        (def fmt-type (if (null? props) () (fmt-get-prop (lit fmt) props)))
        (if (eq? fmt-type (lit head-1))  (%fmt-head-1 head rest-forms col)
        (if (eq? fmt-type (lit head-kw)) (%fmt-head-kw head rest-forms col)
        (if (eq? fmt-type (lit body))    (%fmt-body-only head rest-forms col)
          (%fmt-default head rest-forms col))))))))
  (param form LIST "List form to format")
  (param col INTEGER "Current indentation column")
  (param table ALIST "Formatter table")
  "Format a list form with indentation-aware pretty printing.")

(doc (set! fmt-expr (fn (_ form col)
  (if (fmt-comment? form)
    (display (first (rest form)))
    (if (pair? form) (fmt-list form col ())
      (write form)))))
  (param form ANY "Expression to format")
  (param col INTEGER "Current indentation column")
  "Format any expression.")

(doc (def fmt-tokens (fn (_ tokens table)
  (def %go (fn (_ toks first-token)
    (if (null? toks) ()
      (do (def tok (first toks))
          (if first-token ()
            (if (fmt-comment? tok) ()
              (display "\n")))
          ; Rebind fmt-list to use the table
          (if (pair? tok) (fmt-list tok 0 table) (fmt-expr tok 0))
          (if (fmt-comment? tok) ()
            (display "\n"))
          (%go (rest toks) ())))))
  (%go tokens t)))
  (param tokens LIST "Token list from token-read-string")
  (param table ALIST "Formatter table from fmt-build-table")
  "Format a list of top-level tokens with the given construct table.")

(doc (provide x/tool/fmt
  fmt-build-table fmt-lookup fmt-get-prop fmt-comment? fmt-width
  fmt-expr fmt-list fmt-body fmt-tokens)
  "Comment-preserving s-expression formatter.")
