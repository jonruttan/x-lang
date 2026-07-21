# Examples

Every example carries its exact run command in a header comment. The
directory tells you which dialect it needs: `x/` runs on the default dialect (helium), `xe/`
needs `-l xe` (xenon), `rn/` needs `-l rn` (radon).

Every example is executed in CI (`make check-examples`, part of `make test`),
with output pinned where it is portable — so the run commands and outputs you
see here are verified, not aspirational.

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

## 2. The full-stack dialect (`xe/`)

Needs `-l xe` (xenon), which adds the numeric tower, POSIX, hash tables, and the
JIT.

| File | Lines | What it shows |
|------|-------|---------------|
| [`xe/numeric-tower.x`](xe/numeric-tower.x) | 29 | Automatic promotion across integers, bignums, rationals, floats, and complex numbers |
| [`xe/regex.x`](xe/regex.x) | 25 | The `#/pattern/` literal, and a regex used as a **callable value** |

```sh
sh x.sh -l xe -f examples/xe/numeric-tower.x
```

## 3. The experimental dialect (`rn/`)

Needs `-l rn` (radon). This dialect is explicitly experimental; it adds the raw
syscall surface (file I/O loads on demand — see `rn/cat.x`). These examples
touch the operating system directly.

| File | Lines | What it shows |
|------|-------|---------------|
| [`rn/hello.x`](rn/hello.x) | 10 | Output via a raw `write` syscall instead of the library |
| [`rn/cat.x`](rn/cat.x) | 22 | Reading a file with raw syscalls (note the working-directory caveat in its header) |
| [`rn/execve-ls.x`](rn/execve-ls.x) | 16 | `fork` + `execve` to run `/bin/ls` |

```sh
sh x.sh -l rn -f examples/rn/hello.x
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
