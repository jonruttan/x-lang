; fmt.x -- x-lang comment-preserving formatter
;
; Data-driven: reads construct declarations from a XEON file
; (piped before the target source) to know how to format each form.
; No hardcoded form names -- each language ships its own declarations.
;
; Uses write-to-string for width estimation and write for single-line
; output -- both are C primitives that traverse trees at C speed.
;
; Input order on stdin: constructs.x, then quoted source string.

(do
  ; --- Load construct declarations ---
  ; First form on stdin is the base constructs list.
  ; Optional second form is language-specific extensions.

  (def %constructs (read))
  (def %lang-constructs (read))
  (def %all-constructs
    (if (null? %lang-constructs) %constructs
      (append %constructs %lang-constructs)))

  ; Build lookup alist: ((name . props) ...)
  (def %build-lookup (fn (entries acc)
    (if (null? entries) acc
      (do (def entry (first entries))
          (def name (first entry))
          (def props (rest entry))
          (%build-lookup (rest entries)
            (pair (pair name props) acc))))))
  (def %fmt-table (%build-lookup %all-constructs ()))

  ; Lookup helper: returns property list or () for unknown forms
  (def %fmt-find (fn (key table)
    (if (null? table) ()
      (if (string=? (convert key %string)
                    (convert (first (first table)) %string))
        (first table)
        (%fmt-find key (rest table))))))
  (def %fmt-lookup (fn (name)
    (def entry (%fmt-find name %fmt-table))
    (if (null? entry) ()
      (rest entry))))

  ; Get a specific property from a property list
  (def %get-prop (fn (key props)
    (if (null? props) ()
      (if (pair? (first props))
        (if (eq? (first (first props)) key)
          (rest (first props))
          (%get-prop key (rest props)))
        (%get-prop key (rest props))))))

  ; --- Create formatter base, patch COMMENT to keep tokens ---

  (def %fmt-base (make-base))

  ; Reader that keeps the comment text as a token
  (def %fmt-comment-reader (fn args
    (list (lit %comment) (buffer-token (first args)))))

  ; Navigate type struct: entry = (handle . type-struct)
  ; type-struct has 7 elements, io is the 7th
  (def %entry-io (fn (entry)
    (first (rest (rest (rest (rest (rest (rest entry)))))))))

  ; Find COMMENT entry: first with (analyse + delimit + no read + no write)
  (def %find-comment (fn (alist)
    (if (null? alist) ()
      (do (def io (%entry-io (first alist)))
          (if (and (not (null? (first (first io))))
                   (not (null? (first (first (rest io)))))
                   (null? (first (first (rest (rest io))))))
            (first alist)
            (%find-comment (rest alist)))))))

  ; Push keeping reader onto COMMENT's read stack
  (def %comment-entry (%find-comment (first (first (first %fmt-base)))))
  (def %comment-io (%entry-io %comment-entry))
  (def %comment-read-stack (first (rest (rest %comment-io))))
  (set-first! %comment-read-stack %fmt-comment-reader)

  ; --- Read input string (next form on stdin) and tokenize ---

  (def %input (read))
  (def %tokens (token-read-string %fmt-base %input))

  ; --- Predicates ---

  (def %comment? (fn (tok)
    (if (pair? tok) (eq? (first tok) (lit %comment)) ())))

  ; --- Width: use write-to-string (C speed tree traversal) ---

  (def %form-width (fn (form)
    (if (%comment? form) 80
      (string-length (write-to-string form)))))

  ; --- Pretty printer ---

  (def %spaces (fn (n) (display (string-repeat " " n))))

  ; Forward declarations
  (def %fmt-expr ())
  (def %fmt-list ())
  (def %fmt-body ())

  ; Format a sequence of body forms, each on its own line
  ; Handles improper lists (dotted pairs) by printing ". tail"
  (set! %fmt-body (fn (forms col)
    (if (null? forms) ()
      (if (not (pair? forms))
        (do (display "\n") (%spaces col)
            (display ". ") (%fmt-expr forms col))
        (do (display "\n") (%spaces col)
            (%fmt-expr (first forms) col)
            (%fmt-body (rest forms) col))))))

  ; --- Data-driven formatting ---
  ; Dispatches on the fmt property from the construct table.

  (def %fmt-head-1 (fn (head rest-forms col)
    (if (null? rest-forms) (write (pair head rest-forms))
      (do (display "(") (write head) (display " ")
          (def head-width (+ 2 (string-length (convert head %string))))
          (%fmt-expr (first rest-forms) (+ col head-width))
          (%fmt-body (rest rest-forms) (+ col 2))
          (display ")")))))

  (def %fmt-head-kw (fn (head rest-forms col)
    (do (display "(") (write head) (display " ")
        (def head-width (+ 2 (string-length (convert head %string))))
        (%fmt-expr (first rest-forms) (+ col head-width))
        (%fmt-body (rest rest-forms) (+ col 2))
        (display ")"))))

  (def %fmt-body-only (fn (head rest-forms col)
    (do (display "(") (write head)
        (%fmt-body rest-forms (+ col 2))
        (display ")"))))

  (def %fmt-default (fn (head rest-forms col)
    (do (display "(")
        (%fmt-expr head (+ col 1))
        (%fmt-body rest-forms (+ col 2))
        (display ")"))))

  ; Format a list form with indentation awareness
  (set! %fmt-list (fn (form col)
    (def head (first form))
    (def rest-forms (rest form))

    ; Single-line if narrow enough -- write does the output at C speed
    (if (< (%form-width form) 60)
      (write form)

      ; Multi-line: dispatch on construct table
      (do (def props (if (symbol? head) (%fmt-lookup head) ()))
          (def fmt-type (if (null? props) () (%get-prop (lit fmt) props)))
          (if (eq? fmt-type (lit head-1))  (%fmt-head-1 head rest-forms col)
          (if (eq? fmt-type (lit head-kw)) (%fmt-head-kw head rest-forms col)
          (if (eq? fmt-type (lit body))    (%fmt-body-only head rest-forms col)
            (%fmt-default head rest-forms col))))))))

  ; Format any expression
  (set! %fmt-expr (fn (form col)
    (if (%comment? form)
      (display (first (rest form)))
      (if (pair? form) (%fmt-list form col)
        (write form)))))

  ; --- Main: output formatted tokens ---

  (def %fmt-tokens (fn (tokens first-token)
    (if (null? tokens) ()
      (do (def tok (first tokens))
          ; Add blank line between top-level forms (not before first)
          (if first-token ()
            (if (%comment? tok) ()
              (display "\n")))
          (%fmt-expr tok 0)
          (if (%comment? tok) ()
            (display "\n"))
          (%fmt-tokens (rest tokens) ())))))

  (%fmt-tokens %tokens t))
