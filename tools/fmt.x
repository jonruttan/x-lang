; fmt.x -- x-lang comment-preserving formatter (entry script)
;
; Data-driven: reads construct declarations from a XEON file
; (piped before the target source) to know how to format each form.
;
; Input order on stdin: constructs.x, lang-constructs (or ()), then quoted source string.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref (lit buf) (lit tok)))
(def %token-read-string (prim-ref (lit tok) (lit read-str)))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read (prim-ref (lit io) (lit read)))


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

  ; (Base make): make-base retired when the constructors homed on the Base class
  (def %fmt-base (Base make))

  ; Reader that keeps the comment text as a token
  (def %fmt-comment-reader (fn (_ . args)
    (list (lit %comment) (%buffer-token (first args)))))

  ; Navigate type struct: entry = (handle . type-struct)
  ; type-struct has 7 elements, io is the 7th
  (def %entry-io (fn (_ entry)
    (first (rest (rest (rest (rest (rest (rest entry)))))))))

  ; Find COMMENT entry: first with (analyse + delimit + no read + no write)
  (def %find-comment (fn (_ alist)
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

  ; --- Read input string and tokenize ---

  (def %input (%read))
  (def %tokens (%token-read-string %fmt-base %input))

  ; --- Format ---

  (Fmt tokens %tokens %fmt-table))
