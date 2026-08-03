; doc.x -- Offline documentation generator (entry script)
;
; A pure filter: Markdown for ONE source file to stdout.
;   sh x.sh --no-pin -q -f tools/dev/doc.x -- FILE
; Inputs are slurped by path (no stdin data channel under x.sh -f):
;   1. lib/x/doc/doc-prims.x (retroactive docs for boot modules; an
;      empty table when FILE IS doc-prims.x)
;   2. FILE, the source being documented
;
; Tokenizes both, builds a lookup alist from doc-prims.x, then walks
; the source tokens using the alist as fallback for bare (def ...) forms.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))

(do
  (import x/doc/doc-gen)
  (import x/tool/contract)

  (Contract alloc-guard!)

  (def %argv (Contract argv))
  (when (null? %argv)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/dev/doc.x -- FILE\n")
        (Sys exit 1)))
  (def %file (first %argv))
  (unless (File exists? %file)
    (do (%stderr (Str8 append "Error: " (Str8 append %file " not found\n")))
        (Sys exit 1)))

  (def %prims-path "lib/x/doc/doc-prims.x")
  (def %prims-input
    (if (str=? %file %prims-path) "" (File slurp %prims-path)))
  (def %source-input (File slurp %file))

  ; --- Tokenize both with a fresh base ---
  ; (Base make): make-base retired when the constructors homed on the Base class
  (def %doc-base (Base make))
  (def %prims-tokens (%token-read-string %doc-base %prims-input))
  (def %source-tokens (%token-read-string %doc-base %source-input))

  ; --- Build lookup alist from doc-prims tokens ---
  (def %prims-alist (%doc-build-lookup %prims-tokens))

  ; --- Generate Markdown ---
  (%doc-walk-with-prims %source-tokens %prims-alist))
