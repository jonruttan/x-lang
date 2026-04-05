[← Index](../../index.md)

# x/type/vector

Fixed-size indexed vectors.

> Literal syntax: #(1 2 3). Supports negative indexing.

## Constructors

### `vector`

Create a vector from the given arguments.

**Returns:** `VECTOR` — New vector containing the arguments

### `make-vector`

Create a vector of length n, with every element set to fill.

**Parameters:**

- **n** : `INT` — Number of elements
- **fill** : `ANY` — Value to fill each slot with

**Returns:** `VECTOR` — New vector of length n filled with fill

## Predicates

### `vector?`

Test whether a value is a vector.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOL` — True if x is a vector

## Access

### `vector-ref`

Return the element at index i of a vector.

**Parameters:**

- **v** : `VECTOR` — Vector
- **i** : `INT` — Zero-based index

**Returns:** `ANY` — Element at index i

### `vector-length`

Return the number of elements in a vector.

**Parameters:**

- **v** : `VECTOR` — Vector

**Returns:** `INT` — Number of elements

## Conversion

### `vector->list`

Convert a vector to a list.

**Parameters:**

- **v** : `VECTOR` — Vector to convert

**Returns:** `LIST` — List of the vector's elements

### `list->vector`

Convert a list to a vector.

**Parameters:**

- **lst** : `LIST` — List to convert

**Returns:** `VECTOR` — New vector containing the list's elements

