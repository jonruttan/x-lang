# State image format

This is the byte-level contract between `tools/dev/image-write.x` (the
writer), `tools/dev/image-read.x` (the loader), and `(image rebuild!)` in the
engine. [state-images.md](state-images.md) argues *why* an image looks like
this; this document says *what* one is, what each side may assume, and what a
conforming test checks. When the two disagree, this one is wrong and must be
fixed first — nothing may be added to the format that is not written here.

Everything below is stated for format version 1. "Word" means a machine word
of `%word-size` bytes, little-endian, and every offset is in words unless it
says bytes.

## 1. What an image is

An image is the object graph reachable from one base's environment — its env
chain, its globals tree, and everything they reference — written so that a
*different process*, running the *same engine release*, can rebuild that graph
into a base of its own and continue evaluating in it.

Three facts shape everything else:

1. **No address survives.** The writing process's pointers mean nothing in the
   loading one. Every word the image stores is therefore one of exactly three
   things, and the image must say which: a reference *into the image* (an
   object index), a reference to something *the loader already owns*
   (resolved by name), or a plain *value* (an integer, a code point, bytes).
2. **The loader owns its base.** Its type structs, its static atoms, its
   spine cells, its C functions are its own. The image never carries those; it
   carries *names* for them, and the loader resolves each name against what
   it has. A name that does not resolve is an error the loader can see, never
   a silent nil.
3. **Shape comes from the loader's types**, not from the file — except for
   the three tags that have no type struct to ask (§4.2). The count and kind
   of every unit an object has is what the loader's type for that name
   declares. Writer and loader must therefore agree on every type's shape,
   and §7 lists what makes them disagree.

## 2. File layout

Sections in order, each a run of words, contiguous, no padding between:

| # | section | start word | length (words) |
|---|---|---|---|
| 0 | header | 0 | 19 |
| 1 | type table | 19 | `TWORDS` |
| 2 | statics table | after 1 | `SWORDS` |
| 3 | type-cell table | after 2 | `CWORDS` |
| 4 | relocation table | after 3 | `RWORDS` |
| 5 | foreign table | after 4 | `FWORDS` |
| 6 | object table | after 5 | `OBJW` |
| 7 | byte blob | after 6 | `BLOBN` **bytes** |

The loader derives every start from the header; nothing is at a fixed offset
except the header itself.

### 2.1 Header (19 words)

| word | name | meaning |
|---|---|---|
| 0 | magic | `1196247384` (`"XIMG"` as a little-endian word) |
| 1 | version | `1` |
| 2 | word size | `%word-size` of the writer; the loader refuses a mismatch |
| 3 | byte order | `1`, read back as a word; the loader refuses if it is not `1` |
| 4 | `N` | object count |
| 5 | `OBJW` | object table length, words |
| 6 | `BLOBN` | blob length, **bytes** |
| 7 | `ROOTENV` | object index of the env chain head |
| 8 | `FCOUNT` | foreign entries |
| 9 | `FWORDS` | foreign table length |
| 10 | `TCOUNT` | type rows |
| 11 | `TWORDS` | type table length |
| 12 | `ROOTG` | object index of the globals tree root |
| 13 | `SCOUNT` | statics entries (the *used* ones — §3.2) |
| 14 | `SWORDS` | statics table length |
| 15 | `CCOUNT` | type-cell entries |
| 16 | `CWORDS` | type-cell table length |
| 17 | `RCOUNT` | relocation entries |
| 18 | `RWORDS` | relocation table length |

Words 2 and 3 are the only refusals the header supports today. Engine
release, machine, and library digests are **not** in the header (open, §8).

### 2.2 Names

Several tables carry a *name*: a byte string. A name is stored as

    [len][bytes ...]

`len` is the byte count, the bytes occupy `words-for(len)` words where

    words-for(n) = 1 + ((n + 1) >> 3)

i.e. room for the bytes **and a terminating NUL**, which the zeroed buffer
supplies. The NUL is load-bearing: the loader hands names to
`(type make)`, whose C `strlen`s them.

### 2.3 Steps

A *path* is a list of first/rest steps: `[nsteps][s1 ... sn]`, each step
`0` for first, `1` for rest. Steps are the ones the layout contract
(`engine/tools/contract/base-paths.x`) declares; the writer emits no step the
contract does not name.

## 3. The tables

### 3.1 Type table — "which type is this a row of"

One row per **type name** that has at least one instance in the image:

    [name]

Rows are 1-based; object records refer to a row by index. Two different type
words in the writer's process that carry the same name share **one** row
(the child's and the parent's `STRING`, for instance): the writer aliases
the second to the first. The loader matches a row to its own type by name.

Three rows have no type struct in any base and are recognised by name:

| name | what it tags | units | kind |
|---|---|---|---|
| `SPAIR` | a **type-struct node** — tagged `x_type_pair_obj` | 2 | reference |
| `ATOM` | a static atom — tagged `x_type_atom_obj` | 1 | word |
| `NIL` | a nil-typed object (`#t`, `#f`, and their kin) | 1 | word |

**`PAIR` is not one of them.** An ordinary pair is tagged with the base's own
PAIR type struct, a heap object; its name is `PAIR` and it is not in the type
alist. The loader allocates a `PAIR` row with the type a fresh `(pair 1 2)`
carries. Naming the struct-node tag `PAIR` too was the single bug behind
every "collect after load" failure: the loader rebuilt every ordinary pair
with no type, and the collector never entered one.

The row named `SYMBOL` is special to the rebuild: objects of that row are not
rebuilt, they are **interned** by their bytes into the loader's symbol table,
because the evaluator compares symbols by identity.

### 3.2 Statics table — "something in the loader's base, by path"

An entry names a node the loader can *walk to*; the object record that refers
to it stores `-(entry index)`. Two forms, distinguished by the first word:

    [0][steps]                 walk from the base object
    [1][name][steps]           walk from the struct of the type called name

Every entry is a node on a declared path (every prefix of every row of
`base-paths.x`), plus, for `cell` rows of `base-layout.x`, the cell's value
(one extra `first`). The writer also walks a **pristine** `(Base make)` and
records its off-chain nodes under the same type-rooted paths: that is how the
engine's own handlers — buried under the library's pushes in a stack the
rows do not reach — get a name.

Only entries actually referenced are written, numbered in order of first
reference; `SCOUNT` is that count. A reference the writer could not name is
stored as `-(FULL + 1)` where `FULL` is the writer's *unwritten* full count:
always past the table, so the loader's bound turns it into nil. §8 lists the
references that currently take that road.

A **type handle** — a type's name atom — is always a static, never an object
index, even when the writer's process has it on the chain: the registry,
`make-instance`, `type?` and `by-atom` compare handles by identity, and only
the loader's own atom has the right identity.

### 3.3 Type-cell table — "what the library pushed onto this type's stack"

    [object index][name][steps]

The statics' type-rooted form minus its tag word. `steps` reach the head pair
of a handler list from the struct of the type called `name`; the loader walks
to the *parent* and writes the object at the half the last step names. Rows
are the eleven stacks the `type push-*` coordinates and the from/to cells
name: call, eval, write, display, analyse, delimit, read, from, to, iter, ops.
Name, data, units and the collector's hooks are the engine's and the loader's
own.

### 3.4 Relocation table — "an integer whose value is a type word"

    [object index][name]

The object is an INTEGER whose value, in the writer's process, was the type
word of the type called `name`. The loader writes its *own* type word for
that name into the rebuilt integer: the struct's address for a heap type,
`x_type_pair_obj` for `SPAIR`, `x_type_atom_obj` for `ATOM`, `0` for `NIL`.
This exists because `boot/reflect.x` and `boot/printer.x` cache type words in
globals at boot; carried as plain integers they are addresses of a process
that no longer exists.

*Status: emitted by the writer; the loader-side install is written; the
round trip is untested.*

### 3.5 Foreign table — "a C address, by how to reacquire it"

    [kind][name]

A foreign unit (§4.3) stores an entry index; the loader resolves the entry to
an address and writes that. Kinds:

| kind | name is | loader resolves by |
|---|---|---|
| 1 | `ns/method` | the catalog: `(prim-ref ns method)`'s function pointer |
| 2 | a bare global | evaluating the symbol in the loader's base |
| 3 | a C symbol | `dlsym` on the process |
| 4 | `PROCEDURE` or `OPERATIVE` | the call pointer a fresh closure of that kind carries |
| 5 | (empty) | the `dlopen` handle of the process |

An address that resolves to `0` is a null call pointer waiting to be called.
The loader must report the count; a nonzero count is a broken image.

### 3.6 Object table

`N` records, back to back, **no length word**:

    [type row][flags][unit ...]

The number of units is what the type row's shape says (§4.1). Reading the
table with a shape that disagrees with the writer's desynchronises every
record after the first disagreement, which is the failure mode to suspect
first when a load produces garbage.

`flags` is the writer's flag word masked to the bits that are replayed:
`0x01 WRAP`, `0x02 COV`, `0x04 FRAME`, `0x08 FNFRAME`, `0x40 RO`. `SHARED`
is *set* on every rebuilt object regardless of the writer's bit: the image
lives as long as the process. `OWN`, `META`, `MARK` are never replayed.

### 3.7 Blob

Byte payloads for `bytes` units: `[len][bytes ... NUL]` at the byte offset the
unit stores. Strings and symbol names live here. A `bytes` unit is a pointer
into the blob after rebuild, so the blob's buffer must outlive the image.

## 4. Units

### 4.1 Shape

A type's shape is its unit count and, per unit, a kind: `ref` (0), `word`
(1), `bytes` (2), `foreign` (3), packed two bits per unit into a mask. The
writer reads the shape from *its* type; the loader from *its* own type of the
same name. A units value in a type struct is one of three things, and
`image-walk.x`'s `%sh-count` is the one place both sides read it:

| units value | meaning |
|---|---|
| an INT `n` | `n` units, all `ref` |
| a pair `(n . mask)` | `n` units with kinds from `mask`; `n < 0` is the slot-0-counted form |
| the static `x_type_units_pair_obj` (type word 0) | **2 `ref` units** — what `make-instance` allocates for every library-registered type |

### 4.2 The three tags

`SPAIR`, `ATOM`, `NIL` rows have no type to ask; the loader states their
counts (2/1/1) and kinds (ref/word/word) and passes them to the rebuild as
`given`. The rebuild must not read `x_type_field_units` off the type it
allocates such a row with: `x_type_pair_obj` is a static descriptor, not a
struct tree.

### 4.3 What a unit stores

| kind | stored word |
|---|---|
| `ref` | `> 0`: object index. `< 0`: statics entry. `0`: nil |
| `word` | the value, verbatim (see §3.4 for the one exception) |
| `bytes` | byte offset into the blob |
| `foreign` | foreign entry index; `FCOUNT + 1` if unnameable, which resolves to `0` |

## 5. What the loader installs, and in what order

1. Read the whole file into raw memory.
2. Type rows: match each name to a live type; **register** any the base lacks
   with `(type make name ())` — empty handlers; the type-cell table fills
   them. Declare shapes from `lib/x/type/shape-rows.x` on this base first
   (the img dialect does this at boot).
3. Statics: resolve every entry to a node of *this* base.
4. Foreign: resolve every entry to an address.
5. `(image rebuild!)`: allocate every object with its row's type and shape,
   then patch every unit.
6. Type cells: write each handler-list head into this base's struct.
7. Relocations: write this base's type words into the flagged integers.
8. **Roots, as the last three top-level forms, each a direct primitive call:**
   the local boundary, then the env head, then the globals tree. A `do` or
   any operative here leaves a TCO compound on the save-stack that later
   restores the host's stale env over the install. The loader's own names are
   gone after the third write; the next form on stdin evaluates inside the
   image.

The loader is silent when driven by a runner (`%IMG-PATH` bound); its stdout
is the batch's.

## 6. Invariants a conforming test checks

Each is one spec test, on a **small** image — a base with a handful of defs —
not on x-core. Seconds per cycle.

1. Header round trip: magic, version, word size, byte order, every count.
2. A pair, a string, a symbol, an integer, a character: written and read back
   equal, and the rebuilt pair is `x_obj_type_isspair`-typed like a fresh one.
3. A closure: callable after load; its env resolves; its call pointer is not
   `0`.
4. A class instance: `object?` is true, `class-of` is the class, a method
   dispatches.
5. A type-word integer (`%reflect-satom-tw`): after load equals the loader's
   own `(%reflect-type-word (type of 0))`.
6. A raised `Err`: caught as an object, `(Err kind-of e)` answers.
7. Collect safety: after load, `(heap collect)` twice, then a top-level def,
   a tail-position def inside a call, printing, and a lookup of each —
   ASan-clean.
8. Statics: `#t`, the env-alist cell, a type-name endpoint each resolve to the
   loader's own object (`same?`, not `eq?`).
9. Every foreign entry resolves nonzero; the loader's count of unnameable
   references is 0.
10. Two collects between forms inside the image with no cell installed leave
    a tail-def'd global alive (the pair-type invariant, §3.1).

## 7. Known ways writer and loader disagree

These are the ones found so far; each was found by loading x-core and
crashing, and each is a test in §6 waiting to be written.

- A library type with no declared shape: both sides must read the static
  units pair as 2 refs (§4.1).
- The struct-node tag vs the pair type (§3.1).
- A name without room for its NUL (§2.2).
- A type handle indexed rather than named (§3.2).
- Boot-cached type words (§3.4).
- Roots installed through an operative (§5.8).
- A child base walked with this base's periodic collect on: a collect while
  a frame holds a cursor into another base's chain leaves stale mark bits
  there. Walk the child with collects off, collect this base between walks.
- A child's references to objects this base lent it (`include`, `x-release`,
  `args`): walk both chains, or they are unnameable.

## 8. Open

- `%token-eof` and eight tokenizer-table nodes are unnameable: the first
  needs a "bare global" statics kind, the second is a `todo` subtree of
  `base-layout.x`. Both restore as nil.
- The header carries no engine release, machine or library digest; the build
  script's key does that job outside the file.
- One type row per name means a library type declaring a custom shape would
  need the shape in the file; none does today.
- The relocation table's round trip (§3.4) is untested.
