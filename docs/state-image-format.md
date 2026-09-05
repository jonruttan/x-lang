# State image format

The contract between the writer (`tools/dev/image-write.x`), the loader
(`tools/dev/image-read.x`), and `(image rebuild!)` in the engine.
[state-images.md](state-images.md) argues *why*; this says *what*. When code
and this document disagree, this document is what gets fixed first, and
nothing enters the format that is not written here.

This is version 1 of the format — the first one. The tools in
`tools/dev/` at the time of writing implement an earlier draft that never
loaded a working image; §9 says what it got wrong and what carries over.
Every claim below about the engine was read from `ext/x-expr` and
`x-engine-c` source, and names the file it came from.

## 1. What the engine holds, and where

**All state is on the base.** A base is one atom (`x_base_make`, `x-base.c`)
whose data word points at a tree of pairs and atoms. Every leaf is a *field
cell*, `(value . saved-values)`, and everything the evaluator, the type
system, the reader, the printer, the collector and the allocator know is a
node of that tree. There is no table anywhere that is not reachable from the
base object.

The tree's shape is the contract `engine/tools/contract/base-layout.x`, and
its tags already say which parts belong to whom:

| tag | who builds it | what it holds |
|---|---|---|
| `(build …)` subtrees | `x_eval_make` (`x-eval.c`) from the descriptor | **language state**: env, ctrl, type-alist, io-state, profile counters, the state group |
| `(todo …)` subtrees | `x_base_make` (`x-base.c`) | **process state**: file descriptors, the read buffer, the hooks, the heap group, the allocation group |

That split is the whole design. An image is a base's **language state** and
every object reachable from it. A loader has a base of its own with its own
**process state**, and the image never touches that.

Language state, cell by cell (the `x_eval_field_*` accessors of the
generated `x-eval-layout.h`):

| group | cells | notes |
|---|---|---|
| env | `env-alist` (cell), `env-local-boundary`, `env-global-tree`, `shadow-list` (slots) | the chain, where locals end, the BST over globals, the shadow list |
| ctrl | `save-stack`, `error-handler`, `tco-expr`, `tco-env` | evaluator transients; **nil at image time and at install** (§6) |
| io-group | `type-alist` (cell) | the type registry: `((name-stack . struct) …)`, keyed by the name-stack node (`x_alist_assoc` compares `first(key)`, `x-alist.c`) |
| io-state | `line`, `true`, `false` | `true`/`false` hold the engine statics `x_true_obj`/`x_false_obj` |
| profile | nine counters | plain integers; the loader may keep its own |
| state | `eval-list`, `token-cache`, `sigint`, `err`, `prims`, `file`, `err-line`, `err-file`, `file-registry` | `err` is the one base-resident ERR instance every raise fills (`x_type_err_register`); `prims` is the catalog, a list of `(ns (method . PRIMITIVE) …)` (`x_prim_register`); `sigint` is a shared atom |

Process state, which the loader keeps: `files` (descriptors, write-buf, and
the read buffer — a BUFFER over a C array on `main`'s stack, `x-cli.c`),
the four `hooks` and the heap group's mark/free hooks (static atoms holding
C function pointers), `mark-hooks`, `free-hooks`, `mark-roots`, the
`root-chain` (off-chain stack objects pushed by frames, marked never swept,
`x-base.h`), `obj-meta-extra`, and the `alloc` group.

Two more facts about where things live:

- **Type structs are in the tree.** `x_type_struct_make` (`x-type.c`) builds a
  pair tree per type; the registry cell lists them. A type struct's cells
  hold handler *lists*; the built-in types' handlers, name atoms, and the
  default units/length values are **static objects in the engine binary**
  (`x_type_int_name`, `x_type_int_make_prim`, `x_type_units_pair_obj`, …).
  The library's pushed handlers are heap closures. The SYMBOL type's `data`
  slot holds the intern list and BST (`symbol.c`), so symbol identity is
  part of the tree too.
- **Every base has its own allocation chain**, and the base object is its
  head (`x_obj_alloc`: `x_obj_heap(obj) = x_obj_heap(base); x_obj_heap(base)
  = obj`). Walking from the base object's heap link enumerates everything the
  base ever allocated and not yet freed. A child base (`base make`) has a
  separate chain.

## 2. What an image is

An image is: the values of the language-state cells of one base, and the
transitive closure of objects they reach, written so a different process
running the same engine release can rebuild them as objects of *its* base
and set *its* language-state cells to them.

Consequences, each of which removes something the draft needed:

1. The type registry comes with the image. Types are objects; a type word is
   a reference to an imaged struct. There is no type table, no matching by
   name, no registering of missing types, no handle identity rule, and no
   relocation of cached type words — an INTEGER holding a type word holds an
   address that is now an object reference like any other (§4.3).
2. Handler stacks, the resident ERR, the catalog, the symbol table, the
   file registry all come with the image because they are reachable. No
   type-cell table.
3. The only things not in the image are the two kinds of thing the loader
   already owns: **C functions** and the **engine's static objects**. One
   table names them (§3.3). No statics-by-path table.
4. The roots are the language-state cells, named by the contract (§3.4).

## 3. File layout

Words are `%word-size` bytes, little-endian. Sections are contiguous:

| # | section | length |
|---|---|---|
| 0 | header | fixed |
| 1 | shape table | `SHWORDS` |
| 2 | externals table | `XWORDS` |
| 3 | roots table | `RTWORDS` |
| 4 | object table | `OBJW` |
| 5 | byte blob | `BLOBN` bytes |

### 3.1 Header

| word | name | meaning |
|---|---|---|
| 0 | magic | `"XIMG"` little-endian |
| 1 | version | `1` |
| 2 | word size | refused on mismatch |
| 3 | byte order probe | `1`; refused if not |
| 4 | `N` | object count |
| 5 | `OBJW` | object table words |
| 6 | `BLOBN` | blob bytes |
| 7 | `SHCOUNT` | shape rows |
| 8 | `SHWORDS` | |
| 9 | `XCOUNT` | external entries |
| 10 | `XWORDS` | |
| 11 | `RTCOUNT` | root entries |
| 12 | `RTWORDS` | |
| 13 | `META` | extra metadata words per object the writer's base used (`obj-meta-extra`; 2 in a CLI base) |
| 14 | `RELEASE` | blob offset of the engine release string (`x-release`) |

The loader refuses a `RELEASE` that is not its own: an image is a heap laid
out by one build of the engine, and its externals are named against that
build's catalog and statics.

### 3.2 Names and steps

A name is `[len][bytes…]` in `words-for(len) = 1 + ((len + 1) >> 3)` words —
room for a NUL, which a zeroed buffer supplies. Steps, where used, are
`[n][s…]` with `0` = first, `1` = rest.

### 3.3 Shape table — how many units, of what kind

    [struct index][count][mask]

One row per type struct that has instances in the image, keyed by the
struct's own object index. `count`/`mask` are what the writer read from the
struct's `type-units` cell through the one reader both sides share
(`image-walk.x`'s `%sh-count`): an INT is the count with every unit a
reference; a `(count . mask)` pair is explicit; the static
`x_type_units_pair_obj` means *two reference units* — what `make-instance`
allocates (`X_OBJ_LENGTH_PAIR`, data in slot 0) for every type the library
registers. Kinds are `ref` 0, `word` 1, `bytes` 2, `foreign` 3, two bits per
unit, the last repeating.

Three rows are keyed by **role**, not by struct index, because their type is
a static tag with no struct:

| role | tag | units |
|---|---|---|
| `spair` | `x_type_pair_obj` — a type-struct node | 2 ref |
| `satom` | `x_type_atom_obj` — a static atom | 1 word |
| `nil-typed` | `NULL` type — `#t`, `#f`, the base's own atom | 1 word |

An ordinary pair is **not** a role: its type is the base's PAIR struct, in
the registry like any other, and it has a shape row like any other.

### 3.4 Externals table — what the loader already owns

    [kind][name]

A unit that refers to something outside the image stores an external
index (negative in a `ref` unit, plain in a `foreign` unit). Kinds:

| kind | names | loader resolves to |
|---|---|---|
| 1 `catalog` | `ns/method` | the C function pointer behind its own `(prim-ref ns method)` |
| 2 `bare` | a global's name | the function pointer of the callable bound to that name in a fresh base |
| 3 `dlsym` | a C symbol | `dlsym` |
| 4 `typecall` | `PROCEDURE` or `OPERATIVE` | the call pointer a fresh closure of that kind carries |
| 5 `dlopen` | — | the process handle |
| 6 `static` | a role name | one of the engine's static objects, by role — see below |
| 7 `type-static` | a type name and a row of `base-paths.x` | the static object a **freshly registered** type of that name holds at that row |

Kinds 1–5 are the draft's foreign kinds, unchanged. Kind 6 names the
statics that are not inside any type struct: `true`, `false` (`x_true_obj`,
`x_false_obj`), `tag-atom`, `tag-pair` (the two tags, when they appear as
type words), `units-atom`, `units-pair`, `length-atom`, `length-pair`,
`token-eof` (`x_token_eof_prim`). Kind 7 names the statics that are: a
built-in type's name atom, its C handler atoms, its default units value.
`x_type_int_register` builds INTEGER's struct from the same static
descriptors in every base, so `(type-make INTEGER)` is the same object in
the writer's process and the loader's.

The writer discovers kind-7 names by walking a pristine `(base make)` and
recording every **off-chain** node (heap link 0) under the row that reaches
it. That is why a C reader buried under four library pushes in STRING's read
stack still has a name: it is what a fresh STRING holds at `type-read`.
Kind 6 comes from a fixed list; kind 7 is derived; nothing else is static.

An external the writer cannot name is stored as `XCOUNT + 1`; the loader
resolves it to nil, **counts it, and reports the count**. A nonzero count
is a broken image (§6.9).

### 3.5 Roots table — which cell gets which object

    [cell name][object index]

One entry per language-state cell of `base-layout.x` (§1). The name is the
contract's, so the loader finds the cell by the same path the C accessors
use. `cell` rows get the object in their first slot; `slot` rows get it in
the half of the parent the last step names — the distinction is the
contract's, not the loader's.

### 3.6 Object table

`N` records, no length word:

    [type][flags][unit…]

`type` is the object index of its type struct, or `-1 spair`, `-2 satom`,
`-3 nil-typed`. The unit count and kinds come from the shape row for that
type. `flags` are the writer's flags masked to `WRAP 0x01`, `COV 0x02`,
`FRAME 0x04`, `FNFRAME 0x08`, `RO 0x40`; `SHARED` is set on every rebuilt
object regardless (the image lives as long as the process); `OWN`, `META`,
`MARK` are never replayed.

Unit words: `ref` — `> 0` object index, `< 0` external, `0` nil; `word` —
verbatim; `bytes` — blob byte offset; `foreign` — external index.

### 3.7 Blob

`[len][bytes… NUL]` at the offset a `bytes` unit stores. The loader's buffer
outlives the image; a rebuilt `bytes` unit points into it.

## 4. Rules the writer keeps

### 4.1 The walk

The walk is the imaged base's allocation chain, from the base object's heap
link, filtered to objects the mark reached. The mark is
`(heap tree-mark! base-object TRACE)` — the collector's own traversal from
the base, with a flag the collector does not use — so "reachable" means what
the collector means by it, type hooks included. The mark is made **once per
process**: `chain-clear!` disables later marks.

While a frame holds a cursor into a child base's chain, **this base must not
collect**: the collector marks through whatever a frame holds, and a sweep
clears flags on this chain only, so each collect leaves stale mark bits on
the child. Walk the child with the periodic collect off; collect this base
between walks.

Nothing walks bytes; strings reach the blob through one copy each.

### 4.2 Two chains for a child

A child base's language state may refer to objects this base lent it —
`include` and `syscall` (`x_callable_bind`, root base only), `args`,
`x-machine`, `x-version`, `x-release` (`x_value_bind`, `x-cli.c`). Those
live on this base's chain. The walk covers the child's chain and then this
one, same fold, same mark; what the mark reached is the image, whichever
chain holds it. (An engine primitive that binds the CLI globals into any
base would let the child own them and make the second walk unnecessary —
§8.)

### 4.3 What is a reference

A word is a reference iff its unit's kind is `ref`. An INTEGER's one unit is
`word`; it is never resolved, even when it holds an address — so a global
that caches a type word (`%reflect-satom-tw`, `%print-int-tw`) is written
verbatim and is **wrong after load** unless the library recomputes it.
The draft relocated these by table; this format does not, because the
right fix is in the library: a cached process address is a boot-time computation
the image cannot carry, and `boot/reflect.x` and `boot/printer.x` must
recompute theirs on load (§8).

### 4.4 Names for types

None. A type is its struct's object index. Two bases' STRING types are two
structs and two indices; the loader does not care which is which.

## 5. What the loader does, in order

1. Read the file into raw memory. Refuse on word size, byte order, release.
2. Resolve every external to an address or object (§3.4). Count the ones
   that resolve to nil.
3. `(image rebuild!)`: allocate `N` objects with the type each record names
   — an imaged struct's *rebuilt* object, or the static tag — and the shape
   row's count; patch every unit. Objects are allocated on this base's
   chain with this base's `obj-meta-extra`; the rebuild never reads
   `x_type_field_units` off a static tag.
4. Install the roots (§3.5) as **separate top-level forms, each a direct
   primitive call**, `ctrl` cells last and to nil. Any operative or
   procedure here pushes a TCO compound onto the save-stack that a later
   restore would use to put this base's stale env back (`x_tco_restore`,
   `x-eval.c`); a primitive call pushes nothing. After the last write the
   loader's own names are gone, and the next form on stdin evaluates
   inside the image.

The loader is silent when a runner drives it; with `%IMG-VERBOSE` bound it
prints one line of counts and the unresolved externals by name.

## 6. Invariants — each is one spec test

On a small base, seconds per cycle; the x-core image is the integration
test, not the unit test.

1. Header round trip, and refusal on word size, byte order, release.
2. A pair, a string, a symbol, an integer, a character read back equal; the
   rebuilt pair's type word is the rebuilt PAIR struct; `(pair 1 2)` after
   load has the same type word.
3. A rebuilt closure is callable and its call pointer is nonzero.
4. `(new C …)` makes an instance; `object?` and `class-of` agree; a method
   dispatches; `(Type of instance)` is the rebuilt struct's name-stack node's
   atom.
5. A symbol read after load is `same?` as the imaged symbol of that name
   (the intern table came with the image).
6. A raised `Err` is caught as an object; `(Err kind-of e)` answers; a C
   primitive's type error is the resident ERR.
7. Collect safety: two collects, a top-level def, a tail-position def
   inside a call, printing, then lookups of each — ASan-clean.
8. `#t` after load is `same?` as the loader's `x_true_obj`; the SYMBOL
   type's C reader is the same static as in a fresh base.
9. Unresolved externals: 0.
10. `ctrl` cells are nil in the file and after install; the save-stack is
    empty when the next form is read.

## 7. What must be true of the engine

- Every engine type declares its units (`x_type_field_units` non-nil with a
  correct mask) in its own descriptor. BUFFER holds a pointer into another
  object's bytes and a C stack array; with no declared shape both sides
  would read it as two references. Today `lib/x/type/shape-rows.x` declares
  eight; the engine should declare all of its own.
- `(image rebuild!)` allocates by rebuilt struct or static tag, with `given`
  counts for the three roles, and sets `SHARED`.
- The static bound: an external index past the table is the sentinel.

## 8. Open

- **CLI globals per base.** `include`, `syscall`, `args`, `x-*` are bound
  into the root base by `x-cli.c` only; a child gets them lent from its
  parent, which is what forces the second walk (§4.2). An engine coordinate
  that binds them into any base removes that.
- **Cached process addresses in the library** (§4.3): `%reflect-satom-tw`,
  `%reflect-spair-tw`, the printer's `%print-*-tw` — recompute on load, or
  stop caching.
- **The read buffer** is process state and stays the loader's; the image
  therefore cannot carry a partially consumed input, and does not try.
- **Object metadata** (`obj-meta-extra`: line and file ids) is not carried;
  a loaded image's error reports have no source positions.
- **Digests.** The header carries the engine release; it does not carry a
  digest of the library sources. `tools/dev/image-build.sh`'s key does that
  outside the file.

## 9. What the draft got wrong

The draft treated the base as a static spine the image may only read
through `base-paths.x`, imaged the env and globals hanging off it, and
resolved every other piece of base state against the loader's own base by
name: type structs by type name, handler stacks by cell row, the resident
ERR and the boundary by ad-hoc install, cached type words by relocation.
Each of those was a table, each table a parser, and each grew from the one
before it failing to express the next thing found. Its findings were all
the same finding: the base is one tree, and an image that does not carry
the tree has to reconstruct it by guesswork.

What this format keeps from the draft: the walk and its three rules, the
externals kinds 1–5 and the pristine-base derivation of kind 7, the shape
reader, the primitive-call install, the NUL in names, and the sentinel.
