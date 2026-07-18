# Computational Expressions in C

## Standard Library

The x-lang library is modular: 100+ modules (one module = one `provide`-ing `.x` source file) organized across `lib/x/boot/`, `lib/x/core/`, `lib/x/type/`, `lib/x/protocol/`, `lib/x/num/`, `lib/x/sys/`, `lib/x/doc/`, `lib/x/tool/`, and `lib/x/platform/`. The bootstrap loader `lib/x-core.x` pre-registers all paths and loads 40+ core modules via `provide`/`import` with deduplication.

This document covers the core functions loaded by `lib/x.x` (the base x-lang dialect). For the complete auto-generated reference covering all modules, run `make doc-x` and open `ref/x/index.md` (generated locally, not committed).

**Library version:** `0.2.0`

### Module Categories

| Category | Path | Contents |
|----------|------|----------|
| Boot | `lib/x/boot/` | Operatives, data constructors, strings, module system |
| Core | `lib/x/core/` | Combinators, lists (60+ functions), logic, math, syntax, control, quasiquote, REPL |
| Types | `lib/x/type/` | Characters, strings, vectors, promises, regex, objects, iterators |
| Numeric | `lib/x/num/` | Bignum, float, rational, complex, tower helpers |
| System | `lib/x/sys/` | POSIX, FFI, tokenizer, type system, conversions, GC, file I/O |
| Tools | `lib/x/tool/` | Linter, formatter, coverage, profiler, compiler, assembler |
| Docs | `lib/x/doc/` | Inline documentation, doc generator, primitive docs |
| Platform | `lib/x/platform/` | x86_64, ARM64, syscall tables, sockets |

---

## 1. Functional Combinators

Homed on the `Fn` class — call as `(Fn <method> ...)`. To pass a combinator itself as a value, wrap it, e.g. `(method-ref Fn identity)`.

### `Fn identity`
`(Fn identity x) -> x`
Returns its argument unchanged.
```
(Fn identity 42) -> 42
```

### `Fn const`
`(Fn const x) -> (fn (_ y) x)`
Returns a function that always returns `x`, ignoring its argument.
```
((Fn const 5) 99) -> 5
```

### `Fn compose`
`(Fn compose f g) -> (fn (_ x) (f (g x)))`
Returns a function that applies `g` then `f` (right-to-left composition).
```
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn pipe`
`(Fn pipe f g) -> (fn (_ x) (g (f x)))`
Returns a function that applies `f` then `g` (left-to-right composition).
```
((Fn pipe (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn curry`
`(Fn curry f x) -> (fn (_ y) (f x y))`
Partially applies a two-argument function by fixing its first argument.
```
((Fn curry + 10) 5) -> 15
```

### `Fn flip`
`(Fn flip f) -> (fn (_ a b) (f b a))`
Returns a function that calls `f` with its two arguments reversed.
```
((Fn flip -) 1 10) -> 9
```

### `Fn tap`
`(Fn tap f) -> (fn (_ x) ...x)`
Returns a function that applies `f` to its argument for side effects, then returns the argument.
```
((Fn tap print) 42) -> 42
```

---

## 2. Math

### `Num inc`
`(Num inc n) -> number`
Increments a number by one.
```
(Num inc 5) -> 6
```

### `Num dec`
`(Num dec n) -> number`
Decrements a number by one.
```
(Num dec 5) -> 4
```

### `Num negate`
`(Num negate n) -> number`
Returns the arithmetic negation of a number.
```
(Num negate 7) -> -7
```

### `Num abs`
`(Num abs n) -> number`
Returns the absolute value of a number.
```
(Num abs -3) -> 3
```

### `Num min`
`(Num min a b) -> number`
Returns the smaller of two numbers.
```
(Num min 3 7) -> 3
```

### `Num max`
`(Num max a b) -> number`
Returns the larger of two numbers.
```
(Num max 3 7) -> 7
```

### `Num clamp`
`(Num clamp lo hi n) -> number`
Clamps a number to the inclusive range `[lo, hi]`.
```
(Num clamp 0 10 15) -> 10
```

### `Num min-by`
`(Num min-by f a b) -> a | b`
Returns whichever of `a` or `b` is smaller when compared by applying `f`.
```
(Num min-by (method-ref Num abs) -5 3) -> 3
```

### `Num max-by`
`(Num max-by f a b) -> a | b`
Returns whichever of `a` or `b` is larger when compared by applying `f`.
```
(Num max-by (method-ref Num abs) -5 3) -> -5
```

---

## 3. Number Predicates

### `Num zero?`
`(Num zero? n) -> boolean`
Returns `#t` if the number is zero.
```
(Num zero? 0) -> #t
```

### `Num positive?`
`(Num positive? n) -> boolean`
Returns `#t` if the number is greater than zero.
```
(Num positive? 5) -> #t
```

### `Num negative?`
`(Num negative? n) -> boolean`
Returns `#t` if the number is less than zero.
```
(Num negative? -3) -> #t
```

### `Num even?`
`(Num even? n) -> boolean`
Returns `#t` if the number is even.
```
(Num even? 4) -> #t
```

### `Num odd?`
`(Num odd? n) -> boolean`
Returns `#t` if the number is odd.
```
(Num odd? 3) -> #t
```

---

## 4. Boolean / Logic

### `boolean?`
`(boolean? x) -> boolean`
Returns `#t` if `x` is `#t` or `#f`.
```
(boolean? #t) -> #t
```

### `Fn default-to`
`(Fn default-to d x) -> x | d`
Returns `x` unless it is nil, in which case returns the default value `d`.
```
(Fn default-to 0 ()) -> 0
```

### `Fn until`
`(Fn until pred f x) -> value`
Repeatedly applies `f` to `x` until `pred` returns true, then returns the value.
```
(Fn until (fn (_ n) (> n 10)) (method-ref Num inc) 1) -> 11
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

### `List reduce`
`(List reduce f lst) -> value`
Left fold using the first element as the initial accumulator.
```
(List reduce + (list 1 2 3)) -> 6
```

### `List scan`
`(List scan f init lst) -> list`
Like `fold`, but collects all intermediate accumulator values into a list.
```
(List scan + 0 (list 1 2 3)) -> (0 1 3 6)
```

---

## 6. List Basics

### `length`
`(length lst) -> number`
Returns the number of elements in a list.
```
(length (list 1 2 3)) -> 3
```

### `List ref`
`(List ref n lst) -> value`
Returns the element at zero-based index `n`.
```
(List ref 1 (list 10 20 30)) -> 20
```

### `List last`
`(List last lst) -> value`
Returns the last element of a list.
```
(List last (list 1 2 3)) -> 3
```

### `List init`
`(List init lst) -> list`
Returns all elements except the last.
```
(List init (list 1 2 3)) -> (1 2)
```

### `append`
`(append a b) -> list`
Concatenates two lists.
```
(append (list 1 2) (list 3 4)) -> (1 2 3 4)
```

### `List prepend`
`(List prepend x lst) -> list`
Adds an element to the front of a list.
```
(List prepend 0 (list 1 2)) -> (0 1 2)
```

### `reverse`
`(reverse lst) -> list`
Returns a list with elements in reverse order.
```
(reverse (list 1 2 3)) -> (3 2 1)
```

### `List flatten`
`(List flatten lst) -> list`
Recursively flattens nested lists into a single flat list.
```
(List flatten (list 1 (list 2 (list 3)))) -> (1 2 3)
```

---

## 7. List Iteration

### `map`
`(map f lst) -> list`
Applies `f` to each element and returns a list of results.
```
(map (method-ref Num inc) (list 1 2 3)) -> (2 3 4)
```

### `filter`
`(filter pred lst) -> list`
Returns a list of elements for which `pred` returns true.
```
(filter (method-ref Num even?) (list 1 2 3 4)) -> (2 4)
```

### `for-each`
`(for-each f lst) -> ()`
Applies `f` to each element for side effects only.
```
(for-each print (list 1 2 3)) -> ()
```

### `List flat-map`
`(List flat-map f lst) -> list`
Maps `f` over the list and flattens one level of nesting from the results.
```
(List flat-map (fn (_ x) (list x x)) (list 1 2)) -> (1 1 2 2)
```

---

## 8. List Predicates

### `List any?`
`(List any? pred lst) -> boolean`
Returns `#t` if `pred` is true for at least one element.
```
(List any? even? (list 1 3 4)) -> #t
```

### `List all?`
`(List all? pred lst) -> boolean`
Returns `#t` if `pred` is true for all elements.
```
(List all? even? (list 2 4 6)) -> #t
```

### `List none?`
`(List none? pred lst) -> boolean`
Returns `#t` if `pred` is false for all elements.
```
(List none? even? (list 1 3 5)) -> #t
```

### `List empty?`
`(List empty? lst) -> boolean`
Returns `#t` if the list is nil.
```
(List empty? ()) -> #t
```

---

## 9. Higher-Order Combinators

### `Fn complement`
`(Fn complement pred) -> function`
Returns a function that negates the result of `pred`.
```
((Fn complement even?) 3) -> #t
```

### `Fn partial`
`(Fn partial f . bound) -> function`
Returns a function with the leading arguments of `f` pre-filled.
```
((Fn partial + 10) 5) -> 15
```

### `Fn juxt`
`(Fn juxt . fns) -> function`
Returns a function that applies each of `fns` to its arguments and collects the results in a list.
```
((Fn juxt (method-ref Num inc) (method-ref Num dec)) 5) -> (6 4)
```

### `Fn both`
`(Fn both f g) -> function`
Returns a predicate that is true when both `f` and `g` return true.
```
((Fn both positive? even?) 4) -> #t
```

### `Fn either`
`(Fn either f g) -> function`
Returns a predicate that is true when either `f` or `g` returns true.
```
((Fn either positive? even?) -2) -> #t
```

### `Fn all-pass`
`(Fn all-pass preds) -> function`
Returns a predicate that is true when all predicates in the list pass.
```
((Fn all-pass (list positive? even?)) 4) -> #t
```

### `Fn any-pass`
`(Fn any-pass preds) -> function`
Returns a predicate that is true when any predicate in the list passes.
```
((Fn any-pass (list positive? even?)) -2) -> #t
```

### `List reject`
`(List reject pred lst) -> list`
Returns elements for which `pred` is false (Fn complement of `filter`).
```
(List reject even? (list 1 2 3 4)) -> (1 3)
```

### `List sum`
`(List sum lst) -> number`
Returns the sum of all numbers in a list.
```
(List sum (list 1 2 3)) -> 6
```

### `List product`
`(List product lst) -> number`
Returns the product of all numbers in a list.
```
(List product (list 2 3 4)) -> 24
```

---

## 10. List Search

### `List find`
`(List find pred lst) -> value | ()`
Returns the first element matching `pred`, or `()` if none found.
```
(List find even? (list 1 3 4 6)) -> 4
```

### `List find-index`
`(List find-index pred lst) -> number | ()`
Returns the zero-based index of the first element matching `pred`, or `()` if none found.
```
(List find-index even? (list 1 3 4)) -> 2
```

### `List index-of`
`(List index-of x lst) -> number | ()`
Returns the zero-based index of the first element equal to `x`, or `()` if not found.
```
(List index-of 3 (list 1 2 3 4)) -> 2
```

### `List includes?`
`(List includes? x lst) -> boolean`
Returns `#t` if `x` is found in the list using structural equality.
```
(List includes? 3 (list 1 2 3)) -> #t
```

### `List count-if`
`(List count-if pred lst) -> number`
Returns the number of elements for which `pred` returns true.
```
(List count-if even? (list 1 2 3 4)) -> 2
```

---

## 11. List Slicing

### `List take`
`(List take n lst) -> list`
Returns the first `n` elements of a list.
```
(List take 2 (list 1 2 3 4)) -> (1 2)
```

### `List drop`
`(List drop n lst) -> list`
Returns the list with the first `n` elements removed.
```
(List drop 2 (list 1 2 3 4)) -> (3 4)
```

### `List take-while`
`(List take-while pred lst) -> list`
Returns the longest prefix of elements for which `pred` holds.
```
(List take-while odd? (list 1 3 4 5)) -> (1 3)
```

### `List drop-while`
`(List drop-while pred lst) -> list`
Drops the longest prefix of elements for which `pred` holds.
```
(List drop-while odd? (list 1 3 4 5)) -> (4 5)
```

### `List split-at`
`(List split-at n lst) -> (list list)`
Splits a list at index `n`, returning a pair of the taken and dropped portions.
```
(List split-at 2 (list 1 2 3 4)) -> ((1 2) (3 4))
```

### `List slice`
`(List slice start end lst) -> list`
Returns elements from index `start` up to (but not including) `end`.
```
(List slice 1 3 (list 10 20 30 40)) -> (20 30)
```

---

## 12. List Generators

### `List range`
`(List range start end) -> list`
Generates a list of integers from `start` up to (but not including) `end`.
```
(List range 0 5) -> (0 1 2 3 4)
```

### `List repeat`
`(List repeat n x) -> list`
Returns a list containing `x` repeated `n` times (count first, matching `Str8 repeat`).
```
(List repeat 3 0) -> (0 0 0)
```

### `List times`
`(List times f n) -> list`
Calls `f` with each index from `0` to `n-1` and collects the results.
```
(List times (method-ref Fn identity) 4) -> (0 1 2 3)
```

### `List unfold`
`(List unfold pred f g seed) -> list`
Builds a list by repeatedly applying `f` (value) and `g` (next seed) until `pred` returns true.
```
(List unfold (fn (_ x) (> x 3)) (method-ref Fn identity) (method-ref Num inc) 1) -> (1 2 3)
```

### `List iterate`
`(List iterate f n x) -> list`
Returns a list of `n` values starting with `x`, each subsequent value produced by applying `f`.
```
(List iterate (method-ref Num inc) 4 0) -> (0 1 2 3)
```

### `List zip`
`(List zip a b) -> alist`
Pairs corresponding elements from two lists as assocs; the result is an alist, ready for `Dict from-alist` and the `Assoc` API.
```
(List zip (list 1 2 3) (list 4 5 6)) -> ((1 . 4) (2 . 5) (3 . 6))
```

### `List zip-with`
`(List zip-with f a b) -> list`
Combines corresponding elements from two lists using `f`.
```
(List zip-with + (list 1 2 3) (list 10 20 30)) -> (11 22 33)
```

---

## 13. List Transformation

### `List partition`
`(List partition pred lst) -> (list list)`
Splits a list into two lists: elements satisfying `pred` and elements that do not.
```
(List partition even? (list 1 2 3 4)) -> ((2 4) (1 3))
```

### `List group-by`
`(List group-by f lst) -> alist`
Groups elements into an association list keyed by the result of applying `f`.
```
(List group-by even? (list 1 2 3 4)) -> ((() 1 3) (#t 2 4))
```

### `List sort`
`(List sort cmp lst) -> list`
Sorts a list using merge sort, where `cmp` is a two-argument comparison predicate.
```
(List sort < (list 3 1 2)) -> (1 2 3)
```

### `List sort-by`
`(List sort-by f lst) -> list`
Sorts a list by comparing the results of applying `f` to each element.
```
(List sort-by (method-ref Num abs) (list -3 1 -2)) -> (1 -2 -3)
```

### `List uniq`
`(List uniq lst) -> list`
Removes consecutive duplicate elements (the list should be sorted for full deduplication).
```
(List uniq (list 1 1 2 2 3)) -> (1 2 3)
```

### `List uniq-by`
`(List uniq-by f lst) -> list`
Removes consecutive elements that are equal after applying `f`.
```
(List uniq-by (method-ref Num abs) (list 1 -1 2 -2 3)) -> (1 2 3)
```

### `List intersperse`
`(List intersperse sep lst) -> list`
Inserts `sep` between every pair of adjacent elements.
```
(List intersperse 0 (list 1 2 3)) -> (1 0 2 0 3)
```

### `List transpose`
`(List transpose lsts) -> list`
Transposes a list of lists (swaps rows and columns).
```
(List transpose (list (list 1 2) (list 3 4))) -> ((1 3) (2 4))
```

### `List update`
`(List update n val lst) -> list`
Returns a new list with the element at index `n` replaced by `val`.
```
(List update 1 99 (list 1 2 3)) -> (1 99 3)
```

### `List insert`
`(List insert n val lst) -> list`
Returns a new list with `val` inserted at index `n`.
```
(List insert 1 99 (list 1 2 3)) -> (1 99 2 3)
```

### `List remove`
`(List remove start n lst) -> list`
Returns a new list with `n` elements removed starting at index `start`.
```
(List remove 1 2 (list 1 2 3 4)) -> (1 4)
```

### `List adjust`
`(List adjust n f lst) -> list`
Returns a new list with the element at index `n` transformed by `f`.
```
(List adjust 1 (method-ref Num inc) (list 10 20 30)) -> (10 21 30)
```

---

## 14. Association Lists

Association lists (alists) are lists of pairs `((key . val) ...)` where keys are compared with `eq?` (symbol/pointer equality).

### `assoc-get`
`(assoc-get key alist) -> value | ()`
Looks up `key` in the alist, returning its value or `()` if not found.
```
(assoc-get 'b (list (pair 'a 1) (pair 'b 2))) -> 2
```

### `Assoc get-or`
`(Assoc get-or d key alist) -> value`
Like `assoc-get`, but returns default `d` if the key is not found.
```
(Assoc get-or 0 'z (list (pair 'a 1))) -> 0
```

### `assoc-has?`
`(assoc-has? key alist) -> boolean`
Returns `#t` if the alist contains an entry for `key`.
```
(assoc-has? 'a (list (pair 'a 1))) -> #t
```

### `assoc-del`
`(assoc-del key alist) -> alist`
Returns a new alist with all entries for `key` removed.
```
(assoc-del 'a (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `assoc-put`
`(assoc-put key val alist) -> alist`
Sets `key` to `val` in the alist, replacing any existing entry for that key.
```
(assoc-put 'a 99 (list (pair 'a 1) (pair 'b 2))) -> ((a . 99) (b . 2))
```

### `assoc-keys`
`(assoc-keys alist) -> list`
Returns a list of all keys in the alist.
```
(assoc-keys (list (pair 'a 1) (pair 'b 2))) -> (a b)
```

### `Assoc vals`
`(Assoc vals alist) -> list`
Returns a list of all values in the alist.
```
(Assoc vals (list (pair 'a 1) (pair 'b 2))) -> (1 2)
```

### `Assoc map`
`(Assoc map f alist) -> alist`
Applies `f` to each value in the alist, preserving keys.
```
(Assoc map (method-ref Num inc) (list (pair 'a 1) (pair 'b 2))) -> ((a . 2) (b . 3))
```

### `Assoc filter`
`(Assoc filter pred alist) -> alist`
Filters alist entries by a predicate applied to each `(key . val)` pair.
```
(Assoc filter (fn (_ e) (> (rest e) 1)) (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `Assoc merge`
`(Assoc merge a b) -> alist`
Merges alist `b` into `a`, keeping entries from `a` when keys collide.
```
(Assoc merge (list (pair 'a 1)) (list (pair 'a 9) (pair 'b 2))) -> ((a . 1) (b . 2))
```

### `Assoc pick`
`(Assoc pick keys alist) -> alist`
Returns only the entries whose keys appear in the `keys` list.
```
(Assoc pick (list 'a) (list (pair 'a 1) (pair 'b 2))) -> ((a . 1))
```

### `Assoc omit`
`(Assoc omit keys alist) -> alist`
Returns the alist with entries for the given keys removed.
```
(Assoc omit (list 'a) (list (pair 'a 1) (pair 'b 2))) -> ((b . 2))
```

### `Assoc from-bindings`
`(Assoc from-bindings bindings) -> alist`
Converts a bindings list -- `((key value) ...)` two-element lists, the `let` shape -- into an alist of assocs.
```
(Assoc from-bindings (list (list 'a 1) (list 'b 2))) -> ((a . 1) (b . 2))
```

### `Assoc ->bindings`
`(Assoc ->bindings alist) -> list`
Converts an alist of assocs into a bindings list of two-element lists.
```
(Assoc ->bindings (list (pair 'a 1) (pair 'b 2))) -> ((a 1) (b 2))
```

### `Assoc evolve`
`(Assoc evolve fns alist) -> alist`
Applies transformation functions from the `fns` alist to matching keys in the data alist.
```
(Assoc evolve (list (pair 'a (method-ref Num inc))) (list (pair 'a 1) (pair 'b 2))) -> ((a . 2) (b . 2))
```

---

## 15. String Utilities

### `Str empty?`
`(Str empty? s) -> boolean`
Returns `#t` if the string has zero length.
```
(Str empty? "") -> #t
```

### `Str join`
`(Str join sep lst) -> string`
Joins a list of strings with `sep` between each pair.
```
(Str join ", " (list "a" "b" "c")) -> "a, b, c"
```

### `Str repeat`
`(Str repeat s n) -> string`
Returns the string `s` repeated `n` times.
```
(Str repeat "ab" 3) -> "ababab"
```

### `Str contains?`
`(Str contains? sub s) -> boolean`
Returns `#t` if `sub` is found anywhere within `s`.
```
(Str contains? "ell" "hello") -> #t
```

### `Str starts?`
`(Str starts? pfx s) -> boolean`
Returns `#t` if `s` starts with the prefix `pfx`.
```
(Str starts? "he" "hello") -> #t
```

### `Str ends?`
`(Str ends? sfx s) -> boolean`
Returns `#t` if `s` ends with the suffix `sfx`.
```
(Str ends? "lo" "hello") -> #t
```

### `Str reverse`
`(Str reverse s) -> string`
Returns the string with characters in reverse order.
```
(Str reverse "hello") -> "olleh"
```

---

## 16. Vectors

Vectors are fixed-size, indexed collections backed by lists, created via the `make-type` mechanism. They display as `#(...)`. Operations are homed on the `Vector` class (the `#(...)` literal reader and negative-index `(v i)` access are unchanged).

### `Vector of`
`(Vector of . args) -> vector`
Creates a new vector from the given arguments.
```
(Vector of 1 2 3) -> #(1 2 3)
```

### `Vector vector?`
`(Vector vector? x) -> boolean`
Returns `#t` if `x` is a vector.
```
(Vector vector? (Vector of 1 2)) -> #t
```

### `Vector ref`
`(Vector ref v i) -> value`
Returns the element at zero-based index `i` from vector `v`.
```
(Vector ref (Vector of 10 20 30) 1) -> 20
```

### `Vector length`
`(Vector length v) -> number`
Returns the number of elements in the vector.
```
(Vector length (Vector of 1 2 3)) -> 3
```

### `Vector ->list`
`(Vector ->list v) -> list`
Converts a vector to a list.
```
(Vector ->list (Vector of 1 2 3)) -> (1 2 3)
```

### `Vector from-list`
`(Vector from-list lst) -> vector`
Converts a list to a vector.
```
(Vector from-list (list 1 2 3)) -> #(1 2 3)
```

### `Vector make`
`(Vector make n fill) -> vector`
Creates a vector of length `n` with every element set to `fill`.
```
(Vector make 3 0) -> #(0 0 0)
```

## 17. Objects

Message-passing classes with single inheritance, mutable members, and encapsulated
access, built on the `make-type` mechanism. Send a message by applying an instance
to a **literal** member name (no quote): `(obj name args...)`. A method named
`name` wins; otherwise `name` is a member — `(obj m)` reads it, `(obj m v)` writes
it. From outside, dispatch is the only way in. **Classes are objects too:**
`(Class name args...)` calls a static method, `(Class member)` / `(Class member val)`
reads/writes a class-wide member, and `(Class new member val...)` builds an instance.
See the [Object System](object-system.md) guide for the full walkthrough.

### `def-class`
`(def-class name parent member... (method m (self . args) body...) (static ...))`
Defines a class bound to `name`. `parent` is `()` for none, or `(extends Class)`
for single inheritance. Names are literal (`def-class` is an operative). Members are
declared directly (no wrapper) as `name`, `(name default)`, or `(name default "desc")`;
a `method`-headed form is a method. An optional `(static (List member val)... (method ...)...)`
block adds class-wide members and static methods (inherited by subclasses; `self` is
the class inside them).
```
(do
  (def-class Math () (static (base 10) (method scaled (self n) (* n (self base)))))
  (list (Math scaled 3) (Math base))) -> (30 10)
```

### `new`
`(new class field value ...) -> object`
Constructs an instance; member names are literal, values are evaluated. Unset
members take their declared default (nil if none).
```
(new Point x 1 y 2) -> #<Point x=1 y=2>
```

### member access
`(obj name)` / `(obj name value)`
Reads or writes member `name`: a method named `name` is called, otherwise the
member is read/written.
```
(do (def-class P () n) (def p (new P n 5)) (p n 10) (p n)) -> 10
```

### static access
`(Class name)` / `(Class name value)`
A static method named `name` is called, else `name` is a class-wide member that is
read or written. `(Class new member val...)` constructs an instance.
```
(do (def-class C () (static (n 7) (method get (self) (self n)))) (list (C get) (C n))) -> (7 7)
```

### `super`
`(super self name args...) -> value`
Invokes the parent class's version of a method. Resolves from the parent of the
method's **defining** class (fixed at `def-class` time), so it chains correctly
through multi-level inheritance. Only valid inside an instance method.

### `member` / `set-member!` — inside methods only
`(member 'name)` / `(set-member! 'name value)`
Raw member access that bypasses a same-named method override (the private-data
pattern). Bound only inside method bodies; not available to external code.

### `object?`
`(object? x) -> boolean`
Returns `#t` if `x` is an object instance.
```
(object? (new Point x 1 y 2)) -> #t
```

### `class?`
`(class? x) -> boolean`
Returns `#t` if `x` is a class (a callable class object).

### `class-of`
`(class-of inst) -> class`
Returns the (callable) class an instance belongs to.

### `class-name`
`(class-name x) -> symbol`
Returns the name symbol of a class, or of an instance's class.

### `instance-of?`
`(instance-of? inst class) -> boolean`
Returns `#t` if `inst` is an instance of `class` or any of its subclasses.
```
(instance-of? (new Point x 1 y 2) Point) -> #t
```

---

## 18. Iterators

Lazy traversal of sequences, homed on the `Iter` class. `(Iter new seq)` builds an iterator over a list, vector, string, or `def-class` instance; drive it with `(Iter next it)` / `(Iter empty? it)`, or consume it with the methods below. Build a custom iterator from any step logic with `(Iter make step state)`. An iterator is `[step-fn . state]`: `Iter next` calls `(step it)`, which reads the current item from the state, advances it, and returns the item; the state becoming `()` marks exhaustion.

### `Iter new`
`(Iter new seq) -> iterator`
Builds an iterator over an iterable — a list, vector, string, or class instance (instances yield `(name . value)` pairs). The empty list yields an empty iterator.
```
(Iter ->list (Iter new (Vector of 1 2 3))) -> (1 2 3)
```

### `Iter make`
`(Iter make step state) -> iterator`
Builds an iterator from a step function `(fn (self it) ...)` and an initial state. The step reads the current item from the iterator's state, advances it (e.g. with `set-rest!`), and returns the item; a `()` state means exhausted.

### `Iter next`
`(Iter next it) -> element`
Advances an iterator, returning its next element. (Check `Iter empty?` first.)

### `Iter empty?`
`(Iter empty? it) -> bool`
Reports whether an iterator is exhausted.
```
(do (def it (Iter new (list 1))) (def a (Iter empty? it)) (Iter next it) (list a (Iter empty? it))) -> (#f #t)
```

### `Iter ->list`
`(Iter ->list it) -> list`
Drains an iterator into a list.
```
(Iter ->list (Iter new "abc")) -> (#\a #\b #\c)
```

### `Iter for-each`
`(Iter for-each f it) -> ()`
Applies `f` to each remaining element, for side effects.

### `Iter fold`
`(Iter fold f acc it) -> acc`
Left-folds `(f acc element)` over the remaining elements.
```
(Iter fold + 0 (Iter new (list 1 2 3 4))) -> 10
```
