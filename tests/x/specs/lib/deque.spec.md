# Deque: a double-ended queue (#375)
# @weight 1

The two-list construction: both ends push and pop amortized O(1);
length rides a counter. Empty pops raise kind-'value.

## both ends

### push/pop each end; ->list reads left to right

```scheme
(do (import x/type/deque)
  (def d (Deque make))
  (d push! 2) (d push-left! 1) (d push! 3)
  (list (d ->list) (d pop-left!) (d pop!) (d peek) (d peek-left) (d length)))
```
---
    ((1 2 3) 1 3 2 2 1)

### draining across the internal rebalance keeps order

```scheme
(do (import x/type/deque)
  (def d (Deque make))
  (d push! 1) (d push! 2) (d push! 3) (d push! 4)
  (list (d pop-left!) (d pop-left!) (d pop!) (d pop-left!) (d empty?)))
```
---
    (1 2 4 3 #t)

### empty pops raise 'value

```scheme
(do (import x/type/deque)
  (list (guard (e (Err kind-of e)) ((Deque make) pop!))
        (guard (e (Err kind-of e)) ((Deque make) pop-left!))))
```
---
    ('value 'value)
