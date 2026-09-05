# @weight 1
## assoc-get

### retrieves value by key

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc get 'b al))
```
---
    2

### returns nil for missing key

```x
(do (def al (list (pair 'a 1))) (null? (Assoc get 'z al)))
```
---
    #t

### retrieves value from first entry

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc get 'a al))
```
---
    1

## assoc-get-or

### returns value when key exists

```x
(do (def al (list (pair 'a 1))) (Assoc get-or 99 'a al))
```
---
    1

### returns default when key missing

```x
(do (def al (list (pair 'a 1))) (Assoc get-or 99 'z al))
```
---
    99

### returns a stored nil, not the default

```x
(do (def al (list (pair 'a ()))) (null? (Assoc get-or 99 'a al)))
```
---
    #t

### stored #f is not the default either

```x
(do (def al (list (pair 'a #f))) (Assoc get-or 99 'a al))
```
---
    #f

## assoc-has?

### returns #t when key exists

```x
(do (def al (list (pair 'a 1))) (Assoc has? 'a al))
```
---
    #t

### returns nil when key missing

```x
(do (def al (list (pair 'a 1))) (if (Assoc has? 'z al) "y" "n"))
```
---
    "n"

### finds key after first entry

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc has? 'b al))
```
---
    #t

## assoc-put

### adds key-value pair

```x
(do (def al (list (pair 'a 1))) (Assoc get 'b (Assoc put 'b 2 al)))
```
---
    2

## assoc-del

### removes key from alist

Value, not length: a count of 1 is true whichever entry was deleted.

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc del 'a al))
```
---
    (('b . 2))

### returns the alist unchanged when key not present

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc del 'z al))
```
---
    (('a . 1) ('b . 2))

### removes key not at head

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (null? (Assoc get 'b (Assoc del 'b al))))
```
---
    #t

## assoc-keys

### returns list of keys

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc keys al))
```
---
    ('a 'b)

## assoc-vals

### returns list of values

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc vals al))
```
---
    (1 2)

## assoc-map

### applies function to all values

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc get 'a (Assoc map (method-ref Num inc) al)))
```
---
    2

## assoc-filter

### filters entries by predicate

Value, not length: a count of 1 is true whichever entry survived.

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc filter (fn (_ e) (> (rest e) 1)) al))
```
---
    (('b . 2))

## assoc-merge

### merges two alists, a's entries first

A length assertion alone let #73 hide here: the count is 2 in either order.
Assert the value, and use overlapping keys so priority is covered too.

```x
(Assoc merge (list (pair 'a 1)) (list (pair 'a 9) (pair 'b 2)))
```
---
    (('a . 1) ('b . 2))

### additions keep b's order

```x
(Assoc merge (list (pair 'a 1)) (list (pair 'b 2) (pair 'c 3)))
```
---
    (('a . 1) ('b . 2) ('c . 3))

### a duplicate key inside b keeps its first occurrence

```x
(Assoc merge () (list (pair 'b 2) (pair 'b 9)))
```
---
    (('b . 2))

## assoc-pick

### selects entries by key list

Value, not length: picking the WRONG two keys also counts 2.

```x
(do (def al (list (pair 'a 1) (pair 'b 2) (pair 'c 3))) (Assoc pick (list 'a 'c) al))
```
---
    (('a . 1) ('c . 3))

## assoc-omit

### removes entries by key list

Value, not length: omitting the WRONG key also counts 2.

```x
(do (def al (list (pair 'a 1) (pair 'b 2) (pair 'c 3))) (Assoc omit (list 'a) al))
```
---
    (('b . 2) ('c . 3))

## from-bindings

### converts a bindings list (the let shape) to an alist

```x
(do (def al (Assoc from-bindings (list (list 'a 1) (list 'b 2)))) (Assoc get 'a al))
```
---
    1

## from-plist / ->plist

### plist to alist and back

```x
(do (def al (Assoc from-plist (list 'a 1 'b 2)))
  (list (Assoc get 'b al) (Assoc ->plist al)))
```
---
    (2 ('a 1 'b 2))

### from-plist rejects an odd-length plist

```x
(Assoc from-plist (list 'a 1 'b))
```
---
    Error: #<err:value Assoc from-plist: odd-length plist>

## ->bindings

### converts an alist to a bindings list

```x
(do (def al (list (pair 'a 1))) (first (first (Assoc ->bindings al))))
```
---
    'a

## evolve

### transforms values by matching keys

```x
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc get 'a (Assoc evolve (list (pair 'a (method-ref Num inc))) al)))
```
---
    2

## opt-get-or

### returns the value for a present key (plist)

```x
(Assoc opt-get-or 99 'a (list 'a 1))
```
---
    1

### returns the default for a missing key

```x
(Assoc opt-get-or 99 'z (list 'a 1))
```
---
    99

### reads from an alist store

```x
(Assoc opt-get-or 99 'a (list (pair 'a 1)))
```
---
    1

### keeps a present 0 instead of the default

```x
(Assoc opt-get-or 99 'a (list 'a 0))
```
---
    0

## opt-get-or-else

### returns the value for a present key

```x
(Assoc opt-get-or-else (fn () 99) 'a (list 'a 1))
```
---
    1

### calls the thunk for a missing key

```x
(Assoc opt-get-or-else (fn () 99) 'z (list 'a 1))
```
---
    99

### does not run the thunk when the key is present

```x
(Assoc opt-get-or-else (fn () (error "boom")) 'a (list 'a 1))
```
---
    1

### keeps a present 0 without calling the thunk

```x
(Assoc opt-get-or-else (fn () 99) 'a (list 'a 0))
```
---
    0

## let-opts

### binds from a plist source with defaults

```x
(let-opts (list 'a 1) ((a 0) (b 9)) (list a b))
```
---
    (1 9)

### binds from an alist source

```x
(let-opts (list (pair 'a 1)) ((a 0)) a)
```
---
    1

### default is lazy: not evaluated when the option is present

```x
(let-opts (list 'a 1) ((a (error "boom"))) a)
```
---
    1

### (name key default) binds a renamed key when present

```x
(let-opts (list 'bg-color "red") ((bg bg-color "black")) bg)
```
---
    "red"

### (name key default) uses the default when the renamed key is absent

```x
(let-opts () ((bg bg-color "black")) bg)
```
---
    "black"

### a bare name defaults to nil

```x
(let-opts (list 'x 5) (x y) (list x (null? y)))
```
---
    (5 #t)

### a later default can reference an earlier binding

```x
(let-opts () ((w 10) (h (* w 2))) h)
```
---
    20

### keeps a present 0 instead of the default

```x
(let-opts (list 'a 0) ((a 99)) a)
```
---
    0


## Assoc entry guards (#51 ruled from the benchmark)

The public seats check ONCE per call that the spine head and first entry are
cells -- the two crash shapes the review filed ((Assoc get 'k 42) and
(Assoc get 'k (pair 1 2))) both segfaulted. The boot walkers stay
documented-unchecked: a per-step spine guard measured +66% on the walk and
+7.4% on EVERY method dispatch (the object system routes through assoc-get),
and was still incomplete. Deeper spine garbage keeps first/rest's unchecked
status.

### non-alist receivers raise across the public seats

```x
(list (guard (e (Err kind-of e)) (Assoc get (lit k) 42))
      (guard (e (Err kind-of e)) (Assoc get (lit k) (pair 1 2)))
      (guard (e (lit R)) (Assoc has? (lit k) 42))
      (guard (e (lit R)) (Assoc del (lit k) 42))
      (guard (e (lit R)) (Assoc put (lit k) 1 42))
      (guard (e (lit R)) (Assoc keys 42))
      (guard (e (lit R)) (Assoc vals 42))
      (guard (e (lit R)) (Assoc get-or 0 (lit k) 42)))
```
---
    ('type 'type 'R 'R 'R 'R 'R 'R)

### normal use unchanged, nil alist included

```x
(do
  (def al (list (pair (lit a) 1) (pair (lit b) 2)))
  (list (Assoc get (lit a) al) (Assoc get (lit z) al) (Assoc get (lit a) ())
        (Assoc has? (lit b) al) (Assoc keys al) (Assoc get-or 9 (lit z) al)))
```
---
    (1 () () #t ('a 'b) 9)

## Assoc entry / find (#357: the entry-returning doors, formerly List assq/assoc)

### entry finds the pair by identity; nil is the unambiguous miss

```x
(do (import x/type/assoc)
  (list (rest (Assoc entry 'b (list (pair 'a 1) (pair 'b 2) (pair 'c 3))))
        (null? (Assoc entry 'z (list (pair 'a 1))))))
```
---
    (2 #t)

### find compares with equal?, so string and number keys hit

```x
(do (import x/type/assoc)
  (list (rest (Assoc find 2 (list (pair 1 10) (pair 2 20))))
        (rest (Assoc find "b" (list (pair "a" 1) (pair "b" 2))))
        (null? (Assoc find "z" (list (pair "a" 1))))))
```
---
    (20 2 #t)
