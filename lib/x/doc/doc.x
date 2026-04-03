; doc.x -- Inline documentation system for x-lang
;
; Three forms — same metadata everywhere:
;
; 1. Wrapping def (library functions):
;   (doc (def name (fn (_ (param p TYPE "text") ...) body))
;     (returns TYPE "desc") (example "in" "out") (see other) "Description.")
;
; 2. Wrapping provide (module-level):
;   (doc (provide x/mod sym1 sym2 ...)
;     (note "Literal syntax: ...") (example "expr" "result") "Module desc.")
;
; 3. Bare symbol (C primitives, pre-existing bindings):
;   (doc pair "Create a new pair."
;     (param a ANY "First") (param d ANY "Second") (returns PAIR "A pair"))
;
; Metadata forms: (returns TYPE "desc"), (param name TYPE "desc"),
;   (example "input" "output"), (see name), (note "text")
;
; Loaded before and/or — use nested if, not and/or/cond.

; %doc-registry-cell is set up by x-core.x before this file is loaded.

; --- Helpers ---

; Local reverse (list.x not yet loaded)
(def %doc-reverse
  (fn (_ lst)
    (def %rv
      (fn (self in out)
        (if (null? in) out
          (self (rest in) (pair (first in) out)))))
    (%rv lst ())))

; Local for-each (list.x not yet loaded)
(def %doc-for-each
  (fn (self f lst)
    (if (null? lst) ()
      (do (f (first lst)) (self f (rest lst))))))

; Local str-contains? (string.x not yet loaded)
(def %doc-str-contains?
  (fn (_ sub s)
    (def %sub-len (str-length sub))
    (def %s-len (str-length s))
    (def %go
      (fn (self i)
        (if (< %s-len (+ i %sub-len)) #f
          (if (str=? (substring s i (+ i %sub-len)) sub) #t
            (self (+ i 1))))))
    (if (= %sub-len 0) #t (%go 0))))

; Find last string in a list
(def %doc-find-last-string
  (fn (_ lst)
    (def %go
      (fn (self remaining found)
        (if (null? remaining) found
          (if (str? (first remaining))
            (self (rest remaining) (first remaining))
            (self (rest remaining) found)))))
    (%go lst "")))

; --- Registry operations ---
; Entry: (name desc returns params examples sees notes)

(def %doc-register!
  (fn (_ name desc returns params examples sees notes)
    (set-first! %doc-registry-cell
      (pair (list name desc returns params examples sees notes)
            (first %doc-registry-cell)))))

; Shared alist lookup by eq? on first element
(def %registry-find
  (fn (_ cell name)
    (def %go
      (fn (self alist)
        (if (null? alist) ()
          (if (eq? (first (first alist)) name)
            (first alist)
            (self (rest alist))))))
    (%go (first cell))))

(def %doc-lookup (fn (_ name) (%registry-find %doc-registry-cell name)))

; --- Entry accessors ---
(def %doc-entry-name    (fn (_ e) (first e)))
(def %doc-entry-desc    (fn (_ e) (first (rest e))))
(def %doc-entry-returns (fn (_ e) (first (rest (rest e)))))
(def %doc-entry-params  (fn (_ e) (first (rest (rest (rest e))))))
(def %doc-entry-examples (fn (_ e) (first (rest (rest (rest (rest e)))))))
(def %doc-entry-sees    (fn (_ e) (first (rest (rest (rest (rest (rest e))))))))
(def %doc-entry-notes   (fn (_ e) (first (rest (rest (rest (rest (rest (rest e)))))))))

; --- Strip param annotations from fn parameter list ---

(def %doc-params-acc (pair () ()))

; Extract (name type desc) from a (param name TYPE "desc") form
(def %doc-extract-param
  (fn (_ form)
    (def %p-name (first (rest form)))
    (def %p-type (if (null? (rest (rest form))) () (first (rest (rest form)))))
    (def %p-desc (if (null? (rest (rest form))) ""
                   (if (null? (rest (rest (rest form)))) ""
                     (if (str? (first (rest (rest (rest form)))))
                       (first (rest (rest (rest form))))
                       ""))))
    (list %p-name %p-type %p-desc)))

(def %doc-strip-params
  (fn (self ps)
    (if (null? ps) ()
      (if (not (pair? ps)) ps
        (if (eq? (first ps) (lit param))
          (do
            (def %info (%doc-extract-param ps))
            (set-first! %doc-params-acc
              (pair %info (first %doc-params-acc)))
            (first %info))
          (if (pair? (first ps))
            (if (eq? (first (first ps)) (lit param))
              (do
                (def %info (%doc-extract-param (first ps)))
                (set-first! %doc-params-acc
                  (pair %info (first %doc-params-acc)))
                (pair (first %info) (self (rest ps))))
              (pair (first ps) (self (rest ps))))
            (pair (first ps) (self (rest ps)))))))))

; --- Process metadata sub-forms ---

(def %doc-pending-returns (pair () ()))
(def %doc-pending-examples (pair () ()))
(def %doc-pending-sees (pair () ()))
(def %doc-pending-notes (pair () ()))

(def %doc-process-meta
  (fn (self forms)
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
                    (if (str? (first (rest (rest %form))))
                      (first (rest (rest %form)))
                      ""))))
            (if (eq? %tag (lit example))
              (set-first! %doc-pending-examples
                (pair (pair (first (rest %form)) (first (rest (rest %form))))
                      (first %doc-pending-examples)))
            (if (eq? %tag (lit see))
              (set-first! %doc-pending-sees
                (pair (first (rest %form)) (first %doc-pending-sees)))
            (if (eq? %tag (lit note))
              (set-first! %doc-pending-notes
                (pair (first (rest %form)) (first %doc-pending-notes)))
            (if (eq? %tag (lit param))
              (set-first! %doc-params-acc
                (pair (%doc-extract-param %form)
                      (first %doc-params-acc))))))))))
        (self (rest forms))))))

; --- Reset all pending accumulators ---
(def %doc-reset-pending!
  (fn (_ )
    (set-first! %doc-pending-returns ())
    (set-first! %doc-pending-examples ())
    (set-first! %doc-pending-sees ())
    (set-first! %doc-pending-notes ())
    (set-first! %doc-params-acc ())))

; --- Collect all pending metadata into a register call ---
(def %doc-collect-and-register!
  (fn (_ name desc)
    (%doc-register! name desc
      (first %doc-pending-returns)
      (%doc-reverse (first %doc-params-acc))
      (%doc-reverse (first %doc-pending-examples))
      (%doc-reverse (first %doc-pending-sees))
      (%doc-reverse (first %doc-pending-notes)))))

; --- Reconstruct fn with stripped params ---

(def %doc-strip-fn
  (fn (_ fn-form)
    (if (not (pair? fn-form)) fn-form
      (if (not (eq? (first fn-form) (lit fn))) fn-form
        (do
          (set-first! %doc-params-acc ())
          (def %clean-params (%doc-strip-params (first (rest fn-form))))
          (pair (lit fn) (pair %clean-params (rest (rest fn-form)))))))))

; --- Main doc operative ---
;
; Three modes:
;   (doc (def name value) [meta...] "desc")      — wraps def
;   (doc (provide name sym...) [meta...] "desc")  — wraps provide
;   (doc name [meta...] "desc")                   — bare symbol

(def doc
  (op (def-form . %doc-meta) e
    (if (not (pair? def-form))
      ; --- Bare symbol: just register docs ---
      (do
        (%doc-reset-pending!)
        (%doc-process-meta %doc-meta)
        (%doc-collect-and-register! def-form (%doc-find-last-string %doc-meta))
        def-form)
      ; --- Pair: check if def or provide ---
      (if (eq? (first def-form) (lit provide))
        ; --- Provide-wrapping: register module docs, eval provide ---
        (do
          (def %mod-name (first (rest def-form)))
          (%doc-reset-pending!)
          (%doc-process-meta %doc-meta)
          (%doc-collect-and-register! %mod-name (%doc-find-last-string %doc-meta))
          (tail-eval def-form e))
        ; --- Def-wrapping: extract, strip params, eval ---
        (do
          (def %name (first (rest def-form)))
          (def %value (first (rest (rest def-form))))
          (%doc-reset-pending!)
          (%doc-process-meta %doc-meta)
          (def %ret (first %doc-pending-returns))
          (def %exs (%doc-reverse (first %doc-pending-examples)))
          (def %refs (%doc-reverse (first %doc-pending-sees)))
          (def %nts (%doc-reverse (first %doc-pending-notes)))
          (set-first! %doc-params-acc ())
          (def %clean-value (%doc-strip-fn %value))
          (def %params (%doc-reverse (first %doc-params-acc)))
          (%doc-register! %name (%doc-find-last-string %doc-meta)
            %ret %params %exs %refs %nts)
          (tail-eval (list (lit def) %name %clean-value) e))))))

; note: (note text...) -> no-op, returns nil (standalone section marker)
(def note (op %note-args e ()))

; --- Display helpers ---

(def %display-notes
  (fn (_ notes)
    (%doc-for-each
      (fn (_ n) (display "  ") (display n) (newline))
      notes)))

(def %display-params
  (fn (self ps)
    (if (null? ps) ()
      (do
        (display "  ")
        (display (first (first ps)))
        (if (not (null? (first (rest (first ps)))))
          (do (display " : ")
              (display (first (rest (first ps))))))
        (if (not (str=? (first (rest (rest (first ps)))) ""))
          (do (display " -- ")
              (display (first (rest (rest (first ps)))))))
        (newline)
        (self (rest ps))))))

(def %display-returns
  (fn (_ ret)
    (if (not (null? ret))
      (do (display "  => ")
          (display (first ret))
          (if (not (str=? (first (rest ret)) ""))
            (do (display " -- ")
                (display (first (rest ret)))))
          (newline)))))

(def %display-examples
  (fn (_ examples)
    (%doc-for-each
      (fn (_ ex)
        (display "  > ")
        (display (first ex))
        (display " => ")
        (display (rest ex))
        (newline))
      examples)))

(def %display-sees
  (fn (_ sees)
    (%doc-for-each
      (fn (_ ref) (display "  See: ") (display ref) (newline))
      sees)))

; --- Display ---

(def %display-doc
  (fn (_ entry)
    (display (%doc-entry-name entry))
    (display ": ")
    (display (%doc-entry-desc entry))
    (newline)
    (%display-notes (%doc-entry-notes entry))
    (%display-params (%doc-entry-params entry))
    (%display-returns (%doc-entry-returns entry))
    (%display-examples (%doc-entry-examples entry))
    (%display-sees (%doc-entry-sees entry))))

; --- Module display (uses %module-registry-cell from x-core.x) ---

(def %module-lookup (fn (_ name) (%registry-find %module-registry-cell name)))

(def %display-module
  (fn (_ entry)
    (def %mod-name (first entry))
    (def %mod-doc (%doc-lookup %mod-name))
    (display %mod-name)
    (if (not (null? %mod-doc))
      (if (not (str=? (%doc-entry-desc %mod-doc) ""))
        (do (display " -- ") (display (%doc-entry-desc %mod-doc)))))
    (newline)
    (if (not (null? %mod-doc))
      (do
        (%display-notes (%doc-entry-notes %mod-doc))
        (%display-examples (%doc-entry-examples %mod-doc))
        (newline)))
    (%doc-for-each
      (fn (_ sym)
        (def %e (%doc-lookup sym))
        (display "  ")
        (display sym)
        (if (not (null? %e))
          (do (display " -- ")
              (display (%doc-entry-desc %e))))
        (newline))
      (rest entry))))

(def %display-overview
  (fn (_ )
    (display "x-lang help system") (newline)
    (newline)
    (display "  (help)          show this overview") (newline)
    (display "  (help name)     docs for a function or operative") (newline)
    (display "  (help module)   list a module's exports") (newline)
    (display "  (modules)       list all available modules") (newline)
    (display "  (apropos \"str\") search by name substring") (newline)
    (newline)
    (display "Modules:") (newline)
    (%doc-for-each
      (fn (_ m)
        (display "  ")
        (display (first m))
        ; Show module description if available
        (def %md (%doc-lookup (first m)))
        (if (not (null? %md))
          (if (not (str=? (%doc-entry-desc %md) ""))
            (do (display " -- ") (display (%doc-entry-desc %md)))))
        (newline))
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
        (if (eq? %h-name (lit modules))
          (modules)
          (do
            (def %mod (%module-lookup %h-name))
            (if (not (null? %mod))
              (%display-module %mod)
              (do
                (def %doc-entry (%doc-lookup %h-name))
                (if (null? %doc-entry)
                  (do (display "No documentation for ")
                      (display %h-name) (newline))
                  (%display-doc %doc-entry))))))))))

; apropos: search doc registry by name substring
(def apropos
  (op (pattern) e
    (def %pat (eval pattern e))
    (def %search
      (fn (self entries)
        (if (null? entries) ()
          (do
            (if (%doc-str-contains? %pat
                  (symbol->str (first (first entries))))
              (do (display "  ")
                  (display (first (first entries)))
                  (if (not (str=? (first (rest (first entries))) ""))
                    (do (display " -- ")
                        (display (first (rest (first entries))))))
                  (newline)))
            (self (rest entries))))))
    (%search (first %doc-registry-cell))))

; --- Module discovery ---

; Reverse %module-resolve: "lib/x/core/list.x" -> x/core/list symbol
; Returns () for paths that aren't modules (e.g. "lib/x-core.x")
; Reverse %module-resolve: "lib/x/core/list.x" -> x/core/list symbol
; Uses only primitives available at doc.x load time (no str-starts?/str-ends?)
(def %path->module-name
  (fn (_ path)
    (def %len (str-length path))
    (if (< %len 7) ()
      (if (not (str=? (substring path 0 4) "lib/")) ()
        (if (not (str=? (substring path (- %len 2) %len) ".x")) ()
          (do
            (def %inner (substring path 4 (- %len 2)))
            (if (not (str=? (substring %inner 0 2) "x/")) ()
              (str->symbol %inner))))))))

; Check if module name is in the loaded registry
(def %module-is-loaded?
  (fn (_ name)
    (not (null? (%registry-find %module-registry-cell name)))))

; modules: list all known modules with load status
(def modules
  (fn (_ )
    (display "Modules:") (newline)
    (def %show
      (fn (self paths)
        (if (not (null? paths))
          (do
            (def %name (%path->module-name (first paths)))
            (if (not (null? %name))
              (do
                (display "  ")
                (display %name)
                (if (%module-is-loaded? %name)
                  (do
                    (display "  [loaded]")
                    (def %md (%doc-lookup %name))
                    (if (not (null? %md))
                      (if (not (str=? (%doc-entry-desc %md) ""))
                        (do (display " -- ") (display (%doc-entry-desc %md))))))
                  (display "  [available]"))
                (newline)))
            (self (rest paths))))))
    (%show (first %include-list-cell))))

(doc (provide x/doc/doc doc note help apropos modules)
  (note "doc wraps def or provide for metadata. help for REPL lookup. apropos for search.")
  "Inline documentation system.")
