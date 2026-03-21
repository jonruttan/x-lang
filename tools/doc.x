; doc.x -- Offline documentation generator
;
; Reads a source file (as a quoted string on stdin), tokenizes it,
; walks the token tree to extract (doc ...) and (note ...) forms,
; and outputs Markdown.
;
; New format: (doc (def name value) [metadata...] "description")
; Params are inside fn: (fn ((param name TYPE "desc") ...) body)

(do
  ; --- Tokenize source ---

  (def %input (read))
  (def %doc-base (make-base))
  (def %tokens (token-read-string %doc-base %input))

  ; --- Predicates ---
  ; Tokens come from make-base (separate atom namespace), so use string=?

  (def %sym-is?
    (fn (sym name)
      (if (symbol? sym) (string=? (symbol->string sym) name) ())))

  (def %doc-form?
    (fn (tok)
      (if (pair? tok) (%sym-is? (first tok) "doc") ())))

  (def %note-form?
    (fn (tok)
      (if (pair? tok) (%sym-is? (first tok) "note") ())))

  (def %def-form?
    (fn (tok)
      (if (pair? tok) (%sym-is? (first tok) "def") ())))

  (def %param-form?
    (fn (tok)
      (if (pair? tok) (%sym-is? (first tok) "param") ())))

  (def %provide-form?
    (fn (tok)
      (if (pair? tok) (%sym-is? (first tok) "provide") ())))

  ; --- Find last string in a list ---

  (def %find-last-string
    (fn (lst)
      (def %go
        (fn (remaining found)
          (if (null? remaining) found
            (if (string? (first remaining))
              (%go (rest remaining) (first remaining))
              (%go (rest remaining) found)))))
      (%go lst "")))

  ; --- Extract params from fn parameter list ---
  ; Walk (possibly dotted) param list, collect (param name TYPE "desc") forms

  (def %extract-params
    (fn (ps acc)
      (if (null? ps) (reverse acc)
        (if (not (pair? ps))
          ; Dotted tail: bare symbol or (param ...)
          (if (%param-form? ps)
            (reverse (pair ps acc))
            (reverse acc))
          ; List element
          (if (%param-form? (first ps))
            (%extract-params (rest ps) (pair (first ps) acc))
            (%extract-params (rest ps) acc))))))

  ; --- Extract metadata sub-forms from doc args ---
  ; (returns TYPE "desc"), (example "in" "out"), (see name)

  (def %extract-meta-type
    (fn (forms tag acc)
      (if (null? forms) (reverse acc)
        (if (pair? (first forms))
          (if (%sym-is? (first (first forms)) tag)
            (%extract-meta-type (rest forms) tag
              (pair (first forms) acc))
            (%extract-meta-type (rest forms) tag acc))
          (%extract-meta-type (rest forms) tag acc)))))

  ; --- Extract info from a (doc (def name value) metadata... "desc") form ---

  (def %extract-doc
    (fn (form)
      ; form = (doc (def name value) metadata... "desc")
      (def %def-form (first (rest form)))
      (def %meta (rest (rest form)))
      (def %name (first (rest %def-form)))
      (def %value (if (null? (rest (rest %def-form))) ()
                    (first (rest (rest %def-form)))))
      (def %desc (%find-last-string %meta))
      ; Extract params from fn value
      (def %fn-params
        (if (pair? %value)
          (if (%sym-is? (first %value) "fn")
            (%extract-params (first (rest %value)) ())
            ())
          ()))
      ; Extract metadata sub-forms
      (def %returns (%extract-meta-type %meta "returns" ()))
      (def %examples (%extract-meta-type %meta "example" ()))
      (def %sees (%extract-meta-type %meta "see" ()))
      (list %name %desc %fn-params %returns %examples %sees)))

  ; --- Markdown output helpers ---

  (def %emit-heading
    (fn (level text)
      (for-each (fn (x) (display "#")) (range 0 level))
      (display " ")
      (display text)
      (newline)
      (newline)))

  (def %emit-param
    (fn (p)
      ; p = (param name TYPE "desc")
      (def %p-name (first (rest p)))
      (def %p-type
        (if (null? (rest (rest p))) ()
          (first (rest (rest p)))))
      (def %p-desc
        (if (null? (rest (rest p))) ""
          (if (null? (rest (rest (rest p)))) ""
            (if (string? (first (rest (rest (rest p)))))
              (first (rest (rest (rest p))))
              ""))))
      (display "- **")
      (display %p-name)
      (display "**")
      (if (not (null? %p-type))
        (if (not (string? %p-type))
          (do (display " : `")
              (display %p-type)
              (display "`"))))
      (if (not (string=? %p-desc ""))
        (do (display " — ")
            (display %p-desc)))
      (newline)))

  (def %emit-doc-entry
    (fn (info)
      ; info = (name desc params returns examples sees)
      (def %name (first info))
      (def %desc (first (rest info)))
      (def %params (first (rest (rest info))))
      (def %returns (first (rest (rest (rest info)))))
      (def %examples (first (rest (rest (rest (rest info))))))
      (def %sees (first (rest (rest (rest (rest (rest info)))))))

      ; Function name as heading
      (display "### `")
      (display %name)
      (display "`")
      (newline)
      (newline)

      ; Description
      (if (not (string=? %desc ""))
        (do (display %desc) (newline) (newline)))

      ; Parameters
      (if (not (null? %params))
        (do
          (display "**Parameters:**")
          (newline) (newline)
          (for-each %emit-param %params)
          (newline)))

      ; Returns
      (if (not (null? %returns))
        (do
          (def %ret (first %returns))
          ; (returns TYPE "desc")
          (display "**Returns:** `")
          (display (first (rest %ret)))
          (display "`")
          (if (not (null? (rest (rest %ret))))
            (if (string? (first (rest (rest %ret))))
              (if (not (string=? (first (rest (rest %ret))) ""))
                (do (display " — ")
                    (display (first (rest (rest %ret))))))))
          (newline) (newline)))

      ; Examples
      (if (not (null? %examples))
        (do
          (display "**Examples:**")
          (newline) (newline)
          (display "```") (newline)
          (for-each
            (fn (ex)
              ; (example "input" "output")
              (display (first (rest ex)))
              (display " => ")
              (display (first (rest (rest ex))))
              (newline))
            %examples)
          (display "```") (newline)
          (newline)))

      ; See also
      (if (not (null? %sees))
        (do
          (display "**See also:** ")
          (for-each
            (fn (s)
              (display "`")
              (display (first (rest s)))
              (display "` "))
            %sees)
          (newline) (newline)))))

  ; --- Walk tokens and generate docs ---

  (def %walk
    (fn (tokens)
      (if (null? tokens) ()
        (let ((tok (first tokens))
              (%rest (rest tokens)))
          (if (%doc-form? tok)
            ; Doc form: extract and emit
            (do (%emit-doc-entry (%extract-doc tok))
                (%walk %rest))

          (if (%note-form? tok)
            ; Note form: emit section heading
            (do
              (if (not (null? (rest tok)))
                (do (display "## ")
                    (display (first (rest tok)))
                    (newline)
                    (newline)))
              (%walk %rest))

          (if (%def-form? tok)
            ; Bare def without doc: skip %-prefixed, show others minimally
            (let ((%dname (first (rest tok))))
              (if (string=? (substring (symbol->string %dname) 0 1) "%")
                (%walk %rest)
                (do
                  (display "### `")
                  (display %dname)
                  (display "`")
                  (newline)
                  (newline)
                  (%walk %rest))))

          (if (%provide-form? tok)
            ; Provide form: emit module header
            (do
              (%emit-heading 1 (symbol->string (first (rest tok))))
              (%walk %rest))

            ; Other form: skip
            (%walk %rest)))))))))

  ; --- Main ---

  (%walk %tokens))
