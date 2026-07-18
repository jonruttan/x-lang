# Getting Started with x-lang

## Build

```sh
make clean && make
```

This produces the `x` binary. Requires a C89-compatible compiler (gcc, clang, tcc).

## Start a Session

The simplest way to start:

```sh
sh x.sh
```

This loads the x-lang standard library and drops into a REPL:

```
> (+ 1 2)
3
> (def greeting "hello")
> greeting
"hello"
```

The prompt is `> `. Results are printed after each expression. Nil results print nothing.

For the full-stack dialect with numeric tower, JIT compiler, and POSIX:

```sh
sh x.sh -l x-and
```

To evaluate a file:

```sh
sh x.sh -f program.x
```

## Basic Expressions

### Values

Integers, strings, and characters are self-evaluating:

```
> 42
42
> "hello"
"hello"
> #\a
a
```

### Pairs and Lists

The pair is the fundamental compound structure. A list is a chain of pairs terminated by nil `()`:

```
> (pair 1 2)
(1 . 2)
> (pair 1 (pair 2 (pair 3 ())))
(1 2 3)
> (list 1 2 3)
(1 2 3)
> (first (list 1 2 3))
1
> (rest (list 1 2 3))
(2 3)
```

### Definitions

`def` binds a name in the current environment:

```
> (def x 10)
> (def double (fn (_ n) (* n 2)))
> (double x)
20
```

### Functions

`fn` creates an applicative (a function that evaluates its arguments). The first parameter is always the self-reference (conventionally `_`), followed by the actual parameters:

```
> (def square (fn (_ n) (* n n)))
> (square 5)
25
> (def factorial
    (fn (self n)
      (if (<= n 1) 1 (* n (self (- n 1))))))
> (factorial 10)
3628800
```

The self-reference enables anonymous recursion — name it `self` (or anything) to call the function from within its own body, or `_` when not needed.

### Conditionals

```
> (if (> 3 2) "yes" "no")
"yes"
> (match
    ((> x 100) "big")
    ((> x 10) "medium")
    (#t "small"))
"small"
```

### Sequences

`do` evaluates a sequence of expressions and returns the last:

```
> (do
    (def a 1)
    (def b 2)
    (+ a b))
3
```

### Local Bindings

```
> (let ((x 10) (y 20)) (+ x y))
30
```

## The Fexpr Model

x-lang's evaluation model is distinctive. All C-level primitives are **fexprs**: they receive their arguments unevaluated and choose what to evaluate.

- **`fn`** creates an **applicative** — arguments are evaluated before the body runs (like a normal function)
- **`op`** creates an **operative** — arguments are passed unevaluated, and the caller's environment is available

```
> (def my-if
    (op (test then else) e
      (if (eval test e)
        (eval then e)
        (eval else e))))
> (my-if (> 3 2) "yes" "no")
"yes"
```

`op` binds the unevaluated argument tree and the caller's environment `e`. The body decides what to evaluate and when. This is how all core forms (`if`, `def`, `match`, `do`) are implemented -- they are ordinary operatives, not special forms the evaluator knows about.

`wrap` and `unwrap` convert between applicative and operative behavior:

```
> (def my-add (wrap (op (a b) e (+ (eval a e) (eval b e)))))
> (my-add 1 2)
3
```

## Lists and Higher-Order Functions

The standard library provides a rich set of list operations:

```
> (map (fn (_ x) (* x x)) (list 1 2 3 4 5))
(1 4 9 16 25)
> (filter (fn (_ x) (> x 2)) (list 1 2 3 4 5))
(3 4 5)
> (fold + 0 (list 1 2 3 4 5))
15
> (List sort < (list 3 1 4 1 5 9))
(1 1 3 4 5 9)
> (List zip (list 1 2 3) (list "a" "b" "c"))
((1 "a") (2 "b") (3 "c"))
```

## Modules

Load additional capabilities with `import`:

```
> (import x/type/vector)
> (def v (Vector make 3 0))
> v
#(0 0 0)
```

In the x/and dialect, the numeric tower is pre-loaded:

```
> (Num expt 2 100)
1267650600228229401496703205376
> (+ 1/3 1/6)
1/2
> (* 2.0 3.14)
6.28
> (+ 1+2i 3+4i)
4+6i
```

## Exploration

Use `help` to look up documentation for any bound symbol:

```
> (help '+)
```

Use `modules` to list all registered modules:

```
> (modules)
```

## Choosing a Dialect

| Dialect | Load Command | Use Case |
|---------|-------------|----------|
| x-lang | `sh x.sh` | General programming, scripting, learning |
| x/and | `sh x.sh -l x-and` | Numeric computing, full-stack applications |
| x/or | `sh x.sh -l x-or` | Systems programming, OS interaction |

## Next Steps

- [Specification](spec.md) — Complete language reference with examples
- [Standard Library](standard-library.md) — Core function reference
- x-lang API Reference — auto-generated module documentation: run `make doc-x`, then open `ref/x/index.md`
- [Architecture](architecture.md) — How the interpreter works internally
- [Dialects](dialects.md) — Detailed dialect comparison
- [Modules](modules.md) — The provide/import module system
