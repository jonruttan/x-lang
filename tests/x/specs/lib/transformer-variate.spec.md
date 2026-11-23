# Transformer: variate, an id drawn at random
# @weight 3

`variate` draws the next id at random from the model's scores, each
item's chance in proportion to the exponential of its score over the
temperature; `greatest` limits the draw to that many of the highest
scores. The model is the small one of
`tests/x/lib/transformer-fixture.x`: 11 items, 8 positions, a width of 8,
2 blocks and 2 heads. These cases are a file of their own because each
runs the forward pass, which on a host whose kernels all run pure costs
seconds.

## variate

### among the one greatest, the draw is predict's id

```x
(import x/num/transformer)
(import x/num/random)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (= (m variate (list 1 5) (Random sw 7) 1 1) (m predict (list 1 5))))
```
---
    #t

### a draw is an id of the vocabulary

```x
(import x/num/transformer)
(import x/num/random)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def id (m variate (list 1 5) (Random sw 7) 2))
  (if (< id 0) #f (< id 11)))
```
---
    #t

### a temperature not above 0, a greatest not above 0 and a source that is no Random are refused

Each is refused before any position is worked out.

```x
(import x/num/transformer)
(import x/num/random)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (list (guard (e (Err label e)) (m variate (list 1 5) (Random sw 7) 0))
        (guard (e (Err label e)) (m variate (list 1 5) (Random sw 7) 1 0))
        (guard (e (Err label e)) (m variate (list 1 5) 7))))
```
---
    ('value 'value 'type)
