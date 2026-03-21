; doc.x -- Inline documentation system for x-lang
;
; doc wraps def:
;   (doc (def name (fn ((param p TYPE "text") ...) body))
;     (returns TYPE "desc")
;     (example "input" "output")
;     "Description string is the last string argument.")
;
; doc receives the entire (def ...) unevaluated, extracts metadata,
; strips param annotations from fn params, reconstructs a clean def,
; evals it, and registers the documentation.
;
; Loaded before and/or — use nested if, not and/or/cond.

; %doc-registry-cell is set up by x-core.x before this file is loaded.

; --- Helpers ---

; Local reverse (list.x not yet loaded)
(def %doc-reverse
  (fn (lst)
    (def %rv
      (fn (in out)
        (if (null? in) out
          (%rv (rest in) (pair (first in) out)))))
    (%rv lst ())))

; Find last string in a list
(def %doc-find-last-string
  (fn (lst)
    (def %go
      (fn (remaining found)
        (if (null? remaining) found
          (if (string? (first remaining))
            (%go (rest remaining) (first remaining))
            (%go (rest remaining) found)))))
    (%go lst "")))

; --- Registry operations ---
; Entry: (name desc returns params examples sees)

(def %doc-register!
  (fn (name desc returns params examples sees)
    (set-first! %doc-registry-cell
      (pair (list name desc returns params examples sees)
            (first %doc-registry-cell)))))

(def %doc-lookup
  (fn (name)
    (def %go
      (fn (alist)
        (if (null? alist) ()
          (if (eq? (first (first alist)) name)
            (first alist)
            (%go (rest alist))))))
    (%go (first %doc-registry-cell))))

; --- Strip param annotations from fn parameter list ---
; (param name TYPE "desc") -> name, collecting metadata
; Handles proper lists, dotted tails ((a . rest)), bare symbols.

(def %doc-params-acc (pair () ()))

(def %doc-strip-params
  (fn (ps)
    (if (null? ps) ()
      (if (not (pair? ps)) ps
        ; Check if this is a (param ...) form in dotted-tail position
        (if (eq? (first ps) (lit param))
          ; Dotted tail is itself a param form: (. (param name TYPE "desc"))
          (do
            (def %p-name (first (rest ps)))
            (def %p-type (if (null? (rest (rest ps))) () (first (rest (rest ps)))))
            (def %p-desc (if (null? (rest (rest ps))) ""
                           (if (null? (rest (rest (rest ps)))) ""
                             (if (string? (first (rest (rest (rest ps)))))
                               (first (rest (rest (rest ps))))
                               ""))))
            (set-first! %doc-params-acc
              (pair (list %p-name %p-type %p-desc)
                    (first %doc-params-acc)))
            %p-name)
          ; Regular list element
          (if (pair? (first ps))
            ; First element is a list — might be (param name TYPE "desc")
            (if (eq? (first (first ps)) (lit param))
              (do
                (def %p-name (first (rest (first ps))))
                (def %p-type (if (null? (rest (rest (first ps)))) ()
                               (first (rest (rest (first ps))))))
                (def %p-desc (if (null? (rest (rest (first ps)))) ""
                               (if (null? (rest (rest (rest (first ps))))) ""
                                 (if (string? (first (rest (rest (rest (first ps))))))
                                   (first (rest (rest (rest (first ps)))))
                                   ""))))
                (set-first! %doc-params-acc
                  (pair (list %p-name %p-type %p-desc)
                        (first %doc-params-acc)))
                (pair %p-name (%doc-strip-params (rest ps))))
              ; Not a param form — keep as-is
              (pair (first ps) (%doc-strip-params (rest ps))))
            ; Plain symbol — keep
            (pair (first ps) (%doc-strip-params (rest ps)))))))))

; --- Process metadata sub-forms ---

(def %doc-pending-returns (pair () ()))
(def %doc-pending-examples (pair () ()))
(def %doc-pending-sees (pair () ()))

(def %doc-process-meta
  (fn (forms)
    (if (null? forms) ()
      (do
        (if (pair? (first forms))
          (do
            (def %form (first forms))
            (def %tag (first %form))
            (if (eq? %tag (lit returns))
              (set-first! %doc-pending-returns
                (list (first (rest %form))
                  (if (null? (rest (rest %form))) ""
                    (if (string? (first (rest (rest %form))))
                      (first (rest (rest %form)))
                      ""))))
            (if (eq? %tag (lit example))
              (set-first! %doc-pending-examples
                (pair (pair (first (rest %form)) (first (rest (rest %form))))
                      (first %doc-pending-examples)))
            (if (eq? %tag (lit see))
              (set-first! %doc-pending-sees
                (pair (first (rest %form)) (first %doc-pending-sees))))))))
        (%doc-process-meta (rest forms))))))

; --- Reconstruct fn with stripped params ---

(def %doc-strip-fn
  (fn (fn-form)
    ; fn-form = (fn (params...) body...)
    (if (not (pair? fn-form)) fn-form
      (if (not (eq? (first fn-form) (lit fn))) fn-form
        ; Strip params
        (do
          (set-first! %doc-params-acc ())
          (def %clean-params (%doc-strip-params (first (rest fn-form))))
          (pair (lit fn) (pair %clean-params (rest (rest fn-form)))))))))

; --- Main doc operative ---
;
; (doc (def name value) [metadata...] "description")
;
; First arg is the (def ...) form (unevaluated).
; Remaining args are metadata sub-forms and description.
; Description is the last string argument.

(def doc
  (op (def-form . %doc-meta) e
    ; Extract name and value from (def name value)
    (def %name (first (rest def-form)))
    (def %value (first (rest (rest def-form))))
    ; Extract description (last string in metadata)
    (def %desc (%doc-find-last-string %doc-meta))
    ; Process metadata sub-forms (returns, example, see)
    (set-first! %doc-pending-returns ())
    (set-first! %doc-pending-examples ())
    (set-first! %doc-pending-sees ())
    (%doc-process-meta %doc-meta)
    (def %ret (first %doc-pending-returns))
    (def %exs (%doc-reverse (first %doc-pending-examples)))
    (def %refs (%doc-reverse (first %doc-pending-sees)))
    ; Strip param annotations from fn value
    (set-first! %doc-params-acc ())
    (def %clean-value (%doc-strip-fn %value))
    (def %params (%doc-reverse (first %doc-params-acc)))
    ; Register documentation
    (%doc-register! %name %desc %ret %params %exs %refs)
    ; Tail-eval clean def in caller's env — trampoline runs it after
    ; op unwinds, so save_stack is nil and C def does BST insertion.
    (tail-eval (list (lit def) %name %clean-value) e)))

; note: (note text...) -> no-op, returns nil
(def note (op args e ()))

; --- Display ---

(def %display-doc
  (fn (entry)
    ; entry = (name desc returns params examples sees)
    (display (first entry))
    (display ": ")
    (display (first (rest entry)))
    (newline)
    ; Show params
    (def %show-params
      (fn (ps)
        (if (null? ps) ()
          (do
            ; param = (name type desc)
            (display "  ")
            (display (first (first ps)))
            (if (not (null? (first (rest (first ps)))))
              (do (display " : ")
                  (display (first (rest (first ps))))))
            (if (not (string=? (first (rest (rest (first ps)))) ""))
              (do (display " -- ")
                  (display (first (rest (rest (first ps)))))))
            (newline)
            (%show-params (rest ps))))))
    (%show-params (first (rest (rest (rest entry)))))
    ; Show returns
    (def %ret (first (rest (rest entry))))
    (if (not (null? %ret))
      (do (display "  => ")
          (display (first %ret))
          (if (not (string=? (first (rest %ret)) ""))
            (do (display " -- ")
                (display (first (rest %ret)))))
          (newline)))
    ; Show examples
    (def %show-examples
      (fn (exs)
        (if (null? exs) ()
          (do
            (display "  > ")
            (display (first (first exs)))
            (display " => ")
            (display (rest (first exs)))
            (newline)
            (%show-examples (rest exs))))))
    (%show-examples (first (rest (rest (rest (rest entry))))))
    ; Show see-also
    (def %show-sees
      (fn (refs)
        (if (null? refs) ()
          (do
            (display "  See: ")
            (display (first refs))
            (newline)
            (%show-sees (rest refs))))))
    (%show-sees (first (rest (rest (rest (rest (rest entry)))))))))

; help: (help name) -> display documentation for name
(def help
  (op (name) e
    (def %doc-entry (%doc-lookup name))
    (if (null? %doc-entry)
      (do (display "No documentation for ")
          (display name) (newline))
      (%display-doc %doc-entry))))

(provide x/doc doc note help)
