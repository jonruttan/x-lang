# Deferred cross-module registration (Pact)

`Pact` is the rendezvous for modules that are optional to each other: a
module `join`s under a stable name symbol as its last load-time act, and a
pairwise registration is filed with `when`, which runs the thunk immediately
if every named party has already joined and queues it otherwise, firing
exactly once at the join that completes it. `get`/`has?` read the roll-call.
The numeric tower uses it so its members load in any order (float's
bignum->float conversion is the first client).

## roll-call

### get on an unjoined name is nil

```scheme
(import x/sys/pact)
(null? (Pact get (lit pact-ghost)))
```
---
    #t

### has? is #f (not nil) before a join

```scheme
(import x/sys/pact)
(Pact has? (lit pact-ghost))
```
---
    #f

### join publishes a value that get reads back

```scheme
(import x/sys/pact)
(Pact join (lit pact-alpha) 42)
(Pact get (lit pact-alpha))
```
---
    42

### has? is true after a join

```scheme
(import x/sys/pact)
(Pact has? (lit pact-alpha))
```
---
    #t

### a re-join shadows the earlier value

```scheme
(import x/sys/pact)
(Pact join (lit pact-g) 1)
(Pact join (lit pact-g) 2)
(Pact get (lit pact-g))
```
---
    2

## when-entries

### when fires immediately if the party already joined

```scheme
(import x/sys/pact)
(Pact join (lit pact-b) 7)
(def r1 ())
(Pact when (list (lit pact-b)) (fn (_ b) (set! r1 b)))
r1
```
---
    7

### when defers until the join arrives

```scheme
(import x/sys/pact)
(def r2 ())
(Pact when (list (lit pact-c)) (fn (_ c) (set! r2 c)))
(def before (null? r2))
(Pact join (lit pact-c) 9)
(list before r2)
```
---
    (#t 9)

### a multi-party entry waits for every name, values arrive in names order

```scheme
(import x/sys/pact)
(def r3 ())
(Pact when (list (lit pact-d) (lit pact-e)) (fn (_ d e) (set! r3 (- d e))))
(Pact join (lit pact-d) 10)
(def mid (null? r3))
(Pact join (lit pact-e) 3)
(list mid r3)
```
---
    (#t 7)

### an entry fires exactly once; a re-join does not re-fire it

```scheme
(import x/sys/pact)
(def n1 0)
(Pact when (list (lit pact-f)) (fn (_ v) (set! n1 (+ n1 1))))
(Pact join (lit pact-f) 1)
(Pact join (lit pact-f) 2)
n1
```
---
    1

### a fired thunk may itself file a new when-entry

```scheme
(import x/sys/pact)
(def r4 ())
(Pact when (list (lit pact-h))
  (fn (_ h) (Pact when (list (lit pact-h)) (fn (_ h2) (set! r4 h2)))))
(Pact join (lit pact-h) 5)
r4
```
---
    5
