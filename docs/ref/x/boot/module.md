### `include-once`

Load and evaluate a file, skipping if already loaded.

**Parameters:**

- **path** : `STRING` — File path to include

### `require-once`

Include a file only if it has not been loaded before. Alias for include-once.

**Parameters:**

- **path** : `STRING` — File path to include

**See also:** [`include-once`](#include-once) 

### `provide`

Register a module's exported symbols.

**Parameters:**

- **name** : `SYMBOL` — Module name, e.g. x/list
- **exports** : `SYMBOL` — Exported symbol names (variadic)

### `import`

Import a module (include its file if not yet loaded).

**Parameters:**

- **name** : `SYMBOL` — Module name to import

