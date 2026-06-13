# x-lang Specification

**Version:** 0.2.0

This document is the normative specification for x-lang. Each section maps 1:1
to a test file in `tests/x/specs/`. Behavior described here MUST be implemented
and tested. Items marked **TBD** have uncertain semantics and need investigation.

All primitives receive unevaluated arguments (fexpr-style) and evaluate what
they need internally. Boolean true is `#t`; boolean false is `#f`. Nil is `()`
(the empty list).

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

The empty list `()` is nil. It is falsy. The boolean false value is `#f`.
`()` self-evaluates.

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
(def loop (fn (n) (if (= n 0) #t (loop (- n 1)))))
(loop 1000000) -> #t
```

### Mutual recursion

Mutually tail-recursive functions MUST also run in constant stack space.

```
(def even-tc (fn (n) (if (= n 0) #t (odd-tc (- n 1)))))
(def odd-tc (fn (n) (if (= n 0) #f (even-tc (- n 1)))))
(even-tc 100000) -> #t
```

---

## 2. Core Forms

### `lit`

`(lit expr) -> expr`

Returns `expr` unevaluated. This is the quoting primitive. The reader provides
`'expr` as shorthand for `(lit expr)` (see `core/quote-reader.spec.md`).

```
(lit (+ 1 2)) -> (+ 1 2)
(lit abc) -> abc
'abc -> abc
'(1 2 3) -> (1 2 3)
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
(if #t 1 2) -> 1
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
  (#t 30)) -> 20
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
`#t`.

```
(and 1 2 3) -> 3
(and 1 () 3) -> ()
(and) -> #t
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

`(not x) -> #t | #f`

Logical negation. Returns `#t` if `x` is falsy; `#f` otherwise.

```
(not ()) -> #t
(not 1) -> #f
(not #t) -> #f
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
(guard (e (Str8 append "outer: " e))
  (guard (e (error (Str8 append "re: " e)))
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

`(eq? a b) -> #t | #f`

Pointer identity. Returns `#t` if `a` and `b` are the exact same object.
Symbols with the same name are interned and thus `eq?`.

```
(eq? (lit x) (lit x)) -> #t
(eq? 1 1) -> #f
```

### `=`

`(= a b) -> #t | #f`

Numeric/value equality. Compares integer values (and characters by code point).
Comparing values of different types is undefined.

```
(= 1 1) -> #t
(= 1 2) -> #f
```

### `<`

`(< a b) -> #t | #f`

```
(< 1 2) -> #t
(< 2 1) -> #f
```

### `>`

`(> a b) -> #t | #f`

```
(> 2 1) -> #t
(> 1 2) -> #f
```

### `<=`

`(<= a b) -> #t | #f`

```
(<= 1 1) -> #t
(<= 2 1) -> #f
```

### `>=`

`(>= a b) -> #t | #f`

```
(>= 1 1) -> #t
(>= 0 1) -> #f
```

### `null?`

`(null? x) -> #t | #f`

Returns `#t` if `x` is nil.

```
(null? ()) -> #t
(null? 1) -> #f
```

### `pair?`

`(pair? x) -> #t | #f`

Returns `#t` if `x` is a pair.

```
(pair? (list 1 2)) -> #t
(pair? 1) -> #f
```

### `atom?`

`(atom? x) -> #t | #f`

Returns `#t` if `x` is not a pair. Inverse of `pair?`.

```
(atom? 1) -> #t
(atom? (list 1 2)) -> #f
```

### `number?`

`(number? x) -> #t | #f`

```
(number? 42) -> #t
(number? "hello") -> #f
```

### `string?`

`(string? x) -> #t | #f`

```
(string? "hello") -> #t
(string? 42) -> #f
```

### `symbol?`

`(symbol? x) -> #t | #f`

```
(symbol? (lit x)) -> #t
(symbol? 42) -> #f
```

### `procedure?`

`(procedure? x) -> #t | #f`

Returns `#t` if `x` is a `fn` closure, a `wrap` applicative, or a C primitive.
Returns `#f` for `op` operatives and all other values.

```
(procedure? +) -> #t
(procedure? (fn (x) x)) -> #t
(procedure? 42) -> #f
```

### `char?`

`(char? x) -> #t | #f`

Returns `#t` if `x` is a character object.

```
(char? #\a) -> #t
(char? 42) -> #f
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
(= (integer->char 97) #\a) -> #t
```

---

## 7. Strings

### `str-length`

`(str-length str) -> integer`

Returns the byte length of string `str` (not character count; x-lang strings
are byte arrays with no encoding awareness).

```
(str-length "hello") -> 5
(str-length "") -> 0
```

### `str-ref`

`(str-ref str index) -> char`

Returns the character at zero-based `index` in `str`. Out-of-bounds access is
undefined.

```
(str-ref "hello" 0) -> h
(str-ref "hello" 4) -> o
```

### `Str8 append`

`(Str8 append str1 str2 ...) -> string` (ns `str` is de-registered: the class -- or `(prim-ref (lit str) (lit append))` for load-time/hot fetches -- is the surface)

Concatenates exactly two strings. For multiple strings, use `Str append` (variadic).

```
(Str8 append "hello" " world") -> "hello world"
(Str8 append "" "x") -> "x"
```

### `substring`

`(substring str start end) -> string`

Extracts a substring from `start` (inclusive) to `end` (exclusive).
Out-of-bounds indices are undefined.

```
(substring "hello" 1 3) -> "el"
(substring "hello" 0 5) -> "hello"
```

### `str=?`

`(str=? str1 str2) -> #t | #f`

String content equality.

```
(str=? "abc" "abc") -> #t
(str=? "abc" "xyz") -> #f
```

### `Str8 ->sym`

`(Str8 ->sym str) -> symbol`

Converts a string to an interned symbol.

```
(Str8 ->sym "hello") -> hello
```

### `symbol->str`

`(symbol->str sym) -> string`

Converts a symbol to a string.

```
(symbol->str (lit hello)) -> "hello"
```

### `number->str`

`(number->str n) -> string`

Converts integer to decimal string representation.

```
(number->str 42) -> "42"
(number->str -1) -> "-1"
```

### `str->number`

`(str->number str) -> integer`

Parses string as integer. Supports `0x` prefix for hex. Non-numeric strings
return `0`.

```
(str->number "42") -> 42
(str->number "0xff") -> 255
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

### `Io read`

`(Io read) -> obj`

Reads and parses one s-expression from stdin. Behavior at EOF is
implementation-dependent.

### `Io read-char`

`(Io read-char) -> char | ()`

Reads a single character from stdin. Returns `()` on end-of-input.

### `Heap collect`

`(Heap collect) -> integer`

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
that use byte-length (e.g., `str-length`, `(Str8 append)`).

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

`(Type make name handlers) -> type-handle`

Creates a new runtime type with string `name` and an alist of `handlers`.
Supported handler keys: `call`, `write`, `length`, `analyse`, `delimit`.
Returns a type handle used with `make-instance` and `type?`.

```
(def my-t (Type make "MY-T" (list)))
```

### `make-instance`

`(Type make-instance type-handle data) -> instance`

Creates a new instance of the type. Data is stored and accessible via
`(first instance)`.

```
(def my-t (Type make "MY-T" (list)))
(def obj (Type make-instance my-t 42))
(first obj) -> 42
```

Custom type instances self-evaluate:

```
(def obj (Type make-instance my-t 42))
obj -> <instance>
```

### `type?`

`(Type ? obj type-handle) -> #t | #f`

Returns `#t` if `obj`'s runtime type matches `type-handle`.

```
(Type ? obj my-t) -> #t
(Type ? 42 my-t) -> #f
```

### `type-name`

`(Type name obj) -> string | ()`

Returns the name string of `obj`'s type, or `()` if no type.

```
(Type name obj) -> "MY-T"
(Type name 42) -> "INTEGER"
(Type name "hi") -> "STRING"
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
(def counter-t (Type make "COUNTER"
  (list (pair (lit call) (fn (self . args) (first self))))))
(def c (Type make-instance counter-t 42))
(c) -> 42
```

### Write handler

When `write` or `display` outputs a typed instance, the `write` handler is
called with the instance as `self`.

```
(def my-t (Type make "SHOW"
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

### `Fn identity`

`(Fn identity x) -> x`

Returns its argument unchanged.

```
(Fn identity 42) -> 42
```

### `Fn const`

`(Fn const x) -> (fn (y) x)`

Returns a function that always returns `x`.

```
((Fn const 5) 99) -> 5
```

### `Fn compose`

`(Fn compose f g) -> (fn (x) (f (g x)))`

Right-to-left function composition.

```
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn pipe`

`(Fn pipe f g) -> (fn (x) (g (f x)))`

Left-to-right function composition.

```
((Fn pipe (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn curry`

`(Fn curry f x) -> (fn (y) (f x y))`

Partially applies a two-argument function by fixing its first argument.

```
((Fn curry + 10) 5) -> 15
```

### `Fn flip`

`(Fn flip f) -> (fn (a b) (f b a))`

Reverses the arguments of a binary function.

```
((Fn flip -) 1 10) -> 9
```

### `Fn tap`

`(Fn tap f) -> (fn (x) ...x)`

Returns a function that applies `f` for side effects, then returns the argument.

```
((Fn tap write) 42) -> 42
```

### `List complement`

`(List complement pred) -> function`

```
((List complement even?) 3) -> #t
```

### `List partial`

`(List partial f . bound) -> function`

```
((List partial + 10) 5) -> 15
```

### `List juxt`

`(List juxt . fns) -> function`

```
((List juxt (method-ref Num inc) (method-ref Num dec)) 5) -> (6 4)
```

### `List both`

`(List both f g) -> function`

```
((List both positive? even?) 4) -> #t
((List both positive? even?) 3) -> #f
```

### `List either`

`(List either f g) -> function`

```
((List either positive? even?) -2) -> #t
```

### `List all-pass`

`(List all-pass preds) -> function`

```
((List all-pass (list positive? even?)) 4) -> #t
```

### `List any-pass`

`(List any-pass preds) -> function`

```
((List any-pass (list positive? even?)) -2) -> #t
```

---

## 14. Lib: Math

### `Num inc`

`(Num inc n) -> integer`

```
(Num inc 5) -> 6
(Num inc -1) -> 0
```

### `Num dec`

`(Num dec n) -> integer`

```
(Num dec 5) -> 4
(Num dec 0) -> -1
```

### `Num negate`

`(Num negate n) -> integer`

```
(Num negate 7) -> -7
(Num negate -3) -> 3
```

### `Num abs`

`(Num abs n) -> integer`

```
(Num abs -3) -> 3
(Num abs 3) -> 3
```

### `Num min`

`(Num min a b) -> integer`

```
(Num min 3 7) -> 3
```

### `Num max`

`(Num max a b) -> integer`

```
(Num max 3 7) -> 7
```

### `Num clamp`

`(Num clamp lo hi n) -> integer`

Clamps `n` to the range `[lo, hi]`.

```
(Num clamp 0 10 15) -> 10
(Num clamp 0 10 -5) -> 0
(Num clamp 0 10 5) -> 5
```

### `Num min-by`

`(Num min-by f a b) -> a | b`

Returns whichever of `a`, `b` has the smaller `(f x)`.

```
(Num min-by (method-ref Num abs) -5 3) -> 3
```

### `Num max-by`

`(Num max-by f a b) -> a | b`

Returns whichever of `a`, `b` has the larger `(f x)`.

```
(Num max-by (method-ref Num abs) -5 3) -> -5
```

### `Num zero?`

`(Num zero? n) -> #t | #f`

```
(Num zero? 0) -> #t
(Num zero? 1) -> #f
```

### `Num positive?`

`(Num positive? n) -> #t | #f`

```
(Num positive? 5) -> #t
(Num positive? -1) -> #f
(Num positive? 0) -> #f
```

### `Num negative?`

`(Num negative? n) -> #t | #f`

```
(Num negative? -3) -> #t
(Num negative? 0) -> #f
```

### `Num even?`

`(Num even? n) -> #t | #f`

```
(Num even? 4) -> #t
(Num even? 3) -> #f
```

### `Num odd?`

`(Num odd? n) -> #t | #f`

```
(Num odd? 3) -> #t
(Num odd? 4) -> #f
```

### `List sum`

`(List sum lst) -> integer`

```
(List sum (list 1 2 3)) -> 6
```

### `List product`

`(List product lst) -> integer`

```
(List product (list 2 3 4)) -> 24
```

---

## 15. Lib: Logic

### `boolean?`

`(boolean? x) -> #t | #f`

Returns `#t` if `x` is `#t` or `#f`.

```
(boolean? #t) -> #t
(boolean? #f) -> #t
(boolean? 1) -> #f
```

### `Fn default-to`

`(Fn default-to d x) -> x | d`

Returns `x` if non-nil, otherwise `d`.

```
(Fn default-to 0 ()) -> 0
(Fn default-to 0 42) -> 42
```

### `Fn until`

`(Fn until pred f x) -> value`

Repeatedly applies `f` to `x` until `pred` is true.

```
(Fn until (fn (_ n) (> n 10)) (method-ref Num inc) 1) -> 11
```

### `equal?`

`(equal? a b) -> #t | #f`

Shallow value equality: numbers by value, strings by content, else by identity
(`eq?`). Does not recurse into pairs or lists.

```
(equal? 3 3) -> #t
(equal? "abc" "abc") -> #t
(equal? (list 1) (list 1)) -> #f
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

#### `List reduce`

`(List reduce f lst) -> value`

Left fold using first element as initial value.

```
(List reduce + (list 1 2 3)) -> 6
```

#### `List scan`

`(List scan f init lst) -> list`

Like fold but collects intermediate values.

```
(List scan + 0 (list 1 2 3)) -> (0 1 3 6)
```

### Basics

#### `length`

`(length lst) -> integer`

```
(length (list 1 2 3)) -> 3
(length ()) -> 0
```

#### `List nth`

`(List nth n lst) -> value`

Zero-based index.

```
(List nth 0 (list 10 20 30)) -> 10
(List nth 2 (list 10 20 30)) -> 30
```

#### `List last`

`(List last lst) -> value`

```
(List last (list 1 2 3)) -> 3
```

#### `List init`

`(List init lst) -> list`

All elements except the last.

```
(List init (list 1 2 3)) -> (1 2)
```

#### `append`

`(append a b) -> list`

```
(append (list 1 2) (list 3 4)) -> (1 2 3 4)
```

#### `List prepend`

`(List prepend x lst) -> list`

```
(List prepend 0 (list 1 2)) -> (0 1 2)
```

#### `reverse`

`(reverse lst) -> list`

```
(reverse (list 1 2 3)) -> (3 2 1)
```

#### `List flatten`

`(List flatten lst) -> list`

```
(List flatten (list 1 (list 2 (list 3)))) -> (1 2 3)
```

### Iteration

#### `map`

`(map f lst) -> list`

```
(map (method-ref Num inc) (list 1 2 3)) -> (2 3 4)
```

#### `filter`

`(filter pred lst) -> list`

```
(filter (method-ref Num even?) (list 1 2 3 4)) -> (2 4)
```

#### `for-each`

`(for-each f lst) -> ()`

Applies `f` to each element for side effects only.

```
(for-each display (list 1 2 3)) -> ()
```

#### `List flat-map`

`(List flat-map f lst) -> list`

Maps then flattens one level.

```
(List flat-map (fn (x) (list x x)) (list 1 2)) -> (1 1 2 2)
```

### Predicates

#### `List any?`

`(List any? pred lst) -> #t | #f`

```
(List any? even? (list 1 3 4)) -> #t
(List any? even? (list 1 3 5)) -> #f
```

#### `List every?`

`(List every? pred lst) -> #t | #f`

```
(List every? even? (list 2 4 6)) -> #t
(List every? even? (list 2 3 6)) -> #f
```

#### `List none?`

`(List none? pred lst) -> #t | #f`

```
(List none? even? (list 1 3 5)) -> #t
```

#### `List empty?`

`(List empty? lst) -> #t | #f`

```
(List empty? ()) -> #t
(List empty? (list 1)) -> #f
```

### Filtering

#### `List reject`

`(List reject pred lst) -> list`

Complement of `filter`.

```
(List reject even? (list 1 2 3 4)) -> (1 3)
```

#### `List concat`

`(List concat . lsts) -> list`

```
(List concat (list 1 2) (list 3) (list 4 5)) -> (1 2 3 4 5)
```

### Search

#### `List find`

`(List find pred lst) -> value | ()`

```
(List find even? (list 1 3 4 6)) -> 4
(List find even? (list 1 3 5)) -> ()
```

#### `List find-index`

`(List find-index pred lst) -> integer`

Returns `-1` if not found.

```
(List find-index even? (list 1 3 4)) -> 2
(List find-index even? (list 1 3 5)) -> -1
```

#### `List index-of`

`(List index-of x lst) -> integer`

Returns `-1` if not found.

```
(List index-of 3 (list 1 2 3 4)) -> 2
```

#### `List includes?`

`(List includes? x lst) -> #t | #f`

```
(List includes? 3 (list 1 2 3)) -> #t
(List includes? 9 (list 1 2 3)) -> #f
```

#### `List count`

`(List count pred lst) -> integer`

```
(List count even? (list 1 2 3 4)) -> 2
```

### Slicing

#### `List take`

`(List take n lst) -> list`

```
(List take 2 (list 1 2 3 4)) -> (1 2)
```

#### `List drop`

`(List drop n lst) -> list`

```
(List drop 2 (list 1 2 3 4)) -> (3 4)
```

#### `List take-while`

`(List take-while pred lst) -> list`

```
(List take-while odd? (list 1 3 4 5)) -> (1 3)
```

#### `List drop-while`

`(List drop-while pred lst) -> list`

```
(List drop-while odd? (list 1 3 4 5)) -> (4 5)
```

#### `List split-at`

`(List split-at n lst) -> (list list)`

```
(List split-at 2 (list 1 2 3 4)) -> ((1 2) (3 4))
```

#### `List slice`

`(List slice start end lst) -> list`

```
(List slice 1 3 (list 10 20 30 40)) -> (20 30)
```

### Generators

#### `List range`

`(List range start end) -> list`

```
(List range 0 5) -> (0 1 2 3 4)
```

#### `List repeat`

`(List repeat x n) -> list`

```
(List repeat 0 3) -> (0 0 0)
```

#### `List times`

`(List times f n) -> list`

```
(List times (method-ref Fn identity) 4) -> (0 1 2 3)
```

#### `List unfold`

`(List unfold pred f g seed) -> list`

```
(List unfold (fn (_ x) (> x 3)) (method-ref Fn identity) (method-ref Num inc) 1) -> (1 2 3)
```

#### `List iterate`

`(List iterate f n x) -> list`

```
(List iterate (method-ref Num inc) 4 0) -> (0 1 2 3)
```

#### `List zip`

`(List zip a b) -> list`

```
(List zip (list 1 2 3) (list 4 5 6)) -> ((1 4) (2 5) (3 6))
```

#### `List zip-with`

`(List zip-with f a b) -> list`

```
(List zip-with + (list 1 2 3) (list 10 20 30)) -> (11 22 33)
```

### Transformation

#### `List partition`

`(List partition pred lst) -> (list list)`

```
(List partition even? (list 1 2 3 4)) -> ((2 4) (1 3))
```

#### `List group-by`

`(List group-by f lst) -> alist`

```
(List group-by even? (list 1 2 3 4)) -> ((#f 1 3) (#t 2 4))
```

#### `List sort`

`(List sort cmp lst) -> list`

Merge sort.

```
(List sort < (list 3 1 2)) -> (1 2 3)
```

#### `List sort-by`

`(List sort-by f lst) -> list`

```
(List sort-by (method-ref Num abs) (list -3 1 -2)) -> (1 -2 -3)
```

#### `List uniq`

`(List uniq lst) -> list`

Removes consecutive duplicates.

```
(List uniq (list 1 1 2 2 3)) -> (1 2 3)
```

#### `List uniq-by`

`(List uniq-by f lst) -> list`

```
(List uniq-by (method-ref Num abs) (list 1 -1 2 -2 3)) -> (1 2 3)
```

#### `List intersperse`

`(List intersperse sep lst) -> list`

```
(List intersperse 0 (list 1 2 3)) -> (1 0 2 0 3)
```

#### `List transpose`

`(List transpose lsts) -> list`

```
(List transpose (list (list 1 2) (list 3 4))) -> ((1 3) (2 4))
```

#### `List update`

`(List update n val lst) -> list`

```
(List update 1 99 (list 1 2 3)) -> (1 99 3)
```

#### `List insert`

`(List insert n val lst) -> list`

```
(List insert 1 99 (list 1 2 3)) -> (1 99 2 3)
```

#### `List remove`

`(List remove start n lst) -> list`

```
(List remove 1 2 (list 1 2 3 4)) -> (1 4)
```

#### `List adjust`

`(List adjust n f lst) -> list`

```
(List adjust 1 (method-ref Num inc) (list 10 20 30)) -> (10 21 30)
```

---

## 17. Lib: Alists

Association lists are lists of pairs `((key . val) ...)`. Keys are compared
with `eq?`.

### `assoc-get`

`(assoc-get key alist) -> value | ()`

```
(assoc-get (lit b) (list (pair (lit a) 1) (pair (lit b) 2))) -> 2
(assoc-get (lit z) (list (pair (lit a) 1))) -> ()
```

### `Assoc get-or`

`(Assoc get-or d key alist) -> value`

```
(Assoc get-or 0 (lit z) (list (pair (lit a) 1))) -> 0
```

### `assoc-has?`

`(assoc-has? key alist) -> #t | #f`

```
(assoc-has? (lit a) (list (pair (lit a) 1))) -> #t
(assoc-has? (lit z) (list (pair (lit a) 1))) -> #f
```

### `assoc-del`

`(assoc-del key alist) -> alist`

```
(assoc-del (lit a) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `assoc-put`

`(assoc-put key val alist) -> alist`

```
(assoc-put (lit a) 99 (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 99) (b . 2))
```

### `assoc-keys`

`(assoc-keys alist) -> list`

```
(assoc-keys (list (pair (lit a) 1) (pair (lit b) 2))) -> (a b)
```

### `Assoc vals`

`(Assoc vals alist) -> list`

```
(Assoc vals (list (pair (lit a) 1) (pair (lit b) 2))) -> (1 2)
```

### `Assoc map`

`(Assoc map f alist) -> alist`

Applies `f` to each value.

```
(Assoc map (method-ref Num inc) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 2) (b . 3))
```

### `Assoc filter`

`(Assoc filter pred alist) -> alist`

Filters entries by predicate applied to each `(key . val)` pair.

```
(Assoc filter (fn (_ e) (> (rest e) 1)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `Assoc merge`

`(Assoc merge a b) -> alist`

Merges `b` into `a`, keeping `a`'s entries on collision.

```
(Assoc merge (list (pair (lit a) 1)) (list (pair (lit a) 9) (pair (lit b) 2))) -> ((a . 1) (b . 2))
```

### `Assoc pick`

`(Assoc pick keys alist) -> alist`

Returns entries whose keys appear in `keys`.

```
(Assoc pick (list (lit a)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 1))
```

### `Assoc omit`

`(Assoc omit keys alist) -> alist`

Returns entries whose keys are NOT in `keys`.

```
(Assoc omit (list (lit a)) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((b . 2))
```

### `Assoc from-pairs`

`(Assoc from-pairs lst) -> alist`

Converts list of two-element lists to alist of dotted pairs.

```
(Assoc from-pairs (list (list (lit a) 1) (list (lit b) 2))) -> ((a . 1) (b . 2))
```

### `Assoc to-pairs`

`(Assoc to-pairs alist) -> list`

Converts alist of dotted pairs to list of two-element lists.

```
(Assoc to-pairs (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a 1) (b 2))
```

### `Assoc evolve`

`(Assoc evolve fns alist) -> alist`

Applies transformation functions to matching keys.

```
(Assoc evolve (list (pair (lit a) (method-ref Num inc))) (list (pair (lit a) 1) (pair (lit b) 2))) -> ((a . 2) (b . 2))
```

---

## 18. Lib: Strings

### `Str empty?`

`(Str empty? s) -> #t | #f`

```
(Str empty? "") -> #t
(Str empty? "a") -> #f
```

### `Str join`

`(Str join sep lst) -> string`

```
(Str join ", " (list "a" "b" "c")) -> "a, b, c"
(Str join "" (list "a" "b")) -> "ab"
```

### `Str repeat`

`(Str repeat s n) -> string`

```
(Str repeat "ab" 3) -> "ababab"
(Str repeat "x" 0) -> ""
```

### `Str contains?`

`(Str contains? sub s) -> #t | #f`

```
(Str contains? "ell" "hello") -> #t
(Str contains? "xyz" "hello") -> #f
```

### `Str starts?`

`(Str starts? pfx s) -> #t | #f`

```
(Str starts? "he" "hello") -> #t
(Str starts? "lo" "hello") -> #f
```

### `Str ends?`

`(Str ends? sfx s) -> #t | #f`

```
(Str ends? "lo" "hello") -> #t
(Str ends? "he" "hello") -> #f
```

### `Str reverse`

`(Str reverse s) -> string`

```
(Str reverse "hello") -> "olleh"
(Str reverse "") -> ""
```

---

## 19. Lib: Vectors

Vectors are fixed-size indexed collections backed by lists. They display as
`#(...)`.

### `Vector of`

`(Vector of . args) -> vector`

```
(Vector of 1 2 3) -> #(1 2 3)
(Vector of) -> #()
```

### `Vector vector?`

`(Vector vector? x) -> #t | #f`

```
(Vector vector? (Vector of 1 2)) -> #t
(Vector vector? (list 1 2)) -> #f
```

### `Vector ref`

`(Vector ref v i) -> value`

```
(Vector ref (Vector of 10 20 30) 1) -> 20
```

### `Vector length`

`(Vector length v) -> integer`

```
(Vector length (Vector of 1 2 3)) -> 3
```

### `Vector ->list`

`(Vector ->list v) -> list`

```
(Vector ->list (Vector of 1 2 3)) -> (1 2 3)
```

### `Vector from-list`

`(Vector from-list lst) -> vector`

```
(Vector from-list (list 1 2 3)) -> #(1 2 3)
```

### `Vector make`

`(Vector make n fill) -> vector`

```
(Vector make 3 0) -> #(0 0 0)
```

---

## 20. Lib: Regex

Regex values are created with the `#/pattern/` literal syntax. They compile
the pattern into an AST at read time and match against strings at runtime.

### `Regex regex?`

`(Regex regex? x) -> #t | #f`

```
(Regex regex? #/abc/) -> #t
(Regex regex? "abc") -> #f
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
`#t` on match, `#f` on no match.

```
(#/abc/ "abc") -> #t
(#/abc/ "abd") -> #f
(#/abc/ "ab") -> #f
(#/abc/ "abcd") -> #f
```

### Dot wildcard

`.` matches any single character.

```
(#/./ "x") -> #t
(#/a.c/ "abc") -> #t
(#/a.c/ "axc") -> #t
(#/./ "") -> #f
```

### Star quantifier

`*` matches zero or more of the preceding element.

```
(#/ab*c/ "ac") -> #t
(#/ab*c/ "abc") -> #t
(#/ab*c/ "abbbc") -> #t
(#/a*/ "") -> #t
```

### Plus quantifier

`+` matches one or more of the preceding element.

```
(#/ab+c/ "abc") -> #t
(#/ab+c/ "abbbc") -> #t
(#/ab+c/ "ac") -> #f
```

### Optional quantifier

`?` matches zero or one of the preceding element.

```
(#/ab?c/ "abc") -> #t
(#/ab?c/ "ac") -> #t
(#/ab?c/ "abbc") -> #f
```

### Escape sequences

`\` escapes the following character, treating it as a literal.

```
(#/a\\.b/ "a.b") -> #t
(#/a\\.b/ "axb") -> #f
(#/a\\\\b/ "a\\b") -> #t
(#/a\\*b/ "a*b") -> #t
```

### Backtracking

The `*` quantifier is greedy but backtracks to find a match.

```
(#/a.*b/ "axxb") -> #t
(#/.*b/ "aab") -> #t
(#/a.*b/ "axx") -> #f
```

### Combined patterns

```
(#/a.*/ "abcdef") -> #t
(#/a.b*c/ "axbbc") -> #t
(#/.+/ "abc") -> #t
(#/.+/ "") -> #f
```

### `type-name`

```
(Type name #/abc/) -> "REGEX"
```
