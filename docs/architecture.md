# Computational Expressions in C

## Architecture

The interpreter is a type-agnostic expression evaluator written in C89. It provides atom/pair primitives, an adaptive type system, and fexpr-based evaluation. It has no built-in knowledge of any particular language semantics. It is dangerous and minimal, like a CPU: it executes what it is given without guardrails, and all safety, convenience, and language identity are supplied by libraries loaded at runtime.

### The Four Layers

Each layer expands capabilities without modifying those below it.

**Layer 1: Atom/Pair Bootstrap.** Two intrinsic structural types -- atoms (single datum) and pairs (two data) -- provide enough machinery for evaluation and data construction. The evaluator dispatches through type methods rather than hardcoding knowledge of specific types, so these two suffice to get the system running.

**Layer 2: Adaptive Type System.** `make-type` and `make-instance` introduce new types at runtime. Each type is a nested linked list carrying a fixed prefix of dispatch methods (call, eval, write, length, etc.) and an extensible tail for type-specific data. New types plug into the existing evaluation, printing, and comparison infrastructure the moment they are registered. Types registered at startup include symbols, lists, integers, strings, characters, primitives, procedures, operatives, buffers, whitespace, and comments.

**Layer 3: Standard Library.** `lib/x.x` adds approximately 80 functions written in x-lang itself: combinators, list operations, sorting, association lists, string utilities, and vectors. This layer expands the system into type domains the C core does not address.

**Layer 4: DLL Extension (planned).** Native C functions linked as primitives via shared libraries, extending the interpreter with new type domains (floating point, regular expressions, etc.) at native performance.

### The Base Object

The base object (`p_base`) is the interpreter's root context. It is a nested linked list with three top-level fields:

```
(
  (type-alist)
  (file:in file:out file:err)
  (env-alist symbol-list expr-list buffer token-cache error-handler tco-expr tco-env)
)
```

- **type-alist** -- association list of all registered types, keyed by name.
- **files** -- file descriptors for stdin, stdout, stderr.
- **env** -- the environment tuple: bindings alist, symbol interning list, expression list, read buffer, token cache, error handler stack, and tail-call optimization state.

Field access is via nested `first`/`rest` traversal. The macro `x_base_field_env_alist(X)` expands to `x_firstobj(x_restobj(x_restobj(x_firstobj(X))))`. There is no struct -- the base is the same pair/atom material as every other value.

#### p_base IS nil

The base context object doubles as the nil value for its interpreter. The nil test is:

```c
int x_obj_isnil(x_obj_t *p_base, x_obj_t *p_obj)
{
    return p_obj == p_base || p_obj == NULL;
}
```

Any primitive that returns "nothing" returns `p_base`. Any predicate that fails returns `p_base`. Empty lists terminate at `p_base`. This means nil is not a global constant -- it is the specific base object of the interpreter instance that produced the value. Two separate interpreters (created via `make-base`) have distinct nils.

At construction time, the base bootstraps itself: `x_base_make` allocates an atom with `p_base` (initially NULL) as its own nil, then overwrites the atom's datum with the nested context structure. After construction, `p_base` points to a live value that is also the nil sentinel for all operations within that interpreter.

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

where `p_args` is the raw cdr of the call form as it appeared in source. Each primitive explicitly evaluates what it needs via `x_prim_eval_arg`. Special forms like `if`, `def`, `match`, and `do` evaluate selectively. Arithmetic and comparison primitives evaluate all arguments. `lit` (quote) evaluates nothing.

The evaluator (`x_eval`) does not distinguish special forms from functions. It checks the expression's type for an `eval` dispatch method, calls it, and if the result sets a tail-call expression, trampolines via `goto eval_start`.

#### fn: Applicative Combiners

`fn` creates a closure (procedure). When a procedure is called, the caller's arguments are evaluated first (via `x_prim_evlis`), then bound to the procedure's parameter list in an extended copy of the closure's captured environment. The body is then evaluated in that environment.

```
(fn (x y) (+ x y))
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

3. **Tokenizer.** `x_token_read` iterates the registered type list. Each type provides an `analyse` method that inspects the buffer to determine if the upcoming bytes match that type, and a `delimit` method that determines token boundaries. The tokenizer dispatches to the first type whose analyse method matches.

4. **S-expression reader.** `x_sexp_read` delegates to `x_token_read`. Pair/list syntax is handled by `x_sexp_pair_read` and `x_sexp_list_read`, which recursively call the token reader for sub-expressions. The reader produces a tree of atoms and pairs.

5. **Evaluator.** `x_eval` takes a wrapped expression, checks the expression's type for an `eval` dispatch method, and calls it. Symbols resolve through environment lookup. Lists dispatch through the callable in head position. Self-evaluating types (integers, strings) return themselves.

6. **Writer.** `x_sexp_write` dispatches on type: intrinsic atoms and pairs have hardcoded writers; all other types dispatch through `x_type_field_write`. Output goes to the base's stdout file descriptor.

The REPL loop in `x_cli.c` runs these stages in sequence: prompt, read, eval, print, repeat until EOF.

### Personality System

Language semantics are library files that alias x-lang primitives to match another language's naming conventions. The interpreter core has no knowledge of Scheme or Kernel.

**Scheme personality** (`lib/scm.x`): aliases `fn` to `lambda`, `do` to `begin`, `pair` to `cons`, `first`/`rest` to `car`/`cdr`, `lit` to `quote`, `match` to `cond`, etc. Adds `#t`/`#f` boolean constants. Implements `define` as a wrapper around `def` that supports both variable and function shorthand forms.

**Kernel personality** (`lib/krn.x`): aliases `op` to `$vau` (the fundamental Kernel abstraction). Implements `$define!` as an operative. Derives applicatives from operatives via `wrap`. In Kernel, operatives are first-class and applicatives are the derived form -- the inverse of Scheme's model.

Both personalities are loaded by concatenation before the program source:

```sh
cat lib/x.x lib/scm.x - | ./x
```

The `-` connects stdin for interactive use after library loading. Without any personality file, the bare interpreter exposes only x-lang primitives.

### No File I/O

The interpreter has no open, close, read-file, or write-file primitives. Its only I/O is reading bytes from stdin and writing bytes to stdout/stderr via POSIX `read`/`write` syscalls on the file descriptors stored in the base object. All code loading happens externally through the shell. This keeps the interpreter minimal and confines filesystem interaction to the host environment.
