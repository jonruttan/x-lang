## as-list (the bare boot-layer global; the class method is `List from-seq`)

### passes through list

```scheme
(as-list (list 1 2 3))
```
---
    (1 2 3)

### passes through nil

```scheme
(null? (as-list ()))
```
---
    #t

## fold

### folds left

```scheme
(fold + 0 (list 1 2 3))
```
---
    6

### fold with subtraction

```scheme
(fold - 10 (list 1 2 3))
```
---
    4

## reduce

### reduces without initial value

```scheme
(List reduce + (list 1 2 3 4))
```
---
    10

## scan

### returns intermediate values

```scheme
(List scan + 0 (list 1 2 3))
```
---
    (0 1 3 6)

## length

### counts elements

```scheme
(length (list 1 2 3))
```
---
    3

### empty list is zero

```scheme
(length ())
```
---
    0

## sub

### the (start, length) twin of slice

```scheme
(list (List slice 1 3 (list 10 20 30 40)) (List sub 1 2 (list 10 20 30 40)))
```
---
    ((20 30) (20 30))

## from-seq

### builds a list from any iterable (the from-X verb; ex as-list)

```scheme
(do (import x/type/vector) (List from-seq (Vector of 1 2 3)))
```
---
    (1 2 3)

## of

### the variadic literal, homed on the class

```scheme
(List of 1 2 3)
```
---
    (1 2 3)

## ref

### gets element at index

```scheme
(List ref 1 (list 10 20 30))
```
---
    20

### gets first element

```scheme
(List ref 0 (list 10 20 30))
```
---
    10

### errors past the end instead of crashing

```scheme
(List ref 5 (list 1 2))
```
---
    Error: List ref: index out of range

### negative index counts from the end

```scheme
(List ref -1 (list 1 2))
```
---
    2

### errors when a negative index reaches past the front

```scheme
(List ref -3 (list 1 2))
```
---
    Error: List ref: index out of range

### errors on a nil index (a piped index-search miss fails loudly)

```scheme
(List ref (List index-of 99 (list 1 2)) (list 1 2))
```
---
    Error: List ref: nil index

## last

### returns last element

```scheme
(List last (list 1 2 3))
```
---
    3

### returns only element

```scheme
(List last (list 42))
```
---
    42

## init

### returns all but last

```scheme
(List init (list 1 2 3))
```
---
    (1 2)

## append

### concatenates two lists

```scheme
(append (list 1 2) (list 3 4))
```
---
    (1 2 3 4)

### appends to empty

```scheme
(append () (list 1 2))
```
---
    (1 2)

## prepend

### adds to front

```scheme
(List prepend 0 (list 1 2))
```
---
    (0 1 2)

## reverse

### reverses a list

```scheme
(reverse (list 1 2 3))
```
---
    (3 2 1)

### reverses empty

```scheme
(null? (reverse ()))
```
---
    #t

## flatten

### flattens nested lists

```scheme
(List flatten (list 1 (list 2 (list 3))))
```
---
    (1 2 3)

### flat list unchanged

```scheme
(List flatten (list 1 2 3))
```
---
    (1 2 3)

## map

### applies function to each

```scheme
(map (method-ref Num inc) (list 1 2 3))
```
---
    (2 3 4)

### maps over empty

```scheme
(null? (map (method-ref Num inc) ()))
```
---
    #t

## filter

### keeps matching elements

```scheme
(filter (method-ref Num even?) (list 1 2 3 4))
```
---
    (2 4)

### filters to empty

```scheme
(null? (filter (method-ref Num negative?) (list 1 2 3)))
```
---
    #t

## for-each

### applies function for side effects

```scheme
(null? (for-each (fn (_ x) x) (list 1 2 3)))
```
---
    #t

## reject

### removes matching elements

```scheme
(List reject (method-ref Num even?) (list 1 2 3 4))
```
---
    (1 3)

## flat-map

### maps and flattens

```scheme
(List flat-map (fn (_ x) (list x (* x 10))) (list 1 2 3))
```
---
    (1 10 2 20 3 30)

## append (variadic)

### concatenates multiple lists

```scheme
(List append (list 1) (list 2 3) (list 4))
```
---
    (1 2 3 4)

### concatenates with empty

```scheme
(List append () (list 1) ())
```
---
    (1)

## any?

### returns #t when one matches

```scheme
(List any? (method-ref Num even?) (list 1 2 3))
```
---
    #t

### returns nil when none match

```scheme
(if (List any? (method-ref Num negative?) (list 1 2 3)) "y" "n")
```
---
    "n"

## all?

### returns #t when all match

```scheme
(List all? (method-ref Num positive?) (list 1 2 3))
```
---
    #t

### returns nil when one fails

```scheme
(if (List all? (method-ref Num even?) (list 2 3 4)) "y" "n")
```
---
    "n"

## none?

### returns #t when none match

```scheme
(List none? (method-ref Num negative?) (list 1 2 3))
```
---
    #t

### returns nil when one matches

```scheme
(if (List none? (method-ref Num even?) (list 1 2 3)) "y" "n")
```
---
    "n"

## empty?

### true for empty list

```scheme
(List empty? ())
```
---
    #t

### false for non-empty

```scheme
(if (List empty? (list 1)) "y" "n")
```
---
    "n"

## find

### finds first match

```scheme
(List find (method-ref Num even?) (list 1 3 4 6))
```
---
    4

### returns nil when not found

```scheme
(null? (List find (method-ref Num negative?) (list 1 2 3)))
```
---
    #t

## find-index

### returns index of first match

```scheme
(List find-index (method-ref Num even?) (list 1 3 4 6))
```
---
    2

### misses with nil, like every other miss

```scheme
(null? (List find-index (method-ref Num negative?) (list 1 2 3)))
```
---
    #t

## index-of

### finds element index

```scheme
(List index-of 30 (list 10 20 30))
```
---
    2

### misses with nil, like every other miss

```scheme
(null? (List index-of 99 (list 10 20 30)))
```
---
    #t

## includes?

### finds element in list

```scheme
(List includes? 3 (list 1 2 3))
```
---
    #t

### returns nil when not found

```scheme
(if (List includes? 9 (list 1 2 3)) "y" "n")
```
---
    "n"

## count-if

### counts matching elements

```scheme
(List count-if (method-ref Num even?) (list 1 2 3 4 5 6))
```
---
    3

### returns zero for no matches

```scheme
(List count-if (method-ref Num negative?) (list 1 2 3))
```
---
    0

## take

### takes first n elements

```scheme
(List take 2 (list 1 2 3 4))
```
---
    (1 2)

### takes zero

```scheme
(null? (List take 0 (list 1 2 3)))
```
---
    #t

### takes more than available

```scheme
(List take 5 (list 1 2))
```
---
    (1 2)

## drop

### drops first n elements

```scheme
(List drop 2 (list 1 2 3 4))
```
---
    (3 4)

### drops zero

```scheme
(List drop 0 (list 1 2 3))
```
---
    (1 2 3)

## take-while

### takes while predicate holds

```scheme
(List take-while (method-ref Num positive?) (list 1 2 -3 4))
```
---
    (1 2)

### takes nothing when first fails

```scheme
(null? (List take-while (method-ref Num negative?) (list 1 2 3)))
```
---
    #t

## drop-while

### drops while predicate holds

```scheme
(List drop-while (method-ref Num positive?) (list 1 2 -3 4))
```
---
    (-3 4)

## split-at

### splits list at index

```scheme
(List split-at 2 (list 1 2 3 4))
```
---
    ((1 2) (3 4))

## slice

### extracts sublist

```scheme
(List slice 1 3 (list 10 20 30 40 50))
```
---
    (20 30)

## range

### generates ascending range

```scheme
(List range 0 5)
```
---
    (0 1 2 3 4)

### empty when start >= end

```scheme
(null? (List range 5 5))
```
---
    #t

## repeat

### repeats a value

```scheme
(List repeat 3 0)
```
---
    (0 0 0)

### repeats zero times

```scheme
(null? (List repeat 0 0))
```
---
    #t

## times

### calls function n times

```scheme
(List times (fn (_ i) i) 4)
```
---
    (0 1 2 3)

### applies function to indices

```scheme
(List times (fn (_ i) (* i i)) 4)
```
---
    (0 1 4 9)

## unfold

### builds a list from seed

```scheme
(List unfold (fn (_ x) (> x 5)) (fn (_ x) x) (method-ref Num inc) 1)
```
---
    (1 2 3 4 5)

## iterate

### generates repeated applications

```scheme
(List iterate (fn (_ x) (* x 2)) 4 1)
```
---
    (1 2 4 8)

## zip

### zips two lists into an alist of assocs

```scheme
(List zip (list 1 2 3) (list 4 5 6))
```
---
    ((1 . 4) (2 . 5) (3 . 6))

### stops at shorter list

```scheme
(List zip (list 1 2) (list 3 4 5))
```
---
    ((1 . 3) (2 . 4))

### zip output feeds the keyed consumers directly

```scheme
(do (import x/type/dict)
  ((Dict from-alist (List zip (list (lit a) (lit b)) (list 1 2))) get (lit b)))
```
---
    2

## zip-with

### zips with combining function

```scheme
(List zip-with + (list 1 2 3) (list 10 20 30))
```
---
    (11 22 33)

## partition

### splits by predicate

```scheme
(List partition (method-ref Num even?) (list 1 2 3 4 5 6))
```
---
    ((2 4 6) (1 3 5))

## group-by

### groups by key function

```scheme
(length (List group-by (method-ref Num even?) (list 1 2 3 4 5)))
```
---
    2

### keeps element order within a group and first-seen key order

```scheme
(List group-by (method-ref Num even?) (list 1 2 3 4 5))
```
---
    ((#f 1 3 5) (#t 2 4))

## sort

### sorts ascending

```scheme
(List sort < (list 5 3 1 4 2))
```
---
    (1 2 3 4 5)

### sorts descending

```scheme
(List sort > (list 1 3 2))
```
---
    (3 2 1)

### sorts single element

```scheme
(List sort < (list 1))
```
---
    (1)

### sorts empty

```scheme
(null? (List sort < ()))
```
---
    #t

### is stable: equal keys keep input order

```scheme
(List sort (fn (_ a b) (< (first a) (first b)))
  (list (list 1 90) (list 0 5) (list 1 10) (list 0 7)))
```
---
    ((0 5) (0 7) (1 90) (1 10))

## sort-by

### sorts by key function

```scheme
(List sort-by (method-ref Num abs) (list 3 -1 -2))
```
---
    (-1 -2 3)

## uniq

### removes consecutive duplicates

```scheme
(List uniq (list 1 1 2 2 3 3))
```
---
    (1 2 3)

### keeps non-consecutive duplicates

```scheme
(List uniq (list 1 2 1 2))
```
---
    (1 2 1 2)

## uniq-by

### removes consecutive duplicates by key

```scheme
(length (List uniq-by (method-ref Num abs) (list 1 -1 2 -2 3)))
```
---
    3

## intersperse

### inserts separator between elements

```scheme
(List intersperse 0 (list 1 2 3))
```
---
    (1 0 2 0 3)

### single element unchanged

```scheme
(List intersperse 0 (list 1))
```
---
    (1)

## variadic append

### appends two lists

```scheme
(append (list 1 2) (list 3 4))
```
---
    (1 2 3 4)

### appends three lists

```scheme
(append (list 1) (list 2) (list 3))
```
---
    (1 2 3)

### appends with empty

```scheme
(append () (list 1 2) ())
```
---
    (1 2)

### appends zero lists

```scheme
(null? (append))
```
---
    #t

### appends one list

```scheme
(append (list 1 2))
```
---
    (1 2)

## multi-list map

### maps over two lists

```scheme
(map + (list 1 2 3) (list 10 20 30))
```
---
    (11 22 33)

### maps over three lists

```scheme
(map + (list 1 2) (list 10 20) (list 100 200))
```
---
    (111 222)

### stops at shortest

```scheme
(map + (list 1 2 3) (list 10 20))
```
---
    (11 22)

### single-list backward compat

```scheme
(map (method-ref Num inc) (list 1 2 3))
```
---
    (2 3 4)

## multi-list for-each

### iterates two lists

```scheme
(do (def r ()) (for-each (fn (_ a b) (set! r (pair (+ a b) r))) (list 1 2) (list 10 20)) (reverse r))
```
---
    (11 22)

### single-list backward compat

```scheme
(do (def r ()) (for-each (fn (_ x) (set! r (pair x r))) (list 1 2 3)) (reverse r))
```
---
    (1 2 3)

## transpose

### transposes a matrix

```scheme
(List transpose (list (list 1 2 3) (list 4 5 6)))
```
---
    ((1 4) (2 5) (3 6))

## update

### updates element at index

```scheme
(List update 1 99 (list 10 20 30))
```
---
    (10 99 30)

## insert

### inserts at index

```scheme
(List insert 1 99 (list 10 20 30))
```
---
    (10 99 20 30)

### insert at the length appends

```scheme
(List insert 3 99 (list 10 20 30))
```
---
    (10 20 30 99)

### insert past the end clamps to append

```scheme
(List insert 7 99 (list 10 20 30))
```
---
    (10 20 30 99)

## remove

### removes n elements at start index

```scheme
(List remove 1 2 (list 10 20 30 40))
```
---
    (10 40)

## adjust

### applies function at index

```scheme
(List adjust 1 (method-ref Num inc) (list 10 20 30))
```
---
    (10 21 30)


## memq

### finds element by identity

```scheme
(first (List memq (lit c) (list (lit a) (lit b) (lit c) (lit d))))
```
---
    (lit c)

### returns false when not found

```scheme
(null? (List memq 6 (list 1 2 3)))
```
---
    #t

## member

### finds element by equal?

```scheme
(List member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### returns false when not found

```scheme
(null? (List member 6 (list 1 2 3)))
```
---
    #t

## assq

### finds by identity

```scheme
(rest (List assq (lit b) (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))))
```
---
    2

### returns false when not found

```scheme
(null? (List assq (lit z) (list (pair (lit a) 1))))
```
---
    #t

## assoc

### finds by equal?

```scheme
(rest (List assoc 2 (list (pair 1 10) (pair 2 20) (pair 3 30))))
```
---
    20

### returns false when not found

```scheme
(null? (List assoc 9 (list (pair 1 10))))
```
---
    #t

## fold-right

### combines last-to-first, (f acc element) like fold

```scheme
(List fold-right (fn (_ acc x) (pair x acc)) () (list 1 2 3))
```
---
    (1 2 3)

## chunk

### splits with a short tail

```scheme
(List chunk 2 (list 1 2 3 4 5))
```
---
    ((1 2) (3 4) (5))

### errors on a non-positive size

```scheme
(List chunk 0 (list 1))
```
---
    Error: List chunk: size must be positive

## unzip

### inverts zip

```scheme
(List unzip (List zip (list 1 2) (list 9 8)))
```
---
    ((1 2) (9 8))

## interleave

### alternates, stopping at the shorter

```scheme
(List interleave (list 1 3 5) (list 2 4))
```
---
    (1 2 3 4)

## distinct

### removes all duplicates, keeping first occurrences

```scheme
(List distinct (list 1 2 1 3 2 1))
```
---
    (1 2 3)

### works on strings (equal?, not eq?)

```scheme
(List distinct (list "a" "b" "a"))
```
---
    ("a" "b")

## min / max

### finds extremes

```scheme
(list (List min (list 3 1 2)) (List max (list 3 1 2)))
```
---
    (1 3)

### errors on empty

```scheme
(List min ())
```
---
    Error: List min: empty list
