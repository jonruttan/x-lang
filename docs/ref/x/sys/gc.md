[← Index](../../index.md)

# x/sys/gc

### `heap-collect`

Run a full garbage collection cycle.

**Returns:** `INT` — Number of freed objects

### `heap-mark-root!`

Register a GC root object that will always be marked during collection.

**Parameters:**

- **obj** : `ANY` — Object to protect from GC

### `heap-mark-hook!`

Register a callback to run during the GC mark phase.

**Parameters:**

- **fn** : `CALLABLE` — Function called during mark

### `heap-free-hook!`

Register a callback to run during the GC free phase.

**Parameters:**

- **fn** : `CALLABLE` — Function called when objects are freed

