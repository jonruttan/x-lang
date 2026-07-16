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
; This lint derives the EFFECTIVE load order from lib/x-core.x -- following
; (include ...) verbatim, honouring the %include-list-cell pre-seed that makes
; import/include-once of listed paths no-ops, and expanding (import ...) at
; its load slot -- and flags any load-time-evaluated form whose head (or
; def-class parent / interface reference) is a def-class name not yet defined
; at that point in the order.
;
; Deferred bodies are skipped: fn/op closures, def-class (method ...) bodies,
; (lit ...) data, and quasi outside unquote all evaluate after boot, when the
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
(def %str-make (prim-ref (lit str) (lit make)))

; --- state cells ---
(def %loaded-cell (pair () ()))    ; paths loaded or pre-seeded (strings)
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
    (let ((fd (File open path (lit rdonly))))
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
          ((eq? (first form) (lit lit)) ())
          ((eq? (first form) (lit def-class))
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
                    ((eq? (first f) (lit method)) ())
                    ((eq? (first f) (lit interface)) ())
                    ((eq? (first f) (lit static)) (self (rest f) file))
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
          ((eq? (first form) (lit unquote)) (%walk-form (first (rest form)) file))
          ((eq? (first form) (lit unquote-splicing)) (%walk-form (first (rest form)) file))
          (#t (do (self (first form) file)
                  (self (rest form) file)))))
      (#t ()))))

; The pre-seed: strings pushed onto the include list mark those paths loaded,
; so later import/include-once of them no-op.
(def %collect-strs
  (fn (self form)
    (match
      ((str? form) (%cell-push! %loaded-cell form))
      ((pair? form) (do (self (first form)) (self (rest form))))
      (#t ()))))

; include: verbatim, loads unconditionally.  include-once/require-once/import:
; no-op when the path is already on the include list.  A non-literal or
; relative path can't be simulated -- report it rather than skip silently.
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
        (force (%process-file arg))
        ((%member-str arg (first %loaded-cell)) ())
        (#t (%process-file arg))))))

(def %do-import
  (fn (_ form file)
    (let ((name (first (rest form))))
      (match
        ((symbol? name)
          (let ((path (Str8 append "lib/" (Str8 append (symbol->str name) ".x"))))
            (match
              ((%member-str path (first %loaded-cell)) ())
              (#t (%process-file path)))))
        (#t (%cell-push! %findings-cell (list file () () form)))))))

(set! %walk-form
  (fn (self form file)
    (match
      ((pair? form)
        (let ((h (first form)))
          (match
            ((eq? h (lit lit)) ())
            ((eq? h (lit fn)) ())
            ((eq? h (lit op)) ())
            ((eq? h (lit method)) ())
            ((eq? h (lit quasi)) (%walk-quasi (rest form) file))
            ((eq? h (lit def-class))
              (do (%check-name-list (first (rest (rest form))) file form)
                  (%walk-class-body (rest (rest (rest form))) file)
                  (%cell-push! %defined-cell (first (rest form)))))
            ((eq? h (lit include)) (%do-include form file #t))
            ((eq? h (lit include-once)) (%do-include form file #f))
            ((eq? h (lit require-once)) (%do-include form file #f))
            ((eq? h (lit import)) (%do-import form file))
            ((eq? h (lit set-first!))
              (do (match
                    ((eq? (first (rest form)) (lit %include-list-cell))
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
(def %main
  (fn (_ paths)
    (do (%inventory-files paths)
        (%process-file "lib/x-core.x")
        (match
          ((null? (first %findings-cell)) (do (display "ok") (newline)))
          (#t (%report (reverse (first %findings-cell))))))))

; (rest args) skips argv[0] (the interpreter binary); the rest is the lib
; file list the wrapper passed on the command line.
(%main (rest args))
