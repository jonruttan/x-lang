
== curly-infix empty

-- empty braces produce nil
(null? {})
---
t

== curly-infix single

-- single element is identity
{42}
---
42

-- single symbol
(define x 10)
{x}
---
10

== curly-infix simple

-- addition
{1 + 2}
---
3

-- multiplication
{3 * 4}
---
12

-- comparison
{5 > 3}
---
t

-- subtraction
{10 - 3}
---
7

== curly-infix two-element

-- unary minus
{- 5}
---
-5

-- not returns nil
(null? {not #t})
---
t

== curly-infix variadic

-- same operator folds
{1 + 2 + 3}
---
6

-- five operands
{1 + 2 + 3 + 4 + 5}
---
15

== curly-infix mixed

-- mixed ops produce nfx form
(write {1 + 2 * 3})
---
($nfx$ 1 + 2 * 3)

== curly-infix nested

-- nested curlies
{2 * {3 + 4}}
---
14

-- deeply nested
{{1 + 2} * {3 + 4}}
---
21

== curly-infix with sexp

-- curly inside sexp
(if {3 > 2} "yes" "no")
---
"yes"

-- sexp inside curly
{(+ 1 2) + (+ 3 4)}
---
10
