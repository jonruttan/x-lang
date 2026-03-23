; doc-gen.x -- Markdown documentation generator library
;
; Extracts (doc ...) and (note ...) forms from token trees
; and emits Markdown. Works with tokens from make-base + token-read-string.
(import x/core/list)
(import x/type/string)

; --- Predicates (cross-base: use string=? not eq?) ---

(doc (def doc-sym-is?
  (fn (_ sym name)
    (if (symbol? sym) (string=? (symbol->string sym) name) ())))
  (param sym ANY "Value to test")
  (param name STRING "Expected symbol name")
  (returns BOOLEAN "True if sym is a symbol with the given name")
  "Test if a value is a symbol matching a name string (cross-base safe).")

(def doc-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "doc") ())))
(def doc-note-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "note") ())))
(def doc-def-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "def") ())))
(def doc-param-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "param") ())))
(def doc-provide-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "provide") ())))

; --- Extraction helpers ---

(def doc-find-last-string
  (fn (_ lst)
    (def %go (fn (_ remaining found)
      (if (null? remaining) found
        (if (string? (first remaining))
          (%go (rest remaining) (first remaining))
          (%go (rest remaining) found)))))
    (%go lst "")))

(def doc-extract-params
  (fn (_ ps acc)
    (if (null? ps) (reverse acc)
      (if (not (pair? ps))
        (if (doc-param-form? ps) (reverse (pair ps acc)) (reverse acc))
        (if (doc-param-form? (first ps))
          (doc-extract-params (rest ps) (pair (first ps) acc))
          (doc-extract-params (rest ps) acc))))))

(def doc-extract-meta-type
  (fn (_ forms tag acc)
    (if (null? forms) (reverse acc)
      (if (pair? (first forms))
        (if (doc-sym-is? (first (first forms)) tag)
          (doc-extract-meta-type (rest forms) tag (pair (first forms) acc))
          (doc-extract-meta-type (rest forms) tag acc))
        (doc-extract-meta-type (rest forms) tag acc)))))

; --- Main doc form extraction ---

(doc (def doc-extract
  (fn (_ form)
    (def %second (first (rest form)))
    (def %meta (rest (rest form)))
    (if (doc-def-form? %second)
      (do
        (def %name (first (rest %second)))
        (def %value (if (null? (rest (rest %second))) ()
                      (first (rest (rest %second)))))
        (def %desc (doc-find-last-string %meta))
        (def %fn-params
          (if (pair? %value)
            (if (doc-sym-is? (first %value) "fn")
              (doc-extract-params (first (rest %value)) ())
              ())
            ()))
        (def %returns (doc-extract-meta-type %meta "returns" ()))
        (def %examples (doc-extract-meta-type %meta "example" ()))
        (def %sees (doc-extract-meta-type %meta "see" ()))
        (def %notes (doc-extract-meta-type %meta "note" ()))
        (list %name %desc %fn-params %returns %examples %sees %notes))
      (if (doc-provide-form? %second)
        (do (def %name (first (rest %second)))
            (def %desc (doc-find-last-string %meta))
            (list %name %desc
              (doc-extract-meta-type %meta "param" ())
              (doc-extract-meta-type %meta "returns" ())
              (doc-extract-meta-type %meta "example" ())
              (doc-extract-meta-type %meta "see" ())
              (doc-extract-meta-type %meta "note" ())))
        (do (def %desc (doc-find-last-string %meta))
            (list %second %desc
              (doc-extract-meta-type %meta "param" ())
              (doc-extract-meta-type %meta "returns" ())
              (doc-extract-meta-type %meta "example" ())
              (doc-extract-meta-type %meta "see" ())
              (doc-extract-meta-type %meta "note" ())))))))
  (param form LIST "A (doc ...) token form")
  (returns LIST "(name desc params returns examples sees notes)")
  "Extract structured metadata from a (doc ...) form.")

; --- Markdown output ---

(def doc-emit-heading (fn (_ level text)
  (for-each (fn (_ x) (display "#")) (range 0 level))
  (display " ") (display text) (newline) (newline)))

(def doc-emit-param (fn (_ p)
  (def %p-name (first (rest p)))
  (def %p-type (if (null? (rest (rest p))) () (first (rest (rest p)))))
  (def %p-desc
    (if (null? (rest (rest p))) ""
      (if (null? (rest (rest (rest p)))) ""
        (if (string? (first (rest (rest (rest p)))))
          (first (rest (rest (rest p)))) ""))))
  (display "- **") (display %p-name) (display "**")
  (if (not (null? %p-type))
    (if (not (string? %p-type))
      (do (display " : `") (display %p-type) (display "`"))))
  (if (not (string=? %p-desc ""))
    (do (display " — ") (display %p-desc)))
  (newline)))

(doc (def doc-emit-entry
  (fn (_ info)
    (def %name (nth 0 info))
    (def %desc (nth 1 info))
    (def %params (nth 2 info))
    (def %returns (nth 3 info))
    (def %examples (nth 4 info))
    (def %sees (nth 5 info))
    (def %notes (nth 6 info))
    (display "### `") (display %name) (display "`") (newline) (newline)
    (if (not (string=? %desc "")) (do (display %desc) (newline) (newline)))
    (if (not (null? %notes))
      (for-each (fn (_ n) (display "> ") (display (first (rest n))) (newline) (newline)) %notes))
    (if (not (null? %params))
      (do (display "**Parameters:**") (newline) (newline)
          (for-each doc-emit-param %params) (newline)))
    (if (not (null? %returns))
      (do (def %ret (first %returns))
          (display "**Returns:** `") (display (first (rest %ret))) (display "`")
          (if (not (null? (rest (rest %ret))))
            (if (string? (first (rest (rest %ret))))
              (if (not (string=? (first (rest (rest %ret))) ""))
                (do (display " — ") (display (first (rest (rest %ret))))))))
          (newline) (newline)))
    (if (not (null? %examples))
      (do (display "**Examples:**") (newline) (newline)
          (display "```") (newline)
          (for-each (fn (_ ex)
            (display (first (rest ex))) (display " => ")
            (display (first (rest (rest ex)))) (newline)) %examples)
          (display "```") (newline) (newline)))
    (if (not (null? %sees))
      (do (display "**See also:** ")
          (for-each (fn (_ s) (display "`") (display (first (rest s))) (display "` ")) %sees)
          (newline) (newline)))))
  (param info LIST "Extracted doc info from doc-extract")
  "Emit a single function's documentation as Markdown.")

; --- Token tree walker ---

(doc (def doc-walk
  (fn (_ tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens))
            (%rest (rest tokens)))
        (if (doc-form? tok)
          (do (doc-emit-entry (doc-extract tok)) (doc-walk %rest))
        (if (doc-note-form? tok)
          (do (if (not (null? (rest tok)))
                (do (display "## ") (display (first (rest tok))) (newline) (newline)))
              (doc-walk %rest))
        (if (doc-def-form? tok)
          (let ((%dname (first (rest tok))))
            (if (string=? (substring (symbol->string %dname) 0 1) "%")
              (doc-walk %rest)
              (do (display "### `") (display %dname) (display "`") (newline) (newline)
                  (doc-walk %rest))))
        (if (doc-provide-form? tok)
          (do (doc-emit-heading 1 (symbol->string (first (rest tok))))
              (doc-walk %rest))
          (doc-walk %rest)))))))))
  (param tokens LIST "Token list from token-read-string")
  "Walk a token tree, extracting and emitting all documentation as Markdown.")

(doc (provide x/doc/doc-gen
  doc-sym-is? doc-form? doc-note-form? doc-def-form? doc-param-form?
  doc-provide-form? doc-find-last-string doc-extract-params
  doc-extract-meta-type doc-extract doc-emit-heading doc-emit-param
  doc-emit-entry doc-walk)
  "Markdown documentation generator from x-lang source tokens.")
