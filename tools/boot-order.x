; boot-order.x -- boot-order lint: class-calls before their def-class
;
; The class-call trap: at boot, a load-time-evaluated form whose head names a
; class that is not yet defined either raises Unbound (fatal since the
; no-handler-errors-are-fatal fix) or -- when the name is bound but not yet
; callable -- silently passes through UNEVALUATED (x_type_list_eval's
; data-form rule), capturing the form itself as a truthy value.  A branch not
; taken on this platform (e.g. the Linux arm of an os check) never trips the
; runtime fatality, so the trap needs static coverage too.
;
; This lint derives the EFFECTIVE load order from each boot entry (x-core.x,
; then the three dialect entries) -- following (include ...) verbatim,
; honouring the %include-list-cell pre-seed that makes import/include-once of
; listed paths no-ops, and expanding (import ...) at its load slot -- and
; flags any load-time-evaluated form whose head (or def-class parent /
; interface reference) is a def-class name not yet defined at that point in
; the order.
;
; It also checks the pre-seed/include parallel-list invariant.  Raw `include`
; does NOT register a path (only include-once/import do), so a lib module
; loaded raw must appear in a pre-seed or a later import of it silently
; reloads the file mid-boot (the type/list.x double-load, the x-and/x-or ansi
; double-include that broke (Ansi disable-repl)).  Two extra finding kinds:
;   %%double-load   -- a path actually loaded twice in the simulated order
;   %%unregistered  -- a raw-included lib path never pre-seed registered
;                      (one import away from a double load)
; A finding in x-core.x repeats under each dialect entry -- noise only in
; failure output; the gate is zero findings.
;
; Deferred bodies are skipped: fn/op closures, def-class (method ...) bodies,
; '... data, and quasi outside unquote all evaluate after boot, when the
; full class set exists.
;
; Input: every lib .x path as a command-line argument (the wrapper supplies
; them via find; x-cli binds the command line as `args`).  Stdin carries only
; code -- a mid-stream (read) would consume the tool's own next form, so data
; rides argv.  The class inventory is built from ALL of lib, so a boot-time
; call to a class that only exists outside the boot closure is still
; recognized and flagged.
; Output: one line per finding, then "ok" iff there were none.

(import x/sys/file)

; Cached C instruments (cold path; fetched once).
(def %str-make (prim-ref 'str 'make))

; --- state cells ---
; loaded vs registered are DISTINCT sets, as in the real module system: a raw
; include loads without registering; the pre-seed registers without loading.
; Conflating them (the old single %loaded-cell) is exactly the false
; assumption that let the pre-seed drift hide from this lint.
(def %loaded-cell (pair () ()))    ; paths actually loaded (strings)
(def %registered-cell (pair () ())) ; paths on the include list: pre-seed + once/import
(def %raw-cell (pair () ()))       ; ((path . including-file) ...) raw lib includes
(def %defined-cell (pair () ()))   ; class names def-class'd so far (symbols)
(def %classes-cell (pair () ()))   ; ((name . file) ...) -- every def-class in lib
(def %findings-cell (pair () ()))  ; ((file kind detail) ...), newest first
(def %forms-cache-cell (pair () ())) ; ((path . forms) ...) -- phase 1 tokenizations

(def %cell-push!
  (fn (_ cell v) (set-first! cell (pair v (first cell)))))

; Symbols are interned per-base: eq? membership is sound for them.
(def %memq
  (fn (self x lst)
    (match
      ((null? lst) #f)
      ((eq? x (first lst)) #t)
      (#t (self x (rest lst))))))

; String atoms are NOT interned: path membership needs str=?.
(def %member-str
  (fn (self s lst)
    (match
      ((null? lst) #f)
      ((str=? s (first lst)) #t)
      (#t (self s (rest lst))))))

(def %assq
  (fn (self key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (first alist))
      (#t (self key (rest alist))))))

(def %assoc-str
  (fn (self key alist)
    (match
      ((null? alist) ())
      ((str=? key (first (first alist))) (first alist))
      (#t (self key (rest alist))))))

; --- file reading / parsing ---
(def %read-chunks
  (fn (self fd acc)
    (let ((buf (%str-make 65536)))
      (let ((n (File read fd buf 65536)))
        (match
          ((<= n 0) acc)
          (#t (self fd (Str8 append acc (substring buf 0 n)))))))))

(def %read-file
  (fn (_ path)
    (let ((fd (File open path 'rdonly)))
      (match
        ((< fd 0) (error (Str8 append "boot-order: cannot open " path)))
        (#t
          (let ((text (%read-chunks fd "")))
            (do (File close fd) text)))))))

; Trailing space so the tokenizer closes the final token (read-str drops an
; unterminated tail).  Cached across phases: phase 1 tokenizes every lib
; file for the inventory, phase 2 re-walks the boot closure.
(def %read-forms
  (fn (_ path)
    (let ((hit (%assoc-str path (first %forms-cache-cell))))
      (match
        ((null? hit)
          (let ((forms (Tok read-str (%base) (Str8 append (%read-file path) " "))))
            (do (%cell-push! %forms-cache-cell (pair path forms))
                forms)))
        (#t (rest hit))))))

; --- phase 1: def-class inventory over all of lib ---
(def %inventory-form ())
(def %inventory-list
  (fn (self forms file)
    (match
      ((pair? forms)
        (do (%inventory-form (first forms) file)
            (self (rest forms) file)))
      (#t ()))))
(set! %inventory-form
  (fn (self form file)
    (match
      ((pair? form)
        (match
          ((eq? (first form) 'lit) ())
          ((eq? (first form) 'def-class)
            (do (match
                  ((null? (%assq (first (rest form)) (first %classes-cell)))
                    (%cell-push! %classes-cell (pair (first (rest form)) file)))
                  (#t ()))
                (%inventory-list (rest (rest form)) file)))
          (#t (%inventory-list form file))))
      (#t ()))))

(def %inventory-files
  (fn (self paths)
    (match
      ((pair? paths)
        (do (%inventory-list (%read-forms (first paths)) (first paths))
            (self (rest paths))))
      (#t ()))))

; --- phase 2: simulate the boot load order ---
(def %walk-form ())
(def %process-file ())

(def %walk-list
  (fn (self forms file)
    (match
      ((pair? forms)
        (do (%walk-form (first forms) file)
            (self (rest forms) file)))
      (#t ()))))

; A class-name reference evaluated at load time: sound iff already defined.
(def %check-name
  (fn (_ name file form)
    (let ((entry (%assq name (first %classes-cell))))
      (match
        ((null? entry) ())
        ((%memq name (first %defined-cell)) ())
        (#t (%cell-push! %findings-cell (list file name (rest entry) form)))))))

(def %check-name-list
  (fn (self names file form)
    (match
      ((pair? names)
        (do (match
              ((symbol? (first names)) (%check-name (first names) file form))
              (#t ()))
            (self (rest names) file form)))
      (#t ()))))

; def-class body: (method ...) bodies are deferred; (static ...) recurses;
; (interface ...) is declared NAMES (not evaluated references); member
; values and (doc ...) evaluate at class-build time.
(def %walk-class-body
  (fn (self body file)
    (match
      ((pair? body)
        (do (let ((f (first body)))
              (match
                ((pair? f)
                  (match
                    ((eq? (first f) 'method) ())
                    ((eq? (first f) 'interface) ())
                    ((eq? (first f) 'static) (self (rest f) file))
                    (#t (%walk-form f file))))
                (#t ())))
            (self (rest body) file)))
      (#t ()))))

; quasi: only unquoted parts evaluate at load time.
(def %walk-quasi
  (fn (self form file)
    (match
      ((pair? form)
        (match
          ((eq? (first form) 'unquote) (%walk-form (first (rest form)) file))
          ((eq? (first form) 'unquote-splicing) (%walk-form (first (rest form)) file))
          (#t (do (self (first form) file)
                  (self (rest form) file)))))
      (#t ()))))

; The pre-seed: strings pushed onto the include list REGISTER those paths, so
; later import/include-once of them no-op.  They are not loaded by this.
(def %collect-strs
  (fn (self form)
    (match
      ((str? form) (%cell-push! %registered-cell form))
      ((pair? form) (do (self (first form)) (self (rest form))))
      (#t ()))))

(def %lib-path?
  (fn (_ path) (Str8 starts? "lib/" path)))

; A path about to be loaded that is ALREADY loaded is a double load -- report
; it and skip the re-walk (reality reloads the file; re-walking adds nothing
; the first walk didn't, and skipping keeps cyclic includes terminating).
(def %load-path
  (fn (_ path file form)
    (match
      ((%member-str path (first %loaded-cell))
        (%cell-push! %findings-cell (list file '%%double-load path form)))
      (#t (%process-file path)))))

; include: verbatim, loads unconditionally and does NOT register.
; include-once/require-once: no-op iff REGISTERED (pre-seed or a prior
; once/import) -- a raw include does not register, so a later once/import of
; that path reloads it in reality.  A non-literal or relative path can't be
; simulated -- report it rather than skip silently.
(def %do-include
  (fn (_ form file force)
    (let ((arg (first (rest form))))
      (match
        ((not (str? arg))
          (%cell-push! %findings-cell (list file () () form)))
        ((str=? arg "")
          (%cell-push! %findings-cell (list file () () form)))
        ; a ./ or ../ path resolves against the including file (module.x);
        ; nothing in the boot closure uses one -- report, don't mis-simulate
        ((eq? (str-ref arg 0) 46)
          (%cell-push! %findings-cell (list file () () form)))
        (force
          (do (match
                ((%lib-path? arg) (%cell-push! %raw-cell (pair arg file)))
                (#t ()))
              (%load-path arg file form)))
        ((%member-str arg (first %registered-cell)) ())
        (#t
          ; register BEFORE loading, like module.x -- cycle safety
          (do (%cell-push! %registered-cell arg)
              (%load-path arg file form)))))))

(def %do-import
  (fn (_ form file)
    (let ((name (first (rest form))))
      (match
        ((symbol? name)
          (let ((path (Str8 append "lib/" (Str8 append (symbol->str name) ".x"))))
            (match
              ((%member-str path (first %registered-cell)) ())
              (#t
                (do (%cell-push! %registered-cell path)
                    (%load-path path file form))))))
        (#t (%cell-push! %findings-cell (list file () () form)))))))

(set! %walk-form
  (fn (self form file)
    (match
      ((pair? form)
        (let ((h (first form)))
          (match
            ((eq? h 'lit) ())
            ((eq? h 'fn) ())
            ((eq? h 'op) ())
            ((eq? h 'method) ())
            ((eq? h 'quasi) (%walk-quasi (rest form) file))
            ((eq? h 'def-class)
              (do (%check-name-list (first (rest (rest form))) file form)
                  (%walk-class-body (rest (rest (rest form))) file)
                  (%cell-push! %defined-cell (first (rest form)))))
            ((eq? h 'include) (%do-include form file #t))
            ((eq? h 'include-once) (%do-include form file #f))
            ((eq? h 'require-once) (%do-include form file #f))
            ((eq? h 'import) (%do-import form file))
            ((eq? h 'set-first!)
              (do (match
                    ((eq? (first (rest form)) '%include-list-cell)
                      (%collect-strs (rest (rest form))))
                    (#t ()))
                  (%walk-list (rest form) file)))
            (#t
              (do (match
                    ((symbol? h) (%check-name h file form))
                    ((pair? h) (%walk-form h file))
                    (#t ()))
                  (%walk-list (rest form) file))))))
      (#t ()))))

(set! %process-file
  (fn (_ path)
    ; mark loaded BEFORE walking: cycle safety, and include-once semantics
    (do (%cell-push! %loaded-cell path)
        (%walk-list (%read-forms path) path))))

; --- report ---
(def %show-form-head
  (fn (_ form)
    (do (display "(")
        (display (first form))
        (match
          ((pair? (rest form))
            (do (display " ")
                (match
                  ((symbol? (first (rest form))) (display (first (rest form))))
                  (#t (write (first (rest form)))))))
          (#t ()))
        (display " ...)"))))

(def %report
  (fn (self findings)
    (match
      ((pair? findings)
        (do (let ((f (first findings)))
              (do (display (first f))
                  (display ": ")
                  (match
                    ((null? (first (rest f)))
                      (do (display "unresolvable include/import ")
                          (%show-form-head (first (rest (rest (rest f)))))))
                    ((eq? (first (rest f)) '%%double-load)
                      (do (display "double load of ")
                          (display (first (rest (rest f))))
                          (display " via ")
                          (%show-form-head (first (rest (rest (rest f)))))))
                    ((eq? (first (rest f)) '%%unregistered)
                      (do (display "raw include of ")
                          (display (first (rest (rest f))))
                          (display " is not pre-seed registered -- a later import reloads it")))
                    (#t
                      (do (%show-form-head (first (rest (rest (rest f)))))
                          (display " -- class ")
                          (display (first (rest f)))
                          (display " is defined later (")
                          (display (first (rest (rest f))))
                          (display ")"))))
                  (newline)))
            (self (rest findings))))
      (#t ()))))

; --- main ---
; Each boot entry is a separate simulation (fresh loaded/registered/defined
; state; the class inventory and tokenization cache persist).  After each
; walk, every raw-included lib path must have been registered somewhere in
; that entry's closure, or it is one import away from a double load.
(def %reset-run!
  (fn (_)
    (do (set-first! %loaded-cell ())
        (set-first! %registered-cell ())
        (set-first! %raw-cell ())
        (set-first! %defined-cell ()))))

(def %check-unregistered
  (fn (self raws)
    (match
      ((pair? raws)
        (do (match
              ((%member-str (first (first raws)) (first %registered-cell)) ())
              (#t (%cell-push! %findings-cell
                    (list (rest (first raws)) '%%unregistered
                          (first (first raws)) ()))))
            (self (rest raws))))
      (#t ()))))

(def %simulate
  (fn (_ entry)
    (do (%reset-run!)
        (%process-file entry)
        (%check-unregistered (first %raw-cell)))))

(def %main
  (fn (_ paths)
    (do (%inventory-files paths)
        (%simulate "lib/x-core.x")
        (%simulate "lib/x-base.x")
        (%simulate "lib/he.x")
        (%simulate "lib/xe.x")
        (%simulate "lib/rn.x")
        (match
          ((null? (first %findings-cell)) (do (display "ok") (newline)))
          (#t (%report (%reverse (first %findings-cell))))))))

; (rest args) skips argv[0] (the interpreter binary); the rest is the lib
; file list the wrapper passed on the command line.
(%main (rest args))
