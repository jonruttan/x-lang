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

    ; Every item of a rest parameter's list against its annotation.
    (method %test-items (self key name t xs)
      (when (pair? xs)
        (do (unless (Annotation ? (first xs) t) (self %note! key name t (first xs)))
            (self %test-items key name t (rest xs)))))

    ; rows holds one (NAME TYPE REST?) per tested parameter, in call order,
    ; and vals the arguments in the same order.  A rest parameter's
    ; annotation is each item's type.
    (method %test (self key rows vals)
      (unless (null? rows)
        (let ((name (first (first rows)))
              (t (first (rest (first rows))))
              (v (first vals)))
          (if (first (rest (rest (first rows))))
            (self %test-items key name t v)
            (unless (Annotation ? v t) (self %note! key name t v)))
          (self %test key (rest rows) (rest vals)))))

    ; The closure the installed form calls.  A failure inside the test is
    ; the test's own and is dropped, so a check never changes what a call
    ; answers.
    (method %make (self key rows)
      (let ((busy (self %busy)))
        (fn (_ . vals)
          (unless (first busy)
            (do (%set-first! busy #t)
                (guard (_ ()) (self %test key rows vals))
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
              (self %rows () triples (pair ps names) (pair (list ps t #t) rows)))))
        (#t
          (let ((t (self %type-of (first ps) triples)))
            (if (null? t) (self %rows (rest ps) triples names rows)
              (self %rows (rest ps) triples
                    (pair (first ps) names) (pair (list (first ps) t #f) rows)))))))

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
