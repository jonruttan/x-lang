; fn.x -- Fn: function combinators as static methods.
;
; Loads AFTER object.x in the boot sequence (it needs def-class). Nothing loaded
; before the object system references these combinators -- there are zero call
; sites in the tree -- so the module is the class, and apply, the combinator
; the others are built on, bound over the engine's.

(import x/type/class)

; --- apply: the library's door over the engine's ---
;
; The engine's apply calls through whatever it is handed.  Handed a value
; that is not a closure, an operative or a primitive, it jumps into the
; value's first slot: a crash, not an error.  That is the engine's charter
; (docs/primitives.md, Coordinates: the C layer is a CPU and checks nothing),
; so the door is here.  A value is callable through its type's call
; handler, which is how (v args...) dispatches, and apply takes the same
; door: a vector, a class instance, a generic, or a make-type instance with
; a call handler applies like a closure, and a value with no handler raises
; a type error.
;
; The arguments arrive evaluated.  A closure handler is entered on the
; engine's apply path, which binds them as they are.  Any other handler, an
; operative or one of the engine's C handlers, evaluates its operands the way
; (v x) evaluates x, so it is handed each value quoted: (apply v vals) is
; (v 'val ...), and a symbol or a list among the values arrives as itself.  A
; bare operative gets the values as its operands, as the engine's apply hands
; them over.
;
; A wrapped combiner, (wrap c), is applied as c: the direct call evaluates
; the operands and hands c the values, and the door hands c the values it was
; given.  The engine's apply cannot do that for it: the wrapped combiner is a
; procedure whose parameters and body are nil and whose environment slot holds
; c, and the engine's apply binds it like any closure, so it answered nil.
;
; The engine's apply stays under %apply.  What the library built, or what a
; type cell holds, is applied through it -- let, the class dispatcher, the
; printer and the reflect layer each keep their own capture -- so none of
; them pays for a check it has no use for, and a lang that binds apply over
; this door, as this door is bound over the engine's, cannot retarget them.
(def %apply apply)
; The reflection doors the value path takes.  It dispatches on every call it
; serves, so they are fetched once, here, as the modules that wire types fetch
; theirs; fetched from the catalog on each call they cost 1,283 objects.
(def %apply-type-of (prim-ref (lit type) (lit of)))
(def %apply-by-atom (prim-ref (lit type) (lit by-atom)))
(def %apply-call-top (prim-ref (lit type) (lit call-top)))
; What kind of callable f is, in one call on the door's fast path: (lit fn)
; for a closure or a primitive, which take the values as they are; (lit op)
; for an operative; (lit wrap) for a wrapped combiner, a procedure carrying
; the engine's wrap flag (flag 1, engine/tools/contract/obj-layout.x); and ()
; for anything else, which its type's call handler takes.  The doors it reads
; with are fetched into its own closure, as x/tool/cov.x fetches its flag
; reader, so they add no module global.
(def %apply-kind
  ((fn (_ )
     (def type-of (prim-ref (lit type) (lit of)))
     (def is? (prim-ref (lit type) (lit ?)))
     (def proc-t (type-of (fn (_ ) ())))
     (def prim-t (type-of eq?))
     (def op-t (type-of (op (_ ) ())))
     (def o->p (prim-ref (lit obj) (lit ->ptr)))
     (def ref-word (prim-ref (lit ptr) (lit ref-word)))
     (def bit-and (prim-ref (lit int) (lit &)))
     (def word-size
       (match
         ((< 0 ((prim-ref (lit ptr) (lit ->int)) ((prim-ref (lit int) (lit ->ptr)) 4294967296))) 8)
         (#t 4)))
     (def flags-off (* %obj-slot-flags word-size))
     (fn (_ f)
       (match
         ((is? f proc-t)
           (match
             ((eq? (bit-and (ref-word (o->p f) flags-off) %obj-flag-1) 0) (lit fn))
             (#t (lit wrap))))
         ((is? f prim-t) (lit fn))
         ((is? f op-t) (lit op))
         (#t ()))))
   ()))
; The argument list: the tail alone, or the leading arguments spliced in
; front of it.  A walk of its own, never apply applied to apply: the engine's
; apply evaluates its operands, and a list among the leading arguments would
; be evaluated as a form.
(def %apply-args
  (fn (self spread)
    (match
      ((eq? (rest spread) ()) (first spread))
      (#t (pair (first spread) (self (rest spread)))))))
; Each value as a form that evaluates to itself, for a handler that
; evaluates its operands.
(def %apply-quoted
  (fn (self vals)
    (match
      ((eq? vals ()) ())
      (#t (pair (list (lit lit) (first vals)) (self (rest vals)))))))
; The value path, off the fast path so a closure pays for nothing here.  The
; handler is the one (v args...) would reach.  Its locals are bound with def,
; the primitive; let is derived from apply and builds a form to do it.
(def %apply-value
  (fn (_ f args)
    (def t (%apply-by-atom (%apply-type-of f)))
    (def h (match
             ((eq? t ()) ())
             (#t (%apply-call-top t))))
    (def k (%apply-kind h))
    (match
      ((eq? h ()) (Err raise (lit type) "apply: not callable" f))
      ((eq? k (lit fn)) (%apply h (pair f args)))
      ((eq? k (lit wrap)) (apply h (pair f args)))
      (#t (%apply h (pair f (%apply-quoted args)))))))
(doc (def apply
  (fn (_ (param f CALLABLE "What to apply: a closure, a primitive, an operative, a wrapped combiner, or a value whose type has a call handler")
         . (param spread ANY "Leading arguments, then the list of the rest"))
    (def kind (%apply-kind f))
    (match
      ((eq? spread ()) (Err raise (lit type) "apply: no argument list" ()))
      ((eq? kind (lit fn)) (%apply f (%apply-args spread)))
      ((eq? kind (lit op)) (%apply f (%apply-args spread)))
      ((eq? kind (lit wrap)) (apply (unwrap f) (%apply-args spread)))
      (#t (%apply-value f (%apply-args spread))))))
  (returns ANY "What f answers")
  (example "(apply + (list 1 2))" "3")
  (example "(apply + 1 2 (list 3 4))" "10")
  (example "(apply (Vector of 1 2 3) (list 1))" "2")
  (example "(apply (wrap (op (a) e a)) (list 5))" "5")
  (example "(guard (e (Err tag e)) (apply () (list 1)))" "'type")
  "Apply f to a list of arguments, with any leading arguments spliced in front: (apply f a b (list c d)) calls f with (a b c d). A closure, a primitive or an operative is applied by the engine; a wrapped combiner, (wrap c), is applied as c; any other value is applied through its type's call handler, the way (v args...) calls it, and a value with no handler raises a type error.")

(def-class Fn ()
  (static
    (method identity (self (param x ANY "Value to return"))
      (doc "Return the given value unchanged." (returns ANY "The input value unchanged"))
      x)
    (method const (self (param x ANY "Value to capture"))
      (doc "Return a function that always returns x, ignoring its argument."
        (returns CALLABLE "A function that always returns x"))
      (fn (_ _) x))
    (method compose (self (param f CALLABLE "Outer function") (param g CALLABLE "Inner function"))
      (doc "Right-to-left composition: (Fn compose f g) applies g then f."
        (returns CALLABLE "Composed function f(g(x))")
        (example "((Fn compose (method-ref Num inc) (method-ref Num inc)) 1)" "3"))
      (fn (_ x) (f (g x))))
    (method pipe (self (param f CALLABLE "First function") (param g CALLABLE "Second function"))
      (doc "Left-to-right composition: (Fn pipe f g) applies f then g."
        (returns CALLABLE "Piped function g(f(x))"))
      (fn (_ x) (g (f x))))
    (method curry (self (param f CALLABLE "Binary function to partially apply") (param x ANY "First argument to bind"))
      (doc "Partially apply a binary function by fixing its first argument."
        (returns CALLABLE "Function awaiting one argument"))
      (fn (_ y) (f x y)))
    (method flip (self (param f CALLABLE "Binary function"))
      (doc "Return a function that calls f with its two arguments reversed."
        (returns CALLABLE "Function with reversed argument order"))
      (fn (_ a b) (f b a)))
    (method tap (self (param f CALLABLE "Side-effect function"))
      (doc "Call f on the argument for side effects, then return the argument."
        (returns CALLABLE "Function applying f then returning its argument"))
      (fn (_ x) (f x) x))
    (method default-to (self (param d ANY "Default value") (param x ANY "Value to check"))
      (doc "Return x if non-nil, otherwise return the default d."
        (returns ANY "x if non-nil, otherwise d"))
      (if (null? x) d x))
    (method until (self (param pred CALLABLE "Predicate to stop on")
                        (param f CALLABLE "Transformation function")
                        (param x ANY "Initial value"))
      (doc "Repeatedly apply f to x until pred is satisfied, then return the value."
        (returns ANY "First value satisfying pred"))
      (if (pred x) x (recur self pred f (f x))))
    ; Moved from the List class -- combinators are Fn's charter.
    (method complement (self (param pred CALLABLE "Predicate to negate"))
      (doc "Return a function that negates a predicate." (returns CALLABLE "Negated predicate"))
      (fn (_ . args) (not (apply pred args))))
    (method partial (self (param f CALLABLE "Function to partially apply") . (param bound ANY "Bound leading arguments"))
      (doc "Partially apply a function with leading arguments." (returns CALLABLE "Partially applied function"))
      (fn (_ . args) (apply f (List append bound args))))
    (method juxt (self . (param fns CALLABLE "Functions to apply side by side"))
      (doc "Create a function that applies multiple functions and collects results." (returns CALLABLE "Juxtaposed function"))
      (fn (_ . args) (List map (fn (_ f) (apply f args)) fns)))
    (method both (self (param f CALLABLE "First predicate") (param g CALLABLE "Second predicate"))
      (doc "Combine two predicates with AND." (returns CALLABLE "Combined predicate"))
      (fn (_ x) (and (f x) (g x))))
    (method either (self (param f CALLABLE "First predicate") (param g CALLABLE "Second predicate"))
      (doc "Combine two predicates with OR." (returns CALLABLE "Combined predicate"))
      (fn (_ x) (or (f x) (g x))))
    (method all-pass (self (param preds LIST "List of predicates"))
      (doc "Return a predicate that passes when all predicates pass." (returns CALLABLE "Combined predicate"))
      (fn (_ x) (List all? (fn (_ p) (p x)) preds)))
    (method any-pass (self (param preds LIST "List of predicates"))
      (doc "Return a predicate that passes when any predicate passes." (returns CALLABLE "Combined predicate"))
      (fn (_ x) (List any? (fn (_ p) (p x)) preds)))))

(doc (provide x/core/fn apply Fn)
  (note "Function combinators as static methods: (Fn compose f g), (Fn flip f), (Fn tap f).")
  (example "((Fn compose (method-ref Num inc) (method-ref Num inc)) 1)" "3")
  "Higher-order function combinators, homed on the Fn class.")
