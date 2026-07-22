# x-lang Architecture

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*


The interpreter is a type-agnostic expression evaluator written in C89. It provides atom/pair primitives, an adaptive type system, and fexpr-based evaluation. It has no built-in knowledge of any particular language semantics. It is dangerous and minimal, like a CPU: it executes what it is given without guardrails, and all safety, convenience, and language identity are supplied by libraries loaded at runtime.

### The Four Layers

Each layer expands capabilities without modifying those below it.

**Layer 1: Atom/Pair Bootstrap.** One storage shape, two blessed lengths: every object is a fixed-size vector of datum slots, and the two smallest -- the atom (one slot) and the pair (two) -- provide enough machinery for evaluation and data construction. The evaluator dispatches through type methods rather than hardcoding knowledge of specific types, so these two suffice to get the system running; the user-facing `Vector` type is the same shape with the length exposed.

**Layer 2: Adaptive Type System.** `make-type` and `make-instance` introduce new types at runtime. Each type is a nested linked list carrying a fixed prefix of dispatch methods (call, eval, write, length, etc.) and an extensible tail for type-specific data. New types plug into the existing evaluation, printing, and comparison infrastructure the moment they are registered. Types registered at startup include symbols, lists, integers, strings, characters, primitives, procedures, operatives, buffers, whitespace, and comments.

**Layer 3: Modular Library.** 100+ modules (one module = one `provide`-ing `.x` source file) organized by domain: core operations (`lib/x/core/`), custom types (`lib/x/type/`), a numeric tower (`lib/x/num/`), system interfaces (`lib/x/sys/`), self-hosted tools (`lib/x/tool/`), documentation (`lib/x/doc/`), and platform-specific code (`lib/x/platform/`). The bootstrap sequence in `lib/x-core.x` pre-registers all boot module names and loads 40+ core modules via `provide`/`import` with name-keyed deduplication (`docs/boot-amalgam.md`). This layer is composed into dialects (helium, xenon, radon) that control which capabilities are available.

**Layer 4: FFI and Native Code.** Dynamic library loading via `dlopen`/`dlsym` (`src/x-prim/ffi.c`), typed foreign calls with convention strings, raw pointer operations, and a JIT compiler (`lib/x/tool/compile.x`, `lib/x/tool/asm.x`) that compiles x-lang functions to native x86_64/ARM64 machine code via a data-driven assembler with mmap execution. POSIX system calls (fork, exec, pipe, dup2, wait, open, close, etc.) are wrapped as x-lang functions through the FFI in `lib/x/sys/posix.x`.

### The Base Object

The base object (`p_base`) is the interpreter's root context: a pair tree built from the same atoms and pairs as every other value (there is no struct). x-expr supplies a skeleton -- the I/O and metadata groups, profile counters, hooks, and heap-group -- and this project fills the environment/control half x-expr leaves nil and appends a few fields of its own. Every leaf is either a stack cell `(current . saved)` for dynamic push/pop, or a direct value.

```
base = x_base(p_base)
  first: env + ctrl              (x-expr leaves nil; filled here)
    env    env-alist, env-local-boundary, env-global-tree, shadow-list
    ctrl   save-stack, error-handler, tco-expr, tco-env
  rest:  io + meta               (x-expr skeleton)
    io     type-alist, line, true, false  (+ x-expr's file handles)
    meta   profile counters, eval-list, token-cache,
           mark-hooks, free-hooks, mark-roots, sigint
```

Field access is via nested `first`/`rest` traversal, expressed with the `x_<binary>` accessor family (`x_0` = first, `x_1` = rest, read left-to-right outer-to-inner). For example `x_eval_field_env_alist(X)` resolves to `first(first(first(base)))`. The authoritative layout, including which leaves are field cells versus direct values, is `tools/base-layout.x` (mirrored by `include/x-eval-layout.h` and pinned by `make check-base-paths`).

#### Nil

Nil is `NULL`. The empty list `()` parses to `NULL`, and `x_obj_isnil` checks `p_obj == NULL`. The base object `p_base` is the execution context only -- it is not nil.

### The Object Model

Every runtime value is an `x_obj_t`, a union of pointer, integer, character, string, function pointer, and void pointer. Objects are allocated as contiguous arrays of this union:

```
[ gc | type | flags | data... ]
```

- **gc** -- GC chain pointer (present only when `X_GC` is defined).
- **type** -- pointer to the object's type definition (or to `x_type_atom_obj` / `x_type_pair_obj` for intrinsic types).
- **flags** -- bit field encoding sub-type (prim, fn, int, char, str, ptr) and ownership/read-only status.
- **data** -- one datum for atoms, two for pairs.

Atoms carry a single `x_obj_t` datum. Pairs carry two: `first` and `rest`. All compound structures (lists, environments, the base itself, type definitions) are built from chains of pairs terminated by nil (`p_base`).

### The Contract Pattern

Types and the base object share the same structural contract: a nested linked list with a fixed-layout prefix followed by an extensible tail.

**Type contract** (13 fields across 5 groups):

```
(
  name
  data
  (make free clone units length)
  (call eval convert)
  (analyse delimit write)
)
```

The `struct x_type_t` mirrors this layout for convenient initialization in C, but the runtime representation is pairs. The heap group governs allocation and sizing. The proc group governs evaluation and invocation. The io group governs parsing and output. The `data` field and any pairs appended beyond field 4 are owned by the specific type -- the infrastructure only inspects the prefix it understands.

**Base contract** (3 top-level fields with nested tuples):

```
(
  (type-alist)
  (file-in file-out file-err)
  (env-alist eval-list buffer token-cache error-handler tco-expr tco-env)
)
```

Both contracts are extensible by appending pairs to the tail. This is how the system remains type-agnostic: adding a new type or extending the base does not require modifying existing traversal code.

### Evaluation Model

#### Fexpr Foundation

All C-level primitives are fexprs: they receive their arguments unevaluated. Every primitive has the signature:

```c
x_obj_t *primitive(x_obj_t *p_base, x_obj_t *p_args)
```

where `p_args` is the raw cdr of the call form as it appeared in source. Each primitive explicitly evaluates what it needs via `x_prim_eval_arg`. Core forms like `if`, `def`, `match`, and `do` evaluate selectively. Arithmetic and comparison primitives evaluate all arguments. `lit` (quote) evaluates nothing.

There are no special forms: the evaluator (`x_eval`) does not distinguish the core forms from functions. It checks the expression's type for an `eval` dispatch method, calls it, and if the result sets a tail-call expression, trampolines via `goto eval_start`.

#### fn: Applicative Combiners

`fn` creates a closure (procedure). When a procedure is called, the caller's arguments are evaluated first (via `x_prim_evlis`), then bound to the procedure's parameter list in an extended copy of the closure's captured environment. The body is then evaluated in that environment.

```
(fn (_ x y) (+ x y))
```

This is the applicative evaluation model: arguments are values by the time the body executes.

#### op: Operative Combiners

`op` creates an operative (user-level fexpr). When an operative is called, arguments are passed unevaluated. The operative also receives the caller's environment as an additional binding, giving it full control over if and how to evaluate its arguments.

```
(op (x) e (eval x e))
```

The parameter list binds the unevaluated argument tree. The environment parameter binds the caller's environment. The body executes in the operative's own captured environment, extended with these bindings.

#### wrap / unwrap

`wrap` takes any combiner and produces an applicative: a combiner that evaluates its arguments before delegating to the wrapped combiner. `unwrap` extracts the underlying combiner from an applicative. These allow conversion between operative and applicative behavior without creating new primitive types.

#### Tail-Call Optimization

The evaluator implements TCO via a trampoline. When a primitive sets `tco-expr` on the base object (instead of directly returning a result), `x_eval` loops back to `eval_start` with the new expression. The environment is saved and restored around the trampoline to prevent leaking scope across tail calls.

### The Expression Pipeline

Input flows through a fixed sequence of stages:

```
stdin -> buffer -> tokenizer -> s-expression reader -> evaluator -> writer -> stdout
```

1. **Input.** Bytes arrive on stdin. The interpreter has no file I/O primitives -- loading code is done externally via shell pipe (`cat lib/x.x program.x | ./x`).

2. **Buffer.** A fixed-size `char[]` buffer (`X_CLI_BUFFER_SIZE`, 256 bytes) is wrapped in a buffer type object and attached to the base at `x_base_field_buffer`. The buffer feeds single characters to the tokenizer.

3. **Tokenizer.** `x_token_read` iterates the registered type list. Each type provides an `analyse` method that inspects the buffer to determine if the upcoming bytes match that type, and a `delimit` method that determines token boundaries. The tokenizer dispatches to the highest-scoring type. In the xenon and radon dialects, analyser functions for numeric types are compiled to native machine code at load time via the JIT compiler, significantly accelerating tokenization.

4. **S-expression reader.** `x_sexp_read` delegates to `x_token_read`. Pair/list syntax is handled by `x_sexp_pair_read` and `x_sexp_list_read`, which recursively call the token reader for sub-expressions. The reader produces a tree of atoms and pairs.

5. **Evaluator.** `x_eval` takes a wrapped expression, checks the expression's type for an `eval` dispatch method, and calls it. Symbols resolve through environment lookup. Lists dispatch through the callable in head position. Self-evaluating types (integers, strings) return themselves.

6. **Writer.** `x_sexp_write` dispatches on type: intrinsic atoms and pairs have hardcoded writers; all other types dispatch through `x_type_field_write`. Output goes to the base's stdout file descriptor.

The REPL loop in `x_cli.c` runs these stages in sequence: prompt, read, eval, print, repeat until EOF.

### Dialect System

The library is composed into dialects that control what capabilities are loaded. Each dialect includes all of the previous:

**helium** (`lib/he.x` / `lib/x-core.x`): The light dialect and the default (`lib/x.x` is a pointer to it). Bootstraps 40+ modules providing core operations, combinators, list processing, strings, vectors, promises, quasiquote, and a REPL. No numeric tower or system access.

**xenon** (`lib/xe.x`): Stable full-stack dialect. Adds POSIX wrappers, hash tables, the JIT compiler, and a numeric tower (bignum, float, rational, complex). Each numeric type's tokenizer analyser is compiled to native code immediately after loading, so subsequent source files are parsed through fast compiled analysers rather than interpreted ones.

**radon** (`lib/rn.x`): Experimental dialect. Everything in xenon plus raw syscall lookup tables, file I/O, socket constants, car/cdr composition helpers, character constants, and I/O handle constants.

Dialects are selected via the shell wrapper's `-l` flag:

```sh
sh x.sh              # helium (default)
sh x.sh -l xe        # xenon
sh x.sh -l rn        # radon
```

Language personalities (R5RS Scheme, R7RS Scheme, Kernel, ASH shell, sweet expressions) are loaded as additional libraries on top of a dialect. The interpreter core has no knowledge of any specific language. Without any library, the bare interpreter exposes only C-level primitives.

### I/O Model

The C core has no file-open or file-close primitives. Its only I/O is reading bytes from stdin and writing bytes to stdout/stderr via POSIX `read`/`write` syscalls on the file descriptors stored in the base object. Code loading happens externally through shell concatenation.

The xenon and radon dialects extend this via the FFI: `lib/x/sys/posix.x` wraps fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, and setenv. `lib/x/sys/file.x` (radon only) provides higher-level file I/O with symbolic mode flags. This keeps the C core minimal while still supporting full system access when needed.
