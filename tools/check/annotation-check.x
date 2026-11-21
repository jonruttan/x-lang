; annotation-check.x -- test a documented closure's arguments against its
; annotations at each call.
;
; A (param NAME TYPE ...) form says what a parameter takes, and
; (Annotation ? v TYPE) asks whether a value fits.  AnnotationCheck puts the
; two together for a run of tests: it puts one form at the head of a
; documented closure's body, and on every call that form tests each annotated
; argument and records the ones that do not fit.  Nothing is raised: the call
; goes on as it would have, and the findings are read at the end.
;
; The doctest gate is the first user (tools/check/doctest-split.awk): each
; generated file installs the checks on its module's entries before the
; examples run, and its last case expects no finding.  An example that shows
; a function refusing an argument would be a finding of its own making, so
; the generator turns the checks off for a case that guards an error
; (tools/check/doctest.x).
;
; What is covered: a closure made by fn that a bare documented name or a
; Class/method name reaches, and of its parameters the ones annotated with
; something other than ANY.  A primitive, an operative and a wrapped
; combiner have no body to put the form in and are passed over.

(import x/core/fn)
(import x/doc/registry)
(import x/type/annotation)
(import x/type/env)

(def-class AnnotationCheck ()
  (static
    ; The findings, newest first, in the first of a pair:
    ; (KEY PARAMETER ANNOTATION TYPE-NAME) each.
    (%found (pair () ()))

    ; #t in the first of a pair while nothing is to be tested: while a test
    ; runs, since the test calls library functions that carry the form
    ; themselves, and while the checks are off.
    (%busy (pair #f ()))

    (method %noted? (self key name l)
      (match
        ((null? l) #f)
        ((if (eq? (first (first l)) key) (eq? (first (rest (first l))) name) #f) #t)
        (#t (self %noted? key name (rest l)))))

    ; One finding for a parameter, however many calls miss it.
    (method %note! (self key name t v)
      (let ((cell (self %found)))
        (unless (self %noted? key name (first cell))
          (%set-first! cell
            (pair (list key name t (guard (_ (lit ?)) (Type name v)))
                  (first cell))))))

    ; Whether v fits the row's annotation, noting it when it does not.  A
    ; row is (NAME TYPE REST? PASSED), and PASSED holds, in the first of a
    ; pair, the runtime types whose values have fitted: whether a value fits
    ; follows from its runtime type, so a type that has fitted is not asked
    ; about again.  nil and an object are asked about every time: nil has no
    ; type to remember, and whether an object fits depends on its class.
    (method %fits! (self key row v)
      (let ((name (first row))
            (t (first (rest row)))
            (passed (first (rest (rest (rest row))))))
        (if (Annotation ? v t)
          (unless (if (null? v) #t (object? v))
            (%set-first! passed (pair ((prim-ref (lit type) (lit of)) v) (first passed))))
          (self %note! key name t v))))

    ; The closure the installed form calls.  It walks the rows and the
    ; arguments together; a rest parameter's annotation is each item's type,
    ; so its row is asked of every item.  The walk is the closure's own and
    ; asks the engine for a value's type, so a call whose arguments are of
    ; types seen before costs a few comparisons.  Anything else goes to
    ; %fits!, where a failure is the test's own and is dropped: a check
    ; never changes what a call answers.
    (method %make (self key rows)
      (let ((busy (self %busy))
            (type-of (prim-ref (lit type) (lit of))))
        (def seen?
          (fn (go ty l)
            (match ((null? l) #f) ((eq? (first l) ty) #t) (#t (go ty (rest l))))))
        (def one
          (fn (_ row v)
            (unless (if (null? v) #f
                      (seen? (type-of v) (first (first (rest (rest (rest row)))))))
              (guard (_ ()) (self %fits! key row v)))))
        (def items
          (fn (go row xs)
            (when (pair? xs) (do (one row (first xs)) (go row (rest xs))))))
        (def walk
          (fn (go rs vals)
            (unless (null? rs)
              (do (if (first (rest (rest (first rs))))
                    (items (first rs) (first vals))
                    (one (first rs) (first vals)))
                  (go (rest rs) (rest vals))))))
        (fn (_ . vals)
          (unless (first busy)
            (do (%set-first! busy #t)
                (walk rows vals)
                (%set-first! busy #f))))))

    (method %type-str (self t) (if (symbol? t) (symbol->str t) t))

    ; The annotation NAME is documented with, as a string, or () when it
    ; has none or it is ANY.
    (method %type-of (self name triples)
      (match
        ((null? triples) ())
        ((eq? (first (first triples)) name)
          (let ((t (first (rest (first triples)))))
            (match ((null? t) ())
                   ((str=? (self %type-str t) "ANY") ())
                   (#t (self %type-str t)))))
        (#t (self %type-of name (rest triples)))))

    ; The tested parameters of ps, as (NAMES . ROWS).  Whether a parameter
    ; is the rest one is read from the parameter list, where it is the
    ; dotted tail: a doc form written apart from its definition records no
    ; rest mark.
    (method %rows (self ps triples names rows)
      (match
        ((null? ps) (pair (List reverse names) (List reverse rows)))
        ((not (pair? ps))
          (let ((t (self %type-of ps triples)))
            (if (null? t) (self %rows () triples names rows)
              (self %rows () triples (pair ps names) (pair (list ps t #t (pair () ())) rows)))))
        (#t
          (let ((t (self %type-of (first ps) triples)))
            (if (null? t) (self %rows (rest ps) triples names rows)
              (self %rows (rest ps) triples
                    (pair (first ps) names) (pair (list (first ps) t #f (pair () ())) rows)))))))

    (method %drop (self ps n)
      (if (= n 0) ps (if (pair? ps) (self %drop (rest ps) (- n 1)) ())))

    ; A body that already opens with the form: its head is a closure, where
    ; a written form's head is a symbol.
    (method %installed? (self body)
      (if (pair? (first body)) (eq? (Fn label (first (first body))) (lit fn)) #f))

    ; Put the form at the head of f's body.  The body list is the closure's
    ; own, so its first pair is rewritten in place: the form goes into it
    ; and the form that was there moves to a new pair behind it.  drop is
    ; how many leading parameters are not arguments of the documented call:
    ; the closure itself, and for a class method the receiver too.
    (method %install-one! (self key f drop)
      (let ((e (Doc entry key))
            (body (if (eq? (Fn label f) (lit fn)) (Fn body f) ())))
        (when (if (pair? body) (if (null? e) #f (not (self %installed? body))) #f)
          (let ((r (self %rows (self %drop (Fn params f) drop) (e params) () ())))
            (unless (null? (first r))
              (let ((old (pair (first body) (rest body))))
                (%set-first! body (pair (self %make key (rest r)) (first r)))
                (%set-rest! body old)))))))

    ; A bare name is read from the root; Class/method from the class's
    ; statics.  Any other key, a module's name among them, is passed over.
    (method %install-name! (self key)
      (let ((parts (Str8 split "/" (symbol->str key)))
            (str->sym (prim-ref (lit str) (lit ->sym))))
        (match
          ((null? (rest parts))
            (self %install-one! key (eval key (Env root)) 1))
          ((null? (rest (rest parts)))
            (let ((c (eval (str->sym (first parts)) (Env root))))
              (when (class? c)
                (self %install-one! key
                  (class-static-ref c (str->sym (first (rest parts)))) 2)))))))

    (method %install-names! (self names)
      (when (pair? names)
        (do (guard (_ ()) (self %install-name! (first names)))
            (self %install-names! (rest names)))))

    ; The names of the registry's entries from head back to stop.
    (method %names-since (self head stop acc)
      (match
        ((null? head) acc)
        ((eq? head stop) acc)
        (#t (self %names-since (rest head) stop
              (pair (%doc-entry-name (first head)) acc)))))

    ; Install the checks on every name in names that has a closure to carry
    ; them.  A name that reaches nothing is passed over.
    (method install! (self names)
      (%set-first! (self %busy) #t)
      (self %install-names! names)
      (%set-first! (self %busy) #f)
      ())

    ; Import module and install the checks on the names its import
    ; documents: the registry is a prepend-only list, so the entries ahead
    ; of the head remembered before the import are the new ones.
    (method import! (self module)
      (%doc-commit!)
      (let ((before (first %doc-registry-cell)))
        (eval! (list (lit import) module))
        (%doc-commit!)
        (self install! (self %names-since (first %doc-registry-cell) before ()))))

    ; Off and on again, for a case that passes an argument its callee
    ; refuses on purpose.  Nothing is tested while the checks are off.
    (method off! (self) (%set-first! (self %busy) #t) ())
    (method on! (self) (%set-first! (self %busy) #f) ())

    ; The findings, oldest first.
    (method found (self) (List reverse (first (self %found))))))
