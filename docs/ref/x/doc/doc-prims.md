[← Index](../../index.md)

# x/doc/doc-prims

Retroactive documentation for C primitives, boot forms, and type system functions.

## Core forms

### `lit`

Return the argument unevaluated (quote).

**Parameters:**

- **form** : `ANY` — Any expression

**Returns:** `ANY` — The expression itself

**Examples:**

```
(lit x) => x
(lit (1 2 3)) => (1 2 3)
```

### `def`

Bind a name to a value in the current environment.

> Value is evaluated before the name is bound. Use the self parameter (first arg to fn) for recursion.

**Parameters:**

- **name** : `SYMBOL` — Name to bind
- **value** : `ANY` — Expression to evaluate and bind

**Examples:**

```
(def x 42) => 42
```

**See also:** [`set!`](#set!) 

### `set!`

Mutate an existing binding.

> Signals an error if name is not already bound.

**Parameters:**

- **name** : `SYMBOL` — Bound name to update
- **value** : `ANY` — New value

**See also:** [`def`](#def) 

### `fn`

Create a closure (applicative: arguments are evaluated before the body runs).

**Parameters:**

- **params** : `LIST` — Parameter list: (a b), (a . rest), or args for variadic
- **body** : `ANY` — Body expression(s)

**Returns:** `PROCEDURE` — A new closure

**Examples:**

```
(def add (fn (_ a b) (+ a b))) => 
((fn (_ x) (* x x)) 5) => 25
```

**See also:** [`op`](#op) 

### `op`

Create an operative (fexpr: arguments are NOT evaluated).

> Use eval with the env parameter to evaluate arguments selectively.

**Parameters:**

- **params** : `LIST` — Formal parameters for unevaluated args
- **env-param** : `SYMBOL` — Name bound to caller's environment
- **body** : `ANY` — Body expression(s)

**Returns:** `OPERATIVE` — A new operative

**Examples:**

```
(def my-if (op (test then else) e (if (eval test e) (eval then e) (eval else e)))) => 
```

**See also:** [`fn`](#fn) 

### `apply`

Apply a function to a list of arguments.

**Parameters:**

- **f** : `CALLABLE` — Function to apply
- **args** : `LIST` — Argument list

**Returns:** `ANY` — Result of application

**Examples:**

```
(apply + '(1 2)) => 3
```

### `eval`

Evaluate an expression, optionally in a given environment.

> With one arg: uses TCO (tail-call safe). With env arg: saves/restores env after.

**Parameters:**

- **expr** : `ANY` — Expression to evaluate
- **env** : `LIST` — Environment alist (optional)

**Returns:** `ANY` — Result of evaluation

**See also:** [`eval!`](#eval!) 

### `eval!`

Evaluate in current environment, returning the result immediately.

> No TCO, no env save/restore. Use for non-tail evaluation of computed forms.

**Parameters:**

- **expr** : `ANY` — Expression to evaluate

**Returns:** `ANY` — Result of evaluation

**See also:** [`eval`](#eval) 

### `match`

Pattern matching: evaluate clauses until a test succeeds.

> Similar to cond but a C primitive. Tests are evaluated in order.

**Parameters:**

- **clauses** : `LIST` — ((test result) ...) pairs — first truthy test wins

**Examples:**

```
(match ((= x 0) "zero") ((< x 0) "neg") (#t "pos")) => 
```

### `guard`

Error handler: evaluate body with an error guard.

**Parameters:**

- **var** : `SYMBOL` — Name bound to the error value
- **handler** : `ANY` — Expression evaluated if error occurs (var is bound)
- **body** : `ANY` — Expression to evaluate

**Examples:**

```
(guard (e (list (lit error) e)) (+ 1 "x")) => (error "...")
```

### `error`

Signal an error with a message.

**Parameters:**

- **message** : `STRING` — Error message
- **value** : `ANY` — Associated value (optional)

**Examples:**

```
(error "bad input" 42) => 
```

### `wrap`

Create an applicative from a combiner (evaluates args before calling).

**Parameters:**

- **combiner** : `CALLABLE` — An operative or procedure

**Returns:** `CALLABLE` — An applicative

### `unwrap`

Extract the underlying combiner from an applicative.

**Parameters:**

- **applicative** : `CALLABLE` — A wrapped combiner

**Returns:** `CALLABLE` — The underlying combiner

## Pair operations

### `pair`

Create a new pair (cons cell) from two values.

**Parameters:**

- **a** : `ANY` — First element (head)
- **d** : `ANY` — Second element (tail)

**Returns:** `PAIR` — A new pair

**Examples:**

```
(pair 1 2) => (1 . 2)
(pair 1 (pair 2 ())) => (1 2)
```

**See also:** [`first`](#first) [`rest`](#rest) 

### `first`

Return the first element (head) of a pair.

**Parameters:**

- **p** : `PAIR` — A pair

**Returns:** `ANY` — The first element

**Examples:**

```
(first '(1 2 3)) => 1
```

**See also:** [`rest`](#rest) [`pair`](#pair) 

### `rest`

Return the second element (tail) of a pair.

**Parameters:**

- **p** : `PAIR` — A pair

**Returns:** `ANY` — The second element

**Examples:**

```
(rest '(1 2 3)) => (2 3)
```

**See also:** [`first`](#first) [`pair`](#pair) 

### `set-first!`

Mutate the first element of a pair.

**Parameters:**

- **p** : `PAIR` — A pair
- **val** : `ANY` — New value

### `set-rest!`

Mutate the second element of a pair.

**Parameters:**

- **p** : `PAIR` — A pair
- **val** : `ANY` — New value

### `first-int`

Return the first element as a raw integer.

**Parameters:**

- **p** : `PAIR` — A pair

### `rest-int`

Return the second element as a raw integer.

**Parameters:**

- **p** : `PAIR` — A pair

### `set-first-int!`

Mutate the first element as a raw integer.

**Parameters:**

- **p** : `PAIR` — A pair
- **val** : `INT` — Integer value

### `set-rest-int!`

Mutate the second element as a raw integer.

**Parameters:**

- **p** : `PAIR` — A pair
- **val** : `INT` — Integer value

## Arithmetic

### `+`

Variadic addition. Returns the sum of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Sum of all arguments, or 0 with no arguments

**Examples:**

```
(+ 1 2 3) => 6
(+) => 0
```

### `-`

Variadic subtraction. With one argument, negates. With multiple, folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Difference, or negation with one argument

**Examples:**

```
(- 10 3 2) => 5
(- 5) => -5
```

### `*`

Variadic multiplication. Returns the product of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Product of all arguments, or 1 with no arguments

**Examples:**

```
(* 2 3 4) => 24
(*) => 1
```

### `/`

Variadic integer division. Folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Quotient from left fold

**Examples:**

```
(/ 100 5 2) => 10
```

### `%`

Variadic modulo. Folds left.

**Parameters:**

- **args** : `NUMBER` — Two or more numbers

**Returns:** `NUMBER` — Remainder from left fold

**Examples:**

```
(% 10 3) => 1
```

### `~`

Bitwise NOT.

**Parameters:**

- **n** : `INT` — Integer

**Returns:** `INT` — Bitwise complement

### `&`

Bitwise AND.

**Parameters:**

- **a** : `INT` — First operand
- **b** : `INT` — Second operand

**Returns:** `INT` — Bitwise AND

### `|`

Bitwise OR.

**Parameters:**

- **a** : `INT` — First operand
- **b** : `INT` — Second operand

**Returns:** `INT` — Bitwise OR

### `^`

Bitwise XOR.

**Parameters:**

- **a** : `INT` — First operand
- **b** : `INT` — Second operand

**Returns:** `INT` — Bitwise XOR

### `<<`

Left shift.

**Parameters:**

- **n** : `INT` — Value to shift
- **count** : `INT` — Number of bits

**Returns:** `INT` — Shifted value

### `>>`

Arithmetic right shift.

**Parameters:**

- **n** : `INT` — Value to shift
- **count** : `INT` — Number of bits

**Returns:** `INT` — Shifted value

## Predicates

### `eq?`

Test identity equality (pointer equality for objects, value for atoms).

**Parameters:**

- **a** : `ANY` — First value
- **b** : `ANY` — Second value

**Returns:** `BOOLEAN` — t if identical

### `=`

Test numeric equality.

**Parameters:**

- **a** : `INT` — First number
- **b** : `INT` — Second number

**Returns:** `BOOLEAN` — t if equal

### `<`

Test numeric less-than.

**Parameters:**

- **a** : `INT` — First number
- **b** : `INT` — Second number

**Returns:** `BOOLEAN` — t if a < b

### `char->integer`

Convert a character to its integer code point.

**Parameters:**

- **c** : `CHAR` — A character

**Returns:** `INT` — Code point

### `integer->char`

Convert an integer code point to a character.

**Parameters:**

- **n** : `INT` — Code point

**Returns:** `CHAR` — A character

## Strings

### `str-append`

Concatenate two strings.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `STRING` — Concatenated string

### `str->symbol`

Convert a string to a symbol (interned).

**Parameters:**

- **s** : `STRING` — A string

**Returns:** `SYMBOL` — An interned symbol

### `symbol->str`

Convert a symbol to a string.

**Parameters:**

- **sym** : `SYMBOL` — A symbol

**Returns:** `STRING` — The symbol's name

### `list->str`

Convert a list of characters to a string.

**Parameters:**

- **chars** : `LIST` — List of characters

**Returns:** `STRING` — A string

## I/O

### `write`

Write a value in machine-readable form.

> Strings are quoted, characters show read syntax. Use for serialization.

**Parameters:**

- **val** : `ANY` — Value to write

**See also:** [`display`](#display) [`write-to-str`](#write-to-str) 

### `display`

Display a value in human-readable form.

> Strings are unquoted, characters are bare. Use for user output.

**Parameters:**

- **val** : `ANY` — Value to display

**See also:** [`write`](#write) [`display-to-str`](#display-to-str) 

### `read`

Read and parse one expression from stdin.

**Returns:** `ANY` — Parsed expression

### `read-char`

Read one character from stdin.

**Returns:** `CHAR` — A character, or nil at EOF

### `write-to-str`

Capture write output as a string.

**Parameters:**

- **val** : `ANY` — Value to write

**Returns:** `STRING` — The written representation

### `display-to-str`

Capture display output as a string.

**Parameters:**

- **val** : `ANY` — Value to display

**Returns:** `STRING` — The displayed representation

## Memory management

### `heap-mark`

Mark all reachable objects in the heap.

**Returns:** `INT` — Number of marked objects

### `heap-sweep`

Sweep unmarked objects from the heap.

**Returns:** `INT` — Number of freed objects

### `heap-count`

Return the number of live objects on the heap.

**Returns:** `INT` — Object count

### `gc-pin!`

Pin an object to prevent garbage collection.

**Parameters:**

- **obj** : `ANY` — Object to pin

## Type system

### `make-type`

Create a new custom type with handlers.

> Handlers: call, eval, write, display, read, analyse, first-chars, from, to, iter.

**Parameters:**

- **name** : `STRING` — Type name
- **handlers** : `LIST` — Alist of handler functions

**Returns:** `ATOM` — Type handle

**See also:** [`make-instance`](#make-instance) [`type?`](#type?) [`type-of`](#type-of) 

### `make-instance`

Create an instance of a custom type.

**Parameters:**

- **type** : `ATOM` — Type handle from make-type
- **data** : `ANY` — Instance data

**Returns:** `ANY` — A new type instance

### `type?`

Test if a value is an instance of a type.

**Parameters:**

- **type** : `ATOM` — Type handle
- **val** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if val is of the given type

### `type-of`

Return the type handle of a value.

**Parameters:**

- **val** : `ANY` — Any value

**Returns:** `ATOM` — Type handle

### `type-name`

Return the name string of a type handle.

**Parameters:**

- **type** : `ATOM` — Type handle

**Returns:** `STRING` — Type name

### `make-base`

Create a new base object (execution context).

**Returns:** `BASE` — A fresh base with types and primitives

### `iter`

Create an iterator for a value.

**Parameters:**

- **val** : `ANY` — Iterable value

**Returns:** `CALLABLE` — Iterator function: () -> next value or nil

### `token-read-string`

Tokenize a string using a base's type system.

**Parameters:**

- **base** : `BASE` — Base object with type alist
- **s** : `STRING` — Source string to tokenize

**Returns:** `LIST` — List of parsed tokens

## Foreign function interface

### `dlopen`

Load a shared library.

**Parameters:**

- **path** : `STRING` — Library file path
- **mode** : `INT` — dlopen mode flags

**Returns:** `PTR` — Library handle

### `dlsym`

Look up a symbol in a loaded library.

**Parameters:**

- **lib** : `PTR` — Library handle from dlopen
- **name** : `STRING` — Symbol name

**Returns:** `PTR` — Function or data pointer

### `ptr-call`

Call a C function pointer with string args.

**Parameters:**

- **ptr** : `PTR` — Function pointer
- **args** : `STRING` — Arguments (variadic)

**Returns:** `INT` — Return value

### `obj->ptr`

Get the raw pointer of an x-lang object.

**Parameters:**

- **obj** : `ANY` — Any object

**Returns:** `PTR` — Raw pointer

### `ptr->int`

Convert a pointer to an integer.

**Parameters:**

- **p** : `PTR` — A pointer

**Returns:** `INT` — Integer representation

### `int->ptr`

Convert an integer to a pointer.

**Parameters:**

- **n** : `INT` — Integer value

**Returns:** `PTR` — A pointer

## Continuations

### `call/cc`

Call a function with the current continuation.

**Parameters:**

- **f** : `CALLABLE` — Function receiving the continuation

**Returns:** `ANY` — Result of f, or value passed to continuation

## x-core operatives

### `null?`

Test if a value is nil (the empty list).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if nil

### `pair?`

Test if a value is a pair (cons cell).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if pair

### `atom?`

Test if a value is an atom (not a pair).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if not a pair

### `number?`

Test if a value is an integer.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if integer

### `str?`

Test if a value is a string.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if string

### `symbol?`

Test if a value is a symbol.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if symbol

### `char?`

Test if a value is a character.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if character

### `procedure?`

Test if a value is callable (procedure or primitive).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if procedure or primitive

### `if`

Conditional: evaluate test, then branch.

**Parameters:**

- **test** : `ANY` — Condition expression
- **then** : `ANY` — True branch
- **else** : `ANY` — False branch (optional)

**Examples:**

```
(if (> 3 2) "yes" "no") => "yes"
```

**See also:** [`match`](#match) [`cond`](#cond) 

### `let`

Bind local variables and evaluate body.

> Named let: (let name ((var init) ...) body) creates a loop.

**Parameters:**

- **bindings** : `LIST` — ((name value) ...) binding pairs
- **body** : `ANY` — Body expression

**Examples:**

```
(let ((x 1) (y 2)) (+ x y)) => 3
(let loop ((n 5) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n)))) => 120
```

**See also:** [`let*`](#let*) [`letrec`](#letrec) 

### `do`

Evaluate expressions sequentially, return last result.

**Parameters:**

- **exprs** : `ANY` — One or more expressions

**Examples:**

```
(do (display "hi") 42) => 42
```

### `begin`

Alias for do.

**See also:** [`do`](#do) 

### `not`

Logical negation.

**Parameters:**

- **x** : `ANY` — Value to negate

**Returns:** `BOOLEAN` — t if x is falsy

### `list`

Create a list from arguments.

**Parameters:**

- **args** : `ANY` — Zero or more values

**Returns:** `LIST` — A new list

**Examples:**

```
(list 1 2 3) => (1 2 3)
```

### `and`

Short-circuit logical AND.

**Parameters:**

- **args** : `ANY` — Zero or more expressions

**Returns:** `ANY` — Last truthy value, or #f

**Examples:**

```
(and 1 2 3) => 3
```

### `or`

Short-circuit logical OR.

**Parameters:**

- **args** : `ANY` — Zero or more expressions

**Returns:** `ANY` — First truthy value, or nil

**Examples:**

```
(or #f 42) => 42
```

### `time`

Time an expression's evaluation in microseconds.

**Parameters:**

- **expr** : `ANY` — Expression to time

**Returns:** `ANY` — Result of expr (prints elapsed time as side effect)

**Examples:**

```
(time (fold + 0 (range 0 1000))) => 499500
```

### `convert`

Convert a value between types.

**Parameters:**

- **val** : `ANY` — Value to convert
- **type** : `ATOM` — Target type handle

**Returns:** `ANY` — Converted value

### `newline`

Display a newline character.

### `quasi`

Quasiquote: template with unquote and splicing.

> Use , to unquote a single expression, ,@ to splice a list.

**Parameters:**

- **template** : `ANY` — Template expression with , and ,@ escapes

**Examples:**

```
(let ((x 42)) (quasi (a ,x b))) => (a 42 b)
```

### `repl`

Start the read-eval-print loop.

> Customizable: %repl-prompt and %repl-print control display.

### `include-once`

Load and evaluate a file, skipping if already loaded.

**Parameters:**

- **path** : `STRING` — File path to include

### `provide`

Register a module's exported symbols.

**Parameters:**

- **name** : `SYMBOL` — Module name, e.g. x/list
- **exports** : `SYMBOL` — Exported symbol names (variadic)

### `import`

Import a module (include its file if not yet loaded).

**Parameters:**

- **name** : `SYMBOL` — Module name to import

### `number->str`

Convert an integer to a string.

**Parameters:**

- **n** : `INT` — Integer to convert
- **radix** : `INT` — Base (optional, default 10)

**Returns:** `STRING` — String representation

### `str->number`

Parse a string as an integer.

**Parameters:**

- **s** : `STRING` — String to parse

**Returns:** `INT` — Parsed integer, or nil on failure

### `str-ref`

Return the character at an index in a string.

**Parameters:**

- **s** : `STRING` — A string
- **i** : `INT` — Zero-based index

**Returns:** `CHAR` — Character at index

### `str-length`

Return the length of a string.

**Parameters:**

- **s** : `STRING` — A string

**Returns:** `INT` — Number of characters

### `substring`

Extract a substring.

**Parameters:**

- **s** : `STRING` — Source string
- **start** : `INT` — Start index (inclusive)
- **end** : `INT` — End index (exclusive)

**Returns:** `STRING` — The substring

### `str=?`

Test string equality.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOLEAN` — t if equal

### `make-str`

Create a string of repeated characters.

**Parameters:**

- **n** : `INT` — Length
- **c** : `CHAR` — Fill character

**Returns:** `STRING` — A new string

### `gcd`

Greatest common divisor.

**Parameters:**

- **a** : `INT` — First integer
- **b** : `INT` — Second integer

**Returns:** `INT` — GCD

### `lcm`

Least common multiple.

**Parameters:**

- **a** : `INT` — First integer
- **b** : `INT` — Second integer

**Returns:** `INT` — LCM

### `heap-collect`

Run a full garbage collection cycle.

**Returns:** `INT` — Number of freed objects

### `heap-mark-root!`

Register a GC root object that will always be marked during collection.

**Parameters:**

- **obj** : `ANY` — Object to protect from GC

### `heap-mark-hook!`

Register a callback to run during the GC mark phase.

**Parameters:**

- **fn** : `CALLABLE` — Function called during mark

### `heap-free-hook!`

Register a callback to run during the GC free phase.

**Parameters:**

- **fn** : `CALLABLE` — Function called when objects are freed

### `require-once`

Include a file only if it has not been loaded before. Alias for include-once.

**Parameters:**

- **path** : `STRING` — File path to include

**See also:** [`include-once`](#include-once) 

### `peek-char`

Return the next character from stdin without consuming it.

**Returns:** `CHAR` — The next character, or () at EOF

### `current-line`

Return the current source line number.

**Returns:** `INTEGER` — Line number in the current input

## Type system

### `type-alist`

Return the interpreter's type alist from the base object.

**Returns:** `LIST` — Alist of (name . type-struct) pairs

### `type-by-atom`

Look up a type struct by its handle atom (from type-of).

**Parameters:**

- **handle** : `ATOM` — Type handle returned by type-of

**Returns:** `LIST` — The type struct, or () if not found

### `type-io`

Navigate to a type struct's IO group (analyse, delimit, read, write, display, error).

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — IO group

### `type-cvt`

Navigate to a type struct's conversion group (from, to).

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Conversion group

### `type-write-cell`

Get the write-handler stack cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Stack cell for write handlers

### `type-analyse-cell`

Get the analyse-handler stack cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Stack cell for analyse handlers

### `type-from-cell`

Get the from-conversion cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Alist of source-type to converter function

### `type-to-cell`

Get the to-conversion cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Alist of target-type to converter function

### `type-push-write`

Push a write handler onto a type's write stack.

**Parameters:**

- **ts** : `LIST` — Type struct
- **handler** : `CALLABLE` — Write handler function

### `type-pop-write`

Pop the top write handler from a type's write stack.

**Parameters:**

- **ts** : `LIST` — Type struct

### `type-push-analyse`

Push an analyse handler onto a type's analyse stack.

**Parameters:**

- **ts** : `LIST` — Type struct
- **handler** : `CALLABLE` — Analyse handler function

### `type-cast!`

Overwrite an object's type tag with the type of another object.

**Parameters:**

- **obj** : `ANY` — Object to retype
- **type-src** : `ANY` — Object whose type to copy

**Returns:** `ANY` — The retyped object

### `doc`

Attach documentation metadata to a definition, provide, or bare symbol.

> Three forms: (doc (def name val) meta... desc), (doc (provide name syms) meta... desc), (doc name meta... desc)

> Meta forms: (param name TYPE desc), (returns TYPE desc), (example expr result), (see name), (note text)

### `note`

Section marker for documentation grouping. No-op at runtime.

**Parameters:**

- **text** : `STRING` — Section description

### `help`

Look up documentation in the REPL.

> (help) shows overview. (help name) shows function or module docs. (help modules) lists all modules.

### `apropos`

Search documentation by name substring.

**Parameters:**

- **str** : `STRING` — Substring to search for

### `modules`

List all known modules with load status and descriptions.

