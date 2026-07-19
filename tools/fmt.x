; fmt.x -- x-lang comment-preserving formatter (entry script)
;
; Data-driven: reads construct declarations from a XEON file
; (piped before the target source) to know how to format each form.
;
; Input order on stdin: constructs.x, lang-constructs (or ()), then quoted source string.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))
(def %token-read-string (prim-ref 'tok 'read-str))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read (prim-ref 'io 'read))


(do
  (import x/tool/fmt)

  ; --- Load construct declarations ---
  (def %constructs (%read))
  (def %lang-constructs (%read))
  (def %all-constructs
    (if (null? %lang-constructs) %constructs
      (append %constructs %lang-constructs)))
  (def %fmt-table (Fmt build-table %all-constructs))

  ; --- Create formatter base, patch COMMENT to keep tokens ---
  ;
  ; A FRESH base so the patch happens before the base's first read (the
  ; reader-macro boot-time-only rule); tokenizing rides (tok read-str)
  ; with this base while the script itself keeps running on the booted
  ; one. Navigation is CONTRACT-DRIVEN (#39): the old hand-rolled walk
  ; hardcoded "type-struct has 7 elements, io is the 7th" and a
  ; shape-heuristic COMMENT probe -- both bit-rotted against the layout
  ; and segfaulted. Everything below rides tools/base-paths.x rows
  ; through the reflect/type doors, so a layout change moves these
  ; accessors automatically (or fails the check-base-paths gate loudly).

  (def %fmt-base (Base make))

  ; Reader that keeps the comment text as a token
  (def %fmt-comment-reader (fn (_ . args)
    (list '%comment (%buffer-token (first args)))))

  ; The fresh base's type registry: descriptor row `type-alist`, walked
  ; FROM %fmt-base (reflect's own cell accessor is bound to the running
  ; base). Entries are (handle . type-tree).
  (def %fmt-registry
    (first (%reflect-step %fmt-base (%reflect-path 'type-alist %base-paths))))

  ; Find the COMMENT type by NAME (fresh string via the reflect walk),
  ; not by shape heuristics.
  (def %find-comment (fn (self entries)
    (when (null? entries)
      (Err raise 'state "fmt: no COMMENT type in the fresh base's registry" ()))
    (let ((ts (rest (first entries))))
      (if (str=? (%reflect-sym->str (%reflect-type-tree-name ts)) "COMMENT")
        ts
        (self (rest entries))))))

  ; Push the keeping reader through the blessed door (path-driven cell).
  (%type-push-read (%find-comment %fmt-registry) %fmt-comment-reader)

  ; --- Read input string and tokenize ---

  (def %input (%read))
  (def %tokens (%token-read-string %fmt-base %input))

  ; --- Format ---

  (Fmt tokens %tokens %fmt-table))
