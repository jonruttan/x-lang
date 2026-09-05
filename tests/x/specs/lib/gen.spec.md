# Lazy generators (Gen)
# @weight 1

`Gen` is a lazy generator: a step function over a state that produces values on
demand. Transformers (`map`/`filter`/`take`/…) are lazy and return a new `Gen`;
consumers (`->list`/`fold`/`sum`/…) drive it. Because a `Gen` is an object, the
fluent `((g map f) filter p)` form is ordinary method dispatch, and no
intermediate list is built between stages.

## Constructors

### range -- integers [start, stop)

```x
((Gen range 0 4) ->list)
```
---
    (0 1 2 3)

### range-by -- with a step

```x
((Gen range-by 0 10 3) ->list)
```
---
    (0 3 6 9)

### range-by rejects a zero step (it would never terminate)

```x
((Gen range-by 0 10 0) ->list)
```
---
    Error: #<err:value Gen range-by: step must be non-zero>

### count-from is infinite -- take bounds it

```x
(((Gen count-from 1) take 3) ->list)
```
---
    (1 2 3)

### iterate -- x, (f x), (f (f x)), ...

```x
(((Gen iterate (fn (_ n) (* n 2)) 1) take 4) ->list)
```
---
    (1 2 4 8)

### of -- over given values

```x
((Gen of 1 2 3) ->list)
```
---
    (1 2 3)

## Lazy transformers

### map

```x
(((Gen range 0 4) map (fn (_ x) (* x x))) ->list)
```
---
    (0 1 4 9)

### filter

```x
(((Gen range 0 6) filter (fn (_ x) (Num even? x))) ->list)
```
---
    (0 2 4)

### drop

```x
(((Gen range 0 5) drop 2) ->list)
```
---
    (2 3 4)

### take-while

```x
(((Gen count-from 1) take-while (fn (_ x) (< x 4))) ->list)
```
---
    (1 2 3)

### drop-while

```x
(((Gen range 0 6) drop-while (fn (_ x) (< x 3))) ->list)
```
---
    (3 4 5)

### enumerate -- (index . value)

```x
(((Gen of 10 20) enumerate) ->list)
```
---
    ((0 . 10) (1 . 20))

### zip-with -- stops at the shorter

```x
(((Gen range 0 3) zip-with (fn (_ a b) (+ a b)) (Gen range 10 13)) ->list)
```
---
    (10 12 14)

### scan -- running fold

```x
(((Gen range 1 5) scan (fn (_ a x) (+ a x)) 0) ->list)
```
---
    (1 3 6 10)

### lazy chaining builds no intermediate list

```x
(((((Gen range 0 100) map (fn (_ x) (* x x))) filter (fn (_ x) (Num even? x))) take 3) ->list)
```
---
    (0 4 16)

## Consumers

### fold

```x
((Gen range 1 5) fold (fn (_ a x) (+ a x)) 0)
```
---
    10

### sum / count

```x
(list ((Gen range 1 5) sum) ((Gen range 0 7) count))
```
---
    (10 7)

### any? short-circuits

```x
((Gen range 0 5) any? (fn (_ x) (> x 3)))
```
---
    #t

### find

```x
((Gen range 0 9) find (fn (_ x) (> x 5)))
```
---
    6

### ref / first / last

```x
(list ((Gen range 0 9) ref 3) ((Gen range 5 9) first) ((Gen range 5 9) last))
```
---
    (3 5 8)

### min / max

```x
(list ((Gen of 3 1 4 1 5) min) ((Gen of 3 1 4 1 5) max))
```
---
    (1 5)

### ref errors past the last value (absence discipline: no nil miss)

```x
((Gen range 0 3) ref 9)
```
---
    Error: #<err:index Gen ref: index out of range>

### ref errors on a negative index

```x
((Gen range 0 3) ref -1)
```
---
    Error: #<err:index Gen ref: index out of range>

### first errors on an empty generator; empty? is the presence door

```x
((Gen of) first)
```
---
    Error: #<err:value Gen first: empty generator>

### reduce errors on an empty generator

```x
((Gen of) reduce +)
```
---
    Error: #<err:value Gen reduce: empty generator>

### empty? peeks without consuming (a Gen is persistent)

```x
(do (def g (Gen of 1 2))
  (list ((Gen of) empty?) (g empty?) (g ->list)))
```
---
    (#t #f (1 2))

### from-seq drives any iterable through the C iterator steps

```x
(list ((Gen from-seq (list 1 2 3)) ->list)
      ((Gen from-seq (Vector of 4 5)) ->list)
      ((Gen from-seq "ab") ->list))
```
---
    ((1 2 3) (4 5) (#\a #\b))

### ->vector

```x
((Gen range 0 3) ->vector)
```
---
    #(0 1 2)
