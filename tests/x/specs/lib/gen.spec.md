# Lazy generators (Gen)

`Gen` is a lazy generator: a step function over a state that produces values on
demand. Transformers (`map`/`filter`/`take`/…) are lazy and return a new `Gen`;
consumers (`->list`/`fold`/`sum`/…) drive it. Because a `Gen` is an object, the
fluent `((g map f) filter p)` form is ordinary method dispatch, and no
intermediate list is built between stages.

## Constructors

### range -- integers [start, stop)

```scheme
((Gen range 0 4) ->list)
```
---
    (0 1 2 3)

### range-by -- with a step

```scheme
((Gen range-by 0 10 3) ->list)
```
---
    (0 3 6 9)

### range-by rejects a zero step (it would never terminate)

```scheme
((Gen range-by 0 10 0) ->list)
```
---
    Error: Gen range-by: step must be non-zero

### count-from is infinite -- take bounds it

```scheme
(((Gen count-from 1) take 3) ->list)
```
---
    (1 2 3)

### iterate -- x, (f x), (f (f x)), ...

```scheme
(((Gen iterate (fn (_ n) (* n 2)) 1) take 4) ->list)
```
---
    (1 2 4 8)

### of -- over given values

```scheme
((Gen of 1 2 3) ->list)
```
---
    (1 2 3)

## Lazy transformers

### map

```scheme
(((Gen range 0 4) map (fn (_ x) (* x x))) ->list)
```
---
    (0 1 4 9)

### filter

```scheme
(((Gen range 0 6) filter (fn (_ x) (Num even? x))) ->list)
```
---
    (0 2 4)

### drop

```scheme
(((Gen range 0 5) drop 2) ->list)
```
---
    (2 3 4)

### take-while

```scheme
(((Gen count-from 1) take-while (fn (_ x) (< x 4))) ->list)
```
---
    (1 2 3)

### drop-while

```scheme
(((Gen range 0 6) drop-while (fn (_ x) (< x 3))) ->list)
```
---
    (3 4 5)

### enumerate -- (index . value)

```scheme
(((Gen of 10 20) enumerate) ->list)
```
---
    ((0 . 10) (1 . 20))

### zip-with -- stops at the shorter

```scheme
(((Gen range 0 3) zip-with (fn (_ a b) (+ a b)) (Gen range 10 13)) ->list)
```
---
    (10 12 14)

### scan -- running fold

```scheme
(((Gen range 1 5) scan (fn (_ a x) (+ a x)) 0) ->list)
```
---
    (1 3 6 10)

### lazy chaining builds no intermediate list

```scheme
(((((Gen range 0 100) map (fn (_ x) (* x x))) filter (fn (_ x) (Num even? x))) take 3) ->list)
```
---
    (0 4 16)

## Consumers

### fold

```scheme
((Gen range 1 5) fold (fn (_ a x) (+ a x)) 0)
```
---
    10

### sum / count

```scheme
(list ((Gen range 1 5) sum) ((Gen range 0 7) count))
```
---
    (10 7)

### any? short-circuits

```scheme
((Gen range 0 5) any? (fn (_ x) (> x 3)))
```
---
    #t

### find

```scheme
((Gen range 0 9) find (fn (_ x) (> x 5)))
```
---
    6

### ref / first / last

```scheme
(list ((Gen range 0 9) ref 3) ((Gen range 5 9) first) ((Gen range 5 9) last))
```
---
    (3 5 8)

### min / max

```scheme
(list ((Gen of 3 1 4 1 5) min) ((Gen of 3 1 4 1 5) max))
```
---
    (1 5)

### ->vector

```scheme
((Gen range 0 3) ->vector)
```
---
    #(0 1 2)
