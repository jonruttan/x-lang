# x-lang Modules

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*

## Module System

x-lang provides a simple module system based on three forms: `provide`, `import`, and `include`. The system supports include-once deduplication and a module registry for discovery.

### `provide`

Declares a module and registers its exported symbols:

```
(provide x/core/list
  map filter fold sort reverse append ...)
```

`provide` records the module name and its export list in the module registry. It does not affect evaluation — any definitions in the file are already bound in the environment by the time `provide` runs at the bottom of the file.

### `import`

Loads a module by name, with deduplication:

```
(import x/type/vector)
(import x/num/float)
```

`import` dedups by **module name**: if the name is already in the
loaded-module registry it is a no-op; otherwise it registers the name,
resolves it to a file path through the search roots (e.g., `x/core/list`
becomes `lib/x/core/list.x`), and loads the file. Name-keyed identity is
what makes an installed tree work — the same module reached through a
different root (repo `lib/` vs an installed absolute root) is still the
same module.

### `include`

Raw file inclusion without deduplication:

```
(include "lib/x/core/list.x")
```

`include` always loads the file. Use `import` instead unless you specifically need to reload.

### `include-once`

Like `include`, but tracks which paths have been loaded and skips duplicates:

```
(include-once "./support.x")
```

`include-once` dedups by **path** (it loads files, not modules) and is the
right tool for non-module files. For library modules always use `import` —
the two registries are separate, so an `include-once` of a module file does
not make a later `import` of that module a no-op. Root-relative literals
like `"lib/..."` are boot-closure-only (`make check-path-literals`): they
resolve against the process cwd and break installed trees.

### Module Naming Convention

Module names map directly to file paths:

| Module Name | File Path |
|-------------|-----------|
| `x/core/list` | `lib/x/core/list.x` |
| `x/num/float` | `lib/x/num/float.x` |
| `x/type/vector` | `lib/x/type/vector.x` |
| `x/sys/posix` | `lib/x/sys/posix.x` |

The resolution rule is: `lib/<module-name>.x` where slashes in the module name become directory separators.

Two extensions to the rule:

- **Search roots** — `(import-path! "path/to/root")` adds a search root, so
  `(import my/module)` can resolve outside `lib/` (e.g. an application tree).
  The default root is `lib`.
- **Relative includes** — an `include-once`/`import` path starting with `./`
  or `../` resolves against the *including file's* directory, not the working
  directory. Raw `include` paths stay verbatim.

## Pinning

A project can pin the library modules it depends on: keep the exact
module files it was written against in its own tree, and have `import`
resolve those names there instead of in the installed library. Pinned
code then keeps its behavior as the library evolves.

### The manifest: `pin.xon`

A project declares its pins in a `pin.xon` file at its root. The
manifest is **xon** — x object notation: a sequence of x-lang data forms
(with `;` comments), read with the ordinary reader and **never
evaluated**. Its consumers interpret a closed vocabulary; an unknown
form is a loud error, not a skip.

The pin vocabulary:

```
; pin.xon
(root "deps")     ; overlay root, relative to this file's directory
```

- `(root "DIR")` — adds an overlay root to the import search roots.
  A relative `DIR` resolves against the manifest's own directory; an
  absolute one is used as-is. The directory must exist, and holds
  module files in the standard name layout (`deps/x/core/list.x` pins
  `x/core/list`). Roots listed first win, and every overlay root takes
  precedence over the platform library.

An overlay tree only needs the modules being pinned — anything not
found there falls through to the platform library. Note that a pinned
module's own `import`s also resolve through the roots, so a pin that
must not mix with newer dependencies should vendor its import closure.

### Probing and arming

The shell wrapper probes for `pin.xon` starting from the **program's**
directory (`-f`/`-F`), or the current directory for a REPL, walking up
parent directories git-style. A found manifest is always announced —
one `pinned: <path>` line on stderr — and `--no-pin` skips the probe
entirely.

The wrapper never reads the manifest itself: it hands the path to the
interpreter as data (`(def %pin-file "<path>")` ahead of the boot
entry) and loads `x/tool/pin` right after boot, before the first user
form. That loader — always resolved from the platform library, never
from an overlay — reads the manifest, checks the vocabulary, and arms
the roots via `import-path!`. Because nothing in the manifest is
evaluated, a manifest can only do what pinning does: redirect import
resolution into its own project's files.

### The pin boundary

Two structural rules bound what an overlay can change:

- **One version per name per session.** `import` dedups by module name,
  first load wins — two versions of the same module cannot coexist in
  one session.
- **The boot set is unpinnable.** Modules loaded by the boot closure
  are pre-registered in the loaded-module registry, so an `import` of
  them is a no-op before any search root is consulted. An overlay copy
  of a boot module is ignored by construction; pinning the platform
  itself means running a different boot entry, not overlaying files.

`make check-pin` smokes all of this end to end (overlay resolution,
root precedence, the unpinnable core, the closed vocabulary,
`--no-pin`).

### Bootstrap Sequence

The bootstrap loader `lib/x-core.x` loads modules in a specific order:

1. **Boot phase** — Loads the boot layer via raw `include`: two repo contracts (`tools/base-paths.x`, `tools/obj-layout.x`) and the seven `lib/x/boot/` files (`registry.x`, `operatives.x`, `data.x`, `reflect.x`, `printer.x`, `string.x`, `module.x`). These establish the catalog, the object layout, printing, and the minimum needed for `provide`/`import` to work.

2. **Pre-registration** — Every library path x-core loads (all its raw `include`s, the boot files, and `lib/x-core.x` itself) is pre-registered in the include-list, so `import` calls within those modules are no-ops (the paths are already marked as "included"). Raw `include` does not register a path, so this parallel list is the registration; `make check-boot-order` enforces that the two stay in sync.

3. **Module loading** — Each module is loaded via `include` in dependency order. Modules use `import` for their own dependencies (which resolve as no-ops due to pre-registration) and `provide` at the bottom to register their exports.

This pre-registration pattern is also used by the dialect bodies (`lib/x/boot/xenon.x`, `lib/x/boot/radon.x`) to register their additional modules before loading them.

### Discovery

List all registered modules at the REPL:

```
> (modules)
```

This returns the module registry — an association list of `(name . exports)` pairs.

Look up documentation for a specific function:

```
> (help 'map)
```

### Writing a Module

A typical module file:

```
; my-module.x -- Description of what it does
;
; Requires: list.x (map, filter)

(import x/core/list)

(doc (def my-function
  (fn (_ x y)
    (map (fn (_ a) (+ a y)) x)))
  (param x LIST "Input list")
  (param y INTEGER "Value to add")
  (returns LIST "List with y added to each element")
  "Add y to every element of x.")

(provide x/my-module my-function)
```

Key conventions:
- Comment at the top naming the file and its dependencies
- `import` dependencies before use
- Every `fn` receives itself as argument 0 — write `(fn (_ a) ...)` (or name
  it `self` for recursion). Omitting the self slot does not error: the
  arguments shift by one and the function silently computes garbage.
- Wrap definitions in `(doc ...)` for automatic documentation generation
- `provide` at the bottom listing all public exports
