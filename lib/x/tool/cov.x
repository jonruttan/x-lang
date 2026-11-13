; cov.x -- Library coverage report
;
; Walks the env-alist, inspects procedure bodies for coverage flags
; (X_OBJ_FLAG_2 set by x-bin-profile), and reports covered/total nodes.
(module x/tool/cov)

; The base type handles, from their public door, fetched once at load.
(def %int (Type named INTEGER))
(def %ptr (Type named POINTER))
(def %string (Type named STRING))

; --- Platform detection ---

; Fetch the conversion dispatcher from the catalogue (registered by sys/convert.x).
; Fetch the raw-object prims from the catalogue (ns `obj` is de-registered, R5).
(import x/core/doors int->ptr obj->ptr obj-ref ptr->obj ptr-ref-word str-append type-of)

(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalogue (ns `type` is de-registered, R5).
(def %type-name (prim-ref 'type 'name))
; Fetch the ptr/ffi prims from the catalogue (ns `ptr`/`ffi` are de-registered, R5).



(def %cov-word-size
  (if (> (%cvt (%cvt 4294967296 %ptr) %int) 0) 8 4))
(def %cov-flags-offset (* 2 %cov-word-size))

(doc (def cov-word-size
  (fn (_) %cov-word-size))
  (returns INTEGER "Bytes in a machine word, 8 or 4")
  (example "(import x/tool/cov cov-word-size) (List includes? (cov-word-size) (list 4 8))" "#t")
  (sample "(cov-word-size)" "8 on a 64-bit engine, 4 on a 32-bit one")
  "Return the size of a machine word on this engine, in bytes.")

; --- Object flag inspection ---

; cov-flags, cov-cons? and cov-body are also how x/tool/profile reads the eval
; counts, and anything they call while it reads is counted with the program
; it measures.  So when they run they call only the engine's own forms and
; catalogue primitives -- match, first, rest, eq? and pointer reads -- and none
; of the library's functions.  What they compute once, at load, may use any.

; Object-ADDRESS cast via (obj ->ptr), never the convert catalogue: %cvt
; to %ptr on an INT node is a VALUE cast (the #277 ruling) -- it walked
; garbage for every int in a body.  The door is obj->ptr, imported above.
(doc (def cov-flags
  ((fn (_)
     (fn (_ obj)
       (match ((eq? obj ()) 0)
              (#t (ptr-ref-word (obj->ptr obj) %cov-flags-offset)))))
   ()))
  (param obj ANY "Object to read")
  (returns INTEGER "The object's flags word, or 0 for nil")
  (example "(import x/tool/cov cov-flags) (cov-flags ())" "0")
  "Return the flags word of an object's header.")

(doc (def cov-covered?
  (fn (_ obj) (> (& (cov-flags obj) 2) 0)))
  (param obj ANY "Object to check")
  (returns BOOL "True if object was evaluated (FLAG_2 set)")
  (sample "(cov-covered? (first (cov-body f)))" "#t under x-bin-profile once f has run; #f under an engine that does not mark")
  "Test whether an object was marked as evaluated by x-bin-profile.")

; Cons test by cached type-handle eq? (#342), REPAIRED for the type-label
; model (#402): a fn body is a C-BUILT spine carrying the structural-
; PAIR sentinel label -- its %type-name is NIL and its handle matches
; neither LIST nor PAIR, so the old name compare (and a handle-only
; compare) scored every body 0/0 and the whole sweep reported nothing.
; The sentinel is probed from a real fn's own body spine at load, and
; tested by raw type WORD (header word 1) -- an int compare, no
; navigation, safe on every object per the type-label-trap rule.
(doc (def cov-cons?
  ((fn (_)
     (def %t-list (type-of (list 1)))
     (def %t-pair (type-of (pair 1 2)))
     (def %tw (fn (_ o) (ptr-ref-word (obj->ptr o) %cov-word-size)))
     (def %spair-tw (%tw (obj-ref (fn (_ x) x) 1)))
     (fn (_ x)
       (match ((eq? x ()) #f)
              (#t ((fn (_ t)
                     (match ((eq? t %t-list) #t)
                            ((eq? t %t-pair) #t)
                            (#t (eq? (%tw x) %spair-tw))))
                   (type-of x))))))
   ()))
  (param x ANY "Object to test")
  (returns BOOL "True if x is a pair, a list cell or an engine-built spine cell")
  (example "(import x/tool/cov cov-cons?) (cov-cons? (list 1))" "#t")
  (example "(import x/tool/cov cov-cons?) (cov-cons? 5)" "#f")
  "Test whether an object is a cell a body walk can step through.")

; A procedure's state is (params body . env) and an operative's is
; (params envparam body . env), so the body is the second element of the
; one and the third of the other.  The state is data word 1 of either, read
; by its address rather than through (obj ref), which the library
; implements; an operative is told from a procedure by its type word.
(doc (def cov-body
  ((fn (_)
     (def %type-off (* %obj-slot-type %cov-word-size))
     (def %state-off (* (+ %obj-meta-len 1) %cov-word-size))
     (def %op-tw (ptr-ref-word (obj->ptr (op () _ ())) %type-off))
     (fn (_ val)
       ((fn (_ state)
          ((fn (_ tail)
             (match ((cov-cons? tail) (first tail))
                    (#t ())))
           (match ((cov-cons? state)
                   (match ((eq? (ptr-ref-word (obj->ptr val) %type-off) %op-tw)
                           (rest (rest state)))
                          (#t (rest state))))
                  (#t ()))))
        (ptr->obj (int->ptr (ptr-ref-word (obj->ptr val) %state-off))))))
   ()))
  (param val CALLABLE "Procedure or operative made by fn or op")
  (returns LIST "The body forms, or nil when there are none")
  (example "(import x/tool/cov cov-body) (cov-body (fn (_ x) (+ x 1)))" "(('+ 'x 1))")
  (example "(import x/tool/cov cov-body) (cov-body (op (a) e a))" "('a)")
  "Return the body forms of a procedure or an operative.")

; --- AST coverage counting ---

(doc (def cov-count-tree
  (fn (_ expr depth)
    ; Two counter cells serve the WHOLE walk (#342): the old walk
    ; allocated a fresh (list 0 0) and opened a guard frame per AST
    ; node.  cov-walk's per-function guard is the one that remains --
    ; a node-level error now skips that function's row instead of
    ; zeroing one subtree.
    (def cov-cell (pair 0 ()))
    (def tot-cell (pair 0 ()))
    (def go
      (fn (self e d)
        (match
          ((null? e) ())
          ((> d 15) ())
          ((cov-cons? e)
            (do
              (if (cov-covered? e)
                (%set-first! cov-cell (+ (first cov-cell) 1)) ())
              (%set-first! tot-cell (+ (first tot-cell) 1))
              (self (first e) (+ d 1))
              (self (rest e) (+ d 1))))
          (#t ()))))
    (go expr depth)
    (list (first cov-cell) (first tot-cell))))
  (param expr ANY "AST node to walk")
  (param depth INTEGER "Current recursion depth (limit 15)")
  (returns LIST "(covered total) pair")
  (example "(import x/tool/cov cov-count-tree) (first (rest (cov-count-tree (list 1 2) 0)))" "2")
  (sample "(cov-count-tree (cov-body f) 0)" "(COVERED TOTAL): of the body's cells, those x-bin-profile marked as run, and all of them")
  "Count covered and total AST nodes in a tree.")

; --- Per-function check ---

(doc (def cov-check-fn
  (fn (_ name val tsv-mode)
    (unless (not (str=? (%type-name val) "PROCEDURE"))
      ; A procedure's slot 1 is the spine (params body env) -- the body
      ; FORMS are its second element (#402).  Walking slot 1 whole runs
      ; off into the captured env (only the depth limit bounded it).
      (let ((body (cov-body val)))
        (let ((counts (cov-count-tree body 0)))
          (let ((cov (first counts))
                (total (first (rest counts))))
            (if (> total 0)
              (if tsv-mode
                (do (display "COV\t") (write name) (display #"\t{cov}\t{total}\n"))
                (list name cov total)))))))))
  (param name SYMBOL "Function name")
  (param val ANY "Function value to inspect")
  (param tsv-mode BOOL "Output TSV format if true")
  (returns LIST "(name covered total) or nil")
  (example "(import x/tool/cov cov-check-fn) (first (cov-check-fn 'inc (fn (_ x) (+ x 1)) #f))" "'inc")
  (sample "(cov-check-fn 'inc inc #f)" "('inc COVERED TOTAL), the counts cov-count-tree takes of inc's body")
  "Check coverage for a single function.")

; --- Per-class check (#408) ---

(doc (def cov-check-class
  (fn (_ cname c tsv-mode)
    ; The library's surface lives in class methods post-"functions into
    ; classes" -- top-level bare fns are a handful of wrappers.  A class
    ; is a %class instance whose payload (readable with first, the
    ; custom-type convention) is a keyed alist; the methods / s-methods
    ; rows hold name->handler alists, and each stored handler is a
    ; PROCEDURE with the standard (params body env) spine, so
    ; cov-check-fn reads it directly.  Own methods only: walking every
    ; class's own alists covers each method exactly once.
    (def %asc
      (fn (self k al)
        (if (null? al) ()
          (if (eq? (first (first al)) k) (rest (first al))
            (self k (rest al))))))
    (def %row-walk
      (fn (self prefix al acc)
        (if (null? al) acc
          (let ((r (guard (_ ())
                     (cov-check-fn
                       (str-append prefix
                         (%cvt (first (first al)) %string))
                       (rest (first al)) tsv-mode))))
            (self prefix (rest al)
                  (if (null? r) acc (pair r acc)))))))
    (def data (guard (_ ()) (first c)))
    (def prefix (str-append (%cvt cname %string) "/"))
    (%row-walk prefix (%asc (lit methods) data)
               (%row-walk prefix (%asc (lit s-methods) data) ()))))
  (param cname SYMBOL "Class name (row prefix)")
  (param c CLASS "Class value to inspect")
  (param tsv-mode BOOL "Output TSV format if true")
  (returns LIST "List of (name covered total) rows (empty in TSV mode)")
  (example "(import x/tool/cov cov-check-class) (List includes? \"Iter/next\" (List map first (cov-check-class 'Iter Iter #f)))" "#t")
  "Check coverage of every method a class defines itself.")

; --- Env-alist walker ---

(doc (def cov-walk
  (fn (self alist n tsv-mode)
    (unless (or (null? alist) (> n 5000))
      (do
        (guard (_ ())
          (let ((name (first (first alist)))
                (val (rest (first alist))))
            (if (symbol? name)
              (if (procedure? val)
                (cov-check-fn name val tsv-mode)
                (if (class? val)
                  (cov-check-class name val tsv-mode) ())))))
        (self (rest alist) (+ n 1) tsv-mode)))))
  (param alist LIST "Environment alist to walk")
  (param n INTEGER "Counter (limit 5000)")
  (param tsv-mode BOOL "Output TSV format if true")
  (sample "(cov-walk (list (pair 'inc (fn (_ x) (+ x 1)))) 0 #t)" "one tab-separated row a procedure: COV, 'inc, its covered count and its total (0 and 4 under an engine that does not mark)")
  "Walk an environment alist checking coverage on each procedure and class.")

; --- Library boundary ---

(doc (def cov-skip-to-library
  (fn (self alist)
    (unless (null? alist)
      (if (and (symbol? (first (first alist)))
               (str=? (%cvt (first (first alist)) %string)
                          "%cov-library-end"))
        (rest alist)
        (self (rest alist))))))
  (param alist LIST "Environment alist")
  (returns LIST "Alist from library boundary marker onward")
  (example "(import x/tool/cov cov-skip-to-library) (cov-skip-to-library (list (pair 'a 1) (pair '%cov-library-end 0) (pair 'b 2)))" "(('b . 2))")
  "Skip past test definitions to the library boundary marker.")

; --- Branch coverage ---

; Which forms have branches, and of what kind, comes from the construct
; declarations (lib/x/constructs.x and a lang's own), never from names
; written here.  A declaration is (name (key . value) ...); its branch value
; is one of:
;   cond     (if TEST THEN ELSE): THEN and ELSE are branches
;   clauses  each clause's first body form is a branch (match, cond)
;   short    each argument is a branch (and, or)
;   guard    the handler of (guard (VAR HANDLER) BODY ...) is a branch
; Names are compared as strings: the declarations may be read in another
; base, and a symbol is interned per base.
(doc (def cov-branches
  ((fn (_)
     (def name (fn (_ x) (%cvt x %string)))
     (def branch-kind
       (fn (self props)
         (match ((null? props) ())
                ((and (pair? (first props))
                      (str=? (name (first (first props))) "branch"))
                 (name (rest (first props))))
                (#t (self (rest props))))))
     (def find
       (fn (self key al)
         (match ((null? key) ())
                ((null? al) ())
                ((str=? (first (first al)) key) (rest (first al)))
                (#t (self key (rest al))))))
     ; A nil branch has nothing to evaluate, so nothing to miss.
     (def ran? (fn (_ form) (if (null? form) #t (cov-covered? form))))
     (def each
       (fn (self f xs)
         (when (pair? xs)
           (do (f (first xs)) (self f (rest xs))))))
     ; The walkers, one a kind: (form check walk), where check counts a
     ; branch and walk descends into a form.
     (def walk-if
       (fn (_ form check walk)
         (def args (rest form))
         (when (pair? args)
           (do (walk (first args))
               (def then-else (rest args))
               (when (pair? then-else)
                 (do (check (lit if-then) (first then-else))
                     (walk (first then-else))
                     (when (pair? (rest then-else))
                       (do (check (lit if-else) (first (rest then-else)))
                           (walk (first (rest then-else)))))))))))
     (def walk-clauses
       (fn (_ form check walk)
         (each (fn (_ clause)
                 (when (and (pair? clause) (pair? (rest clause)))
                   (do (check (lit clause) (first (rest clause)))
                       (walk (first (rest clause))))))
               (rest form))))
     (def walk-short
       (fn (_ form check walk)
         (each (fn (_ arg) (check (lit short-circuit) arg) (walk arg))
               (rest form))))
     (def walk-guard
       (fn (_ form check walk)
         (def clause (first (rest form)))
         (when (and (pair? clause) (pair? (rest clause)))
           (do (check (lit guard-handler) (first (rest clause)))
               (walk (first (rest clause)))))
         (each walk (rest (rest form)))))
     (def walkers
       (list (pair "cond" walk-if) (pair "clauses" walk-clauses)
             (pair "short" walk-short) (pair "guard" walk-guard)))
     ; ((name . walker) ...) for the declared constructs that have branches.
     (def table
       (fn (self entries acc)
         (if (null? entries) acc
           (let ((w (find (branch-kind (rest (first entries))) walkers)))
             (self (rest entries)
                   (if (null? w) acc
                     (pair (pair (name (first (first entries))) w) acc)))))))
     (fn (_ forms constructs)
       (def tab (table constructs ()))
       (def covered (pair 0 ()))
       (def total (pair 0 ()))
       (def missed (pair () ()))
       (def check
         (fn (_ label form)
           (%set-first! total (+ (first total) 1))
           (if (ran? form)
             (%set-first! covered (+ (first covered) 1))
             (%set-first! missed (pair (list label form) (first missed))))))
       (def walk
         (fn (self form)
           (when (pair? form)
             (if (not (symbol? (first form)))
               (each self form)
               (let ((w (find (name (first form)) tab)))
                 (if (null? w) (each self form) (w form check self)))))))
       (each walk forms)
       (list (first covered) (first total) (List reverse (first missed)))))
   ()))
  (param forms LIST "Top-level forms, after they have been evaluated")
  (param constructs LIST "Construct declarations, each (name (key . value) ...)")
  (returns LIST "(covered total uncovered), uncovered a list of (label form) in source order")
  (example "(import x/tool/cov cov-branches) (first (rest (cov-branches (lit ((if c (f 1) (g 2)))) (lit ((if (branch . cond)))))))" "2")
  (sample "(cov-branches forms constructs)" "(3 4 ((if-else (g 2)))) once the forms have run under x-bin-profile and one else branch never did")
  "Count the branches in forms that evaluation reached, and list those it did not.")

(doc (provide x/tool/cov
  cov-word-size cov-flags cov-covered? cov-cons? cov-body
  cov-count-tree cov-check-fn cov-check-class cov-walk
  cov-skip-to-library cov-branches)
  (example "(import x/tool/cov cov-cons? cov-body) (cov-cons? (cov-body (fn (_ x) x)))" "#t")
  "Library coverage analysis for x-bin-profile instrumented code.")
