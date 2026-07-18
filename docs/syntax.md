# x-lang syntax: the preferred forms

*The syntax of booted x-lang and the idioms this project prefers — the
least-surprise contract. Items marked **[aspirational: R#]** are ruled but
not yet implemented; the ruling record is issue #45. The bare layer
underneath is [syntax-bare.md](syntax-bare.md).*

## Symbols and quoting

Write **`'x`**, always, in any code that loads after boot. `(lit x)` is
the boot-layer *mechanism* — the operative the quote reader expands to —
and its spelling belongs only in files that load before the quote reader
(the boot block) and in discussions of the mechanism itself.

```scheme
(prim-ref 'buf 'tok)        ; preferred
(prim-ref (lit buf) (lit tok)) ; boot-layer files only
'(a . 1)                    ; a quoted assoc
'(a b c)                    ; quoted list
```

The REPL echoes symbols as `'a` and quoted structures with the same
shorthand — the echo pastes back. (Implemented: the printer's `'`
shorthand is live; `(lit a)` echoes are history.)

`` `x ``, `,x`, `,@x` are the quasiquote family; the printer already
echoes them in shorthand.

## Numbers

- `-1`, `+7`, `0xff` — signed integers and hex are core literals at every
  stage. **Never write `(- 0 1)` for a literal.** `(- 0 x)` remains the
  correct spelling for negating a *variable* (it routes through the
  operand's type dispatch).
- Tower literals — dialect-gated (x/and, x/or, x-base): floats `3.14`,
  `-7.5`; rationals `1/3`, `-2/7`; complexes `3+4i`, `2-3i`; big integers
  as plain digit runs. `-1+2i` (negative real part) parses.
  **[aspirational: R4]**
- Floats print with their point: `1.0` echoes `1.0`, not `1`.
  **[aspirational: R4]**
- Leading-zero integers are decimal (`019` is nineteen); `0x13` is hex.
  (Implemented.)

## Characters and strings

- `#\a`, `#\newline`, `#\€` — everywhere, including boot files. The
  string-index idiom `("x" 0)` is retired.
- Strings escape with `\" \\ \n \t \r \0 \xHH`.
- `$"text {expr} text"` interpolates at read time (expands to
  `(Str8 str …)`).

## Collections

- **Vectors have a literal**: `#(1 2 3)`, `#()` — reads and prints.
- **Lists** quote as data: `'(a b c)`; a bare `(a b c)` is a call.
- **Associations have named doors, not literal syntax** — the name
  carries the shape: `'((a . 1))` is an alist literal via quote;
  `(Dict from-plist '(a 1 b 2))` is the simplest dict literal;
  `from-alist` / `from-bindings` for the other shapes. Dict/Set/Array
  print as opaque `#<obj:…>` forms (echoes of containers do not paste
  back — by design, they are mutable objects).
- `#/pattern/` regex literals (dialect-gated with the tower).

## Idioms

- **Primitives are the preferred inline spelling**: `(+ x 1)`,
  `(first (rest x))`, `(- x 1)`. The class methods (`Num inc`,
  `List second`) are namespace homes and value-passing handles
  (`(method-ref Num inc)`), not required spellings.
- **`when`** is the one-armed conditional; `(if c x ())` is retired.
  **[aspirational: R6]**
- Sequencing: `def`-in-body for stepwise computation, `let` for
  bindings-with-scope. `let*` is retired (its six historical uses
  migrate). **[aspirational: R6]**
- Thunks are `(fn () …)`; a self-only signature `(fn (_) …)` means the
  closure *uses* being self-passed. Don't mix the two for "no arguments".
- Errors are raised with `(error …)` and caught with `guard`; misses are
  nil behind presence doors (the absence discipline, spec.md).

## The echo (what the REPL prints back)

| You type | It echoes |
|---|---|
| `'a` | `'a` |
| `42`, `-7`, `"s"`, `#\a`, `#t` | itself |
| `#(1 2 3)`, `1/2`, `3.14`, `3+4i` | itself (tower forms in tower dialects) |
| `` `(a ,x) `` | quasi shorthand |
| a list value | `('a 'b)` — quoted elements, pasteable |
| fn / op / dict / instance | `#<…>` opaque — deliberately not pasteable |
| `()` | *(blank)* |

## Dialect matrix

| Syntax | bare x | x-lang | x/and, x/or, x-base |
|---|---|---|---|
| ints (signed, hex), strings, `#\` chars, lists, `( . x)`, `;` | ✓ | ✓ | ✓ |
| `#t`/`#f` as booleans, printer | — | ✓ | ✓ |
| `'` `` ` `` `,` `,@` `$"…"` `#(…)` | — | ✓ | ✓ |
| floats, rationals, complexes, bignums, `#/…/` | — | — | ✓ |

The bare column is normative for every implementation of the reader;
see [syntax-bare.md](syntax-bare.md).
