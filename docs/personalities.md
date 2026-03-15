# Computational Expressions in C

## Personalities

A personality is a library file that aliases x-lang primitives and defines derived forms to emulate another language's syntax and semantics. Personalities are loaded via shell pipe before user input:

```
cat lib/x.x lang/r5rs/lib/r5rs.x - | ./x     # R5RS Scheme
cat lib/x.x lang/krn/lib/krn.x - | ./x       # Kernel
cat lib/x.x lang/sl/lib/sl.x - | ./x         # SL
```

The interpreter has no file I/O. Each personality file is a single `(do ...)` expression that binds aliases and derived forms into the environment, then returns a tag symbol (`r5rs`, `krn`, or `sl`).

Because personalities are just library code, they compose with the standard library and with each other. The same base interpreter evaluates all of them.

Personalities live under `lang/<name>/lib/<name>.x`. Each derived language directory can also contain additional libraries and examples.

---

### R5RS Scheme (`lang/r5rs/lib/r5rs.x`)

R5RS-compatible Scheme built on x-lang.

#### Aliases

| Scheme | x-lang |
|--------|--------|
| `lambda` | `fn` |
| `begin` | `do` |
| `set!` | `set` |
| `modulo` | `%` |
| `cons` | `pair` |
| `car` | `first` |
| `cdr` | `rest` |
| `quote` | `lit` |
| `quasiquote` | `quasi` |
| `cond` | `match` |
| `#t` | `#t` |
| `#f` | `()` |

#### Derived Forms

**`define`** — `(define x val)` or `(define (f args...) body...)`

Operative. The function shorthand `(define (f x y) body)` expands to `(def f (fn (x y) body))`.

**`when`** — `(when test body...)`

Operative. Evaluates body forms when test is true.

**`unless`** — `(unless test body...)`

Operative. Evaluates body forms when test is false.

**`let*`** — `(let* ((x 1) (y (+ x 1))) body...)`

Operative. Sequential binding. Expands to nested `let` forms.

**`letrec`** — `(letrec ((f (lambda (n) ...))) body...)`

Operative. Recursive binding. Expands to `let` with initial nil bindings followed by `set!` assignments.

**`let`** — Extended to support named let: `(let loop ((i 0)) body...)`

Operative. Overrides the base `let` to add R5RS named let. The name is bound to a recursive function with the binding variables as parameters. Plain `let` forms pass through to the base `%let`.

**`case`** — `(case key ((datum...) expr) ... (else expr))`

Operative. Evaluates key, then checks each clause's datum list. Uses `=` for numbers, `eq?` for everything else. The `else` clause matches unconditionally.

#### Composition Accessors

```
caar cadr cdar cddr
caaar caadr caddr cdddr
```

Composed `first`/`rest` accessors following the standard `car`/`cdr` naming convention.

#### R5RS Compatibility

| Function | Implementation |
|----------|---------------|
| `list-ref` | `(nth n lst)` |
| `list-tail` | `(drop n lst)` |
| `member` | Linear search using `equal?`, returns sublist or `#f` |
| `assoc` | Association list lookup using `equal?`, returns pair or `#f` |
| `string-copy` | `(substring s 0 (string-length s))` |

---

### Kernel (`lang/krn/lib/krn.x`)

Kernel language built on x-lang. Operatives are first-class; applicatives are derived via `wrap`.

#### Philosophy

In Kernel, the fundamental abstraction is the operative (`$vau`), which receives its operands unevaluated along with the caller's dynamic environment. Applicatives (which evaluate their arguments) are created by wrapping operatives. This is the inverse of Scheme, where `lambda` (applicative) is fundamental and fexprs are absent.

x-lang's C primitives are already fexprs that evaluate their own arguments, so Kernel's operatives map directly to `op` and applicatives map to `wrap`ped operatives.

#### Core Aliases

| Kernel | x-lang |
|--------|--------|
| `$vau` | `op` |
| `cons` | `pair` |
| `car` | `first` |
| `cdr` | `rest` |
| `quote` | `lit` |
| `$cond` | `match` |
| `$if` | `if` |
| `$let` | `let` |
| `$sequence` | `do` |
| `#t` | `#t` |
| `#f` | `()` |
| `#ignore` | `()` |
| `#inert` | `()` |

#### Core Forms

**`$define!`** — `($define! x val)` or `($define! (f args...) body...)`

Operative. Like Scheme's `define` but using `$lambda` for the function shorthand.

**`$lambda`** — `($lambda (args...) body...)`

Operative. Creates an applicative by wrapping a `$vau` form. The environment parameter is bound to `#ignore`.

```
($define! $lambda (op (formals . body) e
  (wrap (eval (pair (lit $vau)
                (pair formals
                  (pair (lit #ignore) body))) e))))
```

**`$when`** — `($when test body...)`

Operative. Evaluates body forms when test is true.

**`$unless`** — `($unless test body...)`

Operative. Evaluates body forms when test is false.

**`$let*`** — `($let* ((x 1) (y (+ x 1))) body...)`

Operative. Sequential binding via nested `$let` expansion.

**`$letrec`** — `($letrec ((f ($lambda (n) ...))) body...)`

Operative. Recursive binding via `$let` + `set`. Uses `lr-` prefixed parameter names to avoid dynamic scoping collisions.

#### Special Values

| Value | Meaning | Representation |
|-------|---------|----------------|
| `#t` | true | `#t` |
| `#f` | false | `()` (nil) |
| `#ignore` | ignored parameter | `()` (nil) |
| `#inert` | no useful value | `()` (nil) |

In standard Kernel, these are distinct types. Here they map to existing x-lang values.

#### Kernel-Specific Predicates

| Predicate | Behavior |
|-----------|----------|
| `operative?` | True if not nil, not a procedure, not a number, string, symbol, or pair |
| `applicative?` | Alias for `procedure?` |
| `boolean?` | True if `#t` or nil |
| `inert?` | Alias for `null?` |

#### Environment Operations

**`get-current-environment`** — `(get-current-environment)`

Operative with no parameters. Returns the caller's environment as a first-class value. Implemented as `(op () e e)`.

**`make-environment`** — `(make-environment)`

Returns a fresh empty environment (nil alist).

#### Reimplemented Functions

Kernel provides its own implementations of common functions using `$lambda` and `$define!` rather than inheriting from `lib/x.x`:

`length`, `append`, `reverse`, `list-ref`, `map`, `filter`, `for-each`

#### Composition Accessors

```
caar cadr cdar cddr caddr
```

#### Number Operations

`zero?`, `positive?`, `negative?`, `even?`, `odd?`, `abs`, `min`, `max`

#### List Search

| Function | Behavior |
|----------|----------|
| `member` | Linear search using `eq?`, returns sublist or `#f` |
| `assoc` | Association list lookup using `eq?`, returns pair or `#f` |

---

### SL (`lang/sl/lib/sl.x`)

SL (Scheme-Like) personality with direct syscall access. Ported from the original SL project, preserving its kernel-hacking capabilities on x-lang's foundation.

#### Aliases

SL includes the same Scheme aliases as R5RS (`lambda`, `begin`, `set!`, `cons`, `car`, `cdr`, `define`, etc.) plus full car/cdr composition accessors up to 4 levels deep (28 accessors: `caar` through `cddddr`).

#### Syscall Interface

The key feature. When compiled with `-DX_SYSCALL`, a C primitive `syscall` is registered that passes arguments directly to the platform's `syscall()` function. It accepts up to 7 arguments (syscall number + 6 parameters), handling integer and string types.

**`syscall-id`** — `(syscall-id (lit write))` => `1`

Looks up a syscall number by name. Uses the x86_64 table by default (314 entries), falling back to an i386/BSD table (191 entries). Returns -1 if not found.

**`display-string`** — `(display-string "hello\n")`

Writes a string to stdout via `syscall`.

**`sl-newline`** — `(sl-newline)`

Writes a newline to stdout via `syscall`.

**`time`** — `(time)`

Returns the current time via `syscall`.

#### Character Constants

| Name | Value |
|------|-------|
| `#newline`, `#nl` | newline character |
| `#cr` | carriage return |
| `#esc` | escape character |
| `#0` | null character |
| `#crnl` | CR+LF pair |

#### I/O Constants

`stdin` (0), `stdout` (1), `stderr` (2)

#### Additional Libraries

**`lang/sl/lib/file.x`** — File I/O via syscall. Provides `fopen`, `fclose`, `fread`, `fwrite`, `fgetc` and file mode/stat flag constants.

```
cat lib/x.x lang/sl/lib/sl.x lang/sl/lib/file.x - | ./x
```

**`lang/sl/lib/socket.x`** — Socket constants. Provides `socketcall-id`, `protocol-format-id`, `sock-id` lookup functions.

#### Examples

Example programs in `lang/sl/examples/`:

- `hello.x` — Hello world via syscall write
- `cat.x` — Display a file using syscall read/write
- `execve-ls.x` — Fork and execute /bin/ls

#### Derived Forms

SL provides the same derived forms as R5RS (`when`, `unless`, `let*`, `letrec`, named `let`, `case`) plus a Scheme-style `do-loop` iteration form.
