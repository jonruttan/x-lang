; doc-gen.x -- Markdown documentation generator library
;
; Extracts (doc ...) and (note ...) forms from token trees
; and emits Markdown. Works with tokens from make-base + %token-read-string.
(import x/core/list)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref (lit tok) (lit read-str)))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))

(import x/type/str)

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
(def doc-set-form? (fn (_ tok)
  (if (pair? tok) (doc-sym-is? (first tok) "set!") ())))
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
    (if (or (doc-def-form? %second) (doc-set-form? %second))
      (let ()  ; scoped: def in tail position would leak to global
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
        (let () (def %name (first (rest %second)))
            (def %desc (doc-find-last-string %meta))
            (list %name %desc
              (doc-extract-meta-type %meta "param" ())
              (doc-extract-meta-type %meta "returns" ())
              (doc-extract-meta-type %meta "example" ())
              (doc-extract-meta-type %meta "see" ())
              (doc-extract-meta-type %meta "note" ())))
        (let () (def %desc (doc-find-last-string %meta))
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
  (for-each (fn (_ _) (display "#")) (List range 0 level))
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
    (def %name (List nth 0 info))
    (def %desc (List nth 1 info))
    (def %params (List nth 2 info))
    (def %returns (List nth 3 info))
    (def %examples (List nth 4 info))
    (def %sees (List nth 5 info))
    (def %notes (List nth 6 info))
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

; --- Lookup alist for retroactive docs ---

(doc (def doc-build-lookup
  (fn (self tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens)))
        (if (doc-form? tok)
          (let ()
            (def %info (doc-extract tok))
            (def %name (List nth 0 %info))
            (if (symbol? %name)
              (pair (pair (symbol->str %name) %info)
                    (self (rest tokens)))
              (self (rest tokens))))
          (self (rest tokens)))))))
  (param tokens LIST "Token list (e.g. from tokenizing doc-prims.x)")
  (returns LIST "Alist of (name-string . extracted-7-tuple) pairs")
  "Build a lookup alist from (doc ...) forms in a token stream.")

(doc (def doc-lookup-alist
  (fn (self alist name-str)
    (if (null? alist) ()
      (if (str=? (first (first alist)) name-str)
        (rest (first alist))
        (self (rest alist) name-str)))))
  (param alist LIST "Alist from doc-build-lookup")
  (param name-str STRING "Function name as string")
  (returns LIST "Extracted 7-tuple, or () if not found")
  "Cross-base-safe lookup in a doc alist by name string.")

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

; --- Emit body with prims alist fallback and deduplication ---

(def %doc-seen-has?
  (fn (self seen name-str)
    (if (null? seen) #f
      (if (str=? (first seen) name-str) #t
        (self (rest seen) name-str)))))

(def %doc-walk-body-with-prims
  (fn (self tokens prims-alist seen)
    (if (null? tokens) ()
      (let ()
        (def %tok (first tokens))
        (def %rest (rest tokens))
        (if (doc-form? %tok)
          (if (doc-provide-form? (first (rest %tok)))
            (self %rest prims-alist seen)
            (let ()
              (def %info (doc-extract %tok))
              (def %name-str (symbol->str (List nth 0 %info)))
              (if (%doc-seen-has? seen %name-str)
                (self %rest prims-alist seen)
                (do (doc-emit-entry %info)
                    (self %rest prims-alist (pair %name-str seen))))))
        (if (doc-note-form? %tok)
          (do (if (not (null? (rest %tok)))
                (do (display "## ") (display (first (rest %tok))) (newline) (newline)))
              (self %rest prims-alist seen))
        (if (or (doc-def-form? %tok) (doc-set-form? %tok))
          (let ()
            (def %dname (first (rest %tok)))
            (def %dname-str (symbol->str %dname))
            (if (str=? (substring %dname-str 0 1) "%")
              (self %rest prims-alist seen)
              (if (%doc-seen-has? seen %dname-str)
                (self %rest prims-alist seen)
                (let ()
                  (def %prims-entry (doc-lookup-alist prims-alist %dname-str))
                  (if (not (null? %prims-entry))
                    (doc-emit-entry %prims-entry)
                    (do (display "### `") (display %dname) (display "`") (newline) (newline)))
                  (self %rest prims-alist (pair %dname-str seen))))))
          (self %rest prims-alist seen))))))))

; --- Page header emission ---

(def %doc-emit-page-header
  (fn (_ tokens)
    (def %provide (%doc-find-provide tokens))
    (if (not (null? %provide))
      (let ()
        (def %mod-name (symbol->str (List nth 0 %provide)))
        ; Back navigation — count slashes to determine depth
        (def %depth
          (fold (fn (_ acc ch) (if (= ch (integer->char 47)) (+ acc 1) acc))
            0 (Str ->list %mod-name)))
        (def %back
          (fold (fn (_ acc _) (%str-append acc "../"))
            "" (List range 0 %depth)))
        (display "[← Index](") (display %back) (display "index.md)")
        (newline) (newline)
        (doc-emit-heading 1 %mod-name)
        (if (not (str=? (List nth 1 %provide) ""))
          (do (display (List nth 1 %provide)) (newline) (newline)))
        (if (not (null? (List nth 6 %provide)))
          (for-each (fn (_ n) (display "> ") (display (first (rest n))) (newline) (newline))
            (List nth 6 %provide)))))))

; --- Public walkers ---

(doc (def doc-walk-with-prims
  (fn (_ tokens prims-alist)
    (%doc-emit-page-header tokens)
    ; Build local doc lookup from standalone (doc name ...) forms in source,
    ; then merge with prims-alist so bare defs find their docs
    (def %local-alist (doc-build-lookup tokens))
    (def %merged (append %local-alist prims-alist))
    (%doc-walk-body-with-prims tokens %merged ())))
  (param tokens LIST "Source file token list")
  (param prims-alist LIST "Alist from doc-build-lookup (or () for none)")
  "Walk source tokens, using prims-alist as fallback docs for bare defs.")

(doc (def doc-walk
  (fn (_ tokens)
    (doc-walk-with-prims tokens ())))
  (param tokens LIST "Token list from %token-read-string")
  "Walk a token tree, extracting and emitting all documentation as Markdown.")

(doc (provide x/doc/doc-gen
  doc-sym-is? doc-form? doc-note-form? doc-def-form? doc-set-form? doc-param-form?
  doc-provide-form? doc-find-last-string doc-extract-params
  doc-extract-meta-type doc-extract doc-emit-heading doc-emit-param
  doc-emit-entry doc-walk)
  "Markdown documentation generator from x-lang source tokens.")
