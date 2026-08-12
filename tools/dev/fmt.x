; fmt.x -- x-lang comment-preserving formatter (entry script)
;
; A pure filter: format ONE file to stdout.
;   sh x.sh --no-pin -q -f tools/dev/fmt.x -- [--lang LANG] FILE
; In-place and check modes are launch glue in the make recipes (fmt-x /
; fmt-check-x): there is no stdin data channel under x.sh -f (the pipe
; carries the script), so inputs are slurped by path -- which also
; retires the old wrapper's awk string-escape hack.
;
; Data-driven: construct declarations (lib/x/constructs.x, plus the
; language-specific table when --lang or the file's path names one) tell
; the formatter how each form nests.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))
(def %token-read-string (prim-ref 'tok 'read-str))

(do
  (import x/tool/fmt)
  (import x/tool/contract)

  (Contract alloc-guard!)

  ; --- args: [--lang LANG] FILE ---
  (def %argv (Contract argv))
  (def %lang
    (if (and (pair? %argv) (str=? (first %argv) "--lang"))
      (if (pair? (rest %argv)) (first (rest %argv)) ()) ()))
  (def %file
    (match
      ((null? %lang) (if (pair? %argv) (first %argv) ()))
      (#t (if (pair? (rest (rest %argv))) (first (rest (rest %argv))) ()))))
  (when (null? %file)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/dev/fmt.x -- [--lang LANG] FILE\n")
        (Sys exit 1)))
  (unless (File exists? %file)
    (do (%stderr (Str8 append "Error: " (Str8 append %file " not found\n")))
        (Sys exit 1)))

  ; Auto-detect language from the file path (the old wrapper's case table)
  (def %lang-of
    (fn (_ path)
      (match
        ((Str8 contains? "/lang/r5rs/" path) "r5rs")
        ((Str8 contains? "/lang/r7rs/" path) "r7rs")
        ((Str8 contains? "/lang/krn/" path) "krn")
        ((Str8 contains? "/lang/ash/" path) "ash")
        ((Str8 contains? "/lang/sweet/" path) "sweet")
        ((Str8 contains? "/lang/sl/" path) "sl")
        (#t ()))))
  (def %the-lang (if (null? %lang) (%lang-of %file) %lang))

  ; --- Load construct declarations (parsed, not evaluated) ---
  (def %parse-one
    (fn (_ path) (first (%token-read-string (%base) (File slurp path)))))
  (def %constructs (%parse-one "lib/x/constructs.x"))
  (def %lang-constructs
    (if (null? %the-lang) ()
      (let ((p (Str8 append "lang/" (Str8 append %the-lang "/lib/constructs.x"))))
        (if (File exists? p) (%parse-one p) ()))))
  (def %all-constructs
    (if (null? %lang-constructs) %constructs
      (%append %constructs %lang-constructs)))
  (def %fmt-table (Fmt build-table %all-constructs))

  ; --- Create formatter base, patch COMMENT to keep tokens ---
  ;
  ; A FRESH base so the patch happens before the base's first read (the
  ; reader-macro boot-time-only rule); tokenizing rides (tok read-str)
  ; with this base while the script itself keeps running on the booted
  ; one. Navigation is CONTRACT-DRIVEN (#39): the old hand-rolled walk
  ; hardcoded "type-struct has 7 elements, io is the 7th" and a
  ; shape-heuristic COMMENT probe -- both bit-rotted against the layout
  ; and segfaulted. Everything below rides tools/contract/base-paths.x rows
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
  (def %find-comment (fn (_ entries)
    (let ((hit (%find (fn (_ e)
                        (str=? (%reflect-sym->str (%reflect-type-tree-name (rest e)))
                               "COMMENT"))
                      entries)))
      (when (null? hit)
        (Err raise 'state "fmt: no COMMENT type in the fresh base's registry" ()))
      (rest hit))))

  ; Push the keeping reader through the blessed door (path-driven cell).
  (%type-push-read (%find-comment %fmt-registry) %fmt-comment-reader)

  ; --- Slurp the target and tokenize ---

  (def %input (File slurp %file))
  (def %tokens (%token-read-string %fmt-base %input))

  ; --- Format ---

  (Fmt tokens %tokens %fmt-table))
