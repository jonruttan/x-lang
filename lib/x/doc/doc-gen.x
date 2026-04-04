; doc-gen.x -- Markdown documentation generator library
;
; Extracts (doc ...) and (note ...) forms from token trees
; and emits Markdown. Works with tokens from make-base + token-read-string.
(import x/core/list)
(import x/type/string)

; --- Predicates (cross-base: use str=? not eq?) ---

(doc (def doc-sym-is?
  (fn (_ sym name)
    (if (symbol? sym) (str=? (symbol->str sym) name) ())))
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
    (def %go (fn (self remaining found)
      (if (null? remaining) found
        (if (str? (first remaining))
          (self (rest remaining) (first remaining))
          (self (rest remaining) found)))))
    (%go lst "")))

(def doc-extract-params
  (fn (self ps acc)
    (if (null? ps) (reverse acc)
      (if (not (pair? ps))
        (if (doc-param-form? ps) (reverse (pair ps acc)) (reverse acc))
        (if (doc-param-form? (first ps))
          (self (rest ps) (pair (first ps) acc))
          (self (rest ps) acc))))))

(def doc-extract-meta-type
  (fn (self forms tag acc)
    (if (null? forms) (reverse acc)
      (if (pair? (first forms))
        (if (doc-sym-is? (first (first forms)) tag)
          (self (rest forms) tag (pair (first forms) acc))
          (self (rest forms) tag acc))
        (self (rest forms) tag acc)))))

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
        (if (str? (first (rest (rest (rest p)))))
          (first (rest (rest (rest p)))) ""))))
  (display "- **") (display %p-name) (display "**")
  (if (not (null? %p-type))
    (if (not (str? %p-type))
      (do (display " : `") (display %p-type) (display "`"))))
  (if (not (str=? %p-desc ""))
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
    (if (not (str=? %desc "")) (do (display %desc) (newline) (newline)))
    (if (not (null? %notes))
      (for-each (fn (_ n) (display "> ") (display (first (rest n))) (newline) (newline)) %notes))
    (if (not (null? %params))
      (do (display "**Parameters:**") (newline) (newline)
          (for-each doc-emit-param %params) (newline)))
    (if (not (null? %returns))
      (do (def %ret (first %returns))
          (display "**Returns:** `") (display (first (rest %ret))) (display "`")
          (if (not (null? (rest (rest %ret))))
            (if (str? (first (rest (rest %ret))))
              (if (not (str=? (first (rest (rest %ret))) ""))
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
          (for-each (fn (_ s)
            (display "[`") (display (first (rest s))) (display "`](#")
            (display (first (rest s))) (display ") ")) %sees)
          (newline) (newline)))))
  (param info LIST "Extracted doc info from doc-extract")
  "Emit a single function's documentation as Markdown.")

; --- Token tree walker ---

; --- Find the (doc (provide ...)) or (provide ...) form in tokens ---

(def %doc-find-provide
  (fn (self tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens)))
        (if (doc-form? tok)
          (let ((%second (first (rest tok))))
            (if (doc-provide-form? %second)
              (doc-extract tok)
              (self (rest tokens))))
          (if (doc-provide-form? tok)
            (list (first (rest tok)) "" () () () () ())
            (self (rest tokens))))))))

; --- Emit body (everything except the provide heading) ---

(def %doc-walk-body
  (fn (self tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens))
            (%rest (rest tokens)))
        (if (doc-form? tok)
          (let ((%second (first (rest tok))))
            (if (doc-provide-form? %second)
              (self %rest)
              (do (doc-emit-entry (doc-extract tok)) (self %rest))))
        (if (doc-note-form? tok)
          (do (if (not (null? (rest tok)))
                (do (display "## ") (display (first (rest tok))) (newline) (newline)))
              (self %rest))
        (if (doc-def-form? tok)
          (let ((%dname (first (rest tok))))
            (if (str=? (substring (symbol->str %dname) 0 1) "%")
              (self %rest)
              (do
                ; Check doc registry for retroactive docs (e.g. from doc-prims.x)
                ; Use string comparison (cross-base safe) since tokens
                ; come from a different base than the doc registry.
                (def %dname-str (symbol->str %dname))
                (def %reg-entry
                  (let ((%go (fn (self alist)
                    (if (null? alist) ()
                      (if (str=? (symbol->str (first (first alist))) %dname-str)
                        (first alist)
                        (self (rest alist)))))))
                    (%go (first %doc-registry-cell))))
                (if (not (null? %reg-entry))
                  ; Emit from registry entry (untagged format).
                  ; Registry: (name desc returns params examples sees notes)
                  (do
                    (display "### `") (display %dname) (display "`") (newline) (newline)
                    ; Description
                    (def %r-desc (%doc-entry-desc %reg-entry))
                    (if (not (str=? %r-desc ""))
                      (do (display %r-desc) (newline) (newline)))
                    ; Notes (bare strings)
                    (def %r-notes (%doc-entry-notes %reg-entry))
                    (if (not (null? %r-notes))
                      (for-each (fn (_ n)
                        (display "> ") (display n) (newline) (newline))
                        %r-notes))
                    ; Parameters (untagged triples: name TYPE "desc")
                    (def %r-params (%doc-entry-params %reg-entry))
                    (if (not (null? %r-params))
                      (do (display "**Parameters:**") (newline) (newline)
                        (for-each (fn (_ p)
                          (display "- **") (display (first p)) (display "**")
                          (if (not (null? (rest p)))
                            (do (display " : `") (display (first (rest p))) (display "`")))
                          (if (not (null? (rest (rest p))))
                            (if (str? (first (rest (rest p))))
                              (do (display " — ") (display (first (rest (rest p)))))))
                          (newline))
                          %r-params)
                        (newline)))
                    ; Returns (untagged pair: TYPE "desc")
                    (def %r-ret (%doc-entry-returns %reg-entry))
                    (if (not (null? %r-ret))
                      (do (display "**Returns:** `") (display (first %r-ret)) (display "`")
                        (if (not (null? (rest %r-ret)))
                          (if (str? (first (rest %r-ret)))
                            (do (display " — ") (display (first (rest %r-ret))))))
                        (newline) (newline)))
                    ; Examples (dotted pairs: ("in" . "out"))
                    (def %r-examples (%doc-entry-examples %reg-entry))
                    (if (not (null? %r-examples))
                      (do (display "**Examples:**") (newline) (newline)
                        (display "```") (newline)
                        (for-each (fn (_ ex)
                          (display (first ex)) (display " => ")
                          (display (rest ex)) (newline))
                          %r-examples)
                        (display "```") (newline) (newline)))
                    ; See also (bare symbols)
                    (def %r-sees (%doc-entry-sees %reg-entry))
                    (if (not (null? %r-sees))
                      (do (display "**See also:** ")
                        (for-each (fn (_ s)
                          (display "[`") (display s) (display "`](#")
                          (display s) (display ") "))
                          %r-sees)
                        (newline) (newline))))
                  (do (display "### `") (display %dname) (display "`") (newline) (newline)))
                (self %rest))))
          (self %rest))))))))

(doc (def doc-walk
  (fn (self tokens)
    ; First pass: find the provide form and emit it as page header
    (def %provide (%doc-find-provide tokens))
    (if (not (null? %provide))
      (do
        (def %mod-name (symbol->str (nth 0 %provide)))
        ; Back navigation — count slashes to determine depth
        (def %depth
          (fold (fn (_ acc ch) (if (= ch (integer->char 47)) (+ acc 1) acc))
            0 (str->list %mod-name)))
        (def %back
          (fold (fn (_ acc x) (str-append acc "../"))
            "" (range 0 %depth)))
        (display "[← Index](") (display %back) (display "index.md)")
        (newline) (newline)
        (doc-emit-heading 1 %mod-name)
        (if (not (str=? (nth 1 %provide) ""))
          (do (display (nth 1 %provide)) (newline) (newline)))
        (if (not (null? (nth 6 %provide)))
          (for-each (fn (_ n) (display "> ") (display (first (rest n))) (newline) (newline))
            (nth 6 %provide)))))
    ; Second pass: emit all function/note entries (skip provide)
    (%doc-walk-body tokens)))
  (param tokens LIST "Token list from token-read-string")
  "Walk a token tree, extracting and emitting all documentation as Markdown.")

(doc (provide x/doc/doc-gen
  doc-sym-is? doc-form? doc-note-form? doc-def-form? doc-param-form?
  doc-provide-form? doc-find-last-string doc-extract-params
  doc-extract-meta-type doc-extract doc-emit-heading doc-emit-param
  doc-emit-entry doc-walk)
  "Markdown documentation generator from x-lang source tokens.")
