; fn.x -- Fn: function combinators as static methods.
;
; Loads AFTER object.x in the boot sequence (it needs def-class). Nothing loaded
; before the object system references these combinators -- there are zero call
; sites in the tree -- so the whole module is just the class.

(import x/type/object)

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
      (fn (_ x) (f x) x))))

(doc (provide x/core/fn Fn)
  (note "Function combinators as static methods: (Fn compose f g), (Fn flip f), (Fn tap f).")
  (example "((Fn compose (method-ref Num inc) (method-ref Num inc)) 1)" "3")
  "Higher-order function combinators, homed on the Fn class.")
