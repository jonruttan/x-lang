# Reflection

*x-lang: computational expressions over a minimal, type-agnostic engine.*

How to look inside a running system: what each kind of thing is, the
doors that answer questions about it, and where the detail lives. This
page names the doors and links their owners; signatures, argument types
and examples are what `(help Name/method)` and the
[generated reference](https://jonruttan.github.io/x-lang/docs/ref/x/index.html)
answer, and they are not repeated here.

## What reflection means here

The engine is a CPU: it executes what it is given and checks nothing. Every
structure it runs on is built from the same atoms and pairs as a program's
own data, laid out as the contracts the engine ships describe
([The Engine Contract](engine-contract.md#what-an-engine-ships)): the words
of an object, the rows of the base, the instruction set. The library reads
those layouts, which is how the printer, the module loader and the
collector's hooks are written in x-lang, and it is how a program can read
them too.

So there are two kinds of door. The **named doors** are classes: each
checks what it is handed, answers a value or `()` for a miss, and is
documented. The **raw doors** read and write words at the contract's
offsets, check nothing, and are the maintenance hatch. This page walks the
named doors by level and names the hatch once, at the end.

## Finding out what exists

The library documents itself: every `(doc …)` form files an entry, and the
same registry serves the prompt, the editor and the reference generator.

- `(help)`, `(help name)`, `(help Class member)` and `(help x/some/module)`
  print an entry, a class's members grouped static and instance, or a
  module's exports. A class listing leaves out members whose names begin
  with `%`; `(help Class %member)` still answers for one.
- `(apropos "sub")` prints every documented name containing the text and
  answers the names, sorted. `(modules)` prints every module the session
  knows, marking the loaded ones.
- `(Doc entry 'name)` answers an entry as data, a record with `name`,
  `desc`, `returns`, `params`, `examples`, `sees`, `notes` and `samples`,
  as the form wrote them; `(Doc names)` lists every documented name.
- At the prompt, Tab completes against the same registry
  ([The interactive session](repl.md#completion)).

[Standard Library](standard-library.md#finding-a-name) says how the library
is laid out and how a call is spelled; the
[Object System](object-system.md#documentation) says how a class documents
its members.

## A value and its type

Every value carries a type label, and the type it names is a structure a
program can read: its name, its handler stacks for evaluation, calling,
reading, writing and iteration, its conversions and its operator table.

- `(Type of v)` answers the handle, `(Type name v)` the name,
  `(Type named NAME)` the handle for a registered name, `(Type ? v t)`
  whether `v` is of `t`.
- `(Type wrap t)` clothes a handle as an instance: `(t name)`,
  `(t fields)` for the field names the layout contract gives a type, and
  `(t cell 'field)` for the cell a field addresses, such as a handler
  stack.
- The `push-*` family pushes a handler onto a stack, `write`, `display`,
  `call`, `iter`, `read` and the generic operators among them, and
  `pop-write` takes the top one back off.

The model is in [Type System](type-system.md#type-reflection-type-wrap) and
the normative form in the [Specification](spec.md#type-reflection); the
[sandboxing tutorial](sandboxing-tutorial.md#wrapping-a-type) restyles a
built-in and puts it back.

## A class and its members

A class is a value, and so is an instance's class.

- `(object? x)` and `(class? x)` say which a value is; `(class-of inst)`
  answers the class, `(class-name c)` its name, `(class-parent c)` the
  class it extends, `(instance-of? inst C)` whether the chain reaches `C`.
- `(class-fields c)`, `(class-methods c)`, `(class-static-fields c)` and
  `(class-static-methods c)` list a class's own members, not inherited
  ones.
- `(method-of C sel)` resolves a static method to its closure through the
  chain; `(Generic methods-of g)` lists a generic's methods, once
  `x/type/generic` is imported.

The table and the words for members are in the
[Object System](object-system.md#introspection).

## A callable

A closure is made of its parameter list, its body forms and the environment
it was made in; an operative is the same with the name it binds the
caller's environment to; a wrapped combiner holds the combiner it wraps;
an engine primitive has no state at all. `Fn` reads them:

- `(Fn label f)` answers `'fn`, `'op`, `'wrap` or `'prim`, and `()` for a
  value that is none of them, a value callable only through its type's
  call handler included.
- `(Fn params f)`, `(Fn body f)` and `(Fn env f)` answer a closure's or an
  operative's parts as written. A wrapped combiner and a primitive answer
  `()` from all three; `unwrap` answers for the one, and the other has
  nothing to read.

`wrap`, `unwrap`, `fn` and `op` themselves are in
[Primitives and core forms](primitives.md#the-c-instruction-set), and the
words `entry` and `state` in the [Glossary](glossary.md#callables).

## An environment

An environment is a first-class value: one pair, its bindings and the
environment it was made in. A frame's bindings are an alist of names and
values; the root's are a tree, and the root has no parent. Every call makes
a child of the closure's environment, an operative receives its caller's
as a value, and `eval` with an environment makes it current. That is
engine law 10 in [Engine Laws](engine-laws.md).

- `(Env current)` answers the environment the form is evaluated in, a
  frame inside a closure body and the root at the top level; `(Env root)`
  answers the running base's root.
- `(Env bindings e)` answers the frame's own bindings as a fresh alist,
  the root's tree flattened; `(Env names e)` the names; `(Env parent e)`
  the enclosing environment; `(Env has? e 'name)` whether a name resolves
  from `e` outward, as lookup finds it.
- `(eval form e)` evaluates in `e`, and a `def` inside binds there and
  stays bound. `(module NAME)` as an expression answers a loaded module's
  environment, a child of the root for a scoped module.

Printing an environment prints its bindings, and the root's bindings are
the whole library; `(Env names e)` is the question to ask of the root.
`Env` is the evaluator's environment, not the process's, which
`Sys environ` and `Sys getenv` read. Module scope, and what leaves a module
and how, is in [Modules](modules.md#module-scope).

## Modules

The module registry is data: which modules the session knows and which
have loaded, what each provides, which module owns a name, and where a
module's names live.

- `(Module names)` lists every known module, sorted; `(Module loaded? 'm)`
  says whether one has provided its exports.
- `(Module exports 'm)` lists them as symbols, a `(global NAME)` export as
  `NAME`; `(Module owner 'sym)` answers the module that provided a name.
- `(Module env 'm)` answers a scoped module's environment, the root for a
  module loaded by `include`, and `()` for one not loaded.

How a module's names are reached from outside is in
[Modules](modules.md#reaching-a-modules-names).

## Where a form came from

The reader stamps the first cell of each form it reads with the line it
began on and the file it came from, and `include` files each path it loads
under an id. `Source` reads the stamps and the registry; `Io` reads the
snapshot a raise takes.

- `(Source line form)` and `(Source file form)` answer a form's line and
  the path of its file, `""` for standard input. A form built at run time,
  or a list cell other than a form's first, carries no stamp and answers
  `()`.
- `(Source path id)` resolves a file id, `(Source files)` lists every
  included file as an alist of id and path, and `(Source here)` is the
  reader's live position as `(path . line)`: evaluated while a file loads,
  it names that file and the line of the form being read.
- `(Io error-line)` and `(Io error-file)` answer where the most recent
  error was raised, frozen at the raise, which is what the prompt's
  `Error [file:line]:` prefix prints.

A program the wrapper streams onto standard input, through `-c` or `-f`,
is read behind the wrapper's own forms: its lines are stream lines and its
file is standard input. A file reached by `include` carries its own lines
and its path.

## The base, the heap and the raw hatch

A base is a whole interpreter: an environment, a type registry, a reader
and a catalogue of instructions. A program can make one, drive it, and read
any of its rows by name.

- `(Base make)` makes an isolated child with the engine's types and
  instructions and no library; `(b eval form)` and `(b bind 'name v)`
  drive it; `(b fields)` lists the base rows the layout contract names and
  `(b cell 'row)` addresses one. The child is the one to inspect this way:
  the running base is reached through the doors above, not as a value.
- `(Heap count)` counts live objects and `(Heap collect)` collects;
  `mark-hook!`, `free-hook!`, `mark-root!` and `pin!` hand the collector
  what it cannot see on its own. Allocation never collects: a collection is
  always an explicit call.
- `(prims)` is the catalogue of instructions the engine filed, an alist of
  namespaces each an alist of methods; `(prim-domain ns)` and
  `(prim-ref ns method)` read it, and `prim-reg!` files an x-lang value
  under a coordinate, which is how the library replaces an engine
  instruction with one of its own.

Below the named doors is the hatch. `(Obj ref o i)` and `(Obj set! o i v)`
read and write an object's data slots, `(Obj meta-ref o i)` its meta words,
`(Obj ->ptr o)` its address, and `Ptr` reads and writes words at any
address. The offsets they take are the engine's, in its `obj-layout.x`, and
a raw door checks nothing: a slot read as an object that is not one walks
off, as the engine's own `first` does on a non-pair. The
[sandboxing tutorial](sandboxing-tutorial.md#inspecting-a-base-field-reflection)
reads a child this way, and
[Primitives and core forms](primitives.md#coordinates) lists what the
coordinates reach.

## What the doors do not answer

There is no backtrace: the engine keeps the save stack and the handler
chain and no record of the calls between them. The running base is not a
value; `Base cell` reads a child. A closure prints as `#<fn>`, and nothing
about it is shown unless asked for through `Fn`.

The tools that read the system through these doors, the profiler, the
coverage tool, the linter, the image writer and the reference generator,
are described in [Dev tools](../tools/dev/README.md).
