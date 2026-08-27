# x-lang Type System

*x-lang: computational expressions over a minimal, type-agnostic engine.*

> **Scope.** The contract pattern, the dispatch model and runtime type
> creation are the language's. The concrete C throughout — the datum union,
> `struct x_type_t`, the `x_type_field_*` and `x_eval_field_*` accessors, the
> base tree's layout — is
> [x-engine-c](https://github.com/jonruttan/x-engine-c)'s, under the
> `x_`-prefix and snake-case affix conventions the [Glossary](glossary.md)
> names as C's. The nouns are shared across engines and settled there, with
> the contract's files as the authority; the authoritative base layout is
> `tools/contract/base-layout.x`.
>
> x-engine-c is the reference implementation and the closest thing to correct,
> but reference is not canonical — conformance is the language's definition of
> correct, and it judges every engine including that one. See
> [The Engine Contract](engine-contract.md).

### The Contract Pattern

Both types and the base object use the same structural mechanism: nested linked lists with a fixed prefix (the **contract**) and an extensible tail. The system reads the prefix it understands; the owner of the structure knows the full layout.

This pattern appears at two levels:

- **Type definitions** — 13-field contract defining how a type behaves
- **The base object** — nested tuples defining interpreter state

Both are extensible by appending pairs beyond the fixed prefix.

---

### Objects

Every runtime value is an object. Objects are union-based data cells with a metadata prefix:

```
[ type-pointer | flags | gc-link? ]   ← metadata (2-3 units)
[ datum-0 | datum-1 | ... ]           ← data (variable length)
```

Each datum is a union:

```c
union x_datum_union {
    x_obj_t *p;         /* pointer to object  */
    x_prim_fn fn;       /* C function pointer  */
    x_int_t i;          /* integer             */
    x_char_t c;         /* character           */
    x_char_t *s;        /* string              */
    void *v;            /* generic pointer     */
};
```

**Atoms** have 1 data unit. **Pairs** have 2 (first, rest). Objects are allocated on the heap and linked through GC chains for collection.

#### Object Flags

```
X_OBJ_FLAG_NONE    0x00   no flags
X_OBJ_FLAG_1       0x01   app-defined (WRAP on procedures, SHADOW on env pairs)
X_OBJ_FLAG_2       0x02   app-defined (COV)
X_OBJ_FLAG_3       0x04   app-defined
X_OBJ_FLAG_4       0x08   app-defined
X_OBJ_FLAG_PRIM    0x10   simple-type code: C primitive     ┐ advisory tag for
X_OBJ_FLAG_FN      0x11   simple-type code: function        │ C consumers --
X_OBJ_FLAG_INT     0x12   simple-type code: integer         │ NOT the type
X_OBJ_FLAG_CHAR    0x13   simple-type code: character       │ slot; the core
X_OBJ_FLAG_STR     0x14   simple-type code: string          │ dispatches on
X_OBJ_FLAG_PTR     0x15   simple-type code: generic pointer ┘ the type pointer
X_OBJ_FLAG_OWN     0x20   object owns its (string) storage (freed with it)
X_OBJ_FLAG_RO      0x40   read-only (advisory)
X_OBJ_FLAG_META    0x80   extended metadata units prepended
X_OBJ_FLAG_SHARED  0x100  permanently retained across GC
X_OBJ_FLAG_MARK    0x200  the GC mark bit
```

Flags `0x01`–`0x08` are app-defined attribute bits; the `WRAP` alias (`0x01`) distinguishes applicative procedures from bare closures. The authoritative bit table is `engine/tools/contract/obj-layout.x`, pinned by `make check-obj-layout`.

---

### The Type Contract

A type definition is a `struct x_type_t` with 19 fields:

```c
struct x_type_t {
    x_obj_t *p_name;       /* type name atom                */
    x_obj_t *p_data;       /* type-specific data            */
    x_obj_t *p_mark;       /* GC mark hook (C fn only)      */
    x_obj_t *p_make;       /* constructor                   */
    x_obj_t *p_free;       /* destructor (C fn only)        */
    x_obj_t *p_clone;      /* copy constructor              */
    x_obj_t *p_units;      /* traced slot count (int; -1 =  */
    x_obj_t *p_length;     /*   dynamic) / element count    */
    x_obj_t *p_call;       /* invocation handler            */
    x_obj_t *p_eval;       /* evaluation handler            */
    x_obj_t *p_from;       /* inbound conversion alist      */
    x_obj_t *p_to;         /* outbound conversion alist     */
    x_obj_t *p_analyse;    /* parser/tokenizer handler      */
    x_obj_t *p_delimit;    /* delimiter detection handler   */
    x_obj_t *p_read;       /* reader handler                */
    x_obj_t *p_write;      /* output/serialization handler  */
    x_obj_t *p_display;    /* human-readable output handler */
    x_obj_t *p_iter;       /* iterator builder              */
    x_obj_t *p_ops;        /* operator handler alist        */
};
```

At runtime, this struct is stored as nested pairs (every leaf a
`(current . saved)` stack, which is what the `type-push-*` registry
operations manipulate without C):

```x
(
  name                                   ; field 0
  data                                   ; field 1
  (mark make free clone units length)    ; field 2 — heap group
  (call eval)                            ; field 3 — proc group
  (from to)                              ; field 4 — cvt group
  (analyse delimit read write display)   ; field 5 — io group
  (iter)                                 ; field 6 — iter group
  (ops)                                  ; field 7 — ops group
)
```

The `ops` alist — `((op-sym . handler) ...)` — is the door the seven C
operators (`+ - * / % = <`) dispatch through; the from-conversion alist
doubles as the arbitration relation when both operands carry handlers (see
"One model, four doors" in [Object System](object-system.md)).

Nil fields indicate the type does not implement that method. The dispatch system checks for nil before invoking.

#### Field Groups

**Identity**: `name`, `data`

- `name` — An atom identifying the type (e.g., `"INTEGER"`, `"SYMBOL"`, `"VECTOR"`)
- `data` — Type-specific storage. The type system does not interpret this field. Types use it for metadata, cached state, or extended method tables.

**Heap**: `make`, `free`, `clone`, `units`, `length`

- `make` — Allocates a new instance from raw data
- `free` — Releases instance resources
- `clone` — Duplicates an instance
- `units` — Returns the number of data units in an instance
- `length` — Returns the logical element count (list length, string length, etc.)

**Proc**: `call`, `eval`

- `call` — Invoked when an instance is used as a procedure. Receives the instance and arguments.
- `eval` — Invoked when an instance appears as an expression to evaluate. Symbols use this for environment lookup. Lists use this for function application.

**Cvt**: `from`, `to`

- `from` — Inbound conversion alist. Maps source type handles to converter functions (other→self).
- `to` — Outbound conversion alist. Maps target type handles to converter functions (self→other).

**IO**: `analyse`, `delimit`, `write`

- `analyse` — Parser handler. Determines if input tokens match this type and constructs instances from source text.
- `delimit` — Detects type-specific delimiters in the input stream.
- `write` — Outputs the external representation of an instance.

#### Field Accessor Macros

```c
x_type_field_name(X)       x_type_field_data(X)

x_type_field_heap(X)       /* the heap tuple itself */
x_type_field_make(X)       x_type_field_free(X)
x_type_field_clone(X)      x_type_field_units(X)
x_type_field_length(X)

x_type_field_proc(X)       /* the proc tuple itself */
x_type_field_call(X)       x_type_field_eval(X)

x_type_field_cvt(X)        /* the cvt tuple itself */
x_type_field_from(X)       x_type_field_to(X)

x_type_field_io(X)         /* the io tuple itself */
x_type_field_analyse(X)    x_type_field_delimit(X)
x_type_field_write(X)
```

#### Extensibility

The type definition is a linked list. Appending pairs beyond field 4 extends the type without breaking the contract. The dispatch system traverses only the fixed prefix. Type-specific code can navigate deeper into the structure to access extended fields.

The `data` field serves a similar purpose at the instance level — types can store arbitrary state there.

---

### Dispatch

The evaluator, call mechanism, writer, and length calculator all follow the same pattern:

1. Get the object's type pointer
2. Look up the relevant method slot (e.g., `x_type_field_call`)
3. If non-nil, invoke it with the object and arguments
4. If nil, return a default (self-evaluation, nil, etc.)

**Evaluation dispatch** — When an expression is evaluated:

- Symbols: `eval` method looks up the symbol in the environment alist
- Lists: `eval` method evaluates the first element (the operator), then dispatches to the operator's `call` method with the remaining elements as arguments
- Everything else: self-evaluates (no `eval` method)

**Call dispatch** — When an object is invoked as a procedure:

- Primitives: `call` invokes the C function pointer directly
- Procedures: `call` binds parameters to evaluated arguments in a new environment, then evaluates the body
- Operatives: `call` binds parameters to unevaluated arguments plus the caller's environment
- Lists: `call` implements indexing — `(lst 0)` returns the first element, `(lst 1 3)` returns a slice
- Strings: `call` implements character access and substring extraction
- Custom types: `call` invokes whatever closure was provided to `make-type`

**Write dispatch** — When a value is output:

- Each type's `write` method produces its external representation
- Primitives/procedures: `#<fn>`
- Lists: `(a b c)` or `(a . b)` for improper lists
- Strings: `"quoted"`
- Integers: bare digits
- Custom types: whatever the `write` handler produces

---

### Built-in Types

| Type | name | make | free | clone | units | length | call | eval | from | to | analyse | delimit | write |
|------|------|------|------|-------|-------|--------|------|------|------|-----|---------|---------|-------|
| ATOM | yes | yes | | | | | | | | | | | |
| PAIR | yes | yes | | | | yes | | | | | | | yes |
| LIST | yes | yes | | | | yes | yes | yes | | | yes | yes | yes |
| INTEGER | yes | yes | | | | | | | | | yes | | yes |
| SYMBOL | yes | yes | | | | | | yes | | | yes | | yes |
| STRING | yes | yes | | | | yes | yes | | | | yes | | yes |
| CHAR | yes | | | | | | | | | | | | |
| PRIMITIVE | yes | yes | | | | | yes | | | | | | yes |
| PROCEDURE | yes | yes | | | | | yes | | | | | | yes |
| OPERATIVE | yes | yes | | | | | yes | | | | | | yes |
| BUFFER | yes | | | | | | | | | | | | |
| ITERATOR | yes | | | | yes | | | | | | | | |
| POINTER | yes | | | | | | | | | | | | |
| WHITESPACE | yes | | | | | | | | | | yes | yes | |
| COMMENT | yes | | | | | | | | | | yes | | |
| VECTOR | yes | | | | yes | | yes | | yes | yes | | | yes |

---

### Runtime Type Creation

#### `make-type`

```x
(Type make name handlers) → type-handle
```

Creates a new type at runtime. `name` is a string. `handlers` is an association list mapping method names to closures:

```x
(Type make "VECTOR"
  (list
    (pair 'call (fn (_ self . args) ...))
    (pair 'write (fn (_ self) ...))))
```

Handler closures follow the universal self-passing convention: the closure
itself arrives as argument 0 (the `_` slot), then the instance, then any
call arguments.

Supported handler keys: `call`, `eval`, `write`, `display`, `length`,
`analyse`, `delimit`, `read`, `from`, `to`, `units`, `free`, `mark`, `iter`,
`ops`. The `iter` handler is `(fn (_ obj) -> iterator)`; it makes `(iter obj)`
build an iterator over the type's values (see the Iterators section of the
standard library). `units` is an **int**, not a function — the count of traced
instance slots, with `-1` the dynamic sentinel (slot 0 holds the payload
count). Caution: `mark`, `free`, and `length` are invoked as raw C function
pointers — installing an x-lang closure in them crashes; use `units` for GC
traversal instead.

Returns a type handle (the name atom) used to create instances and check types.

#### `make-instance`

```x
(Type make-instance type-handle data) → instance
```

Creates an instance of a runtime-defined type. The instance stores `data` and dispatches through the type's registered handlers.

#### `type?`

```x
(Type ? obj type-handle) → #t or ()
```

Tests whether `obj` is an instance of the type identified by `type-handle`.

#### `type-name`

```x
(Type name obj) → string
```

Returns the type name of any object as a string. Non-navigable type tags —
the base sentinel that marks child execution contexts, and bare handle
atoms — answer their own bytes rather than a struct walk, mirroring the C
branches (their fields must not be navigated).

#### Type reflection: `Type wrap`

```x
(Type wrap t) → instance
```

Clothes a type handle (from `Type of`) or the type itself (from
`Type by-atom`) as an interactive Type instance: `(t name)`,
`(t cell 'type-write-stack)`, `(t fields)`, and the wiring verbs
`push-write` / `push-display` / `push-call` / `push-op` as instance
methods. The `handle` member holds the name atom, `raw` the struct the
`Type` statics consume.

`cell` and `fields` walk the layout contract (`engine/tools/contract/base-paths.x`)
— the same rows the C accessor macros flatten — so every struct field is
addressable by its contract name: handler stacks, the conversion catalog
cells, the generic-operator alist. A name whose row is not type-rooted is
refused: a base-rooted path stepped from a type would address
arbitrary spine words. The worked path through this surface is
[Sandboxing and type reflection, step by step](sandboxing-tutorial.md);
the executable reference is [spec.md](spec.md) §11.

#### Example: Vectors

```x
(def %vector (Type make "VECTOR"
  (list
    (pair 'call (fn (_ self . args)
      ((first self) (first args))))
    (pair 'write (fn (_ self)
      (display "#(")
      ((fn (go lst sep)
         (if (not (null? lst))
           (do (if sep (display " "))
               (write (first lst))
               (go (rest lst) #t))))
       (first self) ())
      (display ")"))))))

(def vector (fn args (Type make-instance %vector (rest args))))
(def vector? (fn (_ x) (Type ? x %vector)))
(def vector-ref (fn (_ v i) (v i)))
```

The `call` handler enables `(v 0)` indexing. The `write` handler produces `#(1 2 3)` output. The type integrates into the evaluator and printer without any C code changes.

#### Example: Object System

The standard library's object system (`lib/x/type/class.x`) is the richest use of `make-type`. It defines two callable types — `%object` (instances) and `%class` (classes) — each with an **operative** `call` handler, so `(obj name args...)` reaches the handler with the receiver as `self` and `name` *unevaluated* (a literal selector, no quote needed). The handler looks `name` up as a method (walking the parent chain for inheritance); finding none, it falls back to a member get/set.

```x
(def-class Point ()
  x y
  (method sum (self) (+ (self x) (self y))))

(p sum)              ; dispatches through the %object call handler (no quote)
```

A class is itself a callable `%class` object — `(Class static-method …)` dispatches its statics — wrapping a descriptor alist; each instance carries its class plus a mutable member box, and external code reaches either only through dispatch. Because it all rides on the type system's existing `call` hook, the whole class system — single inheritance, `super`, static methods and class-wide members, encapsulation — needs no C code. See the [Object System](object-system.md) guide for the full API.

#### Performance: compiling analysers

A custom type's `analyse` handler is the tokenizer's hot path — it is invoked for **every token of every source file** parsed while the type is registered, to decide whether the token belongs to this type. An interpreted `(fn …)` closure there costs a full `x_eval` per call, so registering several interpreted analysers makes *all* subsequent parsing dramatically slower (measured at **up to ~20× on symbol-heavy input** with the numeric tower's analysers left interpreted).

The fix is to **JIT-compile the analyser to native code** with `compile`, then install the compiled version. An analyser has the shape `(fn (_ buffer score chr) → next-state-fn | ())`: given the current byte `chr`, it returns a state function to continue scanning, or `()` to decline. `compile` takes the analyser as a quoted `(fn …)` AST plus an **fvar table** binding any free variables the body references (the state functions it transitions to). Pure expressions use the JIT assembler; expressions with fvars use the C-compiler-with-cache path.

```x
; Fetch the wiring helpers from the catalog (registered by sys/type.x)
(def %type-by-atom      (prim-ref 'type 'by-atom))
(def %type-push-analyse (prim-ref 'type 'push-analyse))

; Compile + install the int-capped analyser (digits, with +/- sign)
(set! %compile-fvars
  (list (pair '%int-capped-sign   %int-capped-sign)
        (pair '%int-capped-digits %int-capped-digits)))
(%type-push-analyse (%type-by-atom (Type of 0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %int-capped-sign ())   ; sign
        (if (< chr 58) %int-capped-digits ()))))              ; digit
    %compile-fvars))
(set! %compile-fvars ())
```

Two install idioms:

- **`(%type-push-analyse type compiled)`** — prepend a compiled analyser onto a type's analyse stack (used for each numeric type right after its module loads). Load-time wiring fetches the helper from the catalog as above; interactive reflection can use the class instead: `(Type push-analyse …)`.
- **`(%set-first! slot compiled)`** on a cell of `(%type-analyse-cell …)` — replace an existing interpreted handler in place (used to swap the symbol type's compiled `lit`/`quasi`/`unquote` analysers in for the interpreted ones from `lit-reader.x`).

Do the compilation **incrementally, right after each type's module loads**, so subsequent source files are parsed through the already-compiled (fast) analysers rather than interpreted ones.

Worked examples live in the tower-loading libraries: the xenon/radon bodies (`lib/x/boot/{xenon,radon}.x`, interactive dialects) and `lib/x-base.x` (non-interactive) all compile the quote-family and numeric-tower analysers this way. See [Dialects](dialects.md) for the dialect-level view.

> **Note:** `compile`'s fvar path shells out to the host C compiler and caches the resulting shared object by expression hash, so the *first* load against a cold cache pays the `cc` cost; later loads reuse the cached `.so`.

---

### The Base Object

The base object uses the same nested-list contract pattern as types. It holds the complete state of an interpreter instance.

**`p_base` is not nil.** Nil is `NULL`: `()` parses to `NULL` and `x_obj_isnil` checks `p_obj == NULL`. The base object is the execution context only. (An earlier design used the base as the nil value; that is long gone.)

#### Structure

The base is a deep pair tree, `(hot . cold)`: the hot half holds the
environment and control state, the cold half the I/O and metadata. In
x-engine-c the cold half is its embeddable expression core's skeleton and the
hot half is filled by its eval layer; that split is the engine's own. The
authoritative layout —
including which leaves are field cells `(current . saved)` versus direct
values — is `tools/contract/base-layout.x` (regenerate with `make gen-layout`);
`make check-base-paths` pins it.

```
base
  first: env + ctrl              (core leaves nil; eval layer fills)
    env    env-alist, env-local-boundary, env-global-tree, shadow-list
    ctrl   save-stack, error-handler, tco-expr, tco-env
  rest:  io + meta               (expression-core skeleton)
    io     type-alist, line, true, false  (+ file handles)
    meta   profile counters, eval-list, token-cache,
           mark-hooks, free-hooks, mark-roots, sigint
```

#### Field Accessor Macros

```c
x_eval_field_type_alist(X)     /* type registry               */
x_base_field_filein(X)         /* stdin file descriptor       */
x_base_field_fileout(X)        /* stdout file descriptor      */
x_base_field_fileerr(X)        /* stderr file descriptor      */
x_eval_field_env_alist(X)      /* environment bindings        */
x_eval_field_eval_list(X)      /* expression list             */
x_base_field_buffer(X)         /* input buffer                */
x_eval_field_token_cache(X)    /* token cache                 */
x_eval_field_error_handler(X)  /* error handler (setjmp)      */
x_eval_field_tco_expr(X)       /* TCO expression register     */
x_eval_field_tco_env(X)        /* TCO environment register    */
```

(In x-engine-c the skeleton's accessors are `x_base_field_*`; the eval layer's are `x_eval_field_*` in `engine/include/x-eval-layout.h`.)

#### Properties

**Independence** — Each base is a self-contained interpreter. It has its own type registry, its own variable bindings, its own I/O streams. Creating a new base with `(Base make)` produces an independent interpreter, wrapped as a Base instance: the raw C base object rides the instance's `raw` member, every `Base` static accepts either form, and the instance answers `eval`/`bind`/`make-type` directly.

**Swappable** — A base can be replaced during execution. Swapping the base swaps the entire language — bindings, types, and state — in one operation.

**Extensibility** — The same contract mechanism applies. Additional pairs can be appended beyond the fixed prefix to carry custom state. The system reads only the fields it knows about through the accessor macros.

#### Error Handling

The error handler is a C `setjmp`/`longjmp` chain stored in the base:

```c
typedef struct x_error_handler {
    jmp_buf jmp;
    x_obj_t *p_error;
    x_char_t *error_msg;
    x_obj_t *p_saved_env;
    struct x_error_handler *prev;
} x_error_handler_t;
```

`guard` installs a handler. `error` signals through it. Handlers chain — each `guard` links to the previous handler, restored on exit.

#### Operations

```x
(Base make)                    → new independent base, as a Base instance
(Base make-tok)                → minimal tokenizer base (no types, no prims)
(Base eval base expr)          → evaluate expr in base's environment
(Base bind base name value)    → bind name to value in base's environment
(Base make-type base name h)   → register a custom type on base
(Base wrap r) / (Base raw-of v) → clothe a raw base / unwrap either form
(Base base? v)                 → #t for Base instances only
```

The instance is the interactive surface — `(b eval expr)`, `(b bind n v)`,
`(b make-type name h)` — and reflection rides the layout contract:
`(b cell 'field-name)` walks `engine/tools/contract/base-paths.x`'s base-rooted
row for the name to the addressed cell, `(Base fields)` lists the rows,
and a non-base-rooted name is refused. The worked path is
[Sandboxing and type reflection, step by step](sandboxing-tutorial.md);
the executable reference is [spec.md](spec.md) §12.
