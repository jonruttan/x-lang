# Transformer: generate's kept positions, and release
# @weight 3

`generate` keeps each block's queries, keys and values from one prediction
to the next, and works out one new position for each id it adds; on a host
with a GPU the weights are held there until `release`. The model is the
small one of `tests/x/lib/transformer-fixture.x`: 11 items, 8 positions, a
width of 8, 2 blocks and 2 heads. These cases are a file of their own
because each runs the forward pass, which on a host whose kernels all run
pure costs seconds.

## generate

### generate's kept positions agree with predicting from every id

Each id generate adds is the one predict answers from all the ids before
it.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def by-predict
    (fn (go ids k) (if (= k 0) ids (go (List append ids (list (m predict ids))) (- k 1)))))
  (equal? (m generate (list 1 5) 2) (by-predict (list 1 5) 2)))
```
---
    #t

### generate fills the positions and no more

The model has 8 positions. Seven ids and two more feed back eight; seven
and three would feed back nine, and are refused before any position is
worked out.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (list (List length (m generate (list 1 2 3 4 5 6 7) 2))
        (guard (e (Err label e)) (m generate (list 1 2 3 4 5 6 7) 3))))
```
---
    (9 'value)

## release

### release gives the weights back, and a released model refuses

On a host with a GPU the weights are held there, and a released model
raises a label state when used; on one without, release has nothing to
give back and the model goes on working. This case runs last: it releases
the kept model and drops it.

```x
(import x/num/transformer)
(import x/num/gpu)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (m release)
  (def r (guard (e (Err label e)) (m predict (list 1 2))))
  (m release)
  (set! transformer-fixture-kept ())
  (if (Gpu available?) (eq? r 'state) (number? r)))
```
---
    #t
