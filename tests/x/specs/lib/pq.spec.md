# Pq: a binary-heap priority queue (#375)

Comparator-ordered ((cmp a b) -> #t when a comes strictly first, the
List sort contract); Array-backed; push!/pop! O(log n), peek O(1).
The heap structure under the queue name -- Heap is the GC class.

## ordering

### pops come out in comparator order, duplicates included

```scheme
(do (import x/type/pq)
  (def q (Pq make (fn (_ a b) (< a b))))
  (q push! 5) (q push! 1) (q push! 4) (q push! 1) (q push! 8)
  (list (q peek) (q pop!) (q pop!) (q pop!) (q pop!) (q pop!) (q empty?)))
```
---
    (1 1 1 4 5 8 #t)

### the comparator picks the order: a max-queue

```scheme
(do (import x/type/pq)
  (def q (Pq make (fn (_ a b) (> a b))))
  (q push! 3) (q push! 9) (q push! 6)
  (list (q pop!) (q pop!) (q pop!)))
```
---
    (9 6 3)

### empty peek and pop raise 'value

```scheme
(do (import x/type/pq)
  (def q (Pq make (fn (_ a b) (< a b))))
  (list (guard (e (Err kind-of e)) (q peek))
        (guard (e (Err kind-of e)) (q pop!))))
```
---
    ('value 'value)
