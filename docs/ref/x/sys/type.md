### `type-alist`

Return the interpreter's type alist from the base object.

**Returns:** `LIST` — Alist of (name . type-struct) pairs

### `type-by-atom`

Look up a type struct by its handle atom (from type-of).

**Parameters:**

- **handle** : `ATOM` — Type handle returned by type-of

**Returns:** `LIST` — The type struct, or () if not found

### `type-io`

Navigate to a type struct's IO group (analyse, delimit, read, write, display, error).

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — IO group

### `type-cvt`

Navigate to a type struct's conversion group (from, to).

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Conversion group

### `type-write-cell`

Get the write-handler stack cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Stack cell for write handlers

### `type-analyse-cell`

Get the analyse-handler stack cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Stack cell for analyse handlers

### `type-from-cell`

Get the from-conversion cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Alist of source-type to converter function

### `type-to-cell`

Get the to-conversion cell from a type struct.

**Parameters:**

- **t** : `LIST` — Type struct

**Returns:** `LIST` — Alist of target-type to converter function

### `type-push-write`

Push a write handler onto a type's write stack.

**Parameters:**

- **ts** : `LIST` — Type struct
- **handler** : `CALLABLE` — Write handler function

### `type-pop-write`

Pop the top write handler from a type's write stack.

**Parameters:**

- **ts** : `LIST` — Type struct

### `type-push-analyse`

Push an analyse handler onto a type's analyse stack.

**Parameters:**

- **ts** : `LIST` — Type struct
- **handler** : `CALLABLE` — Analyse handler function

### `type-cast!`

Overwrite an object's type tag with the type of another object.

**Parameters:**

- **obj** : `ANY` — Object to retype
- **type-src** : `ANY` — Object whose type to copy

**Returns:** `ANY` — The retyped object

