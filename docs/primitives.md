# x-lang C Primitives

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*

## Primitives

All primitives receive unevaluated arguments (fexpr-style) and evaluate what they need internally. Boolean true is `#t`; boolean false is `#f`. Nil is `()` (the empty list).

---

### Quoting

### `lit`

`(lit expr) -> expr`

Returns `expr` unevaluated. This is the quoting primitive; the argument is never evaluated. The reader provides `'expr` as shorthand.

```x-repl
(lit (+ 1 2)) -> ('+ 1 2)
'abc -> 'abc
```

---

### Pairs

### `pair`

`(pair a b) -> (a . b)`

Constructs a pair (cons cell) from evaluated `a` and `b`.

```x-repl
(pair 1 2) -> (1 . 2)
```

### `first`

`(first p) -> obj`

Returns the first element (car) of pair `p`.

```x-repl
(first (pair 1 2)) -> 1
```

### `rest`

`(rest p) -> obj`

Returns the rest element (cdr) of pair `p`.

```x-repl
(rest (pair 1 2)) -> 2
```

---

### Equality

### `eq?`

`(eq? a b) -> #t | #f`

Tests scalar-value identity of evaluated `a` and `b`: the same object, or two scalars (integers, characters) carrying the same value, compare `#t`. Use `same?` for strict object identity.

```x-repl
(eq? 'x 'x) -> #t
(eq? 1 1) -> #t
(eq? "a" "a") -> #f
```

### `=`

`(= a b) -> #t | #f`

Tests numeric value equality of evaluated `a` and `b`. Compares the integer values regardless of object identity.

```x-repl
(= 1 1) -> #t
(= 1 2) -> #f
```

---

### Comparison

### `<`

`(< a b) -> #t | #f`

Returns `#t` if integer `a` is strictly less than integer `b`.

```x-repl
(< 1 2) -> #t
(< 2 1) -> #f
```

### `>`

`(> a b) -> #t | #f`

Returns `#t` if integer `a` is strictly greater than integer `b`.

```x-repl
(> 2 1) -> #t
(> 1 2) -> #f
```

### `<=`

`(<= a b) -> #t | #f`

Returns `#t` if integer `a` is less than or equal to integer `b`.

```x-repl
(<= 1 1) -> #t
(<= 2 1) -> #f
```

### `>=`

`(>= a b) -> #t | #f`

Returns `#t` if integer `a` is greater than or equal to integer `b`.

```x-repl
(>= 1 1) -> #t
(>= 0 1) -> #f
```

---

### Arithmetic

### `+`

`(+ a ...) -> integer`

Variadic addition. Evaluates all arguments and returns their sum. Identity element is `0`; `(+)` returns `0`.

```x-repl
(+ 1 2 3) -> 6
(+) -> 0
```

### `-`

`(- a ...) -> integer`

Variadic subtraction. With one argument, negates it. With two or more, subtracts all subsequent values from the first. With no arguments, returns `0`.

```x-repl
(- 5 3) -> 2
(- 5) -> -5
(- 10 3 2) -> 5
(-) -> 0
```

### `*`

`(* a ...) -> integer`

Variadic multiplication. Evaluates all arguments and returns their product. Identity element is `1`; `(*)` returns `1`.

```x-repl
(* 2 3 4) -> 24
(*) -> 1
```

### `/`

`(/ a ...) -> integer`

Variadic integer division. With no arguments, returns `1` (identity). With one argument, returns that value unchanged. With two or more, divides the first by each subsequent value left to right.

```x-repl
(/ 10 2) -> 5
(/ 100 2 5) -> 10
(/) -> 1
```

### `%`

`(% a ...) -> integer`

Variadic integer modulo. With one argument, returns that value unchanged. With two or more, applies modulo left to right.

Unlike `+ - * /`, `%` has no zero-argument identity: `(%)` raises.

```x-repl
(% 10 3) -> 1
(% 17 10 3) -> 1
```

---

### Bitwise

### `~`

`(~ n) -> integer`

Bitwise NOT (one's complement) of integer `n`.

```x-repl
(~ 0) -> -1
(~ -1) -> 0
```

### `&`

`(& a b) -> integer`

Bitwise AND of integers `a` and `b`.

```x-repl
(& 6 3) -> 2
(& 255 15) -> 15
```

### `|`

`(| a b) -> integer`

Bitwise OR of integers `a` and `b`.

```x-repl
(| 6 3) -> 7
(| 0 5) -> 5
```

### `^`

`(^ a b) -> integer`

Bitwise XOR of integers `a` and `b`.

```x-repl
(^ 6 3) -> 5
(^ 5 5) -> 0
```

### `<<`

`(<< a b) -> integer`

Left bit shift of integer `a` by `b` positions.

```x-repl
(<< 1 4) -> 16
(<< 3 2) -> 12
```

### `>>`

`(>> a b) -> integer`

Right bit shift of integer `a` by `b` positions (arithmetic shift).

```x-repl
(>> 16 4) -> 1
(>> 12 2) -> 3
```

---

### Binding

### `def`

`(def name expr) -> value`

Binds `name` (unevaluated symbol) to the result of evaluating `expr` in the current environment. `expr` is evaluated before the binding is created, so it cannot read the binding being defined; recursive functions still work because a closure body resolves names at call time. To reference the name while `expr` itself evaluates, forward-declare with `(def name ())` then `(set! name expr)`.

```x
(def x 42) -> 42
(def fact (fn (_ n) (if (= n 0) 1 (* n (fact (- n 1))))))
(fact 5) -> 120
```

### `set!`

`(set! name expr) -> value`

Mutates an existing binding of `name` to the result of evaluating `expr`. Signals an error if `name` is not already bound in the current environment.

```x-repl
(def x 1) -> 1
(set! x 2) -> 2
(set! unbound 0) -> error: Unbound symbol
```

---

### Control

### `if`

`(if cond then [else]) -> value`

Evaluates `cond`. If truthy (not `()`), tail-evaluates `then`. If falsy, tail-evaluates `else` when provided, or returns `()`. Uses tail-call optimization for the selected branch.

```x-repl
(if #t 1 2) -> 1
(if () 1 2) -> 2
(if () 1) -> ()
```

### `do`

`(do form ...) -> value`

Evaluates each `form` in sequence and returns the value of the last one. The final form is tail-evaluated for TCO. With no arguments, returns `()`.

```x-repl
(do 1 2 3) -> 3
(do (def x 1) (+ x 1)) -> 2
```

### `match`

`(match (test expr) ...) -> value`

Multi-branch conditional (cond-style). Evaluates each `test` in order; for the first truthy test, tail-evaluates the corresponding `expr` and returns it. Returns `()` if no test succeeds.

```x
(match
  ((= 1 2) 10)
  ((= 1 1) 20)
  (#t 30)) -> 20
```

### `let`

`(let ((name val) ...) body ...) -> value`

Creates local bindings by evaluating each `val` in the current environment, then evaluates `body` forms in the extended environment. The final body form is tail-evaluated. Environment is restored after `let` completes.

```x-repl
(let ((x 1) (y 2)) (+ x y)) -> 3
(let ((x 10)) x) -> 10
```

---

### Functions

### `fn`

`(fn (params ...) body ...) -> procedure`

Creates a closure (applicative, lexically scoped). `params` are not evaluated; they name the formal parameters. Every closure receives itself as an implicit first argument — by convention the first formal is `_` when unused, or `self` when the body recurses through it. Supports variadic binding: if `params` is a single symbol instead of a list, it captures the entire argument list, whose head is the closure itself.

```x
(def add (fn (_ a b) (+ a b)))
(add 1 2) -> 3
(def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1))))))
(fact 5) -> 120
(def id (fn args (rest args)))
(id 1 2 3) -> (1 2 3)
```

### `op`

`(op formals env-param body ...) -> operative`

Creates an operative (user-level fexpr). Like `fn`, but receives arguments unevaluated. `formals` binds the raw argument tree, and `env-param` binds the dynamic environment, giving the operative manual control over evaluation.

```x
(def my-quote (op (x) e x))
(my-quote (+ 1 2)) -> ('+ 1 2)
```

### `apply`

`(apply f args) -> value`

Calls callable `f` with a pre-evaluated list of arguments `args`. Works with both closures and C primitives. Arguments in the list are not re-evaluated.

```x-repl
(apply + (list 1 2 3)) -> 6
(apply first (list (list 1 2))) -> 1
```

### `eval`

`(eval expr [env]) -> value`

Evaluates the already-evaluated expression `expr`. With an optional `env` argument, evaluates `expr` in that environment instead of the current one. The environment is restored after evaluation.

```x-repl
(eval '(+ 1 2)) -> 3
```

### `wrap`

`(wrap combiner) -> applicative`

Wraps a combiner (operative or primitive) to create an applicative that evaluates its arguments before passing them to the underlying combiner.

```x
(def my-op (op (x) e x))
(def my-fn (wrap my-op))
(my-fn (+ 1 2)) -> 3
```

### `unwrap`

`(unwrap applicative) -> combiner`

Extracts the underlying combiner from an applicative created by `wrap`.

```x-repl
(unwrap (wrap (op (x) e x))) -> <operative>
```

---

### Predicates

### `null?`

`(null? x) -> #t | #f`

Returns `#t` if `x` evaluates to nil (`()`); `#f` otherwise.

```x-repl
(null? ()) -> #t
(null? 1) -> #f
```

### `pair?`

`(pair? x) -> #t | #f`

Returns `#t` if `x` evaluates to a list pair; `#f` otherwise.

```x-repl
(pair? (list 1 2)) -> #t
(pair? 1) -> #f
```

### `atom?`

`(atom? x) -> #t | #f`

Returns `#t` if `x` evaluates to a non-pair (atom); `#f` if it is a list pair. The inverse of `pair?`.

```x-repl
(atom? 1) -> #t
(atom? (list 1 2)) -> #f
```

### `not`

`(not x) -> #t | #f`

Logical negation. Returns `#t` if `x` evaluates to nil; `#f` otherwise. Equivalent to `null?`.

```x-repl
(not ()) -> #t
(not 1) -> #f
```

### `number?`

`(number? x) -> #t | #f`

Returns `#t` if `x` evaluates to an integer; `#f` otherwise.

```x-repl
(number? 42) -> #t
(number? "hello") -> #f
```

### `str?`

`(str? x) -> #t | #f`

Returns `#t` if `x` evaluates to a string; `#f` otherwise.

```x-repl
(str? "hello") -> #t
(str? 42) -> #f
```

### `symbol?`

`(symbol? x) -> #t | #f`

Returns `#t` if `x` evaluates to a symbol; `#f` otherwise.

```x-repl
(symbol? 'x) -> #t
(symbol? 42) -> #f
```

### `procedure?`

`(procedure? x) -> #t | #f`

Returns `#t` if `x` evaluates to a callable (closure or C primitive); `#f` otherwise.

```x-repl
(procedure? +) -> #t
(procedure? 42) -> #f
```

### `char?`

`(char? x) -> #t | #f`

Returns `#t` if `x` evaluates to a character object; `#f` otherwise.

```x-repl
(char? ((prim-ref 'str 'byte-ref) "hello" 0)) -> #t
(char? 42) -> #f
```

---

### Lists

### `list`

`(list a ...) -> (a ...)`

Constructs a proper list from zero or more evaluated arguments. `(list)` returns `()`.

```x-repl
(list 1 2 3) -> (1 2 3)
(list) -> ()
```

---

### Logic

### `and`

`(and expr ...) -> value`

Short-circuit logical AND. Evaluates each `expr` left to right. Normalizes failure to `#f` at the first falsy value -- it answers "did all pass". If all values are truthy, returns the last one. With no arguments, returns `#t`.

```x-repl
(and 1 2 3) -> 3
(and 1 () 3) -> #f
(and) -> #t
```

### `or`

`(or expr ...) -> value`

Short-circuit logical OR. Evaluates each `expr` left to right. Returns the first truthy value. If every operand is falsy the LAST operand passes through unchanged -- `or` does not normalize its failure the way `and` does, so the result is whichever of `()` or `#f` you supplied last. With no arguments, returns `()`.

```x-repl
(or () () 3) -> 3
(or 1 2) -> 1
(or () #f) -> #f
(or #f ()) -> ()
(or) -> ()
```

---

### I/O

### `write`

`(write obj) -> ()`

Outputs the s-expression representation of evaluated `obj` to stdout (strings are quoted, special characters escaped). Returns `()`.

```x-repl
(write "hello") -> ()  ; prints "hello" (with quotes)
```

### `display`

`(display obj) -> ()`

Outputs the human-readable representation of evaluated `obj` to stdout. Strings are printed without surrounding quotes; all other types use s-expression format. Returns `()`.

```x-repl
(display "hello") -> ()  ; prints hello (without quotes)
(display 42) -> ()       ; prints 42
```

### `newline`

`(newline) -> ()`

Outputs a newline character to stdout. Takes no arguments. Returns `()`.

```x-repl
(newline) -> ()  ; prints \n
```

---

### Strings

Each primitive has a name and a catalog coordinate: `str-append` is filed
under namespace `str`, method `append`. The `str` namespace is de-registered,
so the name itself is not bound and `prim-ref` is the way in --
`((prim-ref 'str 'append) a b)`. The `sym` and `bytes` namespaces are not
de-registered, so `symbol->str` and `bytes->str` are called by name.

The bare global `Str` is the library's UTF-8 string class, not this surface.

Every operation here is BYTE-level. The code-point-aware layer is pure x-lang
built on top of these (`x/protocol/str/utf8`). For everyday string work, use the
`Str` class in the standard library reference rather than these.

### `str-byte-len`

`((prim-ref 'str 'byte-len) s) -> integer`

Number of BYTES in `s`, not code points.

```x-repl
((prim-ref 'str 'byte-len) "hello") -> 5
((prim-ref 'str 'byte-len) "") -> 0
```

### `str-byte-ref`

`((prim-ref 'str 'byte-ref) s i) -> character`

The byte at zero-based index `i`, as a CHARACTER (0-255). A negative `i` counts
from the end.

```x-repl
((prim-ref 'str 'byte-ref) "hello" 0) -> #\h
((prim-ref 'str 'byte-ref) "hello" -1) -> #\o
```

### `str-byte-sub`

`((prim-ref 'str 'byte-sub) s start len) -> string`

A newly allocated string of `len` bytes taken from byte offset `start`. Note
that the third argument is a LENGTH, not an end index.

```x-repl
((prim-ref 'str 'byte-sub) "hello" 1 2) -> "el"
```

### `str-append`

`((prim-ref 'str 'append) a b) -> string`

Concatenates two strings into a newly allocated one.

```x-repl
((prim-ref 'str 'append) "hello" " world") -> "hello world"
```

### `make-str`

`((prim-ref 'str 'make) n) -> string`

A fresh owned `n`-byte string region, space-filled and NUL-terminated.

```x-repl
((prim-ref 'str 'make) 3) -> "   "
```

### `str->symbol`

`((prim-ref 'str '->sym) s) -> symbol`

Converts a string to an interned symbol with the same name.

```x-repl
((prim-ref 'str '->sym) "hello") -> 'hello
```

### `symbol->str`

`(symbol->str y) -> string`

Converts a symbol to a string containing its name.

```x-repl
(symbol->str 'hello) -> "hello"
```

### `bytes->str`

`(bytes->str lst) -> string`

The raw byte-packer: one low byte per character of `lst`. The code-point-aware
counterpart (`list->str`) is pure x-lang and UTF-8 encodes on top of this.

```x-repl
(bytes->str (list 104 105)) -> "hi"
```

---

### Quasiquote

### `quasi`

`(quasi template) -> obj`

Quasiquote expansion. Returns `template` with `unquote` and `unquote-splicing` forms evaluated. Atoms and non-list values are returned as-is. `(unquote expr)` within the template is replaced by the evaluated `expr`. `(unquote-splicing expr)` splices the evaluated list into the surrounding list.

```x
(def x 1)
(quasi (a (unquote x) b)) -> ('a 1 'b)
(def xs (list 2 3))
(quasi (1 (unquote-splicing xs) 4)) -> (1 2 3 4)
```

---

### Errors

### `guard`

`(guard (var handler-body ...) body ...) -> value`

Error recovery form. Evaluates `body` forms in sequence. If an error is signalled during evaluation, binds the error value to `var` and evaluates `handler-body` forms instead. The environment is restored to its state before `body` after an error. Handlers can be nested.

```x
(guard (e (display e) (newline) 0)
  (error "oops")) -> 0  ; prints oops
```

### `error`

`(error message) -> <does not return>`

Signals an error with the evaluated `message`. If a `guard` handler is installed, the error is caught and `message` is bound to the handler variable. If no handler is installed, the error is fatal. `message` may be a string or any object.

```x-repl
(error "something went wrong") -> <error signalled>
```

---

### System

### `heap-collect`

`((prim-ref 'heap 'collect)) -> ()`

Triggers garbage collection by marking all objects reachable from the base
environment. Returns `()`. Reachable through `prim-ref`.

```x-repl
((prim-ref 'heap 'collect)) -> ()
```
