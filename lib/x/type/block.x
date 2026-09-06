; block.x -- block-form methods: (subject sel (names ...) body ...)
;
; A higher-order method normally takes a callable:
;
;   (List map (fn (_ x) (* x 10)) xs)
;
; The block form lets the call site write the parameter names and the body
; directly, with no (fn ...) wrapper:
;
;   (List map (x) (* x 10) xs)
;   (List map (x i) (list i x) xs)        ; a second name is the 0-based index
;
; NOTHING IN THE DISPATCH PATH CHANGES.  A method stored as an `op` already
; receives its argument FORMS plus the caller's env: %class-call-handler
; tail-evals (m class . forms) for a value send, %class-dispatch does the same
; for the prefix form, and %object-dispatch does it for an instance send.  So
; this is a wrapper over the stored method, and a selector nobody wraps pays
; nothing -- no test added to the hot dispatch path.
;
; WHY AN OPERATIVE AND NOT A SHORTER LAMBDA.  The optional index is the point.
; An applicative method cannot know how many parameters its callback declared:
; the language has no arity introspection, and calls are lenient, so a
; two-parameter callback handed one argument silently binds nil rather than
; failing.  An operative SEES the binding list, so the block's NAME COUNT can
; select the callback shape at the call site.
;
; TWO FACTS VARY PER SELECTOR, both declared at wrap time:
;   SHAPE     what the names mean -- element (the default), pair, fold, binary
;   TRAILING  how many argument forms follow the callback.  map/filter/for-each
;             take 1 (the subject, which the value handler splices last); fold
;             takes 2 (init and subject); an instance method takes 0, its
;             receiver being self.
;
; HAZARD.  After wrapping, the stored method IS the operative, so (method-of
; Class sel) -- the de-dispatch door (#332) -- returns an op, and calling that
; handle directly would pass unevaluated forms.  Do not de-dispatch a
; block-enabled selector.  Nothing in the library does today: the resolve-once
; door is used only for start/done?/step and Char upcase/downcase.

(import x/type/class)

(def-class Block ()
  (doc "Block-form methods: give a higher-order method a (names ...) body ... call shape.")

  (static
    ; --- guarded list walks --------------------------------------------
    ; (first ()) and (rest ()) are UNDEFINED (docs/spec.md) and reach a raw
    ; dereference, and a zero- or one-argument send arrives here with a short
    ; list, so every walk below tests before it steps.

    (method %all-syms? (self xs)
      (if (null? xs) #t
        (and (pair? xs) (and (symbol? (first xs)) (recur self (rest xs))))))

    (method %len>=? (self xs n)
      (if (< n 1) #t (and (pair? xs) (recur self (rest xs) (- n 1)))))

    (method %name-count (self xs)
      (if (null? xs) 0 (+ 1 (recur self (rest xs)))))

    ; All but the last n elements, and the last n elements.  Together they
    ; split a send's tail into body forms and trailing argument forms.
    (method %but-last-n (self xs n)
      (if (self %len>=? xs (+ n 1)) (pair (first xs) (recur self (rest xs) n)) ()))

    (method %last-n (self xs n)
      (if (self %len>=? xs (+ n 1)) (recur self (rest xs) n) xs))

    (method %eval-each (self xs e)
      (if (null? xs) () (pair (eval (first xs) e) (recur self (rest xs) e))))

    ; --- recognising a block send --------------------------------------
    ; Block form iff the first argument form is a non-empty list of symbols
    ; and the send is long enough to carry a body plus the trailing
    ; arguments.  An applicative call puts a CALLABLE in that seat -- a
    ; symbol, a (fn ...) form, or a call -- and a bare list of symbols is
    ; none of those.
    ;
    ; The one residual collision is a variadic send whose callable is itself
    ; computed from symbols: (List map (make-f x) a b) reads as a block.
    ; Spell that one with an explicit (fn ...), or bind the callable first.
    (method %block-call? (self args n)
      (and (self %len>=? args n)
        (and (pair? (first args)) (self %all-syms? (first args)))))

    ; --- shapes --------------------------------------------------------
    ; A shape turns the block closure into the callback the unchanged
    ; applicative method already expects.  Each validates its own arity,
    ; because "one or two names" is not the rule everywhere -- fold's
    ; callback is genuinely binary.

    (method %shape-error (self what n)
      (error (%str-append what (%cvt n %string))))

    ; element: (x) is the element; (x i) is the element and then a 0-based
    ; index.  The counter is a box owned by this send, so nested traversals
    ; never share it -- one closure and one box per send, nothing per element.
    (method %shape-element (self blk n)
      (match
        ((eq? n 1) blk)
        ((eq? n 2)
          (let ((box (list 0)))
            (fn (_ x)
              (let ((i (first box)))
                (%set-first! box (+ i 1))
                (blk x i)))))
        (#t (self %shape-error
              "block takes (element) or (element index), got names: " n))))

    ; pair: (p) is the (key . value) pair as it stands; (k v) destructures it.
    ; Dict hands its callback a pair, so on a Dict a second name is the value
    ; -- not an index.
    (method %shape-pair (self blk n)
      (match
        ((eq? n 1) blk)
        ((eq? n 2) (fn (_ p) (blk (first p) (rest p))))
        (#t (self %shape-error
              "block takes (pair) or (key value), got names: " n))))

    ; fold: the callback is genuinely binary -- (acc element) -- with an
    ; optional third name for the index.
    (method %shape-fold (self blk n)
      (match
        ((eq? n 2) blk)
        ((eq? n 3)
          (let ((box (list 0)))
            (fn (_ acc x)
              (let ((i (first box)))
                (%set-first! box (+ i 1))
                (blk acc x i)))))
        (#t (self %shape-error
              "block takes (acc element) or (acc element index), got names: " n))))

    ; binary: a comparator or reducer over two elements.  No index -- there is
    ; no single position to count.
    (method %shape-binary (self blk n)
      (if (eq? n 2) blk
        (self %shape-error "block takes (a b), got names: " n)))

    (method %adapt (self shape blk n)
      (match
        ((eq? shape (lit pair))   (self %shape-pair blk n))
        ((eq? shape (lit fold))   (self %shape-fold blk n))
        ((eq? shape (lit binary)) (self %shape-binary blk n))
        (#t                  (self %shape-element blk n))))

    ; The block closure is built in the CALLER's env, so the body closes over
    ; the call site exactly as an inline (fn ...) would.
    (method %block-fn (self names body e)
      (eval (pair (lit fn) (pair (pair (lit _) names) body)) e))

    ; The operative that replaces the stored method.  `recv` is argument 0
    ; either way: the class for a static method, the instance for an instance
    ; method.  The applicative path re-drives the original through tail-eval
    ; with the receiver spliced as (lit V), so a list-valued subject stays data
    ; and every existing call site -- variadic ones included -- keeps its exact
    ; behaviour.
    (method %block-op (self m shape trailing)
      (op (recv . args) e
        (if (self %block-call? args (+ 2 trailing))
          (apply m
            (pair recv
              (pair (self %adapt shape
                      (self %block-fn (first args)
                            (self %but-last-n (rest args) trailing) e)
                      (self %name-count (first args)))
                    (self %eval-each (self %last-n (rest args) trailing) e))))
          (tail-eval (pair m (pair (list (lit lit) recv) args)) e))))

    (method %imethod-of (self class sel)
      (let ((itab (first (%class-hot class))))
        (%entry-method (%tab-find! itab itab sel))))

    (method method! (self (param class CLASS "Class owning the method")
                          (param sel SYMBOL "Selector to give a block form")
                        . (param opts LIST "Optional shape symbol, then trailing-argument count"))
      (doc "Give a higher-order method a block form: (subject sel (names ...) body ...)."
        (returns ANY "The installed operative")
        (note "Shapes: element (default) -- (x) or (x index); pair -- (p) or (key value);")
        (note "fold -- (acc x) or (acc x index); binary -- (a b), no index.")
        (note "Trailing defaults to 1 for a static method (the subject) and 0 for an")
        (note "instance method (the receiver is self); fold needs 2 (init, subject).")
        (note "The applicative form keeps working unchanged, and (help Class/sel)")
        (note "still answers from the doc registry.")
        (note "Do NOT (method-of Class sel) a block-enabled selector: the stored")
        (note "method is now an operative and a direct call would not evaluate.")
        (example "(do (Block method! List 'map) (List map (x) (* x 2) (list 1 2)))" "(2 4)"))
      (let ((shape (if (null? opts) () (first opts)))
            (sm (method-of class sel)))
        (if (null? sm)
          (let ((im (self %imethod-of class sel)))
            (when (null? im)
              (error (%str-append "Block method!: no such method "
                                  (symbol->str sel))))
            (class def-method! sel
              (self %block-op im shape
                (if (self %len>=? opts 2) (first (rest opts)) 0))))
          (class def-static! sel
            (self %block-op sm shape
              (if (self %len>=? opts 2) (first (rest opts)) 1))))))))

; Each class wires its own selectors, beside the methods being wrapped -- this
; file is the mechanism only, and never reaches down into a collection.  See
; the (Block method! ...) lines at the foot of list.x, vector.x, iter.x,
; seq.x, gen.x, dict.x and set.x.

(doc (provide x/type/block Block)
  (note "The operative sees the binding list, which is what makes the optional")
  (note "index possible: the language has no arity introspection.")
  (example "(List map (x i) (list i x) (list 7 8))" "((0 7) (1 8))")
  "Block-form methods: write a callback's names and body at the call site.")
