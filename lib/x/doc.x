; doc.x -- Inline documentation system for x-lang
;
; Two forms:
;
; 1. Wrapping def (for library functions):
;   (doc (def name (fn ((param p TYPE "text") ...) body))
;     (returns TYPE "desc") (example "in" "out") "Description.")
;
; 2. Bare symbol (for C primitives and pre-existing bindings):
;   (doc pair "Create a new pair."
;     (param a ANY "First element") (param d ANY "Second element"))
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

; Local for-each (list.x not yet loaded)
(def %doc-for-each
  (fn (f lst)
    (if (null? lst) ()
      (do (f (first lst)) (%doc-for-each f (rest lst))))))

; Local string-contains? (string.x not yet loaded)
(def %doc-string-contains?
  (fn (sub s)
    (def %sub-len (string-length sub))
    (def %s-len (string-length s))
    (def %go
      (fn (i)
        (if (< %s-len (+ i %sub-len)) #f
          (if (string=? (substring s i (+ i %sub-len)) sub) #t
            (%go (+ i 1))))))
    (if (= %sub-len 0) #t (%go 0))))

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

; Extract (name type desc) from a (param name TYPE "desc") form
(def %doc-extract-param
  (fn (form)
    (def %p-name (first (rest form)))
    (def %p-type (if (null? (rest (rest form))) () (first (rest (rest form)))))
    (def %p-desc (if (null? (rest (rest form))) ""
                   (if (null? (rest (rest (rest form)))) ""
                     (if (string? (first (rest (rest (rest form)))))
                       (first (rest (rest (rest form))))
                       ""))))
    (list %p-name %p-type %p-desc)))

(def %doc-strip-params
  (fn (ps)
    (if (null? ps) ()
      (if (not (pair? ps)) ps
        ; Check if this is a (param ...) form in dotted-tail position
        (if (eq? (first ps) (lit param))
          (do
            (def %info (%doc-extract-param ps))
            (set-first! %doc-params-acc
              (pair %info (first %doc-params-acc)))
            (first %info))
          ; Regular list element
          (if (pair? (first ps))
            (if (eq? (first (first ps)) (lit param))
              (do
                (def %info (%doc-extract-param (first ps)))
                (set-first! %doc-params-acc
                  (pair %info (first %doc-params-acc)))
                (pair (first %info) (%doc-strip-params (rest ps))))
              (pair (first ps) (%doc-strip-params (rest ps))))
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
                (pair (first (rest %form)) (first %doc-pending-sees)))
            (if (eq? %tag (lit param))
              (set-first! %doc-params-acc
                (pair (%doc-extract-param %form)
                      (first %doc-params-acc)))))))))
        (%doc-process-meta (rest forms))))))

; --- Reconstruct fn with stripped params ---

(def %doc-strip-fn
  (fn (fn-form)
    (if (not (pair? fn-form)) fn-form
      (if (not (eq? (first fn-form) (lit fn))) fn-form
        (do
          (set-first! %doc-params-acc ())
          (def %clean-params (%doc-strip-params (first (rest fn-form))))
          (pair (lit fn) (pair %clean-params (rest (rest fn-form)))))))))

; --- Main doc operative ---
;
; Two modes:
;   (doc (def name value) [metadata...] "description")  — wraps def
;   (doc name [metadata...] "description")               — bare symbol

(def doc
  (op (def-form . %doc-meta) e
    (if (not (pair? def-form))
      ; --- Bare symbol: just register docs ---
      (do
        (def %desc (%doc-find-last-string %doc-meta))
        (set-first! %doc-pending-returns ())
        (set-first! %doc-pending-examples ())
        (set-first! %doc-pending-sees ())
        (set-first! %doc-params-acc ())
        (%doc-process-meta %doc-meta)
        (%doc-register! def-form %desc
          (first %doc-pending-returns)
          (%doc-reverse (first %doc-params-acc))
          (%doc-reverse (first %doc-pending-examples))
          (%doc-reverse (first %doc-pending-sees)))
        def-form)
      ; --- Def-wrapping: extract, strip, eval ---
      (do
        (def %name (first (rest def-form)))
        (def %value (first (rest (rest def-form))))
        (def %desc (%doc-find-last-string %doc-meta))
        (set-first! %doc-pending-returns ())
        (set-first! %doc-pending-examples ())
        (set-first! %doc-pending-sees ())
        (%doc-process-meta %doc-meta)
        (def %ret (first %doc-pending-returns))
        (def %exs (%doc-reverse (first %doc-pending-examples)))
        (def %refs (%doc-reverse (first %doc-pending-sees)))
        (set-first! %doc-params-acc ())
        (def %clean-value (%doc-strip-fn %value))
        (def %params (%doc-reverse (first %doc-params-acc)))
        (%doc-register! %name %desc %ret %params %exs %refs)
        (tail-eval (list (lit def) %name %clean-value) e)))))

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

; --- Module lookup (uses %module-registry-cell from x-core.x) ---

(def %module-lookup
  (fn (name)
    (def %go
      (fn (alist)
        (if (null? alist) ()
          (if (eq? (first (first alist)) name)
            (first alist)
            (%go (rest alist))))))
    (%go (first %module-registry-cell))))

(def %display-module
  (fn (entry)
    ; entry = (name . exports)
    (display (first entry))
    (display ":") (newline)
    (%doc-for-each
      (fn (sym)
        (def %e (%doc-lookup sym))
        (display "  ")
        (display sym)
        (if (not (null? %e))
          (do (display " -- ")
              (display (first (rest %e)))))
        (newline))
      (rest entry))))

(def %display-overview
  (fn ()
    (display "x-lang help system") (newline)
    (newline)
    (display "  (help)          show this overview") (newline)
    (display "  (help name)     docs for a function or operative") (newline)
    (display "  (help module)   list a module's exports") (newline)
    (display "  (apropos \"str\") search by name substring") (newline)
    (newline)
    (display "Modules:") (newline)
    (%doc-for-each
      (fn (m) (display "  ") (display (first m)) (newline))
      (first %module-registry-cell))))

; help: multi-dispatch
;   (help)       -> overview
;   (help name)  -> module listing OR individual doc
(def help
  (op args e
    (if (null? args)
      (%display-overview)
      (do
        (def %h-name (first args))
        (def %mod (%module-lookup %h-name))
        (if (not (null? %mod))
          (%display-module %mod)
          (do
            (def %doc-entry (%doc-lookup %h-name))
            (if (null? %doc-entry)
              (do (display "No documentation for ")
                  (display %h-name) (newline))
              (%display-doc %doc-entry))))))))

; apropos: search doc registry by name substring
(def apropos
  (op (pattern) e
    (def %pat (eval pattern e))
    (def %search
      (fn (entries)
        (if (null? entries) ()
          (do
            (if (%doc-string-contains? %pat
                  (symbol->string (first (first entries))))
              (do (display "  ")
                  (display (first (first entries)))
                  (if (not (string=? (first (rest (first entries))) ""))
                    (do (display " -- ")
                        (display (first (rest (first entries))))))
                  (newline)))
            (%search (rest entries))))))
    (%search (first %doc-registry-cell))))

(provide x/doc doc note help apropos)
