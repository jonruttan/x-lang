# x-lang Specification

**Version:** 0.2.0

This document is the normative specification for x-lang. Each section maps 1:1
to a test file in `tests/x/specs/`. Behavior described here MUST be implemented
and tested. Items marked **TBD** have uncertain semantics and need investigation.

All primitives receive unevaluated arguments (fexpr-style) and evaluate what
they need internally. Boolean true is the symbol `t`; false/nil is the base
environment object (displayed as `()`).

x-lang uses the fexpr evaluation model: every combiner at the C level receives
its arguments unevaluated. Applicative semantics (automatic argument evaluation)
are provided by `fn`, which wraps a closure. This is the inverse of most Lisps
where functions evaluate arguments by default and macros are the special case.
In x-lang, operatives (`op`) are the default and applicatives (`fn`) are the
special case. This follows the Kernel language design.

---

## 1. Evaluation Model

### Self-evaluation

Integers, strings, and characters evaluate to themselves.

```
42 -> 42
"hello" -> "hello"
#\a -> a
```

### Symbol lookup

A symbol evaluates to the value bound to it in the current environment. An
unbound symbol signals an error.

```
(def x 10)
x -> 10
```

### List evaluation

A list `(f args ...)` evaluates `f` to obtain a combiner, then applies it. For
applicatives (created by `fn` or `wrap`), each argument is evaluated before the
call. For operatives (created by `op` or C primitives), arguments are passed
unevaluated.

### Nil

The empty list `()` is the base environment object. It is falsy and serves as
the sole false value. `()` self-evaluates.

```
() -> ()
```

### Tail-call optimization

The following forms evaluate their final expression in tail position:

- `if`: the selected branch
- `do`: the last body form
- `match`: the body of the matching clause
- `let`: the last body form
- `fn`: the last body form
- `and`: the last expression
- `or`: the last expression
- `apply`: the last body form of the applied procedure

Proper tail calls MUST NOT grow the stack. A tail-recursive loop MUST be able
to iterate without limit.

```
(def loop (fn (n) (if (= n 0) t (loop (- n 1)))))
(loop 1000000) -> t
```

### Mutual recursion

Mutually tail-recursive functions MUST also run in constant stack space.

```
(def even-tc (fn (n) (if (= n 0) t (odd-tc (- n 1)))))
(def odd-tc (fn (n) (if (= n 0) () (even-tc (- n 1)))))
(even-tc 100000) -> t
```

---

## 2. Core Forms

### `lit`

`(lit expr) -> expr`

Returns `expr` unevaluated. This is the quoting primitive.

```
(lit (+ 1 2)) -> (+ 1 2)
(lit abc) -> abc
```

### `pair`

`(pair a b) -> (a . b)`

Constructs a pair from evaluated `a` and `b`.

```
(pair 1 2) -> (1 . 2)
(pair 1 (pair 2 ())) -> (1 2)
```

### `first`

`(first p) -> obj`

Returns the first element of pair `p`. Calling `(first ())` is undefined.

```
(first (pair 1 2)) -> 1
(first (list 10 20 30)) -> 10
```

### `rest`

`(rest p) -> obj`

Returns the rest element of pair `p`. Calling `(rest ())` is undefined.

```
(rest (pair 1 2)) -> 2
(rest (list 10 20 30)) -> (20 30)
```

### `list`

`(list a ...) -> (a ...)`

Constructs a proper list from zero or more evaluated arguments.

```
(list 1 2 3) -> (1 2 3)
(list) -> ()
```

### `def`

`(def name expr) -> value`

Binds `name` (unevaluated symbol) to the result of evaluating `expr` in the
current environment. The binding is created before `expr` is evaluated, enabling
recursive definitions. `def` always creates a new binding; it shadows any
existing binding with the same name rather than replacing it.

```
(def x 42) -> 42
```

### `set`

`(set name expr) -> value`

Mutates an existing binding of `name` to the result of evaluating `expr`.
Walks the scope chain to find the nearest enclosing binding of `name` and
modifies it in place. Signals an error if `name` is not bound in any scope.

```
(def x 1)
(set x 2)
x -> 2
```

### `if`

`(if cond then [else]) -> value`

Evaluates `cond`. If truthy, tail-evaluates `then`. If falsy, tail-evaluates
`else` (or returns `()` if omitted).

```
(if t 1 2) -> 1
(if () 1 2) -> 2
(if () 1) -> ()
```

### `do`

`(do form ...) -> value`

Evaluates each `form` in sequence and returns the last value. The final form is
tail-evaluated. With no arguments, returns `()`.

```
(do 1 2 3) -> 3
(do (def x 1) (+ x 1)) -> 2
```

### `match`

`(match (test expr) ...) -> value`

Multi-branch conditional. Evaluates each `test` in order; for the first truthy
test, tail-evaluates the corresponding `expr` and returns it. Returns `()` if
no test succeeds. Each clause has exactly ONE body form; for multiple
expressions, wrap in `do`.

```
(match
  ((= 1 2) 10)
  ((= 1 1) 20)
  (t 30)) -> 20
```

### `let`

`(let ((name val) ...) body ...) -> value`

Creates local bindings, evaluates `body` forms in the extended environment, and
returns the last value. The final body form is tail-evaluated. Environment is
restored after `let` completes.

```
(let ((x 1) (y 2)) (+ x y)) -> 3
(let ((x 10)) x) -> 10
```

### List indexing

Lists support direct indexing when called as functions. A single integer
argument returns the element at that zero-based index. Negative indices count
from the end. Two integer arguments `(lst start len)` return a sublist.

```
(def xs (list 10 20 30 40))
(xs 0) -> 10
(xs 2) -> 30
(xs -1) -> 40
(xs 1 2) -> (20 30)
```

---

## 3. Closures & Operatives

### `fn`

`(fn (params ...) body ...) -> procedure`

Creates a closure (applicative). Arguments are evaluated before binding.
Supports variadic: if `params` is a single symbol, it captures the entire
argument list. A dotted-pair parameter list `(a b . rest)` binds named
parameters and collects remaining arguments into `rest`.

```
(def add (fn (a b) (+ a b)))
(add 1 2) -> 3
(def id (fn args args))
(id 1 2 3) -> (1 2 3)
(def f (fn (a b . rest) rest))
(f 1 2 3 4 5) -> (3 4 5)
```

Closures capture their lexical environment:

```
(def make-adder (fn (n) (fn (x) (+ n x))))
((make-adder 10) 5) -> 15
```

### `op`

`(op formals env-param body ...) -> operative`

Creates an operative (fexpr). Like `fn`, but arguments are NOT evaluated.
`formals` binds the raw argument tree, `env-param` binds the dynamic
environment.

```
(def my-quote (op (x) e x))
(my-quote (+ 1 2)) -> (+ 1 2)
```

The environment parameter can be used for selective evaluation:

```
(def my-if (op (c t f) e (if (eval c e) (eval t e) (eval f e))))
(my-if (= 1 1) "yes" "no") -> "yes"
```

### `wrap`

`(wrap combiner) -> applicative`

Wraps a combiner to create an applicative that evaluates arguments before
passing them to the underlying combiner.

```
(def my-op (op (x) e x))
(def my-fn (wrap my-op))
(my-fn (+ 1 2)) -> 3
```

### `unwrap`

`(unwrap applicative) -> combiner`

Extracts the underlying combiner from an applicative. Calling `unwrap` on a
value that was not created by `wrap` is undefined behavior.

```
(def my-op (op (x) e x))
(def my-fn (wrap my-op))
((unwrap my-fn) (+ 1 2)) -> (+ 1 2)
```

### `apply`

`(apply f args) -> value`

Calls callable `f` with a pre-evaluated list of arguments. Arguments are not
re-evaluated. When applying a C primitive, the arguments must be self-evaluating
values (integers, strings, etc.) since primitives may internally evaluate their
arguments.

```
(apply + (list 1 2 3)) -> 6
(apply list (list 1 2 3)) -> (1 2 3)
```

### `eval`

`(eval expr [env]) -> value`

Evaluates expression `expr`. With optional `env`, evaluates in that environment.

```
(eval (lit (+ 1 2))) -> 3
```

---

## 4. Logic & Control

### `and`

`(and expr ...) -> value`

Short-circuit logical AND. Evaluates each `expr` left to right. Returns `()`
at the first falsy value. If all truthy, returns the last value. `(and)` returns
`t`.

```
(and 1 2 3) -> 3
(and 1 () 3) -> ()
(and) -> t
```

### `or`

`(or expr ...) -> value`

Short-circuit logical OR. Returns the first truthy value. If all falsy, returns
`()`. `(or)` returns `()`.

```
(or () () 3) -> 3
(or 1 2) -> 1
(or) -> ()
```

### `not`

`(not x) -> t | ()`

Logical negation. Returns `t` if `x` is nil; `()` otherwise.

```
(not ()) -> t
(not 1) -> ()
(not t) -> ()
```

### `guard`

`(guard (var handler-body ...) body ...) -> value`

Error recovery. Evaluates `body` forms. If an error is signalled, binds the
error value to `var` and evaluates `handler-body` instead. Handlers nest.

```
(guard (e e) (error "oops")) -> "oops"
(guard (e "caught") (+ 1 2)) -> 3
```

Nested guards:

```
(guard (e (string-append "outer: " e))
  (guard (e (error (string-append "re: " e)))
    (error "inner"))) -> "outer: re: inner"
```

### `error`

`(error message) -> <does not return>`

Signals an error. If a `guard` handler is installed, the error is caught.
Without a handler, `error` terminates the process.

```
(guard (e e) (error "fail")) -> "fail"
```

---

## 5. Arithmetic

All arithmetic operators are variadic and evaluate their arguments.

### `+`

`(+ a ...) -> integer`

Addition. Identity: `0`.

```
(+ 1 2 3) -> 6
(+) -> 0
(+ 5) -> 5
```

### `-`

`(- a ...) -> integer`

Subtraction. One argument: negation. Zero arguments: `0`.

```
(- 5 3) -> 2
(- 5) -> -5
(- 10 3 2) -> 5
(-) -> 0
```

### `*`

`(* a ...) -> integer`

Multiplication. Identity: `1`.

```
(* 2 3 4) -> 24
(*) -> 1
```

### `/`

`(/ a ...) -> integer`

Integer division. Identity: `1`. Division by zero is undefined.

```
(/ 10 2) -> 5
(/ 100 2 5) -> 10
(/) -> 1
```

### `%`

`(% a ...) -> integer`

Integer modulo. Identity: `0`. Modulo by zero is undefined.

```
(% 10 3) -> 1
(% 17 10 3) -> 1
(%) -> 0
```

### `~`

`(~ n) -> integer`

Bitwise NOT (one's complement).

```
(~ 0) -> -1
(~ -1) -> 0
```

### `&`

`(& a b) -> integer`

Bitwise AND.

```
(& 6 3) -> 2
(& 255 15) -> 15
```

### `|`

`(| a b) -> integer`

Bitwise OR.

```
(| 6 3) -> 7
(| 0 5) -> 5
```

### `^`

`(^ a b) -> integer`

Bitwise XOR.

```
(^ 6 3) -> 5
(^ 5 5) -> 0
```

### `<<`

`(<< a b) -> integer`

Left shift.

```
(<< 1 4) -> 16
(<< 3 2) -> 12
```

### `>>`

`(>> a b) -> integer`

Right shift (arithmetic).

```
(>> 16 4) -> 1
(>> 12 2) -> 3
```

---

## 6. Predicates

### `eq?`

`(eq? a b) -> t | ()`

Pointer identity. Returns `t` if `a` and `b` are the exact same object.
Symbols with the same name are interned and thus `eq?`.

```
(eq? (lit x) (lit x)) -> t
(eq? 1 1) -> ()
```

### `=`

`(= a b) -> t | ()`

Numeric/value equality. Compares integer values (and characters by code point).
Comparing values of different types is undefined.

```
(= 1 1) -> t
(= 1 2) -> ()
```

### `<`

`(< a b) -> t | ()`

```
(< 1 2) -> t
(< 2 1) -> ()
```

### `>`

`(> a b) -> t | ()`

```
(> 2 1) -> t
(> 1 2) -> ()
```

### `<=`

`(<= a b) -> t | ()`

```
(<= 1 1) -> t
(<= 2 1) -> ()
```

### `>=`

`(>= a b) -> t | ()`

```
(>= 1 1) -> t
(>= 0 1) -> ()
```

### `null?`

`(null? x) -> t | ()`

Returns `t` if `x` is nil.

```
(null? ()) -> t
(null? 1) -> ()
```

### `pair?`

`(pair? x) -> t | ()`

Returns `t` if `x` is a pair.

```
(pair? (list 1 2)) -> t
(pair? 1) -> ()
```

### `atom?`

`(atom? x) -> t | ()`

Returns `t` if `x` is not a pair. Inverse of `pair?`.

```
(atom? 1) -> t
(atom? (list 1 2)) -> ()
```

### `number?`

`(number? x) -> t | ()`

```
(number? 42) -> t
(number? "hello") -> ()
```

### `string?`

`(string? x) -> t | ()`

```
(string? "hello") -> t
(string? 42) -> ()
```

### `symbol?`

`(symbol? x) -> t | ()`

```
(symbol? (lit x)) -> t
(symbol? 42) -> ()
```

### `procedure?`

`(procedure? x) -> t | ()`

Returns `t` if `x` is a `fn` closure, a `wrap` applicative, or a C primitive.
Returns `()` for `op` operatives and all other values.

```
(procedure? +) -> t
(procedure? (fn (x) x)) -> t
(procedure? 42) -> ()
```

### `char?`

`(char? x) -> t | ()`

Returns `t` if `x` is a character object.

```
(char? #\a) -> t
(char? 42) -> ()
```

### `char->integer`

`(char->integer c) -> integer`

Returns the integer code point of character `c`. Passing a non-character value
is undefined.

```
(char->integer #\a) -> 97
(char->integer #\A) -> 65
```

### `integer->char`

`(integer->char n) -> char`

Returns the character with code point `n`.

```
(integer->char 97) -> a
(integer->char 65) -> A
(= (integer->char 97) #\a) -> t
```

---

## 7. Strings

### `string-length`

`(string-length str) -> integer`

Returns the byte length of string `str` (not character count; x-lang strings
are byte arrays with no encoding awareness).

```
(string-length "hello") -> 5
(string-length "") -> 0
```

### `string-ref`

`(string-ref str index) -> char`

Returns the character at zero-based `index` in `str`. Out-of-bounds access is
undefined.

```
(string-ref "hello" 0) -> h
(string-ref "hello" 4) -> o
```

### `string-append`

`(string-append str1 str2) -> string`

Concatenates exactly two strings. For multiple strings, use `reduce`.

```
(string-append "hello" " world") -> "hello world"
(string-append "" "x") -> "x"
```

### `substring`

`(substring str start end) -> string`

Extracts a substring from `start` (inclusive) to `end` (exclusive).
Out-of-bounds indices are undefined.

```
(substring "hello" 1 3) -> "el"
(substring "hello" 0 5) -> "hello"
```

### `string=?`

`(string=? str1 str2) -> t | ()`

String content equality.

```
(string=? "abc" "abc") -> t
(string=? "abc" "xyz") -> ()
```

### `string->symbol`

`(string->symbol str) -> symbol`

Converts a string to an interned symbol.

```
(string->symbol "hello") -> hello
```

### `symbol->string`

`(symbol->string sym) -> string`

Converts a symbol to a string.

```
(symbol->string (lit hello)) -> "hello"
```

### `number->string`

`(number->string n) -> string`

Converts integer to decimal string representation.

```
(number->string 42) -> "42"
(number->string -1) -> "-1"
```

### `string->number`

`(string->number str) -> integer`

Parses string as integer. Supports `0x` prefix for hex. Non-numeric strings
return `0`.

```
(string->number "42") -> 42
(string->number "0xff") -> 255
```

---

## 8. I/O

### `write`

`(write obj) -> ()`

Outputs the s-expression representation of `obj` to stdout. Strings are quoted,
special characters escaped. Returns `()`.

```
(write "hello")   ; outputs: "hello"
(write 42)        ; outputs: 42
(write (list 1 2)) ; outputs: (1 2)
```

### `display`

`(display obj) -> ()`

Outputs human-readable representation. Strings are printed without quotes.
Returns `()`.

```
(display "hello") ; outputs: hello
(display 42)      ; outputs: 42
```

### `newline`

`(newline) -> ()`

Outputs a newline character.

### `read`

`(read) -> obj`

Reads and parses one s-expression from stdin. Behavior at EOF is
implementation-dependent.

### `read-char`

`(read-char) -> char | ()`

Reads a single character from stdin. Returns `()` on end-of-input.

### `gc`

`(gc) -> ()`

Triggers garbage collection.

---

## 9. Quasiquote

### `quasi`

`(quasi template) -> obj`

Quasiquote. Returns `template` with `unquote` and `unquote-splicing` forms
evaluated.

```
(def x 1)
(quasi (a (unquote x) b)) -> (a 1 b)
```

### `unquote`

`(unquote expr)` -- only valid inside `quasi`.

Evaluates `expr` and substitutes the result.

```
(def x 42)
(quasi (unquote x)) -> 42
```

### `unquote-splicing`

`(unquote-splicing expr)` -- only valid inside `quasi`.

Evaluates `expr` (must produce a list) and splices it into the surrounding list.

```
(def xs (list 2 3))
(quasi (1 (unquote-splicing xs) 4)) -> (1 2 3 4)
```

Nested quasiquote:

```
(quasi (quasi (unquote (unquote (lit x))))) -> (quasi (unquote x))
```

---

## 10. Reader Syntax

The reader converts text into s-expressions. The following syntactic forms are
supported:

### Integers

Sequences of digits, optionally preceded by `-` for negative numbers.

```
42 -> 42
-7 -> -7
0 -> 0
```

### Strings

Delimited by `"`. Strings support C-style backslash escape sequences:

| Escape | Byte   | Name            |
|--------|--------|-----------------|
| `\"`   | `0x22` | double quote    |
| `\\`   | `0x5C` | backslash       |
| `\n`   | `0x0A` | newline         |
| `\t`   | `0x09` | tab             |
| `\r`   | `0x0D` | carriage return |
| `\0`   | `0x00` | null            |
| `\xHH` | *HH*   | hex byte        |

Escape sequences are processed at read time: `"\n"` is a one-character string
containing a newline byte. Unknown escape sequences (e.g., `\q`) preserve the
literal backslash and following character. Invalid `\x` sequences (not followed
by two hex digits) also preserve the literal characters.

The `write` function re-escapes special characters so that the output is a valid
string literal: `(write "\n")` prints `"\n"`, not a raw newline.

Note: `\0` produces a null byte, which terminates the string for all operations
that use byte-length (e.g., `string-length`, `string-append`).

```
"hello" -> "hello"
"" -> ""
"a\"b" -> "a\"b"
"a\\b" -> "a\\b"
```

### Symbols

Sequences of non-whitespace, non-parenthesis, non-quote characters that don't
parse as integers.

```
abc -> <symbol>
+ -> <symbol>
my-var? -> <symbol>
```

### Characters

`#\c` where `c` is a single character. Named characters are also supported:

| Syntax       | Character      | Code |
|--------------|----------------|------|
| `#\space`    | space          | 32   |
| `#\newline`  | newline (LF)   | 10   |
| `#\tab`      | horizontal tab | 9    |

```
#\a -> a
(char->integer #\space) -> 32
(char->integer #\newline) -> 10
(char->integer #\tab) -> 9
```

### Lists

`(a b c)` creates a proper list. `(a b . c)` creates a dotted pair where `c`
is the tail.

```
(1 2 3) -> (1 2 3)
(1 . 2) -> (1 . 2)
```

### Quote shorthand

`'expr` is sugar for `(lit expr)`.

```
'abc -> abc
'(1 2 3) -> (1 2 3)
```

### Quasiquote shorthand

`` `expr `` is sugar for `(quasi expr)`.
`,expr` is sugar for `(unquote expr)`.
`,@expr` is sugar for `(unquote-splicing expr)`.

### Comments

`;` begins a line comment; everything until end-of-line is ignored.

```
; this is a comment
42 ; this is also a comment -> 42
```

### Vector literals

`#(a b c)` creates a vector.

```
#(1 2 3) -> #(1 2 3)
```

### Regex literals

`#/pattern/` creates a regex.

```
#/abc/ -> #/abc/
#/a.*b/ -> #/a.*b/
```

---

## 11. Type Extension

### `make-type`

`(make-type name handlers) -> type-handle`

Creates a new runtime type with string `name` and an alist of `handlers`.
Supported handler keys: `call`, `write`, `length`, `analyse`, `delimit`.
Returns a type handle used with `make-instance` and `type?`.

```
(def my-t (make-type "MY-T" (list)))
```

### `make-instance`

`(make-instance type-handle data) -> instance`

Creates a new instance of the type. Data is stored and accessible via
`(first instance)`.

```
(def my-t (make-type "MY-T" (list)))
(def obj (make-instance my-t 42))
(first obj) -> 42
```

Custom type instances self-evaluate:

```
(def obj (make-instance my-t 42))
obj -> <instance>
```

### `type?`

`(type? obj type-handle) -> t | ()`

Returns `t` if `obj`'s runtime type matches `type-handle`.

```
(type? obj my-t) -> t
(type? 42 my-t) -> ()
```

### `type-name`

`(type-name obj) -> string | ()`

Returns the name string of `obj`'s type, or `()` if no type.

```
(type-name obj) -> "MY-T"
(type-name 42) -> "INTEGER"
(type-name "hi") -> "STRING"
```

### `score-match`

`(score-match score length reader) -> score`

Sets the score fields for the tokenizer protocol. `length` is the match length,
`reader` is the read function to call. Used internally by custom type readers.

```
(score-match score 5 my-reader) -> score
```

### Call handler

When a typed instance is called as a function, the `call` handler is invoked
with the instance as `self` followed by the arguments.

```
(def counter-t (make-type "COUNTER"
  (list (pair (lit call) (fn (self . args) (first self))))))
(def c (make-instance counter-t 42))
(c) -> 42
```

### Write handler

When `write` or `display` outputs a typed instance, the `write` handler is
called with the instance as `self`.

```
(def my-t (make-type "SHOW"
  (list (pair (lit write) (fn (self) (display "[") (display (first self)) (display "]"))))))
```

---

## 12. Sandboxing

### `make-base`

`(make-base) -> base`

Creates a fresh, sandboxed interpreter with all built-in types and primitives.

```
(def b (make-base))
```

### `base-eval`

`(base-eval base expr) -> value`

Evaluates `expr` in the target `base` environment.

```
(def b (make-base))
(base-eval b (lit (+ 1 2))) -> 3
```

Bases are isolated:

```
(def b (make-base))
(base-eval b (lit (def x 42)))
(base-eval b (lit x)) -> 42
```

### `base-bind`

`(base-bind base name value) -> value`

Binds `name` to `value` in the target `base`.

```
(def b (make-base))
(base-bind b (lit x) 42)
(base-eval b (lit x)) -> 42
```

---

## 13. Lib: Combinators

Standard library functions for function composition and transformation.

### `identity`

`(identity x) -> x`

Returns its argument unchanged.

```
(identity 42) -> 42
```

### `const`

`(const x) -> (fn (y) x)`

Returns a function that always returns `x`.

```
((const 5) 99) -> 5
```

### `compose`

`(compose f g) -> (fn (x) (f (g x)))`

Right-to-left function composition.

```
((compose inc inc) 3) -> 5
```

### `pipe`

`(pipe f g) -> (fn (x) (g (f x)))`

Left-to-right function composition.

```
((pipe inc inc) 3) -> 5
```

### `curry`

`(curry f x) -> (fn (y) (f x y))`

Partially applies a two-argument function by fixing its first argument.

```
((curry + 10) 5) -> 15
```

### `flip`

`(flip f) -> (fn (a b) (f b a))`

Reverses the arguments of a binary function.

```
((flip -) 1 10) -> 9
```

### `tap`

`(tap f) -> (fn (x) ...x)`

Returns a function that applies `f` for side effects, then returns the argument.

```
((tap write) 42) -> 42
```

### `complement`

`(complement pred) -> function`

```
((complement even?) 3) -> t
```

### `partial`

`(partial f . bound) -> function`

```
((partial + 10) 5) -> 15
```

### `juxt`

`(juxt . fns) -> function`

```
((juxt inc dec) 5) -> (6 4)
```

### `both`

`(both f g) -> function`

```
((both positive? even?) 4) -> t
((both positive? even?) 3) -> ()
```

### `either`

`(either f g) -> function`

```
((either positive? even?) -2) -> t
```

### `all-pass`

`(all-pass preds) -> function`

```
((all-pass (list positive? even?)) 4) -> t
```

### `any-pass`

`(any-pass preds) -> function`

```
((any-pass (list positive? even?)) -2) -> t
```

---

## 14. Lib: Math

### `inc`

`(inc n) -> integer`

```
(inc 5) -> 6
(inc -1) -> 0
```

### `dec`

`(dec n) -> integer`

```
(dec 5) -> 4
(dec 0) -> -1
```

### `negate`

`(negate n) -> integer`

```
(negate 7) -> -7
(negate -3) -> 3
```

### `abs`

`(abs n) -> integer`

```
(abs -3) -> 3
(abs 3) -> 3
```

### `min`

`(min a b) -> integer`

```
(min 3 7) -> 3
```

### `max`

`(max a b) -> integer`

```
(max 3 7) -> 7
```

### `clamp`

`(clamp lo hi n) -> integer`

Clamps `n` to the range `[lo, hi]`.

```
(clamp 0 10 15) -> 10
(clamp 0 10 -5) -> 0
(clamp 0 10 5) -> 5
```

### `min-by`

`(min-by f a b) -> a | b`

Returns whichever of `a`, `b` has the smaller `(f x)`.

```
(min-by abs -5 3) -> 3
```

### `max-by`

`(max-by f a b) -> a | b`

Returns whichever of `a`, `b` has the larger `(f x)`.

```
(max-by abs -5 3) -> -5
```

### `zero?`

`(zero? n) -> t | ()`

```
(zero? 0) -> t
(zero? 1) -> ()
```

### `positive?`

`(positive? n) -> t | ()`

```
(positive? 5) -> t
(positive? -1) -> ()
(positive? 0) -> ()
```

### `negative?`

`(negative? n) -> t | ()`

```
(negative? -3) -> t
(negative? 0) -> ()
```

### `even?`

`(even? n) -> t | ()`

```
(even? 4) -> t
(even? 3) -> ()
```

### `odd?`

`(odd? n) -> t | ()`

```
(odd? 3) -> t
(odd? 4) -> ()
```

### `sum`

`(sum lst) -> integer`

```
(sum (list 1 2 3)) -> 6
```

### `product`

`(product lst) -> integer`

```
(product (list 2 3 4)) -> 24
```

---

## 15. Lib: Logic

### `boolean?`

`(boolean? x) -> t | ()`

Returns `t` if `x` is `t` or `()`.

```
(boolean? t) -> t
(boolean? ()) -> t
(boolean? 1) -> ()
```

### `default-to`

`(default-to d x) -> x | d`

Returns `x` if non-nil, otherwise `d`.

```
(default-to 0 ()) -> 0
(default-to 0 42) -> 42
```

### `until`

`(until pred f x) -> value`

Repeatedly applies `f` to `x` until `pred` is true.

```
(until (fn (n) (> n 10)) inc 1) -> 11
```

### `equal?`

`(equal? a b) -> t | ()`

Shallow value equality: numbers by value, strings by content, else by identity
(`eq?`). Does not recurse into pairs or lists.

```
(equal? 3 3) -> t
(equal? "abc" "abc") -> t
(equal? (list 1) (list 1)) -> ()
```

---

## 16. Lib: Lists

### Folds

#### `fold`

`(fold f init lst) -> value`

Left fold.

```
(fold + 0 (list 1 2 3)) -> 6
(fold (fn (acc x) (pair x acc)) () (list 1 2 3)) -> (3 2 1)
```

#### `reduce`

`(reduce f lst) -> value`

Left fold using first element as initial value.

```
(reduce + (list 1 2 3)) -> 6
```

#### `scan`

`(scan f init lst) -> list`

Like fold but collects intermediate values.

```
(scan + 0 (list 1 2 3)) -> (0 1 3 6)
```

### Basics

#### `length`

`(length lst) -> integer`

```
(length (list 1 2 3)) -> 3
(length ()) -> 0
```

#### `nth`

`(nth n lst) -> value`

Zero-based index.

```
(nth 0 (list 10 20 30)) -> 10
(nth 2 (list 10 20 30)) -> 30
```

#### `last`

`(last lst) -> value`

```
(last (list 1 2 3)) -> 3
```

#### `init`

`(init lst) -> list`

All elements except the last.

```
(init (list 1 2 3)) -> (1 2)
```

#### `append`

`(append a b) -> list`

```
(append (list 1 2) (list 3 4)) -> (1 2 3 4)
```

#### `prepend`

`(prepend x lst) -> list`

```
(prepend 0 (list 1 2)) -> (0 1 2)
```

#### `reverse`

`(reverse lst) -> list`

```
(reverse (list 1 2 3)) -> (3 2 1)
```

#### `flatten`

`(flatten lst) -> list`

```
(flatten (list 1 (list 2 (list 3)))) -> (1 2 3)
```

### Iteration

#### `map`

`(map f lst) -> list`

```
(map inc (list 1 2 3)) -> (2 3 4)
```

#### `filter`

`(filter pred lst) -> list`

```
(filter even? (list 1 2 3 4)) -> (2 4)
```

#### `for-each`

`(for-each f lst) -> ()`

Applies `f` to each element for side effects only.

```
(for-each display (list 1 2 3)) -> ()
```

#### `flat-map`

`(flat-map f lst) -> list`

Maps then flattens one level.

```
(flat-map (fn (x) (list x x)) (list 1 2)) -> (1 1 2 2)
```

### Predicates

#### `any?`

`(any? pred lst) -> t | ()`

```
(any? even? (list 1 3 4)) -> t
(any? even? (list 1 3 5)) -> ()
```

#### `every?`

`(every? pred lst) -> t | ()`

```
(every? even? (list 2 4 6)) -> t
(every? even? (list 2 3 6)) -> ()
```

#### `none?`

`(none? pred lst) -> t | ()`

```
(none? even? (list 1 3 5)) -> t
```

#### `empty?`

`(empty? lst) -> t | ()`

```
(empty? ()) -> t
(empty? (list 1)) -> ()
```

### Filtering

#### `reject`

`(reject pred lst) -> list`

Complement of `filter`.

```
(reject even? (list 1 2 3 4)) -> (1 3)
```

#### `concat`

`(concat . lsts) -> list`

```
(concat (list 1 2) (list 3) (list 4 5)) -> (1 2 3 4 5)
```

### Search

#### `find`

`(find pred lst) -> value | ()`

```
(find even? (list 1 3 4 6)) -> 4
(find even? (list 1 3 5)) -> ()
```

#### `find-index`

`(find-index pred lst) -> integer`

Returns `-1` if not found.

```
(find-index even? (list 1 3 4)) -> 2
(find-index even? (list 1 3 5)) -> -1
```

#### `index-of`

`(index-of x lst) -> integer`

Returns `-1` if not found.

```
(index-of 3 (list 1 2 3 4)) -> 2
```

#### `includes?`

`(includes? x lst) -> t | ()`

```
(includes? 3 (list 1 2 3)) -> t
(includes? 9 (list 1 2 3)) -> ()
```

#### `count`

`(count pred lst) -> integer`

```
(count even? (list 1 2 3 4)) -> 2
```

### Slicing

#### `take`

`(take n lst) -> list`

```
(take 2 (list 1 2 3 4)) -> (1 2)
```

#### `drop`

`(drop n lst) -> list`

```
(drop 2 (list 1 2 3 4)) -> (3 4)
```

#### `take-while`

`(take-while pred lst) -> list`

```
(take-while odd? (list 1 3 4 5)) -> (1 3)
```

#### `drop-while`

`(drop-while pred lst) -> list`

```
(drop-while odd? (list 1 3 4 5)) -> (4 5)
```

#### `split-at`

`(split-at n lst) -> (list list)`

```
(split-at 2 (list 1 2 3 4)) -> ((1 2) (3 4))
```

#### `slice`

`(slice start end lst) -> list`

```
(slice 1 3 (list 10 20 30 40)) -> (20 30)
```

### Generators

#### `range`

`(range start end) -> list`

```
(range 0 5) -> (0 1 2 3 4)
```

#### `repeat`

`(repeat x n) -> list`

```
(repeat 0 3) -> (0 0 0)
```

#### `times`

`(times f n) -> list`

```
(times identity 4) -> (0 1 2 3)
```

#### `unfold`

`(unfold pred f g seed) -> list`

```
(unfold (fn (x) (> x 3)) identity inc 1) -> (1 2 3)
```

#### `iterate`

`(iterate f n x) -> list`

```
(iterate inc 4 0) -> (0 1 2 3)
```

#### `zip`

`(zip a b) -> list`

```
(zip (list 1 2 3) (list 4 5 6)) -> ((1 4) (2 5) (3 6))
```

#### `zip-with`

`(zip-with f a b) -> list`

```
(zip-with + (list 1 2 3) (list 10 20 30)) -> (11 22 33)
```

### Transformation

#### `partition`

`(partition pred lst) -> (list list)`

```
(partition even? (list 1 2 3 4)) -> ((2 4) (1 3))
```

#### `group-by`

`(group-by f lst) -> alist`

```
(group-by even? (list 1 2 3 4)) -> ((() 1 3) (t 2 4))
```

#### `sort`

`(sort cmp lst) -> list`

Merge sort.

```
(sort < (list 3 1 2)) -> (1 2 3)
```

#### `sort-by`

`(sort-by f lst) -> list`

```
(sort-by abs (list -3 1 -2)) -> (1 -2 -3)
```

#### `uniq`

`(uniq lst) -> list`

Removes consecutive duplicates.

```
(uniq (list 1 1 2 2 3)) -> (1 2 3)
```

#### `uniq-by`

`(uniq-by f lst) -> list`

```
(uniq-by abs (list 1 -1 2 -2 3)) -> (1 2 3)
```

#### `intersperse`

`(intersperse sep lst) -> list`

```
(intersperse 0 (list 1 2 3)) -> (1 0 2 0 3)
```

#### `transpose`

`(transpose lsts) -> list`

```
(transpose (list (list 1 2) (list 3 4))) -> ((1 3) (2 4))
```

#### `update`

`(update n val lst) -> list`

```
(update 1 99 (list 1 2 3)) -> (1 99 3)
```

#### `insert`

`(insert n val lst) -> list`

```
(insert 1 99 (list 1 2 3)) -> (1 99 2 3)
```

#### `remove`

`(remove start n lst) -> list`

```
(remove 1 2 (list 1 2 3 4)) -> (1 4)
```

#### `adjust`

`(adjust n f lst) -> list`

```
(adjust 1 inc (list 10 20 30)) -> (10 21 30)
```

---

## 17. Lib: Alists

Association lists are lists of pairs `((key . val) ...)`. Keys are compared
with `eq?`.

### `aget`

`(aget key alist) -> value | ()`

```
(aget (lit b) (list (pair (lit a) 1) (pair (lit b) 2))) -> 2
(aget (lit z) (list (pair (lit a) 1))) -> ()
```

### `aget-or`

`(aget-or d key alist) -> value`

```
(aget-or 0 (lit z) (list (pair (lit a) 1))) -> 0
```

### `ahas?`

`(ahas? key alist) -> t | ()`

```
(ahas? (lit a) (list (pair (lit a) 1))) -> t
(ahas? (lit z) (list (pair (lit a) 1))) -> ()
```

### `adel`

`(adel key alist) -> alist`

```
(adel (lit a) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `aset`

`(aset key val alist) -> alist`

```
(aset (lit a) 99 (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 99) (b . 2))
```

### `akeys`

`(akeys alist) -> list`

```
(akeys (list (pair (lit a) 1) (pair (lit b) 2))) -> (a b)
```

### `avals`

`(avals alist) -> list`

```
(avals (list (pair (lit a) 1) (pair (lit b) 2))) -> (1 2)
```

### `amap`

`(amap f alist) -> alist`

Applies `f` to each value.

```
(amap inc (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 2) (b . 3))
```

### `afilter`

`(afilter pred alist) -> alist`

Filters entries by predicate applied to each `(key . val)` pair.

```
(afilter (fn (e) (> (rest e) 1)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `amerge`

`(amerge a b) -> alist`

Merges `b` into `a`, keeping `a`'s entries on collision.

```
(amerge (list (pair (lit a) 1)) (list (pair (lit a) 9) (pair (lit b) 2))) -> ((a . 1) (b . 2))
```

### `apick`

`(apick keys alist) -> alist`

Returns entries whose keys appear in `keys`.

```
(apick (list (lit a)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 1))
```

### `aomit`

`(aomit keys alist) -> alist`

Returns entries whose keys are NOT in `keys`.

```
(aomit (list (lit a)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `from-pairs`

`(from-pairs lst) -> alist`

Converts list of two-element lists to alist of dotted pairs.

```
(from-pairs (list (list (lit a) 1) (list (lit b) 2))) -> ((a . 1) (b . 2))
```

### `to-pairs`

`(to-pairs alist) -> list`

Converts alist of dotted pairs to list of two-element lists.

```
(to-pairs (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a 1) (b 2))
```

### `evolve`

`(evolve fns alist) -> alist`

Applies transformation functions to matching keys.

```
(evolve (list (pair (lit a) inc)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 2) (b . 2))
```

---

## 18. Lib: Strings

### `string-empty?`

`(string-empty? s) -> t | ()`

```
(string-empty? "") -> t
(string-empty? "a") -> ()
```

### `string-join`

`(string-join sep lst) -> string`

```
(string-join ", " (list "a" "b" "c")) -> "a, b, c"
(string-join "" (list "a" "b")) -> "ab"
```

### `string-repeat`

`(string-repeat s n) -> string`

```
(string-repeat "ab" 3) -> "ababab"
(string-repeat "x" 0) -> ""
```

### `string-contains?`

`(string-contains? sub s) -> t | ()`

```
(string-contains? "ell" "hello") -> t
(string-contains? "xyz" "hello") -> ()
```

### `string-starts?`

`(string-starts? pfx s) -> t | ()`

```
(string-starts? "he" "hello") -> t
(string-starts? "lo" "hello") -> ()
```

### `string-ends?`

`(string-ends? sfx s) -> t | ()`

```
(string-ends? "lo" "hello") -> t
(string-ends? "he" "hello") -> ()
```

### `string-reverse`

`(string-reverse s) -> string`

```
(string-reverse "hello") -> "olleh"
(string-reverse "") -> ""
```

---

## 19. Lib: Vectors

Vectors are fixed-size indexed collections backed by lists. They display as
`#(...)`.

### `vector`

`(vector . args) -> vector`

```
(vector 1 2 3) -> #(1 2 3)
(vector) -> #()
```

### `vector?`

`(vector? x) -> t | ()`

```
(vector? (vector 1 2)) -> t
(vector? (list 1 2)) -> ()
```

### `vector-ref`

`(vector-ref v i) -> value`

```
(vector-ref (vector 10 20 30) 1) -> 20
```

### `vector-length`

`(vector-length v) -> integer`

```
(vector-length (vector 1 2 3)) -> 3
```

### `vector->list`

`(vector->list v) -> list`

```
(vector->list (vector 1 2 3)) -> (1 2 3)
```

### `list->vector`

`(list->vector lst) -> vector`

```
(list->vector (list 1 2 3)) -> #(1 2 3)
```

### `make-vector`

`(make-vector n fill) -> vector`

```
(make-vector 3 0) -> #(0 0 0)
```

---

## 20. Lib: Regex

Regex values are created with the `#/pattern/` literal syntax. They compile
the pattern into an AST at read time and match against strings at runtime.

### `regex?`

`(regex? x) -> t | ()`

```
(regex? #/abc/) -> t
(regex? "abc") -> ()
```

### Regex literals

```
(write #/abc/) -> #/abc/
(write #//) -> #//
(write #/ab*c/) -> #/ab*c/
(write #/a\\.b/) -> #/a\\.b/
```

### Matching

A regex called as a function performs a full match against a string. Returns
`t` on match, `()` on no match.

```
(#/abc/ "abc") -> t
(#/abc/ "abd") -> ()
(#/abc/ "ab") -> ()
(#/abc/ "abcd") -> ()
```

### Dot wildcard

`.` matches any single character.

```
(#/./ "x") -> t
(#/a.c/ "abc") -> t
(#/a.c/ "axc") -> t
(#/./ "") -> ()
```

### Star quantifier

`*` matches zero or more of the preceding element.

```
(#/ab*c/ "ac") -> t
(#/ab*c/ "abc") -> t
(#/ab*c/ "abbbc") -> t
(#/a*/ "") -> t
```

### Plus quantifier

`+` matches one or more of the preceding element.

```
(#/ab+c/ "abc") -> t
(#/ab+c/ "abbbc") -> t
(#/ab+c/ "ac") -> ()
```

### Optional quantifier

`?` matches zero or one of the preceding element.

```
(#/ab?c/ "abc") -> t
(#/ab?c/ "ac") -> t
(#/ab?c/ "abbc") -> ()
```

### Escape sequences

`\` escapes the following character, treating it as a literal.

```
(#/a\\.b/ "a.b") -> t
(#/a\\.b/ "axb") -> ()
(#/a\\\\b/ "a\\b") -> t
(#/a\\*b/ "a*b") -> t
```

### Backtracking

The `*` quantifier is greedy but backtracks to find a match.

```
(#/a.*b/ "axxb") -> t
(#/.*b/ "aab") -> t
(#/a.*b/ "axx") -> ()
```

### Combined patterns

```
(#/a.*/ "abcdef") -> t
(#/a.b*c/ "axbbc") -> t
(#/.+/ "abc") -> t
(#/.+/ "") -> ()
```

### `type-name`

```
(type-name #/abc/) -> "REGEX"
```
