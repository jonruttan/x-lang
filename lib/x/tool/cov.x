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

(doc (def cov-word-size
  (fn (_) %cov-word-size))
  (returns INTEGER "Bytes in a machine word, 8 or 4")
  "Return the size of a machine word on this engine, in bytes.")

; --- Object flag inspection ---

; cov-flags, cov-cons? and cov-body are also how x/tool/profile reads the eval
; counts, and anything they call while it reads is counted with the program
; it measures.  So when they run they call only the engine's own forms and
; catalog primitives -- match, first, rest, eq? and pointer reads -- and none
; of the library's functions.  What they compute once, at load, may use any.

; Object-ADDRESS cast via (obj ->ptr), never the convert catalog: %cvt
; to %ptr on an INT node is a VALUE cast (the #277 ruling) -- it walked
; garbage for every int in a body.  The prim rides a closure capture,
; not a new module global (the percent-globals budget stays at 8).
(doc (def cov-flags
  ((fn (_)
     (def %o->p (prim-ref 'obj '->ptr))
     (fn (_ obj)
       (match ((eq? obj ()) 0)
              (#t (%ptr-ref-word (%o->p obj) %cov-flags-offset)))))
   ()))
  (param obj ANY "Object to read")
  (returns INTEGER "The object's flags word, or 0 for nil")
  "Return the flags word of an object's header.")

(doc (def cov-covered?
  (fn (_ obj) (> (& (cov-flags obj) 2) 0)))
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
(doc (def cov-cons?
  ((fn (_)
     (def %t-of (prim-ref 'type 'of))
     (def %t-list (%t-of (list 1)))
     (def %t-pair (%t-of (pair 1 2)))
     (def %o->p (prim-ref 'obj '->ptr))
     (def %tw (fn (_ o) (%ptr-ref-word (%o->p o) %cov-word-size)))
     (def %spair-tw (%tw (%obj-ref (fn (_ x) x) 1)))
     (fn (_ x)
       (match ((eq? x ()) #f)
              (#t ((fn (_ t)
                     (match ((eq? t %t-list) #t)
                            ((eq? t %t-pair) #t)
                            (#t (eq? (%tw x) %spair-tw))))
                   (%t-of x))))))
   ()))
  (param x ANY "Object to test")
  (returns BOOL "True if x is a pair, a list cell or an engine-built spine cell")
  "Test whether an object is a cell a body walk can step through.")

; A procedure's state is (params body . env) and an operative's is
; (params envparam body . env), so the body is the second element of the
; one and the third of the other.  The state is data word 1 of either, read
; by its address rather than through (obj ref), which the library
; implements; an operative is told from a procedure by its type word.
(doc (def cov-body
  ((fn (_)
     (def %o->p (prim-ref 'obj '->ptr))
     (def %p->o (prim-ref 'ptr '->obj))
     (def %i->p (prim-ref 'int '->ptr))
     (def %type-off (* %obj-slot-type %cov-word-size))
     (def %state-off (* (+ %obj-meta-len 1) %cov-word-size))
     (def %op-tw (%ptr-ref-word (%o->p (op () _ ())) %type-off))
     (fn (_ val)
       ((fn (_ state)
          ((fn (_ tail)
             (match ((cov-cons? tail) (first tail))
                    (#t ())))
           (match ((cov-cons? state)
                   (match ((eq? (%ptr-ref-word (%o->p val) %type-off) %op-tw)
                           (rest (rest state)))
                          (#t (rest state))))
                  (#t ()))))
        (%p->o (%i->p (%ptr-ref-word (%o->p val) %state-off))))))
   ()))
  (param val CALLABLE "Procedure or operative made by fn or op")
  (returns LIST "The body forms, or nil when there are none")
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
  (param n INTEGER "Counter (limit 5000)")
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
  cov-word-size cov-flags cov-covered? cov-cons? cov-body
  cov-count-tree cov-check-fn cov-check-class cov-walk
  cov-skip-to-library)
  "Library coverage analysis for x-bin-profile instrumented code.")
