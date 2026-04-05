[← Index](../../index.md)

# x/core/list

List processing: map, filter, fold, sort, and 60+ functions.

> Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.

### `as-list`

Convert any iterable to a list. Lists and nil pass through unchanged.

**Returns:** `LIST` — The input as a proper list

## Folds

### `fold`

Fold a function over a list from the left.

**Parameters:**

- **f** : `CALLABLE` — Binary function: (accumulator, element) -> new accumulator
- **init** : `ANY` — Initial accumulator value
- **lst** : `LIST` — List or iterable to fold over

**Returns:** `ANY` — Final accumulated value

**Examples:**

```
(fold + 0 '(1 2 3)) => 6
```

### `reduce`

Fold without an initial value; uses the first element.

**Parameters:**

- **f** : `CALLABLE` — Binary function
- **lst** : `LIST` — Non-empty list or iterable

### `scan`

Like fold, but returns a list of all intermediate values.

**Parameters:**

- **f** : `CALLABLE` — Binary function
- **init** : `ANY` — Initial accumulator value
- **lst** : `LIST` — List or iterable

## Basics

### `length`

Return the number of elements.

**Parameters:**

- **lst** : `LIST` — List or iterable

### `nth`

Return the element at index n (zero-based).

**Parameters:**

- **n** : `INT` — Zero-based index
- **lst** : `LIST` — List

### `last`

Return the last element of a list.

**Parameters:**

- **lst** : `LIST` — Non-empty list

### `init`

Return all elements except the last.

**Parameters:**

- **lst** : `LIST` — Non-empty list

### `append`

Concatenate zero or more lists.

### `prepend`

Add an element to the front of a list.

**Parameters:**

- **x** : `ANY` — Element to prepend
- **lst** : `LIST` — List

### `reverse`

Reverse a list.

**Parameters:**

- **lst** : `LIST` — List or iterable

### `flatten`

Recursively flatten nested lists into a single list.

**Parameters:**

- **lst** : `LIST` — Nested list

## Iteration

### `map`

Apply a function to each element. Supports multiple lists.

**Parameters:**

- **f** : `CALLABLE` — Function to apply

**Returns:** `LIST` — New list

### `filter`

Return elements that satisfy a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

**Returns:** `LIST` — Filtered list

### `for-each`

Apply a function to each element for side effects.

**Parameters:**

- **f** : `CALLABLE` — Function to apply

### `flat-map`

Map then flatten one level.

**Parameters:**

- **f** : `CALLABLE` — Function returning a list
- **lst** : `LIST` — List or iterable

## Predicates

### `any?`

Return #t if any element satisfies the predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

### `every?`

Return #t if all elements satisfy the predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

### `none?`

Return #t if no element satisfies the predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

### `empty?`

Return #t if the list is empty.

**Parameters:**

- **lst** : `LIST` — List

## Combinators

### `complement`

Return a function that negates a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate to negate

**Returns:** `CALLABLE` — Negated predicate

### `partial`

Partially apply a function with leading arguments.

**Parameters:**

- **f** : `CALLABLE` — Function to partially apply

**Returns:** `CALLABLE` — Partially applied function

### `juxt`

Create a function that applies multiple functions and collects results.

**Returns:** `CALLABLE` — Juxtaposed function

### `both`

Combine two predicates with AND.

**Parameters:**

- **f** : `CALLABLE` — First predicate
- **g** : `CALLABLE` — Second predicate

**Returns:** `CALLABLE` — Combined predicate

### `either`

Combine two predicates with OR.

**Parameters:**

- **f** : `CALLABLE` — First predicate
- **g** : `CALLABLE` — Second predicate

**Returns:** `CALLABLE` — Combined predicate

### `all-pass`

Return a predicate that passes when all predicates pass.

**Parameters:**

- **preds** : `LIST` — List of predicates

**Returns:** `CALLABLE` — Combined predicate

### `any-pass`

Return a predicate that passes when any predicate passes.

**Parameters:**

- **preds** : `LIST` — List of predicates

**Returns:** `CALLABLE` — Combined predicate

### `reject`

Return elements that do NOT satisfy a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List

**Returns:** `LIST` — Filtered list

### `concat`

Concatenate all argument lists into one.

**Returns:** `LIST` — Concatenated list

### `sum`

Sum all elements of a list.

**Parameters:**

- **lst** : `LIST` — List of numbers

**Returns:** `INT` — Sum

### `product`

Multiply all elements of a list.

**Parameters:**

- **lst** : `LIST` — List of numbers

**Returns:** `INT` — Product

## Search

### `find`

Return the first element satisfying a predicate, or nil.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

### `find-index`

Return the index of the first element satisfying a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

**Returns:** `INT` — Index, or -1 if not found

### `index-of`

Return the index of the first occurrence of a value.

**Parameters:**

- **x** : `ANY` — Value to find
- **lst** : `LIST` — List

**Returns:** `INT` — Index, or -1 if not found

### `includes?`

Test if a list contains a value.

**Parameters:**

- **x** : `ANY` — Value to search for
- **lst** : `LIST` — List or iterable

**Returns:** `BOOLEAN` — t if found

### `count`

Count elements satisfying a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List or iterable

**Returns:** `INT` — Count of matching elements

## Slicing

### `take`

Take the first n elements of a list.

**Parameters:**

- **n** : `INT` — Number of elements
- **lst** : `LIST` — List

### `drop`

Drop the first n elements of a list.

**Parameters:**

- **n** : `INT` — Number of elements to skip
- **lst** : `LIST` — List

### `take-while`

Take elements from the front while predicate holds.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List

### `drop-while`

Drop elements from the front while predicate holds.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List

### `split-at`

Split a list at position n.

**Parameters:**

- **n** : `INT` — Split position
- **lst** : `LIST` — List

**Returns:** `LIST` — Pair of (taken dropped)

### `slice`

Extract a slice from start to end.

**Parameters:**

- **start** : `INT` — Start index (inclusive)
- **end** : `INT` — End index (exclusive)
- **lst** : `LIST` — List

## Generators

### `range`

Generate a list of integers from start to end.

**Parameters:**

- **start** : `INT` — Start value (inclusive)
- **end** : `INT` — End value (exclusive)

**Returns:** `LIST` — List of integers

**Examples:**

```
(range 0 5) => (0 1 2 3 4)
```

### `repeat`

Create a list of n copies of a value.

**Parameters:**

- **x** : `ANY` — Value to repeat
- **n** : `INT` — Number of repetitions

**Returns:** `LIST` — List of repeated values

### `times`

Apply a function to each index 0..n-1, collecting results.

**Parameters:**

- **f** : `CALLABLE` — Function: index -> value
- **n** : `INT` — Number of iterations

**Returns:** `LIST` — List of results

### `unfold`

Build a list by repeatedly applying step and value functions to a seed.

**Parameters:**

- **pred** : `CALLABLE` — Stop predicate: seed -> boolean
- **f** : `CALLABLE` — Value function: seed -> element
- **g** : `CALLABLE` — Step function: seed -> next-seed
- **seed** : `ANY` — Initial seed value

**Returns:** `LIST` — Generated list

### `iterate`

Generate n values by repeatedly applying f.

**Parameters:**

- **f** : `CALLABLE` — Step function
- **n** : `INT` — Number of iterations
- **x** : `ANY` — Initial value

**Returns:** `LIST` — List of iterated values

### `zip`

Pair up corresponding elements from two lists.

**Parameters:**

- **a** : `LIST` — First list
- **b** : `LIST` — Second list

**Returns:** `LIST` — List of pairs

### `zip-with`

Combine corresponding elements from two lists using a function.

**Parameters:**

- **f** : `CALLABLE` — Combining function
- **a** : `LIST` — First list
- **b** : `LIST` — Second list

**Returns:** `LIST` — Combined list

## Transformation

### `partition`

Split a list into elements that match and don't match a predicate.

**Parameters:**

- **pred** : `CALLABLE` — Predicate function
- **lst** : `LIST` — List

### `group-by`

Group list elements by a key function.

**Parameters:**

- **f** : `CALLABLE` — Key function: element -> group key
- **lst** : `LIST` — List

**Returns:** `LIST` — Alist of (key . elements)

### `sort`

Merge sort a list using a comparison function.

**Parameters:**

- **cmp** : `CALLABLE` — Comparison: (a b) -> #t if a comes first
- **lst** : `LIST` — List or iterable

### `sort-by`

Sort by a key function (ascending).

**Parameters:**

- **f** : `CALLABLE` — Key function: element -> comparable value
- **lst** : `LIST` — List

### `uniq`

Remove consecutive duplicates from a sorted list.

**Parameters:**

- **lst** : `LIST` — Sorted list

### `uniq-by`

Remove consecutive duplicates by key function.

**Parameters:**

- **f** : `CALLABLE` — Key function
- **lst** : `LIST` — Sorted list

### `intersperse`

Insert a separator between each element.

**Parameters:**

- **sep** : `ANY` — Separator element
- **lst** : `LIST` — List

### `transpose`

Transpose rows and columns of a list of lists.

**Parameters:**

- **lsts** : `LIST` — List of lists

**Returns:** `LIST` — Transposed list of lists

### `update`

Replace the element at index n.

**Parameters:**

- **n** : `INT` — Index to update
- **val** : `ANY` — New value
- **lst** : `LIST` — List

### `insert`

Insert a value at index n.

**Parameters:**

- **n** : `INT` — Insertion index
- **val** : `ANY` — Value to insert
- **lst** : `LIST` — List

### `remove`

Remove n elements starting at index.

**Parameters:**

- **start** : `INT` — Start index
- **n** : `INT` — Number of elements to remove
- **lst** : `LIST` — List

### `adjust`

Apply a function to the element at index n.

**Parameters:**

- **n** : `INT` — Index to adjust
- **f** : `CALLABLE` — Transformation function
- **lst** : `LIST` — List

## Type predicate

### `list?`

Test if a value is a proper list.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if proper list

## Membership

### `memq`

Find first occurrence by identity (eq?). Returns the tail from match, or #f.

**Parameters:**

- **x** : `ANY` — Value to search for
- **lst** : `LIST` — List

### `member`

Find first occurrence by equality (equal?). Returns the tail from match, or #f.

**Parameters:**

- **x** : `ANY` — Value to search for
- **lst** : `LIST` — List

## Association

### `assq`

Look up a key in an alist by identity (eq?).

**Parameters:**

- **key** : `ANY` — Key to search for
- **alist** : `LIST` — Association list

### `assoc`

Look up a key in an alist by equality (equal?).

**Parameters:**

- **key** : `ANY` — Key to search for
- **alist** : `LIST` — Association list

### `second`

Return the second element of a list.

**Returns:** `ANY` — The second element

### `third`

Return the third element of a list.

**Returns:** `ANY` — The third element

### `else`

Alias for #t, for use as the default clause in cond/case.

### `list-ref`

Return the nth element of a list (Scheme compatibility).

**Returns:** `ANY` — The element at index n

### `list-tail`

Return the tail of a list after n elements (Scheme compatibility).

**Returns:** `LIST` — The remaining list after dropping n elements

### `str-copy`

Return a copy of a string (Scheme compatibility).

**Returns:** `STRING` — A copy of the string

