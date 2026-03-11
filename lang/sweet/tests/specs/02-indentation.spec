
== indentation single-line

-- tokens on one line form a list
define x 42
---
42

-- function call on one line
+ 1 2
---
3

== indentation basic grouping

-- indented body becomes child
define x
  42
x
---
42

-- indented function call
define x
  + 1 2
x
---
3

-- multiple head tokens with child
if #t
  42
---
42

== indentation if expression

-- if with two branches
if {3 > 2}
  "yes"
  "no"
---
"yes"

-- if false branch
if {3 < 2}
  "yes"
  "no"
---
"no"

== indentation nested

-- two levels of nesting
define x
  +
    1
    2
x
---
3

-- define with lambda
define double
  lambda (n)
    * n 2
double 7
---
14

== indentation factorial

-- recursive factorial
define factorial
  lambda (n)
    if {n <= 1}
      1
      {n * (factorial {n - 1})}
factorial 5
---
120

== indentation with parens

-- parens override indentation
(define x
  42)
x
---
42

-- sexp inside sweet
define x (+ 1 2)
x
---
3

== indentation with curlies

-- curly infix in indented position
define x
  {3 + 4}
x
---
7

== indentation blank lines

-- blank lines between expressions
define x 10

x
---
10

== indentation comments

-- comment line is transparent
define x
  ; this is a comment
  42
x
---
42
