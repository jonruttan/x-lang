; cov.x -- Library coverage report
;
; Walks the env-alist, inspects procedure bodies for coverage flags
; (X_OBJ_FLAG_2 set by x-bin-profile), and reports covered/total nodes.

; --- Platform detection ---

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj-ref (prim-ref 'obj 'ref))

(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-name (prim-ref 'type 'name))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-ref-word (prim-ref 'ptr 'ref-word))



(def %cov-word-size
  (if (> (%cvt (%cvt 4294967296 %ptr) %int) 0) 8 4))
(def %cov-flags-offset (* 2 %cov-word-size))

; --- Object flag inspection ---

; Object-ADDRESS cast via (obj ->ptr), never the convert catalog: %cvt
; to %ptr on an INT node is a VALUE cast (the #277 ruling) -- it walked
; garbage for every int in a body.  The prim rides a closure capture,
; not a new module global (the percent-globals budget stays at 8).
(def %cov-obj-flags
  ((fn (_)
     (def %o->p (prim-ref 'obj '->ptr))
     (fn (_ obj)
       (if (null? obj) 0
         (%ptr-ref-word (%o->p obj) %cov-flags-offset))))
   ()))

(doc (def cov-covered?
  (fn (_ obj) (> (& (%cov-obj-flags obj) 2) 0)))
  (param obj ANY "Object to check")
  (returns BOOL "True if object was evaluated (FLAG_2 set)")
  "Test whether an object was marked as evaluated by x-bin-profile.")

; Cons test by cached type-handle eq? (#342), REPAIRED for the type-tag
; model (#402): a fn body is a C-BUILT spine carrying the structural-
; PAIR sentinel tag -- its %type-name is NIL and its handle matches
; neither LIST nor PAIR, so the old name compare (and a handle-only
; compare) scored every body 0/0 and the whole sweep reported nothing.
; The sentinel is probed from a real fn's own body spine at load, and
; tested by raw type WORD (header word 1) -- an int compare, no
; navigation, safe on every object per the type-tag-trap rule.
(def %cov-is-cons?
  ((fn (_)
     (def %t-of (prim-ref 'type 'of))
     (def %t-list (%t-of (list 1)))
     (def %t-pair (%t-of (pair 1 2)))
     (def %o->p (prim-ref 'obj '->ptr))
     (def %tw (fn (_ o) (%ptr-ref-word (%o->p o) %cov-word-size)))
     (def %spair-tw (%tw (%obj-ref (fn (_ x) x) 1)))
     (fn (_ x)
       (if (null? x) #f
         (let ((t (%t-of x)))
           (if (eq? t %t-list) #t
             (if (eq? t %t-pair) #t
               (eq? (%tw x) %spair-tw)))))))
   ()))

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
        (if (null? e) ()
          (if (> d 15) ()
            (if (%cov-is-cons? e)
              (do
                (if (cov-covered? e)
                  (%set-first! cov-cell (+ (first cov-cell) 1)) ())
                (%set-first! tot-cell (+ (first tot-cell) 1))
                (self (first e) (+ d 1))
                (self (rest e) (+ d 1)))
              ())))))
    (go expr depth)
    (list (first cov-cell) (first tot-cell))))
  (param expr ANY "AST node to walk")
  (param depth INT "Current recursion depth (limit 15)")
  (returns LIST "(covered total) pair")
  "Count covered and total AST nodes in a tree.")

; --- Per-function check ---

(doc (def cov-check-fn
  (fn (_ name val tsv-mode)
    (unless (not (str=? (%type-name val) "PROCEDURE"))
      ; A procedure's slot 1 is the spine (params body env) -- the body
      ; FORMS are its second element (#402).  Walking slot 1 whole runs
      ; off into the captured env (only the depth limit bounded it).
      (let ((body (let ((spine (%obj-ref val 1)))
                    (if (%cov-is-cons? spine)
                      (if (%cov-is-cons? (rest spine))
                        (first (rest spine)) ())
                      ()))))
        (let ((counts (cov-count-tree body 0)))
          (let ((cov (first counts))
                (total (first (rest counts))))
            (if (> total 0)
              (if tsv-mode
                (do (display "COV\t") (write name) (display $"\t{cov}\t{total}\n"))
                (list name cov total)))))))))
  (param name SYMBOL "Function name")
  (param val ANY "Function value to inspect")
  (param tsv-mode BOOL "Output TSV format if true")
  (returns LIST "(name covered total) or nil")
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
                       (%str-append prefix
                         (%cvt (first (first al)) %string))
                       (rest (first al)) tsv-mode))))
            (self prefix (rest al)
                  (if (null? r) acc (pair r acc)))))))
    (def data (guard (_ ()) (first c)))
    (def prefix (%str-append (%cvt cname %string) "/"))
    (%row-walk prefix (%asc (lit methods) data)
               (%row-walk prefix (%asc (lit s-methods) data) ()))))
  (param cname SYMBOL "Class name (row prefix)")
  (param c CLASS "Class value to inspect")
  (param tsv-mode BOOL "Output TSV format if true")
  (returns LIST "List of (name covered total) rows (empty in TSV mode)")
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
  (param n INT "Counter (limit 5000)")
  (param tsv-mode BOOL "Output TSV format if true")
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
  "Skip past test definitions to the library boundary marker.")

(doc (provide x/tool/cov
  cov-covered? cov-count-tree cov-check-fn cov-check-class cov-walk
  cov-skip-to-library)
  "Library coverage analysis for x-bin-profile instrumented code.")
