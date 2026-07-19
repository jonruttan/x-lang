; fn.x -- Fn: function combinators as static methods.
;
; Loads AFTER object.x in the boot sequence (it needs def-class). Nothing loaded
; before the object system references these combinators -- there are zero call
; sites in the tree -- so the whole module is just the class.

(import x/type/class)

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

(doc (provide x/core/fn Fn)
  (note "Function combinators as static methods: (Fn compose f g), (Fn flip f), (Fn tap f).")
  (example "((Fn compose (method-ref Num inc) (method-ref Num inc)) 1)" "3")
  "Higher-order function combinators, homed on the Fn class.")
