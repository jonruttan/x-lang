## as-list

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

## nth

### gets element at index

```scheme
(List nth 1 (list 10 20 30))
```
---
    20

### gets first element

```scheme
(List nth 0 (list 10 20 30))
```
---
    10

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
(map inc (list 1 2 3))
```
---
    (2 3 4)

### maps over empty

```scheme
(null? (map inc ()))
```
---
    #t

## filter

### keeps matching elements

```scheme
(filter even? (list 1 2 3 4))
```
---
    (2 4)

### filters to empty

```scheme
(null? (filter negative? (list 1 2 3)))
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
(List reject even? (list 1 2 3 4))
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

## concat

### concatenates multiple lists

```scheme
(List concat (list 1) (list 2 3) (list 4))
```
---
    (1 2 3 4)

### concatenates with empty

```scheme
(List concat () (list 1) ())
```
---
    (1)

## any?

### returns #t when one matches

```scheme
(List any? even? (list 1 2 3))
```
---
    #t

### returns nil when none match

```scheme
(if (List any? negative? (list 1 2 3)) "y" "n")
```
---
    "n"

## every?

### returns #t when all match

```scheme
(List every? positive? (list 1 2 3))
```
---
    #t

### returns nil when one fails

```scheme
(if (List every? even? (list 2 3 4)) "y" "n")
```
---
    "n"

## none?

### returns #t when none match

```scheme
(List none? negative? (list 1 2 3))
```
---
    #t

### returns nil when one matches

```scheme
(if (List none? even? (list 1 2 3)) "y" "n")
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
(find even? (list 1 3 4 6))
```
---
    4

### returns nil when not found

```scheme
(null? (find negative? (list 1 2 3)))
```
---
    #t

## find-index

### returns index of first match

```scheme
(List find-index even? (list 1 3 4 6))
```
---
    2

### returns -1 when not found

```scheme
(List find-index negative? (list 1 2 3))
```
---
    -1

## index-of

### finds element index

```scheme
(List index-of 30 (list 10 20 30))
```
---
    2

### returns -1 when not found

```scheme
(List index-of 99 (list 10 20 30))
```
---
    -1

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

## count

### counts matching elements

```scheme
(count even? (list 1 2 3 4 5 6))
```
---
    3

### returns zero for no matches

```scheme
(count negative? (list 1 2 3))
```
---
    0

## take

### takes first n elements

```scheme
(take 2 (list 1 2 3 4))
```
---
    (1 2)

### takes zero

```scheme
(null? (take 0 (list 1 2 3)))
```
---
    #t

### takes more than available

```scheme
(take 5 (list 1 2))
```
---
    (1 2)

## drop

### drops first n elements

```scheme
(drop 2 (list 1 2 3 4))
```
---
    (3 4)

### drops zero

```scheme
(drop 0 (list 1 2 3))
```
---
    (1 2 3)

## take-while

### takes while predicate holds

```scheme
(List take-while positive? (list 1 2 -3 4))
```
---
    (1 2)

### takes nothing when first fails

```scheme
(null? (List take-while negative? (list 1 2 3)))
```
---
    #t

## drop-while

### drops while predicate holds

```scheme
(List drop-while positive? (list 1 2 -3 4))
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
(List repeat 0 3)
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
(List times identity 4)
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
(List unfold (fn (_ x) (> x 5)) identity inc 1)
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

### zips two lists

```scheme
(List zip (list 1 2 3) (list 4 5 6))
```
---
    ((1 4) (2 5) (3 6))

### stops at shorter list

```scheme
(List zip (list 1 2) (list 3 4 5))
```
---
    ((1 3) (2 4))

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
(List partition even? (list 1 2 3 4 5 6))
```
---
    ((2 4 6) (1 3 5))

## group-by

### groups by key function

```scheme
(length (List group-by even? (list 1 2 3 4 5)))
```
---
    2

## sort

### sorts ascending

```scheme
(sort < (list 5 3 1 4 2))
```
---
    (1 2 3 4 5)

### sorts descending

```scheme
(sort > (list 1 3 2))
```
---
    (3 2 1)

### sorts single element

```scheme
(sort < (list 1))
```
---
    (1)

### sorts empty

```scheme
(null? (sort < ()))
```
---
    #t

## sort-by

### sorts by key function

```scheme
(List sort-by abs (list 3 -1 -2))
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
(length (List uniq-by abs (list 1 -1 2 -2 3)))
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
(map inc (list 1 2 3))
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
(List adjust 1 inc (list 10 20 30))
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
(if (List memq 6 (list 1 2 3)) "y" "n")
```
---
    "n"

## member

### finds element by equal?

```scheme
(member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### returns false when not found

```scheme
(if (member 6 (list 1 2 3)) "y" "n")
```
---
    "n"

## assq

### finds by identity

```scheme
(rest (List assq (lit b) (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))))
```
---
    2

### returns false when not found

```scheme
(if (List assq (lit z) (list (pair (lit a) 1))) "y" "n")
```
---
    "n"

## assoc

### finds by equal?

```scheme
(rest (assoc 2 (list (pair 1 10) (pair 2 20) (pair 3 30))))
```
---
    20

### returns false when not found

```scheme
(if (assoc 9 (list (pair 1 10))) "y" "n")
```
---
    "n"
