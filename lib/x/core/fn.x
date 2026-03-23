; fn.x -- Functional combinators

(note "Combinators")

(doc (def identity (fn (_ (param x ANY "Value to return")) x))
  (returns ANY "The input value unchanged")
  "Return the given value unchanged.")

(doc (def const (fn (_ (param x ANY "Value to capture")) (fn (_ y) x)))
  (returns CALLABLE "A function that always returns x")
  "Return a function that always returns x, ignoring its argument.")

(doc (def compose (fn (_ (param f CALLABLE "Outer function") (param g CALLABLE "Inner function")) (fn (_ x) (f (g x)))))
  (returns CALLABLE "Composed function: f(g(x))")
  "Right-to-left function composition: (compose f g) returns a function that applies g then f.")

(doc (def pipe (fn (_ (param f CALLABLE "First function") (param g CALLABLE "Second function")) (fn (_ x) (g (f x)))))
  (returns CALLABLE "Piped function: g(f(x))")
  "Left-to-right function composition: (pipe f g) returns a function that applies f then g.")

(doc (def curry (fn (_ (param f CALLABLE "Binary function to partially apply") (param x ANY "First argument to bind")) (fn (_ y) (f x y))))
  (returns CALLABLE "Partially applied function awaiting one argument")
  "Partially apply a binary function by fixing its first argument.")

(doc (def flip (fn (_ (param f CALLABLE "Binary function")) (fn (_ a b) (f b a))))
  (returns CALLABLE "Function with reversed argument order")
  "Return a function that calls f with its two arguments reversed.")

(doc (def tap (fn (_ (param f CALLABLE "Side-effect function")) (fn (_ x) (f x) x)))
  (returns CALLABLE "Function that applies f for side effects and returns x")
  "Return a function that calls f on its argument for side effects, then returns the argument.")

(doc (provide x/core/fn identity const compose pipe curry flip tap)
  (example "((compose inc inc) 1)" "3")
  "Higher-order function combinators.")
