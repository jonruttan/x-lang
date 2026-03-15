# Computational Expressions in C

## Type System

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
X_OBJ_FLAG_NONE  0x00   no flags
X_OBJ_FLAG_1     0x01   (used as WRAP for procedures)
X_OBJ_FLAG_2     0x02   available
X_OBJ_FLAG_3     0x04   available
X_OBJ_FLAG_4     0x08   available
X_OBJ_FLAG_PRIM  0x10   C primitive function
X_OBJ_FLAG_FN    0x11   user-defined function
X_OBJ_FLAG_INT   0x12   integer
X_OBJ_FLAG_CHAR  0x13   character
X_OBJ_FLAG_STR   0x14   string
X_OBJ_FLAG_PTR   0x15   generic pointer
X_OBJ_FLAG_OWN   0x20   object owns its data (freed on collection)
X_OBJ_FLAG_RO    0x40   read-only
X_OBJ_FLAG_GC    0x80   GC mark bit
```

Flags `0x01`-`0x08` are available for type-specific use. The `WRAP` flag (`0x01`) distinguishes applicative procedures from bare closures.

---

### The Type Contract

A type definition is a `struct x_type_t` with 14 fields:

```c
struct x_type_t {
    x_obj_t *p_name;       /* type name atom                */
    x_obj_t *p_data;       /* type-specific data            */
    x_obj_t *p_make;       /* constructor                   */
    x_obj_t *p_free;       /* destructor                    */
    x_obj_t *p_clone;      /* copy constructor              */
    x_obj_t *p_units;      /* memory unit count             */
    x_obj_t *p_length;     /* element count                 */
    x_obj_t *p_call;       /* invocation handler            */
    x_obj_t *p_eval;       /* evaluation handler            */
    x_obj_t *p_from;       /* inbound conversion alist      */
    x_obj_t *p_to;         /* outbound conversion alist     */
    x_obj_t *p_analyse;    /* parser/tokenizer handler      */
    x_obj_t *p_delimit;    /* delimiter detection handler   */
    x_obj_t *p_write;      /* output/serialization handler  */
};
```

At runtime, this struct is stored as nested pairs:

```
(
  name                              ; field 0
  data                              ; field 1
  (make free clone units length)    ; field 2 — heap tuple
  (call eval)                       ; field 3 — proc tuple
  (from to)                         ; field 4 — cvt tuple
  (analyse delimit write)           ; field 5 — io tuple
)
```

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

```
(make-type name handlers) → type-handle
```

Creates a new type at runtime. `name` is a string. `handlers` is an association list mapping method names to closures:

```
(make-type "VECTOR"
  (list
    (pair (lit call) (fn (self . args) ...))
    (pair (lit write) (fn (self) ...))))
```

Supported handler keys: `call`, `eval`, `from`, `to`, `analyse`, `delimit`, `write`, `length`.

Returns a type handle (the name atom) used to create instances and check types.

#### `make-instance`

```
(make-instance type-handle data) → instance
```

Creates an instance of a runtime-defined type. The instance stores `data` and dispatches through the type's registered handlers.

#### `type?`

```
(type? obj type-handle) → #t or ()
```

Tests whether `obj` is an instance of the type identified by `type-handle`.

#### `type-name`

```
(type-name obj) → string
```

Returns the type name of any object as a string.

#### Example: Vectors

```
(def %vector (make-type "VECTOR"
  (list
    (pair (lit call) (fn (self . args)
      ((first self) (first args))))
    (pair (lit write) (fn (self)
      (display "#(")
      (def write-vec (fn (lst sep)
        (if (not (null? lst))
          (do (if sep (display " "))
              (write (first lst))
              (write-vec (rest lst) #t)))))
      (write-vec (first self) ())
      (display ")"))))))

(def vector (fn args (make-instance %vector args)))
(def vector? (fn (x) (type? x %vector)))
(def vector-ref (fn (v i) (v i)))
```

The `call` handler enables `(v 0)` indexing. The `write` handler produces `#(1 2 3)` output. The type integrates into the evaluator and printer without any C code changes.

---

### The Base Object

The base object uses the same nested-list contract pattern as types. It holds the complete state of an interpreter instance.

**`p_base` IS nil.** The base context object is the nil value for its interpreter. `()` evaluates to `p_base`.

#### Structure

```
(
  (type-alist)                              ; type registry
  (file:in file:out file:err)               ; I/O file descriptors
  (env-alist                                ; variable bindings
   eval-list                                ; expression list
   buffer                                   ; input buffer
   token-cache                              ; cached tokens
   error-handler                            ; error handler chain
   tco-expr                                 ; tail call expression
   tco-env)                                 ; tail call environment
)
```

#### Field Accessor Macros

```c
x_base_field_type_alist(X)     /* type registry              */
x_base_field_filein(X)         /* stdin file descriptor       */
x_base_field_fileout(X)        /* stdout file descriptor      */
x_base_field_fileerr(X)        /* stderr file descriptor      */
x_base_field_env_alist(X)      /* environment bindings        */
x_base_field_eval_list(X)      /* expression list             */
x_base_field_buffer(X)         /* input buffer                */
x_base_field_token_cache(X)    /* token cache                 */
x_base_field_error_handler(X)  /* error handler (setjmp)      */
x_base_field_tco_expr(X)       /* TCO expression register     */
x_base_field_tco_env(X)        /* TCO environment register    */
```

#### Properties

**Independence** — Each base is a self-contained interpreter. It has its own type registry, its own variable bindings, its own I/O streams. Creating a new base with `make-base` produces an independent interpreter.

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

```
(make-base)                    → new independent base
(base-eval base expr)          → evaluate expr in base's environment
(base-bind base name value)    → bind name to value in base's environment
```
