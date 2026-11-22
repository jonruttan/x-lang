# Transformer: a language model's forward pass
# @weight 3

`Transformer` reads a model in GPT-2's layout from a safetensors file and
answers logits, a prediction, and generated ids. The model here is small:
11 items, 8 positions, a width of 8, 2 blocks and 2 heads, its weights made
by a formula in `tests/x/lib/transformer-fixture.x`. The logits expected
are those a reference implementation of GPT-2 answers for the same
weights, and a case compares within a ten-thousandth: the products run on
the GPU where there is one and through Matrix's kernels otherwise, and the
two differ in their last places.

Each case's imports are forms of their own, ahead of the form that holds
the numbers: a form is read whole before any of it runs, and a float
written in the form that first loads the float reader is not read as one.

The cases share the model, which the fixture makes once, and ask for few
forward passes of few ids: on a host whose kernels all run pure, a pass of
four ids takes seconds.

## logits

### a row for each id and a column for each item

```x
(import x/num/transformer)
(import x/num/matrix)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def l ((transformer-fixture-model) logits (list 1 5 2 7)))
  (list (l extent) (l encoding) (instance-of? l Matrix)
        (transformer-near? (l ->list)
          '((-0.622341 -0.798763 -0.770171 1.594225 0.344426 0.373017 -0.365137 -0.641403 -0.612811 -0.789232 0.00301)
            (-1.065251 0.775802 0.86604 0.629199 0.69382 0.784057 -1.108989 -1.125409 -1.035171 0.805881 0.403364)
            (1.115094 -0.055052 -0.192408 -0.769145 -0.957624 -1.09498 0.930103 1.206665 1.069308 -0.100837 -0.499751)
            (1.155861 -0.132601 -0.274246 -0.713959 -0.913755 -1.0554 0.865231 1.250291 1.108645 -0.179816 -0.459771)))))
```
---
    ((4 11) 'f32 #t #t)

### one id answers one row

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def l ((transformer-fixture-model) logits (list 4)))
  (list (l extent)
        (transformer-near? (l ->list)
          '((-1.577576 0.216141 0.347549 1.209356 0.792811 0.924219 -0.728249 -1.665182 -1.533774 0.259944 0.383243)))))
```
---
    ((1 11) #t)

### a position's logits do not depend on the ids after it

The rows for the ids 1 and 5 alone are the first two rows for 1, 5, 2 and
7 above.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(transformer-near? (((transformer-fixture-model) logits (list 1 5)) ->list)
  '((-0.622341 -0.798763 -0.770171 1.594225 0.344426 0.373017 -0.365137 -0.641403 -0.612811 -0.789232 0.00301)
    (-1.065251 0.775802 0.86604 0.629199 0.69382 0.784057 -1.108989 -1.125409 -1.035171 0.805881 0.403364)))
```
---
    #t

## predict and generate

### predict answers the id scored highest after the ids

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(list ((transformer-fixture-model) predict (list 1 5 2 7)) ((transformer-fixture-model) predict (list 0)))
```
---
    (7 3)

### generate adds each prediction to the ids the next is made from

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(list ((transformer-fixture-model) generate (list 2 2) 3) ((transformer-fixture-model) generate (list 9 4) 0))
```
---
    ((2 2 7 6 6) (9 4))

### generate's kept positions agree with predicting from every id

generate works out the prompt once and then one position for each id it
adds, attending to the queries, keys and values it kept. Each id it adds
is the one predict answers from all the ids before it.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def by-predict
    (fn (go ids k) (if (= k 0) ids (go (List append ids (list (m predict ids))) (- k 1)))))
  (equal? (m generate (list 1 5 2 7) 4) (by-predict (list 1 5 2 7) 4)))
```
---
    #t

### generate fills the positions and no more

The model has 8 positions. Six ids and three more feed back eight; seven
and three would feed back nine.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (list (List length (m generate (list 1 2 3 4 5 6) 3))
        (guard (e (Err label e)) (m generate (list 1 2 3 4 5 6 7) 3))))
```
---
    (9 'value)

## refusals

### no ids, too many ids, and an id with no item raise a label value

The model has 8 positions and 11 items.

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (list (guard (e (Err label e)) (m logits ()))
        (guard (e (Err label e)) (m logits (list 1 2 3 4 5 6 7 8 9)))
        (guard (e (Err label e)) (m predict (list 1 11)))
        (guard (e (Err label e)) (m generate (list 1 2 3 4 5 6 7 8 9) 1))))
```
---
    ('value 'value 'value 'value)

### heads that do not divide the width raise a label value

```x
(import x/num/transformer)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def tmp (File temp "/tmp/x-transformer-heads-"))
  (File close (first tmp))
  (transformer-fixture (rest tmp))
  (def out (list (guard (e (Err label e)) (Transformer from-file (rest tmp) 3))
                 (guard (e (Err label e)) (Transformer from-file (rest tmp) 0))))
  (File unlink (rest tmp))
  out)
```
---
    ('value 'value)

### a file that lacks a tensor raises a label value

```x
(import x/num/transformer)
(import x/codec/safetensors)
(do
  (def tmp (File temp "/tmp/x-transformer-lacks-"))
  (File close (first tmp))
  (Safetensors write (rest tmp) (Dict from-plist (list "wte.weight" (Tensor zeros '(3 4) 'f32))))
  (def out (guard (e (Err label e)) (Transformer from-file (rest tmp) 2)))
  (File unlink (rest tmp))
  out)
```
---
    'value

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
