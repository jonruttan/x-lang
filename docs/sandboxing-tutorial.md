# Sandboxing and type reflection, step by step

A walkthrough of execution-context ("base") objects for program authors:
making an isolated interpreter, handing it exactly the capabilities you
choose, teaching it custom types, and inspecting any base or type through
the layout contract. The reference lives in
[spec.md](spec.md) (§11 "Type Extension", §12 "Sandboxing") and the
generated pages [ref/x/type/base.md](ref/x/type/base.md) and
[ref/x/type/type.md](ref/x/type/type.md); this page is the path through
it. Every session shown here was run as written (`sh x.sh` from a repo
checkout, the helium dialect).

## What a base buys you, in one minute

An x-lang interpreter's entire state — environment, type registry, reader
state, I/O — lives in one value, the base. `(Base make)` builds a fresh
one: a whole, isolated interpreter you hold as an ordinary value. Nothing
crosses in or out unless you pass it. That gives you sandboxed evaluation
of code you don't fully trust, scratch interpreters for tools that read
source without evaluating it, and custom tokenizer bases whose reader
speaks a different language (the logo app's Logo reader is one of these).

`(Base make)` answers a **Base instance** wrapping the raw C base object.
The instance is the interactive surface; the raw object (its `raw`
member) is what C-level plumbing consumes. Every `Base` static accepts
either form.

## A first sandbox

```x-repl
> (def b (Base make))
#<base:objs 1615>
> (b eval '(* 6 7))
42
> (b eval '(def x 10))
10
> (b eval 'x)
10
```

The echo `#<base:objs 1615>` is the instance's inspection form — the
number is the child's live allocation count, so you can watch a sandbox
grow. Evaluation inside the child is invisible outside, and vice versa:

```x-repl
> x
*** ERROR: Unbound SYMBOL 'x
> (def y 5)
5
> (guard (e 'isolated) (b eval 'y))
'isolated
```

Errors raised inside the child propagate to the caller's `guard`, and the
child stays usable afterwards — a caught error does not corrupt it:

```x-repl
> (guard (e 'caught) (b eval '(error "boom")))
'caught
> (b eval '(+ 40 2))
42
```

## The bare-children contract

A fresh child is the **bare C ISA** — arithmetic, binding, eval — and
nothing more. The library you are typing at lives in the *parent*; the
child has no output verbs, no catalog protocol, no reader macros:

```x-repl
> (guard (e 'bare) (b eval '(display "hi")))
'bare
> (guard (e 'bare) (b eval '(prim-ref 'io 'write-str)))
'bare
```

This is a feature: the child starts with the smallest honest surface, and
everything else is something you explicitly handed it. The contract is
pinned by `tests/x/specs/core/sandbox.spec.md` ("bare-children
contract"), and you can *observe* it — see "Diffing a child against the
parent" below.

## Handing in capabilities

`bind` defines a name in the child. Bind a parent **closure** and the
child gains exactly that capability — the closure runs with the parent's
environment, so it can reach parent state the child cannot:

```x-repl
> (b bind 'shout (fn (_ v) (display v) (display "!\n")))
#<fn>
> (b eval '(shout 7))
7!
```

Values pass through `bind` unchanged, so you can seed data too:

```x-repl
> (b bind 'xs (list 1 2 3))
(1 2 3)
> (b eval '(first xs))
1
```

The shape of a sandboxed evaluator, then: make a base, bind the verbs you
are willing to expose, `guard` around `eval`, and keep everything else
out. What you did not bind, the child cannot name.

## Custom types on a child

`make-type` registers a type on the child — cross-base `make-type`. The
handler closures are built in the *calling* base and travel with the
instances they render:

```x-repl
> (def gizmo (b make-type "GIZMO"
    (list (pair 'write (fn (_ g) (display "<gizmo>"))))))
#<ATOM:0x796014a10>
> (b bind 'gizmo-t gizmo)
#<ATOM:0x796014a10>
> (b bind 'mi (prim-ref 'type 'make-instance))
#<prim>
> (def g (b eval '(mi gizmo-t 5)))
<gizmo>
```

(The handle echoes as an opaque atom — its address varies run to run —
and the last `def` echoes `<gizmo>` because the echo renders the new
instance through the write handler you just registered.)

For tokenizer work — teaching a base to *read* a different surface syntax
— start from `(Base make-tok)` instead: a minimal base with no types and
no prims, so your `analyse`/`read` handlers are the only reader it has.
The worked example is `apps/logo/types.x`, and the specs are the
"base-make-type" sections of `core/sandbox.spec.md`. (Reader-macro
handlers on the *running* base are boot-time only, by ruling — a fresh
child is exactly the sanctioned playground.)

## Inspecting a base: field reflection

Every field of a base is addressable by name. The names come from the
layout contract — `engine/tools/contract/base-paths.x`, one row per field — and
`(Base fields)` lists them:

```x-repl
> (List length (b fields))
64
> (%cell-int (first (b cell 'line)))
1
```

`(b cell 'name)` walks the contract's path from the child and answers the
addressed object; a cell-kind field's value sits in the cell's first
slot. The walk is honest about live state — bind something and read it
back through the environment cell:

```x-repl
> (b bind 'marker 77)
77
> (rest (first (first (b cell 'env-alist))))
77
```

A name whose row is not base-rooted is refused loudly, because a
type-rooted path stepped from a base spine would address arbitrary
interpreter state:

```x-repl
> (guard (e 'refused) (b cell 'type-iter))
'refused
```

## Wrapping a type

The same interactive treatment exists for types. `(Type wrap t)` accepts
a type handle (from `Type of`) or a type struct (from `Type by-atom`) and
answers a Type instance:

```x-repl
> (def t-int (Type wrap (Type of 0)))
#<type:INTEGER>
> (t-int name)
"INTEGER"
> (List length (t-int fields))
44
> (List length ((Type wrap (Type of "s")) fields))
44
```

`(t cell 'field-name)` walks the type-rooted rows of the same layout
contract — handler stacks, the conversion catalog cells, the
generic-operator alist — and refuses base-rooted names, mirroring
`Base cell`.

## How-to: restyle a built-in's rendering, and put it back

Handler stacks shadow: a push sits in front of the current handler, a pop
restores it. Restyling a shared built-in is therefore a round trip —
push, use, pop:

```x-repl
> (t-int push-write (fn (_ n) (display (Str8 append "0x" (%number->str n 16)))))
((#<fn> #<fn> . (())) (#<fn> . (())))
> (list 1 2 42)
(0x1 0x2 0x2a)
> (Type pop-write (t-int raw))
((#<fn> . (())) (#<fn> . (())))
> (list 1 2 42)
(1 2 42)
```

(The push and pop echo the handler-stack group they mutated — you can
see your handler arrive and leave.)

Two things worth knowing before you reach for this:

- **Write and display are separate stacks.** The REPL echo is write mode;
  `display` consults the display stack first and falls back to write only
  when the display stack is empty. INTEGER carries its own display
  handlers, so the push above changes the echo but not `display`.
- **`pop-write` is the only symmetric undo.** If you push onto a shared
  built-in's *display* stack, capture and restore deliberately — and if
  your code between push and pop can raise, restore under a `guard`
  *before* asserting anything, or a failure leaves the shared stack
  restyled for everyone after you. The round trip is pinned by
  `tests/x/specs/lib/type.spec.md`.

## How-to: diff a child against the parent

Child bases register their built-in types from C alone; the parent's
types additionally carry everything the library pushed at boot. Wrap both
sides and the bare-children contract becomes something you can measure —
find the child's INTEGER tree by name bytes and compare write-stack
depths:

```x-repl
> (def %count (fn (self l) (if (null? l) 0 (+ 1 (self (rest l))))))
#<fn>
> (def %find-tree (fn (self nm al)
    (if (null? al) ()
      (if (str=? (%reflect-sym->str (%reflect-type-tree-name (rest (first al)))) nm)
        (rest (first al))
        (self nm (rest al))))))
#<fn>
> (%count ((Type wrap (%find-tree "INTEGER" (first (b cell 'type-alist))))
           cell 'type-write-stack))
1
> (%count ((Type wrap (Type of 0)) cell 'type-write-stack))
2
```

One handler on the child (the C registration), two on the parent (plus
the x printer's boot push) — the delta *is* the contract. Two traps this
example steps around, worth naming because they bite: child type handles
do not intern into the parent, so `(Type name child-handle)` answers nil
— resolve child types by name *bytes* through the raw reflect walk, as
`%find-tree` does; and handler spines are C-built, so `pair?` answers
`#f` on them — walk them with raw `first`/`rest` (the `%count` above),
never the canonical `List` walkers.

## Raw bases, and when you need them

The instance is the right thing to hold almost always. The raw object —
`(b raw)`, or anything the catalog prims hand you — matters at three
seams:

- **C plumbing.** `(prim-ref 'tok 'read-str)` and friends consume raw
  bases. The library's own doors (`Tok read-str`, `Xon parse`) unwrap
  either form, so this only matters when you fetch prims directly.
- **Raw spine walks.** Code that navigates a base with `first`/`rest`
  (as `%find-tree` above navigates type trees) needs the raw object;
  an instance's slots are not a base spine.
- **Re-clothing.** `(Base wrap r)` turns a raw base back into an
  instance; `(Base raw-of v)` unwraps either form and passes raw values
  through — it is the seam helper the statics themselves use.

## Where everything lives

- `(help Base)`, `(help Type)`, `(help Base cell)`, `(help Type wrap)` —
  the in-REPL reference, always current.
- [spec.md](spec.md) §11–§12 — the normative, executable surface (its
  examples run in CI).
- [ref/x/type/base.md](ref/x/type/base.md),
  [ref/x/type/type.md](ref/x/type/type.md) — the generated reference.
- `engine/tools/contract/base-paths.x` — the layout contract both `cell`
  walkers read; `(Base fields)` / `(Type fields)` list its rows.
- `tests/x/specs/core/sandbox.spec.md`,
  `tests/x/specs/lib/type.spec.md`,
  `tests/x/specs/meta/printer.spec.md` — the pinned behaviour.
