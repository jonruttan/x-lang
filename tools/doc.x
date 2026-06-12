; doc.x -- Offline documentation generator (entry script)
;
; Reads two strings from stdin:
;   1. doc-prims.x content (retroactive docs for boot modules)
;   2. Source file content (the file being documented)
;
; Tokenizes both, builds a lookup alist from doc-prims.x, then walks
; the source tokens using the alist as fallback for bare (def ...) forms.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref (lit tok) (lit read-str)))

(do
  (import x/doc/doc-gen)

  ; --- Read inputs ---
  (def %prims-input (read))
  (def %source-input (read))

  ; --- Tokenize both with a fresh base ---
  (def %doc-base (make-base))
  (def %prims-tokens (%token-read-string %doc-base %prims-input))
  (def %source-tokens (%token-read-string %doc-base %source-input))

  ; --- Build lookup alist from doc-prims tokens ---
  (def %prims-alist (doc-build-lookup %prims-tokens))

  ; --- Generate Markdown ---
  (doc-walk-with-prims %source-tokens %prims-alist))
