[← Index](../../index.md)

# x/core/alist

Association list operations.

> Alist format is ((key . val) ...). Keys compared with eq?.

## Lookup

### `assoc-get`

Look up a key in an alist, returning its value or nil.

**Parameters:**

- **key** : `SYMBOL` — Key to look up
- **alist** : `LIST` — Association list

**Returns:** `ANY` — Value associated with key, or nil if not found

### `assoc-get-or`

Look up a key in an alist, returning a default if not found.

**Parameters:**

- **d** : `ANY` — Default value if key is absent
- **key** : `SYMBOL` — Key to look up
- **alist** : `LIST` — Association list

**Returns:** `ANY` — Value associated with key, or the default

### `assoc-has?`

Test whether a key exists in an alist.

**Parameters:**

- **key** : `SYMBOL` — Key to check
- **alist** : `LIST` — Association list

**Returns:** `BOOL` — True if key is present

## Modification

### `assoc-del`

Remove all entries for a key from an alist.

**Parameters:**

- **key** : `SYMBOL` — Key to remove
- **alist** : `LIST` — Association list

**Returns:** `LIST` — Alist without the given key

### `assoc-put`

Set a key-value pair, replacing any existing entry for that key.

**Parameters:**

- **key** : `SYMBOL` — Key to set
- **val** : `ANY` — Value to associate
- **alist** : `LIST` — Association list

**Returns:** `LIST` — Alist with the key set to val

## Extraction

### `assoc-keys`

Return all keys from an alist.

**Parameters:**

- **alist** : `LIST` — Association list

**Returns:** `LIST` — List of keys

### `assoc-vals`

Return all values from an alist.

**Parameters:**

- **alist** : `LIST` — Association list

**Returns:** `LIST` — List of values

## Transformation

### `assoc-map`

Apply a function to every value in an alist, preserving keys.

**Parameters:**

- **f** : `CALLABLE` — Function applied to each value
- **alist** : `LIST` — Association list

**Returns:** `LIST` — New alist with transformed values

### `assoc-filter`

Keep only entries satisfying a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate: (entry) -> bool
- **alist** : `LIST` — Association list

**Returns:** `LIST` — Filtered alist

### `assoc-merge`

Merge two alists; keys in the first take priority.

**Parameters:**

- **a** : `LIST` — Base alist (takes priority)
- **b** : `LIST` — Alist to merge in

**Returns:** `LIST` — Merged alist; entries in a shadow those in b

### `assoc-pick`

Select entries whose keys appear in a given list.

**Parameters:**

- **keys** : `LIST` — List of keys to keep
- **alist** : `LIST` — Association list

**Returns:** `LIST` — Alist containing only the selected keys

### `assoc-omit`

Remove entries whose keys appear in a given list.

**Parameters:**

- **keys** : `LIST` — List of keys to exclude
- **alist** : `LIST` — Association list

**Returns:** `LIST` — Alist without the excluded keys

## Conversion

### `from-pairs`

Convert a list of (key value) lists into an alist of dotted pairs.

**Parameters:**

- **lst** : `LIST` — List of two-element lists

**Returns:** `LIST` — Association list

### `to-pairs`

Convert an alist of dotted pairs into a list of (key value) lists.

**Parameters:**

- **alist** : `LIST` — Association list

**Returns:** `LIST` — List of two-element lists

### `evolve`

Apply per-key transform functions to values in an alist.

**Parameters:**

- **fns** : `LIST` — Alist of key -> transform function
- **alist** : `LIST` — Association list to transform

**Returns:** `LIST` — Alist with selected values transformed

