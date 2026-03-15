# Computational Expressions in C

## Standard Library

The x standard library (`lib/x.x`) provides ~80 functions organized into 16 sections. It is loaded automatically and defines the core functional programming vocabulary for x-lang.

**Library version:** `0.2.0`

---

## 1. Functional Combinators

### `identity`
`(identity x) -> x`
Returns its argument unchanged.
```
(identity 42) -> 42
```

### `const`
`(const x) -> (fn (y) x)`
Returns a function that always returns `x`, ignoring its argument.
```
((const 5) 99) -> 5
```

### `compose`
`(compose f g) -> (fn (x) (f (g x)))`
Returns a function that applies `g` then `f` (right-to-left composition).
```
((compose inc inc) 3) -> 5
```

### `pipe`
`(pipe f g) -> (fn (x) (g (f x)))`
Returns a function that applies `f` then `g` (left-to-right composition).
```
((pipe inc inc) 3) -> 5
```

### `curry`
`(curry f x) -> (fn (y) (f x y))`
Partially applies a two-argument function by fixing its first argument.
```
((curry + 10) 5) -> 15
```

### `flip`
`(flip f) -> (fn (a b) (f b a))`
Returns a function that calls `f` with its two arguments reversed.
```
((flip -) 1 10) -> 9
```

### `tap`
`(tap f) -> (fn (x) ...x)`
Returns a function that applies `f` to its argument for side effects, then returns the argument.
```
((tap print) 42) -> 42
```

---

## 2. Math

### `inc`
`(inc n) -> number`
Increments a number by one.
```
(inc 5) -> 6
```

### `dec`
`(dec n) -> number`
Decrements a number by one.
```
(dec 5) -> 4
```

### `negate`
`(negate n) -> number`
Returns the arithmetic negation of a number.
```
(negate 7) -> -7
```

### `abs`
`(abs n) -> number`
Returns the absolute value of a number.
```
(abs -3) -> 3
```

### `min`
`(min a b) -> number`
Returns the smaller of two numbers.
```
(min 3 7) -> 3
```

### `max`
`(max a b) -> number`
Returns the larger of two numbers.
```
(max 3 7) -> 7
```

### `clamp`
`(clamp lo hi n) -> number`
Clamps a number to the inclusive range `[lo, hi]`.
```
(clamp 0 10 15) -> 10
```

### `min-by`
`(min-by f a b) -> a | b`
Returns whichever of `a` or `b` is smaller when compared by applying `f`.
```
(min-by abs -5 3) -> 3
```

### `max-by`
`(max-by f a b) -> a | b`
Returns whichever of `a` or `b` is larger when compared by applying `f`.
```
(max-by abs -5 3) -> -5
```

---

## 3. Number Predicates

### `zero?`
`(zero? n) -> boolean`
Returns `#t` if the number is zero.
```
(zero? 0) -> #t
```

### `positive?`
`(positive? n) -> boolean`
Returns `#t` if the number is greater than zero.
```
(positive? 5) -> #t
```

### `negative?`
`(negative? n) -> boolean`
Returns `#t` if the number is less than zero.
```
(negative? -3) -> #t
```

### `even?`
`(even? n) -> boolean`
Returns `#t` if the number is even.
```
(even? 4) -> #t
```

### `odd?`
`(odd? n) -> boolean`
Returns `#t` if the number is odd.
```
(odd? 3) -> #t
```

---

## 4. Boolean / Logic

### `boolean?`
`(boolean? x) -> boolean`
Returns `#t` if `x` is `#t` or `()` (the two canonical boolean values).
```
(boolean? #t) -> #t
```

### `default-to`
`(default-to d x) -> x | d`
Returns `x` unless it is nil, in which case returns the default value `d`.
```
(default-to 0 ()) -> 0
```

### `until`
`(until pred f x) -> value`
Repeatedly applies `f` to `x` until `pred` returns true, then returns the value.
```
(until (fn (n) (> n 10)) inc 1) -> 11
```

### `equal?`
`(equal? a b) -> boolean`
Structural equality that compares numbers by value, strings by content, and everything else by identity.
```
(equal? 3 3) -> #t
```

---

## 5. List Folds

### `fold`
`(fold f init lst) -> value`
Left fold: reduces a list to a single value by applying `f` to the accumulator and each element.
```
(fold + 0 (list 1 2 3)) -> 6
```

### `reduce`
`(reduce f lst) -> value`
Left fold using the first element as the initial accumulator.
```
(reduce + (list 1 2 3)) -> 6
```

### `scan`
`(scan f init lst) -> list`
Like `fold`, but collects all intermediate accumulator values into a list.
```
(scan + 0 (list 1 2 3)) -> (0 1 3 6)
```

---

## 6. List Basics

### `length`
`(length lst) -> number`
Returns the number of elements in a list.
```
(length (list 1 2 3)) -> 3
```

### `nth`
`(nth n lst) -> value`
Returns the element at zero-based index `n`.
```
(nth 1 (list 10 20 30)) -> 20
```

### `last`
`(last lst) -> value`
Returns the last element of a list.
```
(last (list 1 2 3)) -> 3
```

### `init`
`(init lst) -> list`
Returns all elements except the last.
```
(init (list 1 2 3)) -> (1 2)
```

### `append`
`(append a b) -> list`
Concatenates two lists.
```
(append (list 1 2) (list 3 4)) -> (1 2 3 4)
```

### `prepend`
`(prepend x lst) -> list`
Adds an element to the front of a list.
```
(prepend 0 (list 1 2)) -> (0 1 2)
```

### `reverse`
`(reverse lst) -> list`
Returns a list with elements in reverse order.
```
(reverse (list 1 2 3)) -> (3 2 1)
```

### `flatten`
`(flatten lst) -> list`
Recursively flattens nested lists into a single flat list.
```
(flatten (list 1 (list 2 (list 3)))) -> (1 2 3)
```

---

## 7. List Iteration

### `map`
`(map f lst) -> list`
Applies `f` to each element and returns a list of results.
```
(map inc (list 1 2 3)) -> (2 3 4)
```

### `filter`
`(filter pred lst) -> list`
Returns a list of elements for which `pred` returns true.
```
(filter even? (list 1 2 3 4)) -> (2 4)
```

### `for-each`
`(for-each f lst) -> ()`
Applies `f` to each element for side effects only.
```
(for-each print (list 1 2 3)) -> ()
```

### `flat-map`
`(flat-map f lst) -> list`
Maps `f` over the list and flattens one level of nesting from the results.
```
(flat-map (fn (x) (list x x)) (list 1 2)) -> (1 1 2 2)
```

---

## 8. List Predicates

### `any?`
`(any? pred lst) -> boolean`
Returns `#t` if `pred` is true for at least one element.
```
(any? even? (list 1 3 4)) -> #t
```

### `every?`
`(every? pred lst) -> boolean`
Returns `#t` if `pred` is true for all elements.
```
(every? even? (list 2 4 6)) -> #t
```

### `none?`
`(none? pred lst) -> boolean`
Returns `#t` if `pred` is false for all elements.
```
(none? even? (list 1 3 5)) -> #t
```

### `empty?`
`(empty? lst) -> boolean`
Returns `#t` if the list is nil.
```
(empty? ()) -> #t
```

---

## 9. Higher-Order Combinators

### `complement`
`(complement pred) -> function`
Returns a function that negates the result of `pred`.
```
((complement even?) 3) -> #t
```

### `partial`
`(partial f . bound) -> function`
Returns a function with the leading arguments of `f` pre-filled.
```
((partial + 10) 5) -> 15
```

### `juxt`
`(juxt . fns) -> function`
Returns a function that applies each of `fns` to its arguments and collects the results in a list.
```
((juxt inc dec) 5) -> (6 4)
```

### `both`
`(both f g) -> function`
Returns a predicate that is true when both `f` and `g` return true.
```
((both positive? even?) 4) -> #t
```

### `either`
`(either f g) -> function`
Returns a predicate that is true when either `f` or `g` returns true.
```
((either positive? even?) -2) -> #t
```

### `all-pass`
`(all-pass preds) -> function`
Returns a predicate that is true when all predicates in the list pass.
```
((all-pass (list positive? even?)) 4) -> #t
```

### `any-pass`
`(any-pass preds) -> function`
Returns a predicate that is true when any predicate in the list passes.
```
((any-pass (list positive? even?)) -2) -> #t
```

### `reject`
`(reject pred lst) -> list`
Returns elements for which `pred` is false (complement of `filter`).
```
(reject even? (list 1 2 3 4)) -> (1 3)
```

### `concat`
`(concat . lsts) -> list`
Concatenates zero or more lists into one.
```
(concat (list 1 2) (list 3) (list 4 5)) -> (1 2 3 4 5)
```

### `sum`
`(sum lst) -> number`
Returns the sum of all numbers in a list.
```
(sum (list 1 2 3)) -> 6
```

### `product`
`(product lst) -> number`
Returns the product of all numbers in a list.
```
(product (list 2 3 4)) -> 24
```

---

## 10. List Search

### `find`
`(find pred lst) -> value | ()`
Returns the first element matching `pred`, or `()` if none found.
```
(find even? (list 1 3 4 6)) -> 4
```

### `find-index`
`(find-index pred lst) -> number`
Returns the zero-based index of the first element matching `pred`, or `-1` if none found.
```
(find-index even? (list 1 3 4)) -> 2
```

### `index-of`
`(index-of x lst) -> number`
Returns the zero-based index of the first element equal to `x`, or `-1` if not found.
```
(index-of 3 (list 1 2 3 4)) -> 2
```

### `includes?`
`(includes? x lst) -> boolean`
Returns `#t` if `x` is found in the list using structural equality.
```
(includes? 3 (list 1 2 3)) -> #t
```

### `count`
`(count pred lst) -> number`
Returns the number of elements for which `pred` returns true.
```
(count even? (list 1 2 3 4)) -> 2
```

---

## 11. List Slicing

### `take`
`(take n lst) -> list`
Returns the first `n` elements of a list.
```
(take 2 (list 1 2 3 4)) -> (1 2)
```

### `drop`
`(drop n lst) -> list`
Returns the list with the first `n` elements removed.
```
(drop 2 (list 1 2 3 4)) -> (3 4)
```

### `take-while`
`(take-while pred lst) -> list`
Returns the longest prefix of elements for which `pred` holds.
```
(take-while odd? (list 1 3 4 5)) -> (1 3)
```

### `drop-while`
`(drop-while pred lst) -> list`
Drops the longest prefix of elements for which `pred` holds.
```
(drop-while odd? (list 1 3 4 5)) -> (4 5)
```

### `split-at`
`(split-at n lst) -> (list list)`
Splits a list at index `n`, returning a pair of the taken and dropped portions.
```
(split-at 2 (list 1 2 3 4)) -> ((1 2) (3 4))
```

### `slice`
`(slice start end lst) -> list`
Returns elements from index `start` up to (but not including) `end`.
```
(slice 1 3 (list 10 20 30 40)) -> (20 30)
```

---

## 12. List Generators

### `range`
`(range start end) -> list`
Generates a list of integers from `start` up to (but not including) `end`.
```
(range 0 5) -> (0 1 2 3 4)
```

### `repeat`
`(repeat x n) -> list`
Returns a list containing `x` repeated `n` times.
```
(repeat 0 3) -> (0 0 0)
```

### `times`
`(times f n) -> list`
Calls `f` with each index from `0` to `n-1` and collects the results.
```
(times identity 4) -> (0 1 2 3)
```

### `unfold`
`(unfold pred f g seed) -> list`
Builds a list by repeatedly applying `f` (value) and `g` (next seed) until `pred` returns true.
```
(unfold (fn (x) (> x 3)) identity inc 1) -> (1 2 3)
```

### `iterate`
`(iterate f n x) -> list`
Returns a list of `n` values starting with `x`, each subsequent value produced by applying `f`.
```
(iterate inc 4 0) -> (0 1 2 3)
```

### `zip`
`(zip a b) -> list`
Pairs corresponding elements from two lists into a list of two-element lists.
```
(zip (list 1 2 3) (list 4 5 6)) -> ((1 4) (2 5) (3 6))
```

### `zip-with`
`(zip-with f a b) -> list`
Combines corresponding elements from two lists using `f`.
```
(zip-with + (list 1 2 3) (list 10 20 30)) -> (11 22 33)
```

---

## 13. List Transformation

### `partition`
`(partition pred lst) -> (list list)`
Splits a list into two lists: elements satisfying `pred` and elements that do not.
```
(partition even? (list 1 2 3 4)) -> ((2 4) (1 3))
```

### `group-by`
`(group-by f lst) -> alist`
Groups elements into an association list keyed by the result of applying `f`.
```
(group-by even? (list 1 2 3 4)) -> ((() 1 3) (#t 2 4))
```

### `sort`
`(sort cmp lst) -> list`
Sorts a list using merge sort, where `cmp` is a two-argument comparison predicate.
```
(sort < (list 3 1 2)) -> (1 2 3)
```

### `sort-by`
`(sort-by f lst) -> list`
Sorts a list by comparing the results of applying `f` to each element.
```
(sort-by abs (list -3 1 -2)) -> (1 -2 -3)
```

### `uniq`
`(uniq lst) -> list`
Removes consecutive duplicate elements (the list should be sorted for full deduplication).
```
(uniq (list 1 1 2 2 3)) -> (1 2 3)
```

### `uniq-by`
`(uniq-by f lst) -> list`
Removes consecutive elements that are equal after applying `f`.
```
(uniq-by abs (list 1 -1 2 -2 3)) -> (1 2 3)
```

### `intersperse`
`(intersperse sep lst) -> list`
Inserts `sep` between every pair of adjacent elements.
```
(intersperse 0 (list 1 2 3)) -> (1 0 2 0 3)
```

### `transpose`
`(transpose lsts) -> list`
Transposes a list of lists (swaps rows and columns).
```
(transpose (list (list 1 2) (list 3 4))) -> ((1 3) (2 4))
```

### `update`
`(update n val lst) -> list`
Returns a new list with the element at index `n` replaced by `val`.
```
(update 1 99 (list 1 2 3)) -> (1 99 3)
```

### `insert`
`(insert n val lst) -> list`
Returns a new list with `val` inserted at index `n`.
```
(insert 1 99 (list 1 2 3)) -> (1 99 2 3)
```

### `remove`
`(remove start n lst) -> list`
Returns a new list with `n` elements removed starting at index `start`.
```
(remove 1 2 (list 1 2 3 4)) -> (1 4)
```

### `adjust`
`(adjust n f lst) -> list`
Returns a new list with the element at index `n` transformed by `f`.
```
(adjust 1 inc (list 10 20 30)) -> (10 21 30)
```

---

## 14. Association Lists

Association lists (alists) are lists of pairs `((key . val) ...)` where keys are compared with `eq?` (symbol/pointer equality).

### `aget`
`(aget key alist) -> value | ()`
Looks up `key` in the alist, returning its value or `()` if not found.
```
(aget 'b (list (pair 'a 1) (pair 'b 2))) -> 2
```

### `aget-or`
`(aget-or d key alist) -> value`
Like `aget`, but returns default `d` if the key is not found.
```
(aget-or 0 'z (list (pair 'a 1))) -> 0
```

### `ahas?`
`(ahas? key alist) -> boolean`
Returns `#t` if the alist contains an entry for `key`.
```
(ahas? 'a (list (pair 'a 1))) -> #t
```

### `adel`
`(adel key alist) -> alist`
Returns a new alist with all entries for `key` removed.
```
(adel 'a (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `aset`
`(aset key val alist) -> alist`
Sets `key` to `val` in the alist, replacing any existing entry for that key.
```
(aset 'a 99 (list (pair 'a 1) (pair 'b 2))) -> ((a . 99) (b . 2))
```

### `akeys`
`(akeys alist) -> list`
Returns a list of all keys in the alist.
```
(akeys (list (pair 'a 1) (pair 'b 2))) -> (a b)
```

### `avals`
`(avals alist) -> list`
Returns a list of all values in the alist.
```
(avals (list (pair 'a 1) (pair 'b 2))) -> (1 2)
```

### `amap`
`(amap f alist) -> alist`
Applies `f` to each value in the alist, preserving keys.
```
(amap inc (list (pair 'a 1) (pair 'b 2))) -> ((a . 2) (b . 3))
```

### `afilter`
`(afilter pred alist) -> alist`
Filters alist entries by a predicate applied to each `(key . val)` pair.
```
(afilter (fn (e) (> (rest e) 1)) (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `amerge`
`(amerge a b) -> alist`
Merges alist `b` into `a`, keeping entries from `a` when keys collide.
```
(amerge (list (pair 'a 1)) (list (pair 'a 9) (pair 'b 2))) -> ((a . 1) (b . 2))
```

### `apick`
`(apick keys alist) -> alist`
Returns only the entries whose keys appear in the `keys` list.
```
(apick (list 'a) (list (pair 'a 1) (pair 'b 2))) -> ((a . 1))
```

### `aomit`
`(aomit keys alist) -> alist`
Returns the alist with entries for the given keys removed.
```
(aomit (list 'a) (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `from-pairs`
`(from-pairs lst) -> alist`
Converts a list of two-element lists into an alist of dotted pairs.
```
(from-pairs (list (list 'a 1) (list 'b 2))) -> ((a . 1) (b . 2))
```

### `to-pairs`
`(to-pairs alist) -> list`
Converts an alist of dotted pairs into a list of two-element lists.
```
(to-pairs (list (pair 'a 1) (pair 'b 2))) -> ((a 1) (b 2))
```

### `evolve`
`(evolve fns alist) -> alist`
Applies transformation functions from the `fns` alist to matching keys in the data alist.
```
(evolve (list (pair 'a inc)) (list (pair 'a 1) (pair 'b 2))) -> ((a . 2) (b . 2))
```

---

## 15. String Utilities

### `string-empty?`
`(string-empty? s) -> boolean`
Returns `#t` if the string has zero length.
```
(string-empty? "") -> #t
```

### `string-join`
`(string-join sep lst) -> string`
Joins a list of strings with `sep` between each pair.
```
(string-join ", " (list "a" "b" "c")) -> "a, b, c"
```

### `string-repeat`
`(string-repeat s n) -> string`
Returns the string `s` repeated `n` times.
```
(string-repeat "ab" 3) -> "ababab"
```

### `string-contains?`
`(string-contains? sub s) -> boolean`
Returns `#t` if `sub` is found anywhere within `s`.
```
(string-contains? "ell" "hello") -> #t
```

### `string-starts?`
`(string-starts? pfx s) -> boolean`
Returns `#t` if `s` starts with the prefix `pfx`.
```
(string-starts? "he" "hello") -> #t
```

### `string-ends?`
`(string-ends? sfx s) -> boolean`
Returns `#t` if `s` ends with the suffix `sfx`.
```
(string-ends? "lo" "hello") -> #t
```

### `string-reverse`
`(string-reverse s) -> string`
Returns the string with characters in reverse order.
```
(string-reverse "hello") -> "olleh"
```

---

## 16. Vectors

Vectors are fixed-size, indexed collections backed by lists, created via the `make-type` mechanism. They display as `#(...)`.

### `vector`
`(vector . args) -> vector`
Creates a new vector from the given arguments.
```
(vector 1 2 3) -> #(1 2 3)
```

### `vector?`
`(vector? x) -> boolean`
Returns `#t` if `x` is a vector.
```
(vector? (vector 1 2)) -> #t
```

### `vector-ref`
`(vector-ref v i) -> value`
Returns the element at zero-based index `i` from vector `v`.
```
(vector-ref (vector 10 20 30) 1) -> 20
```

### `vector-length`
`(vector-length v) -> number`
Returns the number of elements in the vector.
```
(vector-length (vector 1 2 3)) -> 3
```

### `vector->list`
`(vector->list v) -> list`
Converts a vector to a list.
```
(vector->list (vector 1 2 3)) -> (1 2 3)
```

### `list->vector`
`(list->vector lst) -> vector`
Converts a list to a vector.
```
(list->vector (list 1 2 3)) -> #(1 2 3)
```

### `make-vector`
`(make-vector n fill) -> vector`
Creates a vector of length `n` with every element set to `fill`.
```
(make-vector 3 0) -> #(0 0 0)
```
