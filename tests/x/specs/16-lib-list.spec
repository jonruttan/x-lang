
== fold

-- folds left
(fold + 0 (list 1 2 3))
---
6

-- fold with subtraction
(fold - 10 (list 1 2 3))
---
4

== reduce

-- reduces without initial value
(reduce + (list 1 2 3 4))
---
10

== scan

-- returns intermediate values
(scan + 0 (list 1 2 3))
---
(0 1 3 6)

== length

-- counts elements
(length (list 1 2 3))
---
3

-- empty list is zero
(length ())
---
0

== nth

-- gets element at index
(nth 1 (list 10 20 30))
---
20

-- gets first element
(nth 0 (list 10 20 30))
---
10

== last

-- returns last element
(last (list 1 2 3))
---
3

-- returns only element
(last (list 42))
---
42

== init

-- returns all but last
(init (list 1 2 3))
---
(1 2)

== append

-- concatenates two lists
(append (list 1 2) (list 3 4))
---
(1 2 3 4)

-- appends to empty
(append () (list 1 2))
---
(1 2)

== prepend

-- adds to front
(prepend 0 (list 1 2))
---
(0 1 2)

== reverse

-- reverses a list
(reverse (list 1 2 3))
---
(3 2 1)

-- reverses empty
(null? (reverse ()))
---
t

== flatten

-- flattens nested lists
(flatten (list 1 (list 2 (list 3))))
---
(1 2 3)

-- flat list unchanged
(flatten (list 1 2 3))
---
(1 2 3)

== map

-- applies function to each
(map inc (list 1 2 3))
---
(2 3 4)

-- maps over empty
(null? (map inc ()))
---
t

== filter

-- keeps matching elements
(filter even? (list 1 2 3 4))
---
(2 4)

-- filters to empty
(null? (filter negative? (list 1 2 3)))
---
t

== for-each

-- applies function for side effects
(null? (for-each (fn (x) x) (list 1 2 3)))
---
t

== reject

-- removes matching elements
(reject even? (list 1 2 3 4))
---
(1 3)

== flat-map

-- maps and flattens
(flat-map (fn (x) (list x (* x 10))) (list 1 2 3))
---
(1 10 2 20 3 30)

== concat

-- concatenates multiple lists
(concat (list 1) (list 2 3) (list 4))
---
(1 2 3 4)

-- concatenates with empty
(concat () (list 1) ())
---
(1)

== any?

-- returns t when one matches
(any? even? (list 1 2 3))
---
t

-- returns nil when none match
(if (any? negative? (list 1 2 3)) "y" "n")
---
"n"

== every?

-- returns t when all match
(every? positive? (list 1 2 3))
---
t

-- returns nil when one fails
(if (every? even? (list 2 3 4)) "y" "n")
---
"n"

== none?

-- returns t when none match
(none? negative? (list 1 2 3))
---
t

-- returns nil when one matches
(if (none? even? (list 1 2 3)) "y" "n")
---
"n"

== empty?

-- true for empty list
(empty? ())
---
t

-- false for non-empty
(if (empty? (list 1)) "y" "n")
---
"n"

== find

-- finds first match
(find even? (list 1 3 4 6))
---
4

-- returns nil when not found
(null? (find negative? (list 1 2 3)))
---
t

== find-index

-- returns index of first match
(find-index even? (list 1 3 4 6))
---
2

-- returns -1 when not found
(find-index negative? (list 1 2 3))
---
-1

== index-of

-- finds element index
(index-of 30 (list 10 20 30))
---
2

-- returns -1 when not found
(index-of 99 (list 10 20 30))
---
-1

== includes?

-- finds element in list
(includes? 3 (list 1 2 3))
---
t

-- returns nil when not found
(if (includes? 9 (list 1 2 3)) "y" "n")
---
"n"

== count

-- counts matching elements
(count even? (list 1 2 3 4 5 6))
---
3

-- returns zero for no matches
(count negative? (list 1 2 3))
---
0

== take

-- takes first n elements
(take 2 (list 1 2 3 4))
---
(1 2)

-- takes zero
(null? (take 0 (list 1 2 3)))
---
t

-- takes more than available
(take 5 (list 1 2))
---
(1 2)

== drop

-- drops first n elements
(drop 2 (list 1 2 3 4))
---
(3 4)

-- drops zero
(drop 0 (list 1 2 3))
---
(1 2 3)

== take-while

-- takes while predicate holds
(take-while positive? (list 1 2 -3 4))
---
(1 2)

-- takes nothing when first fails
(null? (take-while negative? (list 1 2 3)))
---
t

== drop-while

-- drops while predicate holds
(drop-while positive? (list 1 2 -3 4))
---
(-3 4)

== split-at

-- splits list at index
(split-at 2 (list 1 2 3 4))
---
((1 2) (3 4))

== slice

-- extracts sublist
(slice 1 3 (list 10 20 30 40 50))
---
(20 30)

== range

-- generates ascending range
(range 0 5)
---
(0 1 2 3 4)

-- empty when start >= end
(null? (range 5 5))
---
t

== repeat

-- repeats a value
(repeat 0 3)
---
(0 0 0)

-- repeats zero times
(null? (repeat 0 0))
---
t

== times

-- calls function n times
(times identity 4)
---
(0 1 2 3)

-- applies function to indices
(times (fn (i) (* i i)) 4)
---
(0 1 4 9)

== unfold

-- builds a list from seed
(unfold (fn (x) (> x 5)) identity inc 1)
---
(1 2 3 4 5)

== iterate

-- generates repeated applications
(iterate (fn (x) (* x 2)) 4 1)
---
(1 2 4 8)

== zip

-- zips two lists
(zip (list 1 2 3) (list 4 5 6))
---
((1 4) (2 5) (3 6))

-- stops at shorter list
(zip (list 1 2) (list 3 4 5))
---
((1 3) (2 4))

== zip-with

-- zips with combining function
(zip-with + (list 1 2 3) (list 10 20 30))
---
(11 22 33)

== partition

-- splits by predicate
(partition even? (list 1 2 3 4 5 6))
---
((2 4 6) (1 3 5))

== group-by

-- groups by key function
(length (group-by even? (list 1 2 3 4 5)))
---
2

== sort

-- sorts ascending
(sort < (list 5 3 1 4 2))
---
(1 2 3 4 5)

-- sorts descending
(sort > (list 1 3 2))
---
(3 2 1)

-- sorts single element
(sort < (list 1))
---
(1)

-- sorts empty
(null? (sort < ()))
---
t

== sort-by

-- sorts by key function
(sort-by abs (list 3 -1 -2))
---
(-1 -2 3)

== uniq

-- removes consecutive duplicates
(uniq (list 1 1 2 2 3 3))
---
(1 2 3)

-- keeps non-consecutive duplicates
(uniq (list 1 2 1 2))
---
(1 2 1 2)

== uniq-by

-- removes consecutive duplicates by key
(length (uniq-by abs (list 1 -1 2 -2 3)))
---
3

== intersperse

-- inserts separator between elements
(intersperse 0 (list 1 2 3))
---
(1 0 2 0 3)

-- single element unchanged
(intersperse 0 (list 1))
---
(1)

== variadic append

-- appends two lists
(append (list 1 2) (list 3 4))
---
(1 2 3 4)

-- appends three lists
(append (list 1) (list 2) (list 3))
---
(1 2 3)

-- appends with empty
(append () (list 1 2) ())
---
(1 2)

-- appends zero lists
(null? (append))
---
t

-- appends one list
(append (list 1 2))
---
(1 2)

== multi-list map

-- maps over two lists
(map + (list 1 2 3) (list 10 20 30))
---
(11 22 33)

-- maps over three lists
(map + (list 1 2) (list 10 20) (list 100 200))
---
(111 222)

-- stops at shortest
(map + (list 1 2 3) (list 10 20))
---
(11 22)

-- single-list backward compat
(map inc (list 1 2 3))
---
(2 3 4)

== multi-list for-each

-- iterates two lists
(do (def r ()) (for-each (fn (a b) (set r (pair (+ a b) r))) (list 1 2) (list 10 20)) (reverse r))
---
(11 22)

-- single-list backward compat
(do (def r ()) (for-each (fn (x) (set r (pair x r))) (list 1 2 3)) (reverse r))
---
(1 2 3)

== transpose

-- transposes a matrix
(transpose (list (list 1 2 3) (list 4 5 6)))
---
((1 4) (2 5) (3 6))

== update

-- updates element at index
(update 1 99 (list 10 20 30))
---
(10 99 30)

== insert

-- inserts at index
(insert 1 99 (list 10 20 30))
---
(10 99 20 30)

== remove

-- removes n elements at start index
(remove 1 2 (list 10 20 30 40))
---
(10 40)

== adjust

-- applies function at index
(adjust 1 inc (list 10 20 30))
---
(10 21 30)
