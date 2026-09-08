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
;   (List map (i x) (list i x) xs)        ; two names: the 0-based index, then the element
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
; THREE FACTS VARY PER SELECTOR, all declared at wrap time:
;   SHAPE     what the names mean -- element (the default), pair, fold,
;             binary, thunk (no names: `()`, for a lazy default)
;   TRAILING  how many argument forms follow the callback.  map/filter/for-each
;             take 1 (the subject, which the value handler splices last); fold
;             takes 2 (init and subject); an instance method takes 0, its
;             receiver being self.
;   POSITION  where the callback sits, when it is not first.  List's
;             constructor-count rule puts the count ahead of it -- (List times
;             n f), (List adjust n f lst) -- so those wrap at position 1, and
;             the forms before the callback evaluate in the caller's env.
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
    ; `pos` is where the binding list sits; `n` the minimum send length
    ; (leading forms + names + one body form + trailing).  `()` is accepted
    ; as a binding list -- the thunk shape -- and each shape validates its
    ; own count, so `()` in an element seat still fails, only clearly.
    (method %block-call? (self args pos n)
      (and (self %len>=? args n)
        (let ((names (self %nth args pos)))
          (and (or (null? names) (pair? names)) (self %all-syms? names)))))

    (method %nth (self xs i)
      (if (null? xs) () (if (< i 1) (first xs) (recur self (rest xs) (- i 1)))))

    (method %take-n (self xs n)
      (if (< n 1) () (if (null? xs) () (pair (first xs) (recur self (rest xs) (- n 1))))))

    (method %drop-n (self xs n)
      (if (< n 1) xs (if (null? xs) () (recur self (rest xs) (- n 1)))))

    (method %append (self a b)
      (if (null? a) b (pair (first a) (recur self (rest a) b))))

    ; --- shapes --------------------------------------------------------
    ; A shape turns the block closure into the callback the unchanged
    ; applicative method already expects.  Each validates its own arity,
    ; because "one or two names" is not the rule everywhere -- fold's
    ; callback is genuinely binary.

    (method %shape-error (self what n)
      (error (%str-append what (%cvt n %string))))

    ; element: (x) is the element; (i x) is the 0-based index and THEN the
    ; element -- index first, the order Gen enumerate's (index . value) pair
    ; already fixed for this library.  The counter is a box owned by this
    ; send, so nested traversals never share it -- one closure and one box
    ; per send, nothing per element.
    (method %shape-element (self blk n)
      (match
        ((eq? n 1) blk)
        ((eq? n 2)
          (let ((box (list 0)))
            (fn (_ x)
              (let ((i (first box)))
                (%set-first! box (+ i 1))
                (blk i x)))))
        (#t (self %shape-error
              "block takes (element) or (index element), got names: " n))))

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
    ; optional index, which precedes the element it indexes: (acc i x).
    (method %shape-fold (self blk n)
      (match
        ((eq? n 2) blk)
        ((eq? n 3)
          (let ((box (list 0)))
            (fn (_ acc x)
              (let ((i (first box)))
                (%set-first! box (+ i 1))
                (blk acc i x)))))
        (#t (self %shape-error
              "block takes (acc element) or (acc index element), got names: " n))))

    ; binary: a comparator or reducer over two elements.  No index -- there is
    ; no single position to count.
    (method %shape-binary (self blk n)
      (if (eq? n 2) blk
        (self %shape-error "block takes (a b), got names: " n)))

    ; thunk: a nullary callback -- a lazy default, run only on a miss.  The
    ; binding list is `()`, so the body reads as the value it stands in for:
    ; (d get-or-else () (compute-default) k).
    (method %shape-thunk (self blk n)
      (if (eq? n 0) blk
        (self %shape-error "block takes () -- a thunk binds no names, got names: " n)))

    (method %adapt (self shape blk n)
      (match
        ((eq? shape (lit pair))   (self %shape-pair blk n))
        ((eq? shape (lit fold))   (self %shape-fold blk n))
        ((eq? shape (lit binary)) (self %shape-binary blk n))
        ((eq? shape (lit thunk))  (self %shape-thunk blk n))
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
    (method %block-op (self m shape trailing pos)
      (op (recv . args) e
        (if (self %block-call? args pos (+ pos (+ 2 trailing)))
          ; args = (lead... names body... trailing...): the leading forms
          ; evaluate in the caller's env and ride ahead of the callback.
          (let ((tail (self %drop-n args pos)))
            (apply m
              (pair recv
                (self %append (self %eval-each (self %take-n args pos) e)
                  (pair (self %adapt shape
                          (self %block-fn (first tail)
                                (self %but-last-n (rest tail) trailing) e)
                          (self %name-count (first tail)))
                        (self %eval-each (self %last-n (rest tail) trailing) e))))))
          (tail-eval (pair m (pair (list (lit lit) recv) args)) e))))

    ; --- documenting the wrap ------------------------------------------
    ; (help Class/sel) answered only the applicative signature: true, and
    ; incomplete -- the block form is a second call shape a reader cannot
    ; discover from it.  The wrap is the one place that knows the shape, so it
    ; adds the note itself: one fact, stated where it is decided, instead of
    ; fifty (doc ...) forms repeating it by hand and drifting.
    ;
    ; A method's doc is PENDING -- a (%bare KEY desc . meta) entry -- until the
    ; first (help) commits it, and every library wrap runs at boot, before
    ; that.  So the note is spliced onto the pending entry's meta when there is
    ; one; a wrap made after (help) has run finds the committed registry entry
    ; and prepends to its notes instead.  An undocumented method gets nothing,
    ; which is what it had.
    (method %shape-note (self shape)
      (match
        ((eq? shape (lit pair))
          "Block form: (p) body ... in place of f binds the (key . value) pair; (k v) binds the key and the value.")
        ((eq? shape (lit fold))
          "Block form: (acc x) body ... in place of f; (acc i x) adds the 0-based index ahead of the element.")
        ((eq? shape (lit binary))
          "Block form: (a b) body ... in place of f binds the two operands.")
        ((eq? shape (lit thunk))
          "Block form: () body ... in place of the thunk -- the body is the default, run only on a miss.")
        (#t
          "Block form: (x) body ... in place of f binds the element; (i x) binds the 0-based index, then the element.")))

    (method %last-cell (self xs)
      (if (null? (rest xs)) xs (recur self (rest xs))))

    (method %nth-cell (self xs i)
      (if (null? xs) () (if (< i 1) xs (recur self (rest xs) (- i 1)))))

    ; The pending entry keyed "Class/sel", by NAME: keys are symbols made by
    ; %str->symbol at stash time, and a symbol built here may not be eq? to
    ; one built there.  The kind and key are tested before symbol->str
    ; touches them -- it is unchecked on a non-symbol (#638).
    (method %pending-entry (self key)
      ((fn (go l)
         (if (null? l) ()
           (let ((e (first l)))
             (if (and (pair? e)
                   (and (pair? (rest e))
                     (and (symbol? (first (rest e)))
                       (str=? (symbol->str (first (rest e))) key))))
               e
               (go (rest l))))))
       (first %doc-pending-cell)))

    ; Idempotent: wrapping a selector twice must not say the same thing
    ; twice, so both paths look for the text before adding it.
    (method %notes-have? (self strs text)
      (if (null? strs) #f
        (if (and (str? (first strs)) (str=? (first strs) text)) #t
          (recur self (rest strs) text))))

    (method %meta-has-note? (self meta text)
      (if (null? meta) #f
        (let ((f (first meta)))
          (if (and (pair? f) (and (eq? (first f) (lit note))
                     (and (pair? (rest f)) (and (str? (first (rest f)))
                       (str=? (first (rest f)) text)))))
            #t
            (recur self (rest meta) text)))))

    (method %doc-note! (self class sel shape)
      (let ((key (%str-append (symbol->str (class-name class))
                   (%str-append "/" (symbol->str sel))))
            (text (self %shape-note shape)))
        (let ((pend (self %pending-entry key)))
          (if (null? pend)
            (let ((e (%doc-lookup ((prim-ref (lit str) (lit ->sym)) key))))
              (unless (null? e)
                (let ((cell (self %nth-cell e 6)))          ; the notes slot
                  (unless (self %notes-have? (first cell) text)
                    (%set-first! cell (pair text (first cell)))))))
            (unless (self %meta-has-note? (rest (rest pend)) text)
              (%set-rest! (self %last-cell pend) (list (list (lit note) text))))))))

    (method %imethod-of (self class sel)
      (let ((itab (first (%class-hot class))))
        (%entry-method (%tab-find! itab itab sel))))

    (method method! (self (param class CLASS "Class owning the method")
                          (param sel SYMBOL "Selector to give a block form")
                        . (param opts LIST "Optional: shape symbol, trailing-argument count, callback position"))
      (doc "Give a higher-order method a block form: (subject sel (names ...) body ...)."
        (returns ANY "The installed operative")
        (note "Shapes: element (default) -- (x) or (index x); pair -- (p) or (key value);")
        (note "fold -- (acc x) or (acc index x); binary -- (a b), no index;")
        (note "thunk -- (), a nullary callback such as a lazy default.")
        (note "Trailing defaults to 1 for a static method (the subject) and 0 for an")
        (note "instance method (the receiver is self); fold needs 2 (init, subject).")
        (note "Position defaults to 0; (List times n f) wraps at 1, the count")
        (note "ahead of it evaluating in the caller's env.")
        (note "The applicative form keeps working unchanged, and (help Class/sel)")
        (note "still answers from the doc registry.")
        (note "Do NOT (method-of Class sel) a block-enabled selector: the stored")
        (note "method is now an operative and a direct call would not evaluate.")
        (example "(do (Block method! List 'map) (List map (x) (* x 2) (list 1 2)))" "(2 4)"))
      (let ((shape (if (null? opts) () (first opts)))
            (pos (if (self %len>=? opts 3) (first (rest (rest opts))) 0))
            (sm (method-of class sel)))
        (if (null? sm)
          (let ((im (self %imethod-of class sel)))
            (when (null? im)
              (error (%str-append "Block method!: no such method "
                                  (symbol->str sel))))
            (class def-method! sel
              (self %block-op im shape
                (if (self %len>=? opts 2) (first (rest opts)) 0) pos))
            (self %doc-note! class sel shape))
          (do
            (class def-static! sel
              (self %block-op sm shape
                (if (self %len>=? opts 2) (first (rest opts)) 1) pos))
            (self %doc-note! class sel shape)))))))

; Each class wires its own selectors, beside the methods being wrapped -- this
; file is the mechanism only, and never reaches down into a collection.  See
; the (Block method! ...) lines at the foot of list.x, vector.x, iter.x,
; seq.x, gen.x, dict.x and set.x.

(doc (provide x/type/block Block)
  (note "The operative sees the binding list, which is what makes the optional")
  (note "index possible: the language has no arity introspection.")
  (example "(List map (i x) (list i x) (list 7 8))" "((0 7) (1 8))")
  "Block-form methods: write a callback's names and body at the call site.")
