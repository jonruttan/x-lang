# Counter: a counting map (#375)

Dict-backed tallies: absent keys read 0, add! increments by 1 or n,
most-common ranks by count (stable sort -- ties keep table order).

## tallying

### from-list counts occurrences; absent keys read 0

```scheme
(do (import x/type/counter)
  (def c (Counter from-list (list 'a 'b 'a 'c 'a 'b)))
  (list (c get 'a) (c get 'b) (c get 'z) (c total)))
```
---
    (3 2 0 6)

### most-common ranks descending; n takes the top slice

```scheme
(do (import x/type/counter)
  (def c (Counter from-list (list 'a 'b 'a 'c 'a 'b)))
  (c most-common 2))
```
---
    (('a . 3) ('b . 2))

### add! by n, del! forgets, chaining works

```scheme
(do (import x/type/counter)
  (def c (Counter make))
  ((c add! 'x 10) add! 'x)
  (def before (c get 'x))
  (c del! 'x)
  (list before (c get 'x)))
```
---
    (11 0)
