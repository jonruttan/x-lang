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
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str->symbol (prim-ref (lit str) (lit ->sym)))
; Two-arg front for %str<? (the pure-X byte compare defined below; the body
; resolves it at call time, so definition order is fine). Was the C (str <?)
; prim, retired -- sorting help output is cold, no C residency case.
(def %str-lt (fn (_ a b) (%str<? a b 0)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))


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
; Entry: (name desc returns params examples sees notes samples)
;
; example vs sample (#16): (example "in" "out") is an EXECUTABLE
; contract -- "out" is the true echo, and tools/doctest.x runs every
; example as a regression test. (sample "in" "prose") is an
; illustration -- side-effectful, environment-dependent, or
; prose-described -- rendered by help exactly like an example but
; never executed.

(def %doc-register!
  (fn (_ name desc returns params examples sees notes samples)
    (set-first! %doc-registry-cell
      (pair (list name desc returns params examples sees notes samples)
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
(def %doc-entry-samples (fn (_ e) (first (rest (rest (rest (rest (rest (rest (rest e))))))))))

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
          (let ()  ; scoped: def in tail position would leak to global
            (def %info (%doc-extract-param ps))
            (set-first! %doc-params-acc
              (pair %info (first %doc-params-acc)))
            (first %info))
          (if (pair? (first ps))
            (if (eq? (first (first ps)) (lit param))
              (let ()
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
(def %doc-pending-samples (pair () ()))

(def %doc-process-meta
  (fn (self forms)
    (if (null? forms) ()
      (do
        (if (pair? (first forms))
          (let ()
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
            (if (eq? %tag (lit sample))
              (set-first! %doc-pending-samples
                (pair (pair (first (rest %form)) (first (rest (rest %form))))
                      (first %doc-pending-samples)))
            (if (eq? %tag (lit see))
              (set-first! %doc-pending-sees
                (pair (first (rest %form)) (first %doc-pending-sees)))
            (if (eq? %tag (lit note))
              (set-first! %doc-pending-notes
                (pair (first (rest %form)) (first %doc-pending-notes)))
            (if (eq? %tag (lit param))
              (set-first! %doc-params-acc
                (pair (%doc-extract-param %form)
                      (first %doc-params-acc)))))))))))
        (self (rest forms))))))

; --- Reset all pending accumulators ---
(def %doc-reset-pending!
  (fn (_ )
    (set-first! %doc-pending-returns ())
    (set-first! %doc-pending-examples ())
    (set-first! %doc-pending-sees ())
    (set-first! %doc-pending-notes ())
    (set-first! %doc-pending-samples ())
    (set-first! %doc-params-acc ())))

; --- Collect all pending metadata into a register call ---
(def %doc-collect-and-register!
  (fn (_ name desc)
    (%doc-register! name desc
      (first %doc-pending-returns)
      (%doc-reverse (first %doc-params-acc))
      (%doc-reverse (first %doc-pending-examples))
      (%doc-reverse (first %doc-pending-sees))
      (%doc-reverse (first %doc-pending-notes))
      (%doc-reverse (first %doc-pending-samples)))))

; --- Reconstruct fn with stripped params ---

(def %doc-strip-fn
  (fn (_ fn-form)
    (if (not (pair? fn-form)) fn-form
      (if (not (eq? (first fn-form) (lit fn))) fn-form
        (let ()
          (set-first! %doc-params-acc ())
          (def %clean-params (%doc-strip-params (first (rest fn-form))))
          (pair (lit fn) (pair %clean-params (rest (rest fn-form)))))))))

; --- Lazy doc: stash at load, process on first help/apropos/modules ---
;
; Loading ~100 (doc ...) forms through the full metadata processor adds
; ~1s of startup. The fast path below just strips (param ...) forms from
; fn signatures (needed for the fn to actually work) and stashes the raw
; metadata. %doc-commit! walks the stash and fills the registry the first
; time anything reads it.

(def %doc-pending-cell (pair () ()))

; Fast param strip: extract just the names, skip accumulation into
; %doc-params-acc (the commit phase re-runs %doc-strip-fn to collect it).
(def %doc-strip-params-fast
  (fn (self ps)
    (if (null? ps) ()
      (if (not (pair? ps)) ps
        (if (eq? (first ps) (lit param))
          (first (rest ps))
          (if (pair? (first ps))
            (if (eq? (first (first ps)) (lit param))
              (pair (first (rest (first ps))) (self (rest ps)))
              (pair (first ps) (self (rest ps))))
            (pair (first ps) (self (rest ps)))))))))

(def %doc-strip-fn-fast
  (fn (_ fn-form)
    (if (not (pair? fn-form)) fn-form
      (if (not (eq? (first fn-form) (lit fn))) fn-form
        (pair (lit fn)
          (pair (%doc-strip-params-fast (first (rest fn-form)))
                (rest (rest fn-form))))))))

; --- Main doc operative (fast path) ---
;
; Three modes:
;   (doc (def name value) [meta...] "desc")      — wraps def
;   (doc (provide name sym...) [meta...] "desc")  — wraps provide
;   (doc name [meta...] "desc")                   — bare symbol

(def doc
  (op (def-form . %doc-meta) e
    (if (not (pair? def-form))
      ; bare symbol
      (do
        (set-first! %doc-pending-cell
          (pair (pair (lit %bare) (pair def-form %doc-meta))
                (first %doc-pending-cell)))
        def-form)
      (if (eq? (first def-form) (lit provide))
        ; provide-wrap
        (do
          (set-first! %doc-pending-cell
            (pair (pair (lit %provide) (pair def-form %doc-meta))
                  (first %doc-pending-cell)))
          (tail-eval def-form e))
        ; def-wrap: strip fast, stash full form for later re-strip, eval.
        ; NOTE: keep this a `do`, not a frame-introducing `let`/`let ()`, and
        ; inline name/value rather than `def`-ing them: this is an OPERATIVE
        ; whose final `tail-eval` must run in the op's own tail so it defines
        ; the symbol in the caller's env `e`.  A `let` frame here breaks that
        ; tail-eval (lib defs get mis-scoped).  Inlining keeps it leak-free.
        (do
          (set-first! %doc-pending-cell
            (pair (pair (lit %def) (pair def-form %doc-meta))
                  (first %doc-pending-cell)))
          (tail-eval
            (list (first def-form) (first (rest def-form))
                  (%doc-strip-fn-fast (first (rest (rest def-form)))))
            e))))))

; Commit one stashed entry into the registry (reproduces original doc logic).
(def %doc-commit-entry!
  (fn (_ kind form meta)
    (if (eq? kind (lit %bare))
      (do
        (%doc-reset-pending!)
        (%doc-process-meta meta)
        (%doc-collect-and-register! form (%doc-find-last-string meta)))
    (if (eq? kind (lit %provide))
      (do
        (%doc-reset-pending!)
        (%doc-process-meta meta)
        (%doc-collect-and-register! (first (rest form))
          (%doc-find-last-string meta)))
      ; %def
      (let ()
        (def %value (first (rest (rest form))))
        (%doc-reset-pending!)
        (%doc-process-meta meta)
        (set-first! %doc-params-acc ())
        (%doc-strip-fn %value)
        (%doc-collect-and-register! (first (rest form))
          (%doc-find-last-string meta)))))))

(def %doc-commit!
  (fn (_ )
    (def %pending (first %doc-pending-cell))
    (if (null? %pending) ()
      (let ()
        (set-first! %doc-pending-cell ())
        (def %go
          (fn (self lst)
            (if (null? lst) ()
              (let ()
                (def %e (first lst))
                (%doc-commit-entry! (first %e)
                  (first (rest %e)) (rest (rest %e)))
                (self (rest lst))))))
        ; Stash order is most-recent-first; reverse so older entries
        ; are registered first (mirrors load order).
        (%go (%doc-reverse %pending))))))

; note: (note text...) -> no-op, returns nil (standalone section marker)
(def note (op %note-args _ ()))

; --- Color stubs (overridden by x/repl/ansi.x when loaded) ---

(def %c-reset "")
(def %c-bold "")
(def %c-dim "")
(def %c-name "")
(def %c-type "")
(def %c-param "")
(def %c-example "")
(def %c-error "")
(def %c-module "")

; Code highlighting stub (overridden by x/repl/ansi.x when loaded)
(def %highlight-code display)

; --- Display helpers ---

(def %display-notes
  (fn (_ notes)
    (%doc-for-each
      (fn (_ n) (display "  ") (display %c-dim) (display n) (display %c-reset) (newline))
      notes)))

(def %display-params
  (fn (self ps)
    (if (null? ps) ()
      (do
        (display "  ")
        (display %c-param) (display (first (first ps))) (display %c-reset)
        (if (not (null? (first (rest (first ps)))))
          (do (display " : ")
              (display %c-type) (display (first (rest (first ps)))) (display %c-reset)))
        (if (not (str=? (first (rest (rest (first ps)))) ""))
          (do (display " -- ")
              (display (first (rest (rest (first ps)))))))
        (newline)
        (self (rest ps))))))

(def %display-returns
  (fn (_ ret)
    (if (not (null? ret))
      (do (display "  => ")
          (display %c-type) (display (first ret)) (display %c-reset)
          (if (not (str=? (first (rest ret)) ""))
            (do (display " -- ")
                (display (first (rest ret)))))
          (newline)))))

(def %display-examples
  (fn (_ examples)
    (%doc-for-each
      (fn (_ ex)
        (display "  > ")
        (%highlight-code (first ex))
        (display " => ")
        (display (rest ex))
        (newline))
      examples)))

(def %display-sees
  (fn (_ sees)
    (%doc-for-each
      (fn (_ ref) (display "  See: ") (display ref) (newline))
      sees)))

; Print a coloured name at an indent: `<indent>%c-name<name>%c-reset`.  name
; may be a symbol or string -- display renders either bare.  No newline, so a
; caller can append a description (%display-entry-line) or another suffix (e.g.
; modules' load status).
(def %display-name
  (fn (_ indent name)
    (display indent) (display %c-name) (display name) (display %c-reset)))

; Print one "<name> -- <desc>" listing line (description omitted when empty),
; then a newline.  The single formatter every name+desc listing routes through
; -- module exports, apropos hits, class members, the overview -- so colour and
; layout cannot drift apart between them.
(def %display-entry-line
  (fn (_ indent name desc)
    (%display-name indent name)
    (if (not (str=? desc ""))
      (do (display " -- ") (display desc)))
    (newline)))

; --- Display ---

; Find which module exports a given symbol
(def %module-for-sym
  (fn (_ sym)
    (def %has
      (fn (self lst)
        (if (null? lst) #f
          (if (eq? (first lst) sym) #t
            (self (rest lst))))))
    (def %search
      (fn (self mods)
        (if (null? mods) ()
          (if (%has (rest (first mods)))
            (first (first mods))
            (self (rest mods))))))
    (%search (first %module-registry-cell))))

(def %display-doc
  (fn (_ entry)
    (display %c-name) (display (%doc-entry-name entry)) (display %c-reset)
    (display ": ")
    (display (%doc-entry-desc entry))
    (newline)
    (def %mod (%module-for-sym (%doc-entry-name entry)))
    (if (not (null? %mod))
      (do (display "  module: ") (display %c-module) (display %mod) (display %c-reset) (newline)))
    (%display-notes (%doc-entry-notes entry))
    (%display-params (%doc-entry-params entry))
    (%display-returns (%doc-entry-returns entry))
    (%display-examples (%doc-entry-examples entry))
    (%display-examples (%doc-entry-samples entry))
    (%display-sees (%doc-entry-sees entry))))

; --- Module display (uses %module-registry-cell from x-core.x) ---

(def %module-lookup (fn (_ name) (%registry-find %module-registry-cell name)))

(def %display-module
  (fn (_ entry e)
    (def %mod-name (first entry))
    (def %mod-doc (%doc-lookup %mod-name))
    (%display-entry-line "" %mod-name
      (if (null? %mod-doc) "" (%doc-entry-desc %mod-doc)))
    (if (not (null? %mod-doc))
      (do
        (%display-notes (%doc-entry-notes %mod-doc))
        (%display-examples (%doc-entry-examples %mod-doc))
        (%display-examples (%doc-entry-samples %mod-doc))
        (newline)))
    (%doc-for-each
      (fn (_ sym)
        (def %e (%doc-lookup sym))
        (%display-entry-line "  " sym
          (if (null? %e) "" (%doc-entry-desc %e)))
        ; if sym names a class, expand its documented methods underneath.
        ; Only expand under the class's CANONICAL name, so aliases (e.g. Str,
        ; Str -> StrUTF8) stay collapsed instead of repeating the whole list.
        (def %v (guard (_ ()) (eval sym e)))
        (if (if (null? %v) #f
              (if (class? %v)
                (str=? (symbol->str sym) (symbol->str (class-name %v))) #f))
          (%display-class-sections %v "    ")
          ()))
      ; exports sorted alphabetically, matching the (help) overview
      (List sort (fn (_ a b) (%str-lt (symbol->str a) (symbol->str b)))
            (rest entry)))))

(def %display-overview
  (fn (_ )
    (display %c-bold) (display "x-lang help system") (display %c-reset) (newline)
    (newline)
    (display "  (help)          show this overview") (newline)
    (display "  (help name)     docs for a function or operative") (newline)
    (display "  (help module)   list a module's exports") (newline)
    (display "  (modules)       list all available modules") (newline)
    (display "  (apropos \"str\") search by name substring") (newline)
    (newline)
    (display %c-bold) (display "Modules:") (display %c-reset) (newline)
    (%doc-for-each
      (fn (_ m)
        (def %md (%doc-lookup (first m)))
        (%display-entry-line "  " (first m)
          (if (null? %md) "" (%doc-entry-desc %md))))
      ; alphabetical by module name (sort is a List method now)
      (List sort
        (fn (_ a b) (%str-lt (symbol->str (first a)) (symbol->str (first b))))
        (first %module-registry-cell)))))

; True if the string x appears in the list of strings lst.
(def %member-str?
  (fn (self x lst)
    (if (null? lst) #f
      (if (str=? x (first lst)) #t
        (self x (rest lst))))))

; Walk a class's chain looking up "<class>/method" docs; return the first hit
; (most-derived wins), or nil. Lets (help Class method) find inherited methods.
(def %find-method-doc
  (fn (self c method-str)
    (if (null? c) ()
      (let ()
        (def %k (%str->symbol
                  (%str-append (symbol->str (class-name c))
                    (%str-append "/" method-str))))
        (def %e (%doc-lookup %k))
        (if (null? %e) (self (class-parent c) method-str) %e)))))

; --- Class help: members/methods grouped static vs instance, sorted, merged ---

; Lexicographic byte compare of two strings (sorts member/method names).
(def %str<?
  (fn (loop a b i)
    (if (>= i (str-length a)) (< (str-length a) (str-length b))
      (if (>= i (str-length b)) #f
        (let ((ca (%char->integer (str-ref a i)))
              (cb (%char->integer (str-ref b i))))
          (if (< ca cb) #t (if (> ca cb) #f (loop a b (+ i 1)))))))))

; #t if symbol x is in the list of symbols lst.
(def %member-sym?
  (fn (loop x lst)
    (if (null? lst) #f
      (if (eq? x (first lst)) #t (loop x (rest lst))))))

; Description registered under "<class-str>/name", or "" if undocumented.
(def %doc-desc-for
  (fn (_ class-str name)
    (let ((e (%doc-lookup (%str->symbol
               (%str-append class-str (%str-append "/" (symbol->str name)))))))
      (if (null? e) "" (%doc-entry-desc e)))))

; Make (name . desc) for each name in `names` not already in `seen`.
(def %section-here
  (fn (loop cstr seen names)
    (if (null? names) ()
      (if (%member-sym? (first names) seen)
        (loop cstr seen (rest names))
        (pair (pair (first names) (%doc-desc-for cstr (first names)))
              (loop cstr seen (rest names)))))))

; Walk the inheritance chain MOST-DERIVED FIRST, collecting one category's
; (name . desc) entries (via `accessor`: class -> own name list); a subclass
; override hides the inherited entry of the same name.
(def %section-walk
  (fn (loop c accessor seen)
    (if (null? c) ()
      (%append (%section-here (symbol->str (class-name c)) seen (accessor c))
              (loop (class-parent c) accessor (%append (accessor c) seen))))))

; The merged, sorted (name . desc) entries for one category of a class.
(def %class-section-entries
  (fn (_ cls accessor)
    (List sort (fn (_ a b) (%str<? (symbol->str (first a)) (symbol->str (first b)) 0))
          (%section-walk cls accessor ()))))

; Print "name -- desc" (desc omitted when empty) for each entry at `indent`.
(def %display-entries
  (fn (loop entries indent)
    (if (null? entries) ()
      (do
        (%display-entry-line indent
          (symbol->str (first (first entries))) (rest (first entries)))
        (loop (rest entries) indent)))))

; Print a labelled section (header + entries), or nothing when empty.
(def %display-section
  (fn (_ label entries indent)
    (if (null? entries) ()
      (do
        (display indent) (display label) (newline)
        (%display-entries entries (%str-append indent "  "))))))

; Print a class's members + methods, grouped static vs instance, at `base` indent.
; Empty sections are hidden; inheritance is merged + sorted within each section.
(def %display-class-sections
  (fn (_ cls base)
    (let ((s-mem  (%class-section-entries cls class-static-members))
          (s-meth (%class-section-entries cls class-static-methods))
          (i-mem  (%class-section-entries cls class-members))
          (i-meth (%class-section-entries cls class-methods)))
      (do
        (if (if (null? s-mem) (null? s-meth) #f) ()    ; static: only if non-empty
          (do
            (display base) (display "static:") (newline)
            (%display-section "members:" s-mem  (%str-append base "  "))
            (%display-section "methods:" s-meth (%str-append base "  "))))
        (%display-section "members:" i-mem  base)
        (%display-section "methods:" i-meth base)))))

; Resolve an evaluated value to a class for help: the class itself, or -- when
; the value is an INSTANCE (object?) -- its class (class-of), so (help rng)
; documents rng's class. Returns () for anything else. (An instance is not a
; pair? at the x-lang level, so object?/class-of are the correct, safe tests.)
(def %resolve-class
  (fn (_ v)
    (if (class? v) v
      (if (object? v) (class-of v) ()))))

; help: multi-dispatch
;   (help)       -> overview
;   (help name)  -> module listing OR individual doc OR a class/instance's docs
(def help
  (op args e
    (%doc-commit!)
    (if (null? args)
      (%display-overview)
      (if (not (null? (rest args)))
        ; (help Class method) -> walk Class's chain for the method doc, so an
        ; inherited method (keyed under the ancestor that defines it) is found.
        (let ()
          (def %cls-arg (first args))
          (def %meth-str (symbol->str (first (rest args))))
          (def %maybe-cls (%resolve-class (guard (_ ()) (eval %cls-arg e))))
          (def %me
            (if (if (null? %maybe-cls) #f (class? %maybe-cls))
              (%find-method-doc %maybe-cls %meth-str)
              (%doc-lookup (%str->symbol
                (%str-append (symbol->str %cls-arg)
                  (%str-append "/" %meth-str))))))
          (if (null? %me)
            (do (display %c-error) (display "No documentation for ")
                (display %cls-arg) (display " ") (display (first (rest args)))
                (display %c-reset) (newline))
            (%display-doc %me)))
      (let ()
        (def %h-name (first args))
        (if (eq? %h-name (lit modules))
          (modules)
          (let ()
            (def %mod (%module-lookup %h-name))
            (if (not (null? %mod))
              (%display-module %mod e)
              (let ()
                ; A class is shown as its summary (the body-level (doc ...), if any)
                ; ABOVE its member/method sections -- so detect class BEFORE the
                ; generic doc-lookup, which would otherwise show the summary alone.
                (def %cls (%resolve-class (guard (_ ()) (eval %h-name e))))
                (if (if (null? %cls) #f (class? %cls))
                  (let ()
                    (def %cdoc (%doc-lookup (class-name %cls)))
                    (if (null? %cdoc)
                      (do (display %c-name) (display (class-name %cls))
                          (display %c-reset) (newline))
                      (%display-doc %cdoc))
                    (%display-class-sections %cls "  "))
                  (let ()
                    (def %doc-entry (%doc-lookup %h-name))
                    (if (not (null? %doc-entry))
                      (%display-doc %doc-entry)
                      (let ()
                        ; Not a binding/module/doc/class. It may still be a METHOD
                        ; name on some class (e.g. upcase on Char/Str8) -- surface
                        ; those rather than a bare "no documentation".
                        (def %hits (%apropos-matches (symbol->str %h-name)))
                        (if (null? %hits)
                          (do (display %c-error) (display "No documentation for ")
                              (display %h-name) (display %c-reset) (newline))
                          (do (display "No top-level doc for ") (display %h-name)
                              (display "; documented methods matching it:") (newline)
                              (%apropos-show %hits))))))))))))))))

; Doc-registry entries whose name CONTAINS pat (a string), sorted by name.
; Shared by apropos and help's name-not-found fallback.
(def %apropos-matches
  (fn (_ pat)
    (def %go
      (fn (self entries acc)
        (if (null? entries) acc
          (self (rest entries)
            (if (%doc-str-contains? pat (symbol->str (first (first entries))))
              (pair (first entries) acc)
              acc)))))
    (List sort (fn (_ a b) (%str-lt (symbol->str (first a)) (symbol->str (first b))))
          (%go (first %doc-registry-cell) ()))))

; Display matching (name . doc) entries one per line.
(def %apropos-show
  (fn (self entries)
    (if (null? entries) ()
      (do
        (%display-entry-line "  " (first (first entries)) (first (rest (first entries))))
        (self (rest entries))))))

; apropos: search the doc registry by name substring. The pattern may be a
; bare symbol ((apropos upcase)), a string ((apropos "upcase")), or any
; expression that evaluates to one ((apropos (lit upcase))).
(def apropos
  (op (pattern) e
    (%doc-commit!)
    (def %raw (if (symbol? pattern) pattern (eval pattern e)))
    (def %pat (if (symbol? %raw) (symbol->str %raw) %raw))
    (%apropos-show (%apropos-matches %pat))))

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
          (let ()
            (def %inner (substring path 4 (- %len 2)))
            (if (not (str=? (substring %inner 0 2) "x/")) ()
              (%str->symbol %inner))))))))

; Check if module name is in the loaded registry
(def %module-is-loaded?
  (fn (_ name)
    (not (null? (%registry-find %module-registry-cell name)))))

; modules: list all known modules with load status
(def modules
  (fn (_ )
    (%doc-commit!)
    (display %c-bold) (display "Modules:") (display %c-reset) (newline)
    (def %show
      (fn (self paths)
        (if (not (null? paths))
          (let ()
            (def %name (%path->module-name (first paths)))
            (if (not (null? %name))
              (do
                (%display-name "  " %name)
                (if (%module-is-loaded? %name)
                  (let ()
                    (display "  [loaded]")
                    (def %md (%doc-lookup %name))
                    (if (not (null? %md))
                      (if (not (str=? (%doc-entry-desc %md) ""))
                        (do (display " -- ") (display (%doc-entry-desc %md))))))
                  (display "  [available]"))
                (newline)))
            (self (rest paths))))))
    ; sorted by path (== module order); sort is non-destructive, so the
    ; live include/load queue is left untouched
    (%show (List sort (fn (_ a b) (%str-lt a b)) (first %include-list-cell)))))

(doc (provide x/doc/doc doc note help apropos modules)
  (note "doc wraps def or provide for metadata. help for REPL lookup. apropos for search.")
  "Inline documentation system.")
