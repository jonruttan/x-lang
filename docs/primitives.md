# x-lang C Primitives

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*

## Primitives

All primitives receive unevaluated arguments (fexpr-style) and evaluate what they need internally. Boolean true is `#t`; boolean false is `#f`. Nil is `()` (the empty list).

**What "primitive" means here, and what it does not.** This file documents the
forms the language answers to once it has booted. Not all of them are C: `if`,
`let`, `and`, `or`, `display` and `quasi` are operatives written in x-lang, and
`not`, `list` and `str?` are procedures. The C surface itself has one source of
truth — `tools/contract/isa.x` in the engine — and `make check-isa` diffs it
against the C source, so it cannot drift silently.

A bare spelling is also not always the C entry point. `+` is a library generic
over the numeric tower; the primitive it bottoms out in is the coordinate
`(int +)`, reached as `((prim-ref (lit int) (lit +)) 1 2)`. Several namespaces
(`str`, `mem`, `heap`, `io`, `sym`) are de-registered, so their coordinates have
no bare name at all and `prim-ref` is the only door — the Strings section below
is written that way throughout.

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

Variadic integer modulo. With one argument, returns that value unchanged; with
two or more, applies modulo left to right. **With no arguments it is an error**
(`%: needs at least one argument`) — unlike `+` and `*`, which have identities
to return, and unlike `/`, which answers `1`.

```x-repl
(% 10 3) -> 1
(% 17 10 3) -> 1
(% 5) -> 5
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

Returns `#t` if `x` evaluates to a string; `#f` otherwise. The spelling is
`str?`, matching the `str` namespace the string coordinates live in — there is
no `string?`.

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
(char? (Io read-char)) -> #t
(char? 42) -> #f
```

### `Type ?`

`(Type ? obj type-handle) -> #t | #f`

Returns `#t` if the runtime type of `obj` matches `type-handle` (as returned by `(Type make …)`); `#f` otherwise. Returns `#f` for nil or objects without a type.

```x
(def my-t (Type make "my-type" (list)))
(Type ? (Type make-instance my-t 42) my-t) -> #t
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

Short-circuit logical AND. Evaluates each `expr` left to right. **Short-circuits
to `#f`** — not to the falsy value that stopped it. If every value is truthy,
returns the last one; with no arguments, returns `#t`.

The last expression is returned as-is, so a falsy value in final position comes
back unchanged: `(and 1 ())` is `()`, while `(and 1 () 3)` is `#f`. Falsy is
`{(), #f}`, and only a short circuit normalizes it.

```x-repl
(and 1 2 3) -> 3
(and 1 () 3) -> #f
(and 1 ()) -> ()
(and) -> #t
```

### `or`

`(or expr ...) -> value`

Short-circuit logical OR. Evaluates each `expr` left to right, returning the
first truthy value. If every value is falsy it returns **the last one**, not a
normalized `()`: `(or () #f)` is `#f` and `(or #f ())` is `()`. With no
arguments, returns `()`.

```x-repl
(or () () 3) -> 3
(or 1 2) -> 1
(or () #f) -> #f
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

### `Io read`

`(Io read) -> obj`

Reads and parses one s-expression from stdin. Returns the parsed object.

```x-repl
(Io read) -> <parsed s-expression from stdin>
```

### `Io read-char`

`(Io read-char) -> char | ()`

Reads a single character from stdin. Returns a character object, or `()` on end-of-input.

```x-repl
(Io read-char) -> <char>
```

---

### Strings

THESE ARE COORDINATES, NOT BARE NAMES. The `str`, `sym` and `mem` namespaces are
de-registered once the library is up: the bare spellings are dropped and the
catalog is the door, so a call reads `((prim-ref (lit str) (lit byte-len)) s)`.
That is deliberate — the names belong to the library, which puts `Str8` and
friends in front of these — and it is why the examples below look the way they
do rather than like the `string-length` family they replaced.

BYTES, NOT CHARACTERS. Every operation here counts bytes. UTF-8 is a library
concern (`x/codec/utf8`, `Str8` / `StrUtf8`); the engine stores bytes and a NUL
terminator, and bytes past the NUL are unobservable.

### `str byte-len`

`((prim-ref (lit str) (lit byte-len)) str) -> integer`

The length of `str` in bytes.

```x-repl
((prim-ref (lit str) (lit byte-len)) "hello") -> 5
((prim-ref (lit str) (lit byte-len)) "") -> 0
```

### `str byte-ref`

`((prim-ref (lit str) (lit byte-ref)) str index) -> char`

The character at the zero-based byte `index`.

```x-repl
((prim-ref (lit str) (lit byte-ref)) "hello" 0) -> #\h
((prim-ref (lit str) (lit byte-ref)) "hello" 4) -> #\o
```

### `str append`

`((prim-ref (lit str) (lit append)) str1 str2) -> string`

Concatenates two strings, returning a new one.

```x-repl
((prim-ref (lit str) (lit append)) "hello" " world") -> "hello world"
```

### `str byte-sub`

`((prim-ref (lit str) (lit byte-sub)) str start len) -> string`

A new string of `len` bytes starting at zero-based `start`.

**The third argument is a LENGTH, not an end index.** Both readings agree at
`start` 0, which is why a library caller passed `(+ off n)` here for months and
only fields at a non-zero offset came back wrong (found by the conformance
suite, which uses a non-zero start on purpose).

```x-repl
((prim-ref (lit str) (lit byte-sub)) "hello" 1 3) -> "ell"
```

### `mem cmp`

`((prim-ref (lit mem) (lit cmp)) a b n) -> 0 | -1 | 1`

Block comparison over `n` bytes: a true `memcmp`, so NULs do not terminate it.
This is what string equality bottoms out in; there is no `string=?` primitive.

```x-repl
((prim-ref (lit mem) (lit cmp)) "abc" "abc" 3) -> 0
((prim-ref (lit mem) (lit cmp)) "abc" "xyz" 3) -> -1
```

### `str ->sym` / `sym ->str`

`((prim-ref (lit str) (lit ->sym)) str) -> symbol`
`((prim-ref (lit sym) (lit ->str)) sym) -> string`

Interning, both ways. Symbols intern per base, so the same spelling on either
side of a `base make` boundary gives two different objects.

```x-repl
((prim-ref (lit str) (lit ->sym)) "hello") -> 'hello
((prim-ref (lit sym) (lit ->str)) (lit hello)) -> "hello"
```

### Numbers and strings: not here

There is no `number->string` or `string->number` primitive, and no `convert`
coordinate in the ISA — number formatting and parsing are library code
(`x/type/convert`, `Str8`, the numeric tower). This section documented both for
a long time; nothing implemented them.

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

### Meta

### `Base make`

`(Base make) -> base`

Creates a fresh, sandboxed interpreter base environment with all built-in types and primitives registered. The new base has its own environment, type registry, and read buffer.

```x-repl
(def b (Base make)) -> <base>
```

### `Base eval`

`(Base eval base expr) -> value`

Evaluates expression `expr` in the target `base` environment. List nil terminators are rewritten to match the target base. Errors in the target base propagate to the calling base if a `guard` handler is installed.

```x
(def b (Base make))
(Base eval b '(+ 1 2)) -> 3
```

### `Base bind`

`(Base bind base name value) -> value`

Binds `name` to `value` in the target `base` environment. List values are rewritten to use the target base's nil. All arguments are evaluated in the calling environment before binding in the target.

```x
(def b (Base make))
(Base bind b 'x 42) -> 42
```

---

### Types

These are C primitives filed in the catalog under namespace `type`; the bare
names are **de-registered** (R5). The surface is the `Type` class (methods
`make`, `make-instance`, `?`, `of`, `name`); load-time/hot code fetches via
`(prim-ref 'type 'make)` etc.

### `Type make`

`(Type make name handlers) -> type-handle`

Creates a new runtime type with string `name` and an association list of `handlers`. Supported handler keys include `call`, `write`, `analyse`, `read`, `iter`, `from`, `to`, and `ops`, each mapping to a closure. Returns a type handle atom used to create instances and check types.

```x-repl
(def my-type (Type make "my-type" (list (pair 'call (fn (_ obj . args) args))))) -> <type-handle>
```

### `Type make-instance`

`(Type make-instance type-handle data) -> instance`

Creates a new instance of the runtime type identified by `type-handle`, storing `data` as its contents. Returns `()` if the type handle is not registered.

```x
(def my-t (Type make "my-type" (list)))
(Type make-instance my-t 42) -> <instance>
```

### `Type ?`

`(Type ? obj type-handle) -> #t | #f`

Returns `#t` if the runtime type of `obj` matches `type-handle`; `#f` otherwise. Returns `#f` for nil or objects without a type. Documented above in Predicates.

### `Type of`

`(Type of value) -> type-handle | ()`

Returns the runtime type handle of `value` (`()` for nil). The handle is the interned name atom; conversions and dispatch key on it.

### `Type name`

`(Type name obj-or-handle) -> string | ()`

Returns the name string of `obj`'s runtime type, or of a type handle directly. Returns `()` if `obj` is nil or has no type.

```x
(def my-t (Type make "my-type" (list)))
(Type name (Type make-instance my-t 42)) -> "my-type"
```

---

### System

### `heap collect`

`((prim-ref (lit heap) (lit collect))) -> ()`

Triggers garbage collection by marking all objects reachable from the base
environment. Returns `()`.

There is no bare `gc`: collection is a coordinate in the `heap` namespace,
which is de-registered, so `prim-ref` is the door. The sibling coordinates —
`heap count`, `heap mark`, `heap pin!`, `heap mark-hook!`, `heap free-hook!` —
reach the collector the same way.

```x-repl
((prim-ref (lit heap) (lit collect))) -> ()
```
