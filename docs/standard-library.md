# x-lang Standard Library

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*


The x-lang library is modular: ~100 modules (one module = one `provide`-ing `.x` source file) organized across `lib/x/boot/`, `lib/x/core/`, `lib/x/type/`, `lib/x/protocol/`, `lib/x/num/`, `lib/x/sys/`, `lib/x/doc/`, `lib/x/tool/`, and `lib/x/platform/`. The bootstrap loader `lib/x-core.x` pre-registers all paths and loads 40+ core modules via `provide`/`import` with deduplication.

This document covers the core functions loaded by `lib/x.x` (the base x-lang dialect). For the complete auto-generated reference covering all modules, see the [x-lang API Reference](https://jonruttan.github.io/x-lang/docs/ref/x/index.html) (offline: `make doc-x`, then `ref/x/index.md`).

**Library version:** `0.5.2`

### Module Categories

| Category | Path | Contents |
|----------|------|----------|
| Boot | `lib/x/boot/` | Operatives, data constructors, strings, module system |
| Core | `lib/x/core/` | Combinators, lists (60+ functions), logic, math, syntax, control, quasiquote, REPL |
| Types | `lib/x/type/` | Characters, strings, vectors, promises, regex, objects, records, traits, generics, iterators |
| Numeric | `lib/x/num/` | Bigint, float, rational, complex, and the tower mixed-type policy (`x/num/tower`) |
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
```x-repl
(Fn identity 42) -> 42
```

### `Fn const`
`(Fn const x) -> (fn (_ y) x)`
Returns a function that always returns `x`, ignoring its argument.
```x-repl
((Fn const 5) 99) -> 5
```

### `Fn compose`
`(Fn compose f g) -> (fn (_ x) (f (g x)))`
Returns a function that applies `g` then `f` (right-to-left composition).
```x-repl
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn pipe`
`(Fn pipe f g) -> (fn (_ x) (g (f x)))`
Returns a function that applies `f` then `g` (left-to-right composition).
```x-repl
((Fn pipe (method-ref Num inc) (method-ref Num inc)) 3) -> 5
```

### `Fn curry`
`(Fn curry f x) -> (fn (_ y) (f x y))`
Partially applies a two-argument function by fixing its first argument.
```x-repl
((Fn curry + 10) 5) -> 15
```

### `Fn flip`
`(Fn flip f) -> (fn (_ a b) (f b a))`
Returns a function that calls `f` with its two arguments reversed.
```x-repl
((Fn flip -) 1 10) -> 9
```

### `Fn tap`
`(Fn tap f) -> (fn (_ x) ...x)`
Returns a function that applies `f` to its argument for side effects, then returns the argument.
```x-repl
((Fn tap (method-ref Num inc)) 42) -> 42
```

---

## 2. Math

### `Num inc`
`(Num inc n) -> number`
Increments a number by one.
```x-repl
(Num inc 5) -> 6
```

### `Num dec`
`(Num dec n) -> number`
Decrements a number by one.
```x-repl
(Num dec 5) -> 4
```

### `Num negate`
`(Num negate n) -> number`
Returns the arithmetic negation of a number.
```x-repl
(Num negate 7) -> -7
```

### `Num abs`
`(Num abs n) -> number`
Returns the absolute value of a number.
```x-repl
(Num abs -3) -> 3
```

### `Num min`
`(Num min a b) -> number`
Returns the smaller of two numbers.
```x-repl
(Num min 3 7) -> 3
```

### `Num max`
`(Num max a b) -> number`
Returns the larger of two numbers.
```x-repl
(Num max 3 7) -> 7
```

### `Num clamp`
`(Num clamp lo hi n) -> number`
Clamps a number to the inclusive range `[lo, hi]`.
```x-repl
(Num clamp 0 10 15) -> 10
```

### `Num min-by`
`(Num min-by f a b) -> a | b`
Returns whichever of `a` or `b` is smaller when compared by applying `f`.
```x-repl
(Num min-by (method-ref Num abs) -5 3) -> 3
```

### `Num max-by`
`(Num max-by f a b) -> a | b`
Returns whichever of `a` or `b` is larger when compared by applying `f`.
```x-repl
(Num max-by (method-ref Num abs) -5 3) -> -5
```

---

## 3. Number Predicates

### `Num zero?`
`(Num zero? n) -> boolean`
Returns `#t` if the number is zero.
```x-repl
(Num zero? 0) -> #t
```

### `Num positive?`
`(Num positive? n) -> boolean`
Returns `#t` if the number is greater than zero.
```x-repl
(Num positive? 5) -> #t
```

### `Num negative?`
`(Num negative? n) -> boolean`
Returns `#t` if the number is less than zero.
```x-repl
(Num negative? -3) -> #t
```

### `Num even?`
`(Num even? n) -> boolean`
Returns `#t` if the number is even.
```x-repl
(Num even? 4) -> #t
```

### `Num odd?`
`(Num odd? n) -> boolean`
Returns `#t` if the number is odd.
```x-repl
(Num odd? 3) -> #t
```

---

## 4. Boolean / Logic

### `boolean?`
`(boolean? x) -> boolean`
Returns `#t` if `x` is `#t` or `#f`.
```x-repl
(boolean? #t) -> #t
```

### `Fn default-to`
`(Fn default-to d x) -> x | d`
Returns `x` unless it is nil, in which case returns the default value `d`.
```x-repl
(Fn default-to 0 ()) -> 0
```

### `Fn until`
`(Fn until pred f x) -> value`
Repeatedly applies `f` to `x` until `pred` returns true, then returns the value.
```x-repl
(Fn until (fn (_ n) (> n 10)) (method-ref Num inc) 1) -> 11
```

### `equal?`
`(equal? a b) -> boolean`
Structural equality that compares numbers by value, strings by content, and everything else by identity.
```x-repl
(equal? 3 3) -> #t
```

---

## 5. List Folds

### `List fold`
`(List fold f init lst) -> value`
Left fold: reduces a list to a single value by applying `f` to the accumulator and each element.
```x-repl
(List fold + 0 (list 1 2 3)) -> 6
```

### `List reduce`
`(List reduce f lst) -> value`
Left fold using the first element as the initial accumulator.
```x-repl
(List reduce + (list 1 2 3)) -> 6
```

### `List scan`
`(List scan f init lst) -> list`
Like `List fold`, but collects all intermediate accumulator values into a list.
```x-repl
(List scan + 0 (list 1 2 3)) -> (0 1 3 6)
```

---

## 6. List Basics

### `List length`
`(List length lst) -> number`
Returns the number of elements in a list.
```x-repl
(List length (list 1 2 3)) -> 3
```

### `List ref`
`(List ref n lst) -> value`
Returns the element at zero-based index `n`.
```x-repl
(List ref 1 (list 10 20 30)) -> 20
```

### `List last`
`(List last lst) -> value`
Returns the last element of a list.
```x-repl
(List last (list 1 2 3)) -> 3
```

### `List init`
`(List init lst) -> list`
Returns all elements except the last.
```x-repl
(List init (list 1 2 3)) -> (1 2)
```

### `List append`
`(List append a b) -> list`
Concatenates two lists.
```x-repl
(List append (list 1 2) (list 3 4)) -> (1 2 3 4)
```

### `List prepend`
`(List prepend x lst) -> list`
Adds an element to the front of a list.
```x-repl
(List prepend 0 (list 1 2)) -> (0 1 2)
```

### `List reverse`
`(List reverse lst) -> list`
Returns a list with elements in reverse order.
```x-repl
(List reverse (list 1 2 3)) -> (3 2 1)
```

### `List flatten`
`(List flatten lst) -> list`
Recursively flattens nested lists into a single flat list.
```x-repl
(List flatten (list 1 (list 2 (list 3)))) -> (1 2 3)
```

---

## 7. List Iteration

### `List map`
`(List map f lst) -> list`
Applies `f` to each element and returns a list of results.
```x-repl
(List map (method-ref Num inc) (list 1 2 3)) -> (2 3 4)
```

### `List filter`
`(List filter pred lst) -> list`
Returns a list of elements for which `pred` returns true.
```x-repl
(List filter (method-ref Num even?) (list 1 2 3 4)) -> (2 4)
```

### `List for-each`
`(List for-each f lst) -> ()`
Applies `f` to each element for side effects only.
```x-repl
(do (def %n 0) (List for-each (fn (_ x) (set! %n (+ %n x))) (list 1 2 3)) %n) -> 6
```

### `List flat-map`
`(List flat-map f lst) -> list`
Maps `f` over the list and flattens one level of nesting from the results.
```x-repl
(List flat-map (fn (_ x) (list x x)) (list 1 2)) -> (1 1 2 2)
```

---

## 8. List Predicates

### `List any?`
`(List any? pred lst) -> boolean`
Returns `#t` if `pred` is true for at least one element.
```x-repl
(List any? (method-ref Num even?) (list 1 3 4)) -> #t
```

### `List all?`
`(List all? pred lst) -> boolean`
Returns `#t` if `pred` is true for all elements.
```x-repl
(List all? (method-ref Num even?) (list 2 4 6)) -> #t
```

### `List none?`
`(List none? pred lst) -> boolean`
Returns `#t` if `pred` is false for all elements.
```x-repl
(List none? (method-ref Num even?) (list 1 3 5)) -> #t
```

### `List empty?`
`(List empty? lst) -> boolean`
Returns `#t` if the list is nil.
```x-repl
(List empty? ()) -> #t
```

---

## 9. Higher-Order Combinators

### `Fn complement`
`(Fn complement pred) -> function`
Returns a function that negates the result of `pred`.
```x-repl
((Fn complement (method-ref Num even?)) 3) -> #t
```

### `Fn partial`
`(Fn partial f . bound) -> function`
Returns a function with the leading arguments of `f` pre-filled.
```x-repl
((Fn partial + 10) 5) -> 15
```

### `Fn juxt`
`(Fn juxt . fns) -> function`
Returns a function that applies each of `fns` to its arguments and collects the results in a list.
```x-repl
((Fn juxt (method-ref Num inc) (method-ref Num dec)) 5) -> (6 4)
```

### `Fn both`
`(Fn both f g) -> function`
Returns a predicate that is true when both `f` and `g` return true.
```x-repl
((Fn both (method-ref Num positive?) (method-ref Num even?)) 4) -> #t
```

### `Fn either`
`(Fn either f g) -> function`
Returns a predicate that is true when either `f` or `g` returns true.
```x-repl
((Fn either (method-ref Num positive?) (method-ref Num even?)) -2) -> #t
```

### `Fn all-pass`
`(Fn all-pass preds) -> function`
Returns a predicate that is true when all predicates in the list pass.
```x-repl
((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 4) -> #t
```

### `Fn any-pass`
`(Fn any-pass preds) -> function`
Returns a predicate that is true when any predicate in the list passes.
```x-repl
((Fn any-pass (list (method-ref Num positive?) (method-ref Num even?))) -2) -> #t
```

### `List reject`
`(List reject pred lst) -> list`
Returns elements for which `pred` is false (Fn complement of `List filter`).
```x-repl
(List reject (method-ref Num even?) (list 1 2 3 4)) -> (1 3)
```

### `List sum`
`(List sum lst) -> number`
Returns the sum of all numbers in a list.
```x-repl
(List sum (list 1 2 3)) -> 6
```

### `List product`
`(List product lst) -> number`
Returns the product of all numbers in a list.
```x-repl
(List product (list 2 3 4)) -> 24
```

---

## 10. List Search

### `List find`
`(List find pred lst) -> value | ()`
Returns the first element matching `pred`, or `()` if none found.
```x-repl
(List find (method-ref Num even?) (list 1 3 4 6)) -> 4
```

### `List find-index`
`(List find-index pred lst) -> number | ()`
Returns the zero-based index of the first element matching `pred`, or `()` if none found.
```x-repl
(List find-index (method-ref Num even?) (list 1 3 4)) -> 2
```

### `List index-of`
`(List index-of x lst) -> number | ()`
Returns the zero-based index of the first element equal to `x`, or `()` if not found.
```x-repl
(List index-of 3 (list 1 2 3 4)) -> 2
```

### `List includes?`
`(List includes? x lst) -> boolean`
Returns `#t` if `x` is found in the list using structural equality.
```x-repl
(List includes? 3 (list 1 2 3)) -> #t
```

### `List count-if`
`(List count-if pred lst) -> number`
Returns the number of elements for which `pred` returns true.
```x-repl
(List count-if (method-ref Num even?) (list 1 2 3 4)) -> 2
```

---

## 11. List Slicing

### `List take`
`(List take n lst) -> list`
Returns the first `n` elements of a list.
```x-repl
(List take 2 (list 1 2 3 4)) -> (1 2)
```

### `List drop`
`(List drop n lst) -> list`
Returns the list with the first `n` elements removed.
```x-repl
(List drop 2 (list 1 2 3 4)) -> (3 4)
```

### `List take-while`
`(List take-while pred lst) -> list`
Returns the longest prefix of elements for which `pred` holds.
```x-repl
(List take-while (method-ref Num odd?) (list 1 3 4 5)) -> (1 3)
```

### `List drop-while`
`(List drop-while pred lst) -> list`
Drops the longest prefix of elements for which `pred` holds.
```x-repl
(List drop-while (method-ref Num odd?) (list 1 3 4 5)) -> (4 5)
```

### `List split-at`
`(List split-at n lst) -> (list list)`
Splits a list at index `n`, returning a pair of the taken and dropped portions.
```x-repl
(List split-at 2 (list 1 2 3 4)) -> ((1 2) (3 4))
```

### `List slice`
`(List slice start end lst) -> list`
Returns elements from index `start` up to (but not including) `end`.
```x-repl
(List slice 1 3 (list 10 20 30 40)) -> (20 30)
```

---

## 12. List Generators

### `List range`
`(List range start end) -> list`
Generates a list of integers from `start` up to (but not including) `end`.
```x-repl
(List range 0 5) -> (0 1 2 3 4)
```

### `List repeat`
`(List repeat n x) -> list`
Returns a list containing `x` repeated `n` times (count first, matching `Str8 repeat`).
```x-repl
(List repeat 3 0) -> (0 0 0)
```

### `List times`
`(List times f n) -> list`
Calls `f` with each index from `0` to `n-1` and collects the results.
```x-repl
(List times 4 (method-ref Fn identity)) -> (0 1 2 3)
```

### `List unfold`
`(List unfold pred f g seed) -> list`
Builds a list by repeatedly applying `f` (value) and `g` (next seed) until `pred` returns true.
```x-repl
(List unfold (fn (_ x) (> x 3)) (method-ref Fn identity) (method-ref Num inc) 1) -> (1 2 3)
```

### `List iterate`
`(List iterate f n x) -> list`
Returns a list of `n` values starting with `x`, each subsequent value produced by applying `f`.
```x-repl
(List iterate (method-ref Num inc) 4 0) -> (0 1 2 3)
```

### `List zip`
`(List zip a b) -> alist`
Pairs corresponding elements from two lists as assocs; the result is an alist, ready for `Dict from-alist` and the `Assoc` API.
```x-repl
(List zip (list 1 2 3) (list 4 5 6)) -> ((1 . 4) (2 . 5) (3 . 6))
```

### `List zip-with`
`(List zip-with f a b) -> list`
Combines corresponding elements from two lists using `f`.
```x-repl
(List zip-with + (list 1 2 3) (list 10 20 30)) -> (11 22 33)
```

---

## 13. List Transformation

### `List partition`
`(List partition pred lst) -> (list list)`
Splits a list into two lists: elements satisfying `pred` and elements that do not.
```x-repl
(List partition (method-ref Num even?) (list 1 2 3 4)) -> ((2 4) (1 3))
```

### `List group-by`
`(List group-by f lst) -> alist`
Groups elements into an association list keyed by the result of applying `f`.
```x-repl
(List group-by (method-ref Num even?) (list 1 2 3 4)) -> ((#f 1 3) (#t 2 4))
```

### `List sort`
`(List sort cmp lst) -> list`
Sorts a list using merge sort, where `cmp` is a two-argument comparison predicate.
```x-repl
(List sort < (list 3 1 2)) -> (1 2 3)
```

### `List sort-by`
`(List sort-by f lst) -> list`
Sorts a list by comparing the results of applying `f` to each element.
```x-repl
(List sort-by (method-ref Num abs) (list -3 1 -2)) -> (1 -2 -3)
```

### `List uniq`
`(List uniq lst) -> list`
Removes consecutive duplicate elements (the list should be sorted for full deduplication).
```x-repl
(List uniq (list 1 1 2 2 3)) -> (1 2 3)
```

### `List uniq-by`
`(List uniq-by f lst) -> list`
Removes consecutive elements that are equal after applying `f`.
```x-repl
(List uniq-by (method-ref Num abs) (list 1 -1 2 -2 3)) -> (1 2 3)
```

### `List intersperse`
`(List intersperse sep lst) -> list`
Inserts `sep` between every pair of adjacent elements.
```x-repl
(List intersperse 0 (list 1 2 3)) -> (1 0 2 0 3)
```

### `List transpose`
`(List transpose lsts) -> list`
Transposes a list of lists (swaps rows and columns).
```x-repl
(List transpose (list (list 1 2) (list 3 4))) -> ((1 3) (2 4))
```

### `List update`
`(List update n val lst) -> list`
Returns a new list with the element at index `n` replaced by `val`.
```x-repl
(List update 1 99 (list 1 2 3)) -> (1 99 3)
```

### `List insert`
`(List insert n val lst) -> list`
Returns a new list with `val` inserted at index `n`.
```x-repl
(List insert 1 99 (list 1 2 3)) -> (1 99 2 3)
```

### `List remove`
`(List remove start n lst) -> list`
Returns a new list with `n` elements removed starting at index `start`.
```x-repl
(List remove 1 2 (list 1 2 3 4)) -> (1 4)
```

### `List adjust`
`(List adjust n f lst) -> list`
Returns a new list with the element at index `n` transformed by `f`.
```x-repl
(List adjust 1 (method-ref Num inc) (list 10 20 30)) -> (10 21 30)
```

---

## 14. Association Lists

Association lists (alists) are lists of pairs `((key . val) ...)` where keys are compared with `eq?` (symbol/pointer equality).

### `Assoc get`
`(Assoc get key alist) -> value | ()`
Looks up `key` in the alist, returning its value or `()` if not found.
```x-repl
(Assoc get 'b (list (pair 'a 1) (pair 'b 2))) -> 2
```

### `Assoc get-or`
`(Assoc get-or d key alist) -> value`
Like `Assoc get`, but returns default `d` if the key is not found.
```x-repl
(Assoc get-or 0 'z (list (pair 'a 1))) -> 0
```

### `Assoc has?`
`(Assoc has? key alist) -> boolean`
Returns `#t` if the alist contains an entry for `key`.
```x-repl
(Assoc has? 'a (list (pair 'a 1))) -> #t
```

### `Assoc del`
`(Assoc del key alist) -> alist`
Returns a new alist with all entries for `key` removed.
```x-repl
(Assoc del 'a (list (pair 'a 1) (pair 'b 2))) -> (('b . 2))
```

### `Assoc put`
`(Assoc put key val alist) -> alist`
Sets `key` to `val` in the alist, replacing any existing entry for that key.
```x-repl
(Assoc put 'a 99 (list (pair 'a 1) (pair 'b 2))) -> (('a . 99) ('b . 2))
```

### `Assoc keys`
`(Assoc keys alist) -> list`
Returns a list of all keys in the alist.
```x-repl
(Assoc keys (list (pair 'a 1) (pair 'b 2))) -> ('a 'b)
```

### `Assoc vals`
`(Assoc vals alist) -> list`
Returns a list of all values in the alist.
```x-repl
(Assoc vals (list (pair 'a 1) (pair 'b 2))) -> (1 2)
```

### `Assoc map`
`(Assoc map f alist) -> alist`
Applies `f` to each value in the alist, preserving keys.
```x-repl
(Assoc map (method-ref Num inc) (list (pair 'a 1) (pair 'b 2))) -> (('a . 2) ('b . 3))
```

### `Assoc filter`
`(Assoc filter pred alist) -> alist`
Filters alist entries by a predicate applied to each `(key . val)` pair.
```x-repl
(Assoc filter (fn (_ e) (> (rest e) 1)) (list (pair 'a 1) (pair 'b 2))) -> (('b . 2))
```

### `Assoc merge`
`(Assoc merge a b) -> alist`
Merges alist `b` into `a`, keeping entries from `a` when keys collide.
```x-repl
(Assoc merge (list (pair 'a 1)) (list (pair 'a 9) (pair 'b 2))) -> (('a . 1) ('b . 2))
```

### `Assoc pick`
`(Assoc pick keys alist) -> alist`
Returns only the entries whose keys appear in the `keys` list.
```x-repl
(Assoc pick (list 'a) (list (pair 'a 1) (pair 'b 2))) -> (('a . 1))
```

### `Assoc omit`
`(Assoc omit keys alist) -> alist`
Returns the alist with entries for the given keys removed.
```x-repl
(Assoc omit (list 'a) (list (pair 'a 1) (pair 'b 2))) -> (('b . 2))
```

### `Assoc from-bindings`
`(Assoc from-bindings bindings) -> alist`
Converts a bindings list -- `((key value) ...)` two-element lists, the `let` shape -- into an alist of assocs.
```x-repl
(Assoc from-bindings (list (list 'a 1) (list 'b 2))) -> (('a . 1) ('b . 2))
```

### `Assoc ->bindings`
`(Assoc ->bindings alist) -> list`
Converts an alist of assocs into a bindings list of two-element lists.
```x-repl
(Assoc ->bindings (list (pair 'a 1) (pair 'b 2))) -> (('a 1) ('b 2))
```

### `Assoc evolve`
`(Assoc evolve fns alist) -> alist`
Applies transformation functions from the `fns` alist to matching keys in the data alist.
```x-repl
(Assoc evolve (list (pair 'a (method-ref Num inc))) (list (pair 'a 1) (pair 'b 2))) -> (('a . 2) ('b . 2))
```

---

## 15. String Utilities

### `Str empty?`
`(Str empty? s) -> boolean`
Returns `#t` if the string has zero length.
```x-repl
(Str empty? "") -> #t
```

### `Str join`
`(Str join sep lst) -> string`
Joins a list of strings with `sep` between each pair.
```x-repl
(Str join ", " (list "a" "b" "c")) -> "a, b, c"
```

### `Str repeat`
`(Str repeat s n) -> string`
Returns the string `s` repeated `n` times.
```x-repl
(Str repeat 3 "ab") -> "ababab"
```

### `Str includes?`
`(Str includes? sub s) -> boolean`
Returns `#t` if `sub` is found anywhere within `s`.
```x-repl
(Str includes? "ell" "hello") -> #t
```

### `Str starts?`
`(Str starts? pfx s) -> boolean`
Returns `#t` if `s` starts with the prefix `pfx`.
```x-repl
(Str starts? "he" "hello") -> #t
```

### `Str ends?`
`(Str ends? sfx s) -> boolean`
Returns `#t` if `s` ends with the suffix `sfx`.
```x-repl
(Str ends? "lo" "hello") -> #t
```

### `Str reverse`
`(Str reverse s) -> string`
Returns the string with characters in reverse order.
```x-repl
(Str reverse "hello") -> "olleh"
```

---

## 16. Vectors

Vectors are fixed-size, indexed collections backed by lists, created via the `make-type` mechanism. They display as `#(...)`. Operations are homed on the `Vector` class (the `#(...)` literal reader and negative-index `(v i)` access are unchanged).

### `Vector of`
`(Vector of . args) -> vector`
Creates a new vector from the given arguments.
```x-repl
(Vector of 1 2 3) -> #(1 2 3)
```

### `Vector vector?`
`(Vector vector? x) -> boolean`
Returns `#t` if `x` is a vector.
```x-repl
(Vector vector? (Vector of 1 2)) -> #t
```

### `Vector ref`
`(Vector ref v i) -> value`
Returns the element at zero-based index `i` from vector `v`.
```x-repl
(Vector ref 1 (Vector of 10 20 30)) -> 20
```

### `Vector length`
`(Vector length v) -> number`
Returns the number of elements in the vector.
```x-repl
(Vector length (Vector of 1 2 3)) -> 3
```

### `Vector ->list`
`(Vector ->list v) -> list`
Converts a vector to a list.
```x-repl
(Vector ->list (Vector of 1 2 3)) -> (1 2 3)
```

### `Vector from-list`
`(Vector from-list lst) -> vector`
Converts a list to a vector.
```x-repl
(Vector from-list (list 1 2 3)) -> #(1 2 3)
```

### `Vector make`
`(Vector make n fill) -> vector`
Creates a vector of length `n` with every element set to `fill`.
```x-repl
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
```x
(do
  (def-class Math () (static (base 10) (method scaled (self n) (* n (self base)))))
  (list (Math scaled 3) (Math base))) -> (30 10)
```

### `new`
`(new class field value ...) -> object`
Constructs an instance; member names are literal, values are evaluated. Unset
members take their declared default (nil if none).
```x-repl
(do (def-class Point () x y) (new Point x 1 y 2)) -> #<Point x=1 y=2>
```

### member access
`(obj name)` / `(obj name value)`
Reads or writes member `name`: a method named `name` is called, otherwise the
member is read/written.
```x-repl
(do (def-class P () n) (def p (new P n 5)) (p n 10) (p n)) -> 10
```

### static access
`(Class name)` / `(Class name value)`
A static method named `name` is called, else `name` is a class-wide member that is
read or written. `(Class new member val...)` constructs an instance.
```x-repl
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
```x-repl
(do (def-class Point () x y) (object? (new Point x 1 y 2))) -> #t
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
```x-repl
(do (def-class Point () x y) (instance-of? (new Point x 1 y 2) Point)) -> #t
```

### `(private ...)` / `(protected ...)` — class body blocks
Enforced visibility for the members and methods declared inside:
`private` = the defining class's methods only; `protected` = methods anywhere
on its chain. Checked at the dispatch door (violations name class, selector,
tier, and definer); opt-in per class; `(help)` still lists everything.

### `method-of`
`(method-of Class sel) -> closure | ()`
The sanctioned de-dispatch door: resolves a static method once so a hot loop
can call the bare closure directly — `((method-of C 'step) C cur v)`. Do not
wrap the handle; a stored method already evaluates its arguments exactly once.

### `def-method!` / `def-static!`
`(C def-method! sel fn)` / `(C def-static! sel fn)`
Add an instance / static method to a class after definition. `sel` and `fn`
are evaluated (computed selectors work); the fn receives `(self . args)` and
uses `(self f)` member access. Cached dispatch tables refold automatically.

### `%init` / `%repr` / `%str` / `%missing` — protocol hooks
Methods the runtime invokes: `%init` runs after every construction; `write`
prefers a `%repr` returning a string, `display` prefers `%str`; a
`(method %missing (self sel args) ...)` catches any dispatch miss (instance
and static sides, inherited). Without `%missing` a miss errors naming the
class and selector.

### `def-record`
`(def-record Name field... )` — a data-carrier class: the ordinary
positional/keyword constructor and field doors, plus `(r with 'field v ...)`
(functional update, quoted keys) and `(r =? other)` (structural equality —
a method; `eq?`/`same?` keep identity).
```x-repl
(do (def-record Pt x y) (def p (new Pt 1 2)) (list (p x) ((p with 'y 9) y) (p =? (new Pt 1 2)))) -> (1 9 #t)
```

### `def-generic` / `on` — `x/type/generic`
`(def-generic g)` defines an open multi-argument generic (a callable value);
`(on g ((a Class) b (c handle)) body...)` adds a method — class keys match
instances (subclasses included), handle keys exactly, bare names anything.
Pointwise specificity, cvt-lattice tie-break, errors naming candidates.
`Generic add!` / `miss!` / `methods-of` are the computed-registration,
miss-handler, and introspection doors.

### `def-trait` / `with` / `delegates` — `x/type/trait`
`(def-trait T (require sel...) (method ...) (static ...))` bundles methods;
`(with T...)` in a `def-class` body mixes them in (own > trait > inherited;
collisions and unmet requires refuse at definition). `(delegates field
(sel... (theirs ours)...))` generates late-bound forwarders to a field's
value — the wrapper relationship stated once.

### `num+ num- num* num/ num% num< num=` — `x/num/tower`
The tower's mixed-type policy as callable generics: same-type pairs stay on
each numeric module's fast worker; a mixed pair promotes through the cvt
from-lattice (the absorbing module's own coercion formula); an unrelated
pair errors naming both types. `(import x/num/tower)` whenever two numeric
modules meet.

---

## 18. Iterators

Lazy traversal of sequences, homed on the `Iter` class. `(Iter new seq)` builds an iterator over a list, vector, string, or `def-class` instance; drive it with `(Iter next it)` / `(Iter empty? it)`, or consume it with the methods below. Build a custom iterator from any step logic with `(Iter make step state)`. An iterator is `[step-fn . state]`: `Iter next` calls `(step it)`, which reads the current item from the state, advances it, and returns the item; the state becoming `()` marks exhaustion.

### `Iter new`
`(Iter new seq) -> iterator`
Builds an iterator over an iterable — a list, vector, string, or class instance (instances yield `(name . value)` pairs). The empty list yields an empty iterator.
```x-repl
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
```x-repl
(do (def it (Iter new (list 1))) (def a (Iter empty? it)) (Iter next it) (list a (Iter empty? it))) -> (#f #t)
```

### `Iter ->list`
`(Iter ->list it) -> list`
Drains an iterator into a list.
```x-repl
(Iter ->list (Iter new "abc")) -> (#\a #\b #\c)
```

### `Iter for-each`
`(Iter for-each f it) -> ()`
Applies `f` to each remaining element, for side effects.

### `Iter fold`
`(Iter fold f acc it) -> acc`
Left-folds `(f acc element)` over the remaining elements.
```x-repl
(Iter fold + 0 (Iter new (list 1 2 3 4))) -> 10
```
