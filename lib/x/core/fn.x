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
; (docs/glossary.md "core": the C prims are unchecked, the library is the
; guard site), so the door is here.  A value is callable through its type's
; call handler -- (v args...) dispatches that way -- and apply takes the same
; door: a vector, a class instance, a generic, or a make-type instance with
; a call handler applies like a closure, and a value with no handler raises
; a type error.
;
; The arguments arrive evaluated.  A closure handler is entered on the
; engine's apply path, which binds them as they are; an operative handler
; receives them as its operands, as a bare operative does under apply.
;
; The engine's apply stays under %apply.  What the library built, or what a
; type cell holds, is applied through it -- let, the class dispatcher, the
; printer and the reflect layer each keep their own capture -- so none of
; them pays for a check it has no use for, and a lang that binds apply over
; this door, as this door is bound over the engine's, cannot retarget them.
(def %apply apply)
; The argument list: the tail alone, or the leading arguments spliced in
; front of it.  A walk of its own, never apply applied to apply: the engine's
; apply evaluates its operands, and a list among the leading arguments would
; be evaluated as a form.
(def %apply-args
  (fn (self spread)
    (if (null? (rest spread))
      (first spread)
      (pair (first spread) (self (rest spread))))))
; The value path, off the fast path so a closure pays for nothing here:
; the reflection doors are fetched inline, per the caching rule, and the
; handler is the one (v args...) would reach.
(def %apply-value
  (fn (_ f args)
    (let ((t ((prim-ref (lit type) (lit by-atom))
              ((prim-ref (lit type) (lit of)) f))))
      (let ((h (if (null? t) () ((prim-ref (lit type) (lit call-top)) t))))
        (if (null? h)
          (Err raise (lit type) "apply: not callable" f)
          (%apply h (pair f args)))))))
(doc (def apply
  (fn (_ (param f CALLABLE "What to apply: a closure, a primitive, an operative, or a value whose type has a call handler")
         . (param spread ANY "Leading arguments, then the list of the rest"))
    (match
      ((null? spread) (Err raise (lit type) "apply: no argument list" ()))
      ((procedure? f) (%apply f (%apply-args spread)))
      ((operative? f) (%apply f (%apply-args spread)))
      (#t (%apply-value f (%apply-args spread))))))
  (returns ANY "What f answers")
  (example "(apply + (list 1 2))" "3")
  (example "(apply + 1 2 (list 3 4))" "10")
  (example "(apply (Vector of 1 2 3) (list 1))" "2")
  (example "(guard (e (Err tag e)) (apply () (list 1)))" "'type")
  "Apply f to a list of arguments, with any leading arguments spliced in front: (apply f a b (list c d)) calls f with (a b c d). A closure, a primitive or an operative is applied by the engine; any other value is applied through its type's call handler, the way (v args...) calls it, and a value with no handler raises a type error.")

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
