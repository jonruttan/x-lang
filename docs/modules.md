# Computational Expressions in C

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

`import` resolves the module name to a file path (e.g., `x/core/list` becomes `lib/x/core/list.x`), then includes the file if it hasn't been included already. Repeated `import` calls for the same module are no-ops.

### `include`

Raw file inclusion without deduplication:

```
(include "lib/x/core/list.x")
```

`include` always loads the file. Use `import` instead unless you specifically need to reload.

### `include-once`

Like `include`, but tracks which paths have been loaded and skips duplicates:

```
(include-once "lib/x/core/list.x")
```

`import` is built on `include-once` internally.

### Module Naming Convention

Module names map directly to file paths:

| Module Name | File Path |
|-------------|-----------|
| `x/core/list` | `lib/x/core/list.x` |
| `x/num/float` | `lib/x/num/float.x` |
| `x/type/vector` | `lib/x/type/vector.x` |
| `x/sys/posix` | `lib/x/sys/posix.x` |

The resolution rule is: `lib/<module-name>.x` where slashes in the module name become directory separators.

### Bootstrap Sequence

The bootstrap loader `lib/x-core.x` loads modules in a specific order:

1. **Boot phase** — Loads `operatives.x`, `data.x`, `string.x`, `module.x` via raw `include`. These four files establish the minimum needed for `provide`/`import` to work.

2. **Pre-registration** — All 25 core module paths are pre-registered in the include-list, so `import` calls within those modules are no-ops (the paths are already marked as "included").

3. **Module loading** — Each module is loaded via `include` in dependency order. Modules use `import` for their own dependencies (which resolve as no-ops due to pre-registration) and `provide` at the bottom to register their exports.

This pre-registration pattern is also used by `lib/x-and.x` and `lib/x-or.x` to register their additional modules before loading them.

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
    (map (fn (a) (+ a y)) x)))
  (param x LIST "Input list")
  (param y INTEGER "Value to add")
  (returns LIST "List with y added to each element")
  "Add y to every element of x.")

(provide x/my-module my-function)
```

Key conventions:
- Comment at the top naming the file and its dependencies
- `import` dependencies before use
- Wrap definitions in `(doc ...)` for automatic documentation generation
- `provide` at the bottom listing all public exports
