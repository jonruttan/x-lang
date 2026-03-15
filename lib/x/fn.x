; fn.x -- Functional combinators

(def identity (fn (x) x))

(def const (fn (x) (fn (y) x)))

(def compose (fn (f g) (fn (x) (f (g x)))))

(def pipe (fn (f g) (fn (x) (g (f x)))))

(def curry (fn (f x) (fn (y) (f x y))))

(def flip (fn (f) (fn (a b) (f b a))))

(def tap (fn (f) (fn (x) (f x) x)))
