# @weight 2
## block-form methods (`x/type/block`): (subject sel (names ...) body ...)

### one name binds the element

```x
(List map (x) (* x 10) (list 1 2 3))
```
---
    (10 20 30)

### two names bind the 0-based index, then the element

```x
(List map (i x) (list i x) (list 7 8 9))
```
---
    ((0 7) (1 8) (2 9))

### the body closes over the call site

```x
(let ((k 100)) (List map (x) (+ x k) (list 1 2)))
```
---
    (101 102)

### the block sees a binding made after the wrap

```x
(do (def %blk-mult 3) (List map (x) (* x %blk-mult) (list 1 2)))
```
---
    (3 6)

### an index counter is per send, not shared

```x
(List map (i x) (List map (j y) (list i j x y) (list "a")) (list "p" "q"))
```
---
    (((0 0 "p" "a")) ((1 0 "q" "a")))

## the applicative form is untouched

### an explicit fn still works

```x
(List map (fn (_ x) (* x 2)) (list 1 2 3))
```
---
    (2 4 6)

### the variadic multi-list form still works

```x
(List map (fn (_ a b) (+ a b)) (list 1 2) (list 10 20))
```
---
    (11 22)

### a bare callable name still works

```x
(List map first (list (list 1 2) (list 3 4)))
```
---
    (1 3)

### a computed callable is still a call, not a binding list

```x
(do (def %blk-mk (fn (_) (fn (_ x) (* x 5)))) (List map (%blk-mk) (list 1 2)))
```
---
    (5 10)

## arity is checked per shape

### three names is an error for the element shape

```x
(guard (e "raised") (List map (a b c) a (list 1)))
```
---
    "raised"

### the error names the accepted shapes

```x
(guard (e e) (List map (a b c) a (list 1)))
```
---
    "block takes (element) or (index element), got names: 3"

## wrapping is per selector

### an unwrapped selector still reads its first argument as a callable

`unfold` takes three callables, so it is deliberately not wrapped -- a block
for one of three would confuse more than it saves -- and `(x)` there is a
call, not a binding list.

```x
(guard (e "not-callable") (List unfold (x) (> x 1) (list 1 2)))
```
---
    "not-callable"

### Block method! refuses a selector the class does not have

```x
(guard (e e) (Block method! List 'no-such-selector))
```
---
    "Block method!: no such method no-such-selector"

## documentation survives the wrap

### help still reports the applicative signature

```x
(help List/map)
```
---
      => LIST -- New list

## the element shape across the wrapped selectors

### filter

```x
(List filter (x) (> x 1) (list 3 1 2))
```
---
    (3 2)

### for-each returns nil and runs for effect

```x
(let ((acc (list ()))) (List for-each (x) (%set-first! acc (pair x (first acc))) (list 1 2 3)) (first acc))
```
---
    (3 2 1)

### find

```x
(List find (x) (> x 1) (list 1 2 3))
```
---
    2

### any? and all?

```x
(list (List any? (x) (> x 2) (list 1 2 3)) (List all? (x) (> x 0) (list 1 2 3)))
```
---
    (#t #t)

### sort-by, with the index available

```x
(List sort-by (i x) (- 0 x) (list 1 3 2))
```
---
    (3 2 1)

## the fold shape: (acc element)

### fold threads the accumulator

```x
(List fold (acc x) (+ acc x) 0 (list 1 2 3))
```
---
    6

### a third name is the index

```x
(List fold (acc i x) (+ acc (* x i)) 0 (list 5 5 5))
```
---
    15

### the init is evaluated, not treated as body

```x
(List fold (acc x) (+ acc x) (* 10 10) (list 1))
```
---
    101

## the binary shape: (a b)

### sort takes a comparator block

```x
(List sort (a b) (< a b) (list 3 1 2))
```
---
    (1 2 3)

### reduce takes a combiner block

```x
(List reduce (a b) (+ a b) (list 1 2 3))
```
---
    6

## Vector carries the same forms

### map with an index

```x
(#(1 2 3) map (i x) (* x i))
```
---
    #(0 2 6)

### fold, value form

```x
(#(1 2 3) fold (acc x) (+ acc x) 0)
```
---
    6

## Seq wraps once and every subclass inherits it

### a string iterates through Seq's block form

```x
(Str8 fold (acc i c) (+ acc i) 0 "abcd")
```
---
    6

## instance-method classes use the same surface

### Gen is an instance method -- the receiver is self, not a trailing argument

```x
(((Gen range 0 4) map (i x) (list i x)) ->list)
```
---
    ((0 0) (1 1) (2 2) (3 3))

### Gen fold carries its init after the body

```x
((Gen range 1 5) fold (acc x) (+ acc x) 0)
```
---
    10

### Dict uses the pair shape: two names are key and value

```x
(do (import x/type/dict)
    (let ((d (Dict from-alist (list (pair 'a 1)))))
      (let ((acc (list ()))) (d for-each (k v) (%set-first! acc (list k v))) (first acc))))
```
---
    ('a 1)

### Dict with one name still receives the pair

```x
(do (import x/type/dict)
    (let ((d (Dict from-alist (list (pair 'a 1)))))
      (let ((acc (list ()))) (d for-each (p) (%set-first! acc p)) (first acc))))
```
---
    ('a . 1)

### Set fold takes its init after the body

```x
(do (import x/type/set) ((Set of 1 2 3) fold (acc x) (+ acc x) 0))
```
---
    6

## group-by and partition

### group-by takes a key block

```x
(List group-by (x) (% x 2) (list 1 2 3 4))
```
---
    ((1 1 3) (0 2 4))

### group-by can key on the index

```x
(List group-by (i x) (< i 2) (list "a" "b" "c"))
```
---
    ((#t "a" "b") (#f "c"))

### partition takes a predicate block

```x
(List partition (x) (> x 2) (list 1 2 3 4))
```
---
    ((3 4) (1 2))

## Dict map uses the pair shape too

### two names are key and value

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1 'b 2)) map (k v) (* v 10)) get 'b))
```
---
    20

### the key is available to the body

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1)) map (k v) (list k v)) get 'a))
```
---
    ('a 1)

### one name binds the whole entry

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1)) map (e) (rest e)) get 'a))
```
---
    1

### the applicative form is untouched

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1)) map (fn (_ e) (* (rest e) 3))) get 'a))
```
---
    3

## every remaining callable-first selector

### List: the predicates

```x
(list (List count-if (x) (> x 1) (list 3 1 2 1)) (List none? (x) (> x 9) (list 1)) (List reject (x) (> x 1) (list 3 1 2 1)) (List find-index (x) (= x 2) (list 3 1 2)))
```
---
    (2 #t (1 1) 2)

### List: uniq-by (consecutive duplicates) and drop-while

```x
(list (List uniq-by (x) x (list 1 1 2 2 1)) (List drop-while (x) (> x 1) (list 3 1 2 1)))
```
---
    ((1 2 1) (1 2 1))

### List: fold-right and scan take the fold shape

```x
(list (List fold-right (acc x) (pair x acc) () (list 3 1 2)) (List scan (acc x) (+ acc x) 0 (list 1 2 3)))
```
---
    ((3 1 2) (0 1 3 6))

### List: zip-with is binary over two lists

```x
(List zip-with (a b) (+ a b) (list 1 2) (list 10 20))
```
---
    (11 22)

### List: iterate's successor takes one name; the count and seed trail

```x
(List iterate (x) (* x 2) 4 1)
```
---
    (1 2 4 8)

### Gen: none?, drop-while, scan, zip-with

```x
(list ((Gen range 0 3) none? (x) (> x 5)) (((Gen range 0 6) drop-while (x) (< x 3)) ->list) (((Gen range 1 5) scan (a x) (+ a x) 0) ->list) (((Gen of 1 2) zip-with (a b) (+ a b) (Gen of 10 20)) ->list))
```
---
    (#t (3 4 5) (1 3 6 10) (11 22))

### Gen: the constructors are static, and the seed follows the block

```x
(list (((Gen iterate (x) (* x 2) 1) take 4) ->list) ((Gen make (st) (if (< st 3) (pair st (+ st 1)) ()) 0) ->list))
```
---
    ((1 2 4 8) (0 1 2))

### Iter make: a nil next-state ends after that value

```x
(Iter ->list (Iter make (st) (if (< st 2) (pair st (+ st 1)) (pair st ())) 0))
```
---
    (0 1 2)

### Assoc: map hands the block the value, filter the assoc -- two shapes on one class

```x
(list (Assoc map (v) (* v 10) (list (pair 'a 1) (pair 'b 2))) (Assoc filter (k v) (> v 1) (list (pair 'a 1) (pair 'b 2))))
```
---
    ((('a . 10) ('b . 20)) (('b . 2)))

## the callback need not be first

### times: the count is ahead of the block

```x
(List times 4 (i) (* i i))
```
---
    (0 1 4 9)

### adjust: the index, then the block, then the list

```x
(List adjust 0 (x) (* x 100) (list 1 2 3))
```
---
    (100 2 3)

### a leading form is evaluated in the caller's env

```x
(let ((n 2)) (List times (+ n 1) (i) i))
```
---
    (0 1 2)

### the applicative form at position 1 is unchanged

```x
(list (List times 3 (fn (_ i) (+ i 1))) (List adjust 1 (fn (_ x) (- x)) (list 1 2 3)))
```
---
    ((1 2 3) (1 -2 3))

## a thunk is a block with no names

### Dict get-or-else: the body is the default, and runs only on a miss

```x
(do (import x/type/dict)
  (let ((d (Dict from-plist (list 'a 1))))
    (list (d get-or-else () (* 6 7) 'zzz) (d get-or-else () (error "must not run") 'a))))
```
---
    (42 1)

### Assoc opt-get-or-else

```x
(Assoc opt-get-or-else () 99 'q (list (pair 'a 1)))
```
---
    99

### the thunk shape refuses names

```x
(do (import x/type/dict) (guard (e e) ((Dict from-plist (list 'a 1)) get-or-else (x) x 'a)))
```
---
    "block takes () -- a thunk binds no names, got names: 1"

### an empty binding list in an element seat fails clearly, not silently

```x
(guard (e e) (List map () 1 (list 1)))
```
---
    "block takes (element) or (index element), got names: 0"

## the wrap documents itself

`(help Class/sel)` answered only the applicative signature -- true, and
incomplete. The wrap is the one place that knows the shape, so it adds a
"Block form:" note to the method's own entry. The registry is inspected
directly here rather than help's output, so the spec is not coupled to
help's layout.

### a wrapped method's help carries the block form

```x
(do (help List map)
    (List any? (n) (Str8 includes? "Block form" n) (%doc-entry-notes (%doc-lookup ((prim-ref 'str '->sym) "List/map")))))
```
---
    #t

### the note is shape-specific: fold names the accumulator, thunk names no one

```x
(do (import x/type/dict) (help List fold)
    (list (List any? (n) (Str8 includes? "(acc i x)" n) (%doc-entry-notes (%doc-lookup ((prim-ref 'str '->sym) "List/fold"))))
          (List any? (n) (Str8 includes? "() body" n) (%doc-entry-notes (%doc-lookup ((prim-ref 'str '->sym) "Dict/get-or-else"))))))
```
---
    (#t #t)

### an inherited method finds the ancestor's note

```x
(do (help Str8 for-each)
    (List any? (n) (Str8 includes? "Block form" n) (%doc-entry-notes (%doc-lookup ((prim-ref 'str '->sym) "Seq/for-each")))))
```
---
    #t

### the note shows the method's own head, the block in the callable's seat

```x
(do (help Vector filter)
    (List any? (n) (Str8 includes? "(Vector filter (x) body ... v)" n) (%doc-entry-notes (%doc-lookup (%str->symbol "Vector/filter")))))
```
---
    #t

### an instance method's head has no class; a fold's carries its init and subject

```x
(do (import x/type/dict) (help Dict for-each) (help List fold)
    (list (List any? (n) (Str8 includes? "(for-each (p) body ...)" n) (%doc-entry-notes (%doc-lookup (%str->symbol "Dict/for-each"))))
          (List any? (n) (Str8 includes? "(List fold (acc x) body ... init lst)" n) (%doc-entry-notes (%doc-lookup (%str->symbol "List/fold"))))))
```
---
    (#t #t)

### a callback that is not first keeps its place in the head

```x
(do (help List times)
    (List any? (n) (Str8 includes? "(List times n (x) body ...)" n) (%doc-entry-notes (%doc-lookup (%str->symbol "List/times")))))
```
---
    #t

### wrapping twice does not say it twice

```x
(do (help List map) (Block method! List 'map) (Block method! List 'map)
    (List count-if (n) (Str8 includes? "Block form" n) (%doc-entry-notes (%doc-lookup ((prim-ref 'str '->sym) "List/map")))))
```
---
    1

## a list has value dispatch (0.14.0): a symbol selector sends to `List`

`(%bind-call-over! (Type of (list 1)) List)` sits OVER the engine's list
call, so the value form reads exactly as a vector's or a string's --
`((List of 1 2 3) filter (x) (> x 1))` -- while an index or a slice still
goes to the handler underneath, and nested list DATA the iterator
re-evaluates keeps its echo.

### the block form at the value, subject spliced last

```x
((List of 1 2 3) filter (x) (> x 1))
```
---
    (2 3)

### two names bind the 0-based index, then the element

```x
((List of 1 2 3) map (i x) (* i x))
```
---
    (0 2 6)

### a fold's init trails the block

```x
((List of 1 2 3) fold (acc x) (+ acc x) 0)
```
---
    6

### the applicative form rides the same door

```x
((List of 1 2 3) map (fn (_ x) (* x 10)))
```
---
    (10 20 30)

### an index and a slice still go to the list call underneath

```x
(list ((List of 1 2 3) 0) ((List of 1 2 3) 1 3))
```
---
    (1 (2 3))

### nested list data re-evaluated by the iterator keeps its echo

```x
(List map (fn (_ e) e) (lit ((1 2) x)))
```
---
    ((1 2) 'x)

### a selector the class does not have is a method miss, not a crash

```x
((List of 1 2 3) frob)
```
---
    Error: object: no such method frob

## a builder's block: `Vector build`

`Vector build` takes its count ahead of the callback, as `List times` does,
so it wraps at position 1; the applicative form stays live beside it.

### the block form builds by index

```x
(Vector build 3 (i) (* i i))
```
---
    #(0 1 4)

### the applicative form is unchanged

```x
(Vector build 3 (fn (_ i) (* i i)))
```
---
    #(0 1 4)

### its help note shows the count ahead of the block

```x
(do (help Vector build)
    (List any? (n) (Str8 includes? "(Vector build n (x) body ...)" n) (%doc-entry-notes (%doc-lookup (%str->symbol "Vector/build")))))
```
---
    #t
