# Examples

Every example carries its exact run command in a header comment. The
directory tells you which dialect it needs: `x/` runs on base x-lang, `and/`
needs `-l x-and`, `or/` needs `-l x-or`.

Read them in this order.

## 1. Base x-lang (`x/`)

No flags needed — these run on the default dialect.

| File | Lines | What it shows |
|------|-------|---------------|
| [`x/hello.x`](x/hello.x) | 7 | Output: `display` and `newline`. Start here. |
| [`x/lists.x`](x/lists.x) | 32 | Pairs, list construction, and the higher-order functions (`map`, `filter`, `fold`) |
| [`x/factorial.x`](x/factorial.x) | 31 | **Self-as-argument-0** — recursion without a global name — plus a tail-recursive accumulator and a note on where 64-bit integers run out |
| [`x/fibonacci.x`](x/fibonacci.x) | 27 | Recursion and iteration compared |

```sh
sh x.sh -f examples/x/hello.x
```

`x/factorial.x` is the one to read closely if you only read one: it explains
why every closure receives itself as its first argument, which is the piece of
x-lang that surprises people coming from Scheme.

## 2. The full-stack dialect (`and/`)

Needs `-l x-and`, which adds the numeric tower, POSIX, hash tables, and the
JIT.

| File | Lines | What it shows |
|------|-------|---------------|
| [`and/numeric-tower.x`](and/numeric-tower.x) | 29 | Automatic promotion across integers, bignums, rationals, floats, and complex numbers |
| [`and/regex.x`](and/regex.x) | 25 | The `#/pattern/` literal, and a regex used as a **callable value** |

```sh
sh x.sh -l x-and -f examples/and/numeric-tower.x
```

## 3. The experimental dialect (`or/`)

Needs `-l x-or`. This dialect is explicitly experimental; it adds raw syscall
tables and file I/O. These examples touch the operating system directly.

| File | Lines | What it shows |
|------|-------|---------------|
| [`or/hello.x`](or/hello.x) | 10 | Output via a raw `write` syscall instead of the library |
| [`or/cat.x`](or/cat.x) | 22 | Reading a file with raw syscalls (note the working-directory caveat in its header) |
| [`or/execve-ls.x`](or/execve-ls.x) | 16 | `fork` + `execve` to run `/bin/ls` |

```sh
sh x.sh -l x-or -f examples/or/hello.x
```

## 4. A whole second language

[`logo/ch1.logo`](logo/ch1.logo) holds the Chapter-1 turtle programs from
*Turtle Geometry* (Abelson & diSessa, 1981) — written in **Logo**, not
x-lang. They run under the Logo interpreter in
[`apps/logo/`](../apps/logo/), which is itself ~2,400 lines of x-lang.

```sh
sh x.sh -l logo             # REPL + live turtle at http://localhost:8080
```

See [`apps/logo/README.md`](../apps/logo/README.md) for the command reference
and for how to load `ch1.logo`.

## Not yet covered

Two of the language's headline features have no example here. Until they do,
the references are:

- **Fexprs / `op`** — user-level operatives that receive their arguments
  unevaluated along with the caller's environment. See
  [The Fexpr Model](../docs/tutorial.md#the-fexpr-model) and
  [`docs/spec.md`](../docs/spec.md).
- **The object system / `def-class`** — see
  [`docs/object-system.md`](../docs/object-system.md).
