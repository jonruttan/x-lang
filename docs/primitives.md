# Computational Expressions in C

## Primitives

All primitives receive unevaluated arguments (fexpr-style) and evaluate what they need internally. Boolean true is `#t`; boolean false is `#f`. Nil is `()` (the empty list).

---

### Quoting

### `lit`

`(lit expr) -> expr`

Returns `expr` unevaluated. This is the quoting primitive; the argument is never evaluated.

```
(lit (+ 1 2)) -> (+ 1 2)
```

---

### Pairs

### `pair`

`(pair a b) -> (a . b)`

Constructs a pair (cons cell) from evaluated `a` and `b`.

```
(pair 1 2) -> (1 . 2)
```

### `first`

`(first p) -> obj`

Returns the first element (car) of pair `p`.

```
(first (pair 1 2)) -> 1
```

### `rest`

`(rest p) -> obj`

Returns the rest element (cdr) of pair `p`.

```
(rest (pair 1 2)) -> 2
```

---

### Equality

### `eq?`

`(eq? a b) -> #t | #f`

Tests pointer identity of evaluated `a` and `b`. Returns `#t` if `a` and `b` are the exact same object; `#f` otherwise.

```
(eq? (lit x) (lit x)) -> #t
(eq? 1 1) -> #f
```

### `=`

`(= a b) -> #t | #f`

Tests numeric value equality of evaluated `a` and `b`. Compares the integer values regardless of object identity.

```
(= 1 1) -> #t
(= 1 2) -> #f
```

---

### Comparison

### `<`

`(< a b) -> #t | #f`

Returns `#t` if integer `a` is strictly less than integer `b`.

```
(< 1 2) -> #t
(< 2 1) -> #f
```

### `>`

`(> a b) -> #t | #f`

Returns `#t` if integer `a` is strictly greater than integer `b`.

```
(> 2 1) -> #t
(> 1 2) -> #f
```

### `<=`

`(<= a b) -> #t | #f`

Returns `#t` if integer `a` is less than or equal to integer `b`.

```
(<= 1 1) -> #t
(<= 2 1) -> #f
```

### `>=`

`(>= a b) -> #t | #f`

Returns `#t` if integer `a` is greater than or equal to integer `b`.

```
(>= 1 1) -> #t
(>= 0 1) -> #f
```

---

### Arithmetic

### `+`

`(+ a ...) -> integer`

Variadic addition. Evaluates all arguments and returns their sum. Identity element is `0`; `(+)` returns `0`.

```
(+ 1 2 3) -> 6
(+) -> 0
```

### `-`

`(- a ...) -> integer`

Variadic subtraction. With one argument, negates it. With two or more, subtracts all subsequent values from the first. With no arguments, returns `0`.

```
(- 5 3) -> 2
(- 5) -> -5
(- 10 3 2) -> 5
(-) -> 0
```

### `*`

`(* a ...) -> integer`

Variadic multiplication. Evaluates all arguments and returns their product. Identity element is `1`; `(*)` returns `1`.

```
(* 2 3 4) -> 24
(*) -> 1
```

### `/`

`(/ a ...) -> integer`

Variadic integer division. With no arguments, returns `1` (identity). With one argument, returns that value unchanged. With two or more, divides the first by each subsequent value left to right.

```
(/ 10 2) -> 5
(/ 100 2 5) -> 10
(/) -> 1
```

### `%`

`(% a ...) -> integer`

Variadic integer modulo. With no arguments, returns `0`. With one argument, returns that value unchanged. With two or more, applies modulo left to right.

```
(% 10 3) -> 1
(% 17 10 3) -> 1
(%) -> 0
```

---

### Bitwise

### `~`

`(~ n) -> integer`

Bitwise NOT (one's complement) of integer `n`.

```
(~ 0) -> -1
(~ -1) -> 0
```

### `&`

`(& a b) -> integer`

Bitwise AND of integers `a` and `b`.

```
(& 6 3) -> 2
(& 255 15) -> 15
```

### `|`

`(| a b) -> integer`

Bitwise OR of integers `a` and `b`.

```
(| 6 3) -> 7
(| 0 5) -> 5
```

### `^`

`(^ a b) -> integer`

Bitwise XOR of integers `a` and `b`.

```
(^ 6 3) -> 5
(^ 5 5) -> 0
```

### `<<`

`(<< a b) -> integer`

Left bit shift of integer `a` by `b` positions.

```
(<< 1 4) -> 16
(<< 3 2) -> 12
```

### `>>`

`(>> a b) -> integer`

Right bit shift of integer `a` by `b` positions (arithmetic shift).

```
(>> 16 4) -> 1
(>> 12 2) -> 3
```

---

### Binding

### `def`

`(def name expr) -> value`

Binds `name` (unevaluated symbol) to the result of evaluating `expr` in the current environment. The binding is created before `expr` is evaluated, which enables recursive definitions: the name is visible inside `expr`'s evaluation.

```
(def x 42) -> 42
(def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) -> <procedure>
```

### `set`

`(set name expr) -> value`

Mutates an existing binding of `name` to the result of evaluating `expr`. Signals an error if `name` is not already bound in the current environment.

```
(def x 1) -> 1
(set x 2) -> 2
(set unbound 0) -> error: Unbound symbol
```

---

### Control

### `if`

`(if cond then [else]) -> value`

Evaluates `cond`. If truthy (not `()`), tail-evaluates `then`. If falsy, tail-evaluates `else` when provided, or returns `()`. Uses tail-call optimization for the selected branch.

```
(if #t 1 2) -> 1
(if () 1 2) -> 2
(if () 1) -> ()
```

### `do`

`(do form ...) -> value`

Evaluates each `form` in sequence and returns the value of the last one. The final form is tail-evaluated for TCO. With no arguments, returns `()`.

```
(do 1 2 3) -> 3
(do (def x 1) (+ x 1)) -> 2
```

### `match`

`(match (test expr) ...) -> value`

Multi-branch conditional (cond-style). Evaluates each `test` in order; for the first truthy test, tail-evaluates the corresponding `expr` and returns it. Returns `()` if no test succeeds.

```
(match
  ((= 1 2) 10)
  ((= 1 1) 20)
  (#t 30)) -> 20
```

### `let`

`(let ((name val) ...) body ...) -> value`

Creates local bindings by evaluating each `val` in the current environment, then evaluates `body` forms in the extended environment. The final body form is tail-evaluated. Environment is restored after `let` completes.

```
(let ((x 1) (y 2)) (+ x y)) -> 3
(let ((x 10)) x) -> 10
```

---

### Functions

### `fn`

`(fn (params ...) body ...) -> procedure`

Creates a closure (applicative, lexically scoped). `params` are not evaluated; they name the formal parameters. Supports variadic binding: if `params` is a single symbol instead of a list, it captures the entire argument list.

```
(def add (fn (a b) (+ a b)))
(add 1 2) -> 3
(def id (fn args args))
(id 1 2 3) -> (1 2 3)
```

### `op`

`(op formals env-param body ...) -> operative`

Creates an operative (user-level fexpr). Like `fn`, but receives arguments unevaluated. `formals` binds the raw argument tree, and `env-param` binds the dynamic environment, giving the operative manual control over evaluation.

```
(def my-quote (op (x) e x))
(my-quote (+ 1 2)) -> (+ 1 2)
```

### `apply`

`(apply f args) -> value`

Calls callable `f` with a pre-evaluated list of arguments `args`. Works with both closures and C primitives. Arguments in the list are not re-evaluated.

```
(apply + (list 1 2 3)) -> 6
(apply first (list (list 1 2))) -> 1
```

### `eval`

`(eval expr [env]) -> value`

Evaluates the already-evaluated expression `expr`. With an optional `env` argument, evaluates `expr` in that environment instead of the current one. The environment is restored after evaluation.

```
(eval (lit (+ 1 2))) -> 3
```

### `wrap`

`(wrap combiner) -> applicative`

Wraps a combiner (operative or primitive) to create an applicative that evaluates its arguments before passing them to the underlying combiner.

```
(def my-op (op (x) e x))
(def my-fn (wrap my-op))
(my-fn (+ 1 2)) -> 3
```

### `unwrap`

`(unwrap applicative) -> combiner`

Extracts the underlying combiner from an applicative created by `wrap`.

```
(unwrap (wrap (op (x) e x))) -> <operative>
```

---

### Predicates

### `null?`

`(null? x) -> #t | #f`

Returns `#t` if `x` evaluates to nil (`()`); `#f` otherwise.

```
(null? ()) -> #t
(null? 1) -> #f
```

### `pair?`

`(pair? x) -> #t | #f`

Returns `#t` if `x` evaluates to a list pair; `#f` otherwise.

```
(pair? (list 1 2)) -> #t
(pair? 1) -> #f
```

### `atom?`

`(atom? x) -> #t | #f`

Returns `#t` if `x` evaluates to a non-pair (atom); `#f` if it is a list pair. The inverse of `pair?`.

```
(atom? 1) -> #t
(atom? (list 1 2)) -> #f
```

### `not`

`(not x) -> #t | #f`

Logical negation. Returns `#t` if `x` evaluates to nil; `#f` otherwise. Equivalent to `null?`.

```
(not ()) -> #t
(not 1) -> #f
```

### `number?`

`(number? x) -> #t | #f`

Returns `#t` if `x` evaluates to an integer; `#f` otherwise.

```
(number? 42) -> #t
(number? "hello") -> #f
```

### `string?`

`(string? x) -> #t | #f`

Returns `#t` if `x` evaluates to a string; `#f` otherwise.

```
(string? "hello") -> #t
(string? 42) -> #f
```

### `symbol?`

`(symbol? x) -> #t | #f`

Returns `#t` if `x` evaluates to a symbol; `#f` otherwise.

```
(symbol? (lit x)) -> #t
(symbol? 42) -> #f
```

### `procedure?`

`(procedure? x) -> #t | #f`

Returns `#t` if `x` evaluates to a callable (closure or C primitive); `#f` otherwise.

```
(procedure? +) -> #t
(procedure? 42) -> #f
```

### `char?`

`(char? x) -> #t | #f`

Returns `#t` if `x` evaluates to a character object; `#f` otherwise.

```
(char? (read-char)) -> #t
(char? 42) -> #f
```

### `type?`

`(type? obj type-handle) -> #t | #f`

Returns `#t` if the runtime type of `obj` matches `type-handle` (as returned by `make-type`); `#f` otherwise. Returns `#f` for nil or objects without a type.

```
(def my-t (make-type "my-type" (list)))
(type? (make-instance my-t 42) my-t) -> #t
```

---

### Lists

### `list`

`(list a ...) -> (a ...)`

Constructs a proper list from zero or more evaluated arguments. `(list)` returns `()`.

```
(list 1 2 3) -> (1 2 3)
(list) -> ()
```

---

### Logic

### `and`

`(and expr ...) -> value`

Short-circuit logical AND. Evaluates each `expr` left to right. Returns `()` at the first falsy value. If all values are truthy, returns the last one. With no arguments, returns `#t`.

```
(and 1 2 3) -> 3
(and 1 () 3) -> ()
(and) -> #t
```

### `or`

`(or expr ...) -> value`

Short-circuit logical OR. Evaluates each `expr` left to right. Returns the first truthy value. If all values are falsy, returns `()`. With no arguments, returns `()`.

```
(or () () 3) -> 3
(or 1 2) -> 1
(or) -> ()
```

---

### I/O

### `write`

`(write obj) -> ()`

Outputs the s-expression representation of evaluated `obj` to stdout (strings are quoted, special characters escaped). Returns `()`.

```
(write "hello") -> ()  ; prints "hello" (with quotes)
```

### `display`

`(display obj) -> ()`

Outputs the human-readable representation of evaluated `obj` to stdout. Strings are printed without surrounding quotes; all other types use s-expression format. Returns `()`.

```
(display "hello") -> ()  ; prints hello (without quotes)
(display 42) -> ()       ; prints 42
```

### `newline`

`(newline) -> ()`

Outputs a newline character to stdout. Takes no arguments. Returns `()`.

```
(newline) -> ()  ; prints \n
```

### `read`

`(read) -> obj`

Reads and parses one s-expression from stdin. Returns the parsed object.

```
(read) -> <parsed s-expression from stdin>
```

### `read-char`

`(read-char) -> char | ()`

Reads a single character from stdin. Returns a character object, or `()` on end-of-input.

```
(read-char) -> <char>
```

---

### Strings

### `string-length`

`(string-length str) -> integer`

Returns the length of string `str` in bytes.

```
(string-length "hello") -> 5
(string-length "") -> 0
```

### `string-ref`

`(string-ref str index) -> string`

Returns a single-character string at the given zero-based `index` in `str`.

```
(string-ref "hello" 0) -> "h"
(string-ref "hello" 4) -> "o"
```

### `string-append`

`(string-append str1 str2) -> string`

Concatenates two strings and returns a new string.

```
(string-append "hello" " world") -> "hello world"
```

### `substring`

`(substring str start end) -> string`

Returns a new string extracted from `str` starting at index `start` (inclusive) up to `end` (exclusive). Indices are zero-based.

```
(substring "hello" 1 3) -> "el"
```

### `string=?`

`(string=? str1 str2) -> #t | #f`

Returns `#t` if strings `str1` and `str2` have equal contents; `#f` otherwise.

```
(string=? "abc" "abc") -> #t
(string=? "abc" "xyz") -> #f
```

### `string->symbol`

`(string->symbol str) -> symbol`

Converts a string to an interned symbol with the same name.

```
(string->symbol "hello") -> hello
```

### `symbol->string`

`(symbol->string sym) -> string`

Converts a symbol to a string containing the symbol's name.

```
(symbol->string (lit hello)) -> "hello"
```

### `number->string`

`(number->string n) -> string`

Converts integer `n` to its decimal string representation.

```
(number->string 42) -> "42"
(number->string -1) -> "-1"
```

### `string->number`

`(string->number str) -> integer`

Parses a string as an integer and returns the numeric value. Supports base detection via prefix (e.g. `0x` for hex).

```
(string->number "42") -> 42
(string->number "0xff") -> 255
```

---

### Quasiquote

### `quasi`

`(quasi template) -> obj`

Quasiquote expansion. Returns `template` with `unquote` and `unquote-splicing` forms evaluated. Atoms and non-list values are returned as-is. `(unquote expr)` within the template is replaced by the evaluated `expr`. `(unquote-splicing expr)` splices the evaluated list into the surrounding list.

```
(def x 1)
(quasi (a (unquote x) b)) -> (a 1 b)
(def xs (list 2 3))
(quasi (1 (unquote-splicing xs) 4)) -> (1 2 3 4)
```

---

### Errors

### `guard`

`(guard (var handler-body ...) body ...) -> value`

Error recovery form. Evaluates `body` forms in sequence. If an error is signalled during evaluation, binds the error value to `var` and evaluates `handler-body` forms instead. The environment is restored to its state before `body` after an error. Handlers can be nested.

```
(guard (e (display e) (newline) 0)
  (error "oops")) -> 0  ; prints oops
```

### `error`

`(error message) -> <does not return>`

Signals an error with the evaluated `message`. If a `guard` handler is installed, the error is caught and `message` is bound to the handler variable. If no handler is installed, the error is fatal. `message` may be a string or any object.

```
(error "something went wrong") -> <error signalled>
```

---

### Meta

### `make-base`

`(make-base) -> base`

Creates a fresh, sandboxed interpreter base environment with all built-in types and primitives registered. The new base has its own environment, type registry, and read buffer.

```
(def b (make-base)) -> <base>
```

### `base-eval`

`(base-eval base expr) -> value`

Evaluates expression `expr` in the target `base` environment. List nil terminators are rewritten to match the target base. Errors in the target base propagate to the calling base if a `guard` handler is installed.

```
(def b (make-base))
(base-eval b (lit (+ 1 2))) -> 3
```

### `base-bind`

`(base-bind base name value) -> value`

Binds `name` to `value` in the target `base` environment. List values are rewritten to use the target base's nil. All arguments are evaluated in the calling environment before binding in the target.

```
(def b (make-base))
(base-bind b (lit x) 42) -> 42
```

---

### Types

### `make-type`

`(make-type name handlers) -> type-handle`

Creates a new runtime type with string `name` and an association list of `handlers`. Supported handler keys are `call`, `write`, and `length`, each mapping to a closure. Returns a type handle atom used to create instances and check types.

```
(def my-type (make-type "my-type" (list (pair (lit call) (fn (obj args) args))))) -> <type-handle>
```

### `make-instance`

`(make-instance type-handle data) -> instance`

Creates a new instance of the runtime type identified by `type-handle`, storing `data` as its contents. Returns `()` if the type handle is not registered.

```
(def my-t (make-type "my-type" (list)))
(make-instance my-t 42) -> <instance>
```

### `type?`

`(type? obj type-handle) -> #t | #f`

Returns `#t` if the runtime type of `obj` matches `type-handle`; `#f` otherwise. Returns `#f` for nil or objects without a type. Documented above in Predicates.

### `type-name`

`(type-name obj) -> string | ()`

Returns the name string of `obj`'s runtime type. Returns `()` if `obj` is nil or has no type.

```
(def my-t (make-type "my-type" (list)))
(type-name (make-instance my-t 42)) -> "my-type"
```

---

### System

### `gc`

`(gc) -> ()`

Triggers garbage collection by marking all objects reachable from the base environment. Returns `()`.

```
(gc) -> ()
```
