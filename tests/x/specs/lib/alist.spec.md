## assoc-get

### retrieves value by key

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-get 'b al))
```
---
    2

### returns nil for missing key

```scheme
(do (def al (list (pair 'a 1))) (null? (assoc-get 'z al)))
```
---
    #t

### retrieves value from first entry

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-get 'a al))
```
---
    1

## assoc-get-or

### returns value when key exists

```scheme
(do (def al (list (pair 'a 1))) (Assoc get-or 99 'a al))
```
---
    1

### returns default when key missing

```scheme
(do (def al (list (pair 'a 1))) (Assoc get-or 99 'z al))
```
---
    99

### returns a stored nil, not the default

```scheme
(do (def al (list (pair 'a ()))) (null? (Assoc get-or 99 'a al)))
```
---
    #t

### stored #f is not the default either

```scheme
(do (def al (list (pair 'a #f))) (Assoc get-or 99 'a al))
```
---
    #f

## assoc-has?

### returns #t when key exists

```scheme
(do (def al (list (pair 'a 1))) (assoc-has? 'a al))
```
---
    #t

### returns nil when key missing

```scheme
(do (def al (list (pair 'a 1))) (if (assoc-has? 'z al) "y" "n"))
```
---
    "n"

### finds key after first entry

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-has? 'b al))
```
---
    #t

## assoc-put

### adds key-value pair

```scheme
(do (def al (list (pair 'a 1))) (assoc-get 'b (assoc-put 'b 2 al)))
```
---
    2

## assoc-del

### removes key from alist

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (length (assoc-del 'a al)))
```
---
    1

### returns same length when key not present

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (length (assoc-del 'z al)))
```
---
    2

### removes key not at head

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (null? (assoc-get 'b (assoc-del 'b al))))
```
---
    #t

## assoc-keys

### returns list of keys

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-keys al))
```
---
    ('a 'b)

## assoc-vals

### returns list of values

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (Assoc vals al))
```
---
    (1 2)

## assoc-map

### applies function to all values

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-get 'a (Assoc map (method-ref Num inc) al)))
```
---
    2

## assoc-filter

### filters entries by predicate

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (length (Assoc filter (fn (_ e) (> (rest e) 1)) al)))
```
---
    1

## assoc-merge

### merges two alists, a's entries first

A length assertion alone let #73 hide here: the count is 2 in either order.
Assert the value, and use overlapping keys so priority is covered too.

```scheme
(Assoc merge (list (pair 'a 1)) (list (pair 'a 9) (pair 'b 2)))
```
---
    (('a . 1) ('b . 2))

### additions keep b's order

```scheme
(Assoc merge (list (pair 'a 1)) (list (pair 'b 2) (pair 'c 3)))
```
---
    (('a . 1) ('b . 2) ('c . 3))

### a duplicate key inside b keeps its first occurrence

```scheme
(Assoc merge () (list (pair 'b 2) (pair 'b 9)))
```
---
    (('b . 2))

## assoc-pick

### selects entries by key list

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2) (pair 'c 3))) (length (Assoc pick (list 'a 'c) al)))
```
---
    2

## assoc-omit

### removes entries by key list

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2) (pair 'c 3))) (length (Assoc omit (list 'a) al)))
```
---
    2

## from-bindings

### converts a bindings list (the let shape) to an alist

```scheme
(do (def al (Assoc from-bindings (list (list 'a 1) (list 'b 2)))) (assoc-get 'a al))
```
---
    1

## from-plist / ->plist

### plist to alist and back

```scheme
(do (def al (Assoc from-plist (list 'a 1 'b 2)))
  (list (assoc-get 'b al) (Assoc ->plist al)))
```
---
    (2 ('a 1 'b 2))

### from-plist rejects an odd-length plist

```scheme
(Assoc from-plist (list 'a 1 'b))
```
---
    Error: #<err:value Assoc from-plist: odd-length plist>

## ->bindings

### converts an alist to a bindings list

```scheme
(do (def al (list (pair 'a 1))) (first (first (Assoc ->bindings al))))
```
---
    'a

## evolve

### transforms values by matching keys

```scheme
(do (def al (list (pair 'a 1) (pair 'b 2))) (assoc-get 'a (Assoc evolve (list (pair 'a (method-ref Num inc))) al)))
```
---
    2

## opt-get-or

### returns the value for a present key (plist)

```scheme
(Assoc opt-get-or 99 'a (list 'a 1))
```
---
    1

### returns the default for a missing key

```scheme
(Assoc opt-get-or 99 'z (list 'a 1))
```
---
    99

### reads from an alist store

```scheme
(Assoc opt-get-or 99 'a (list (pair 'a 1)))
```
---
    1

### keeps a present 0 instead of the default

```scheme
(Assoc opt-get-or 99 'a (list 'a 0))
```
---
    0

## opt-get-or-else

### returns the value for a present key

```scheme
(Assoc opt-get-or-else (fn () 99) 'a (list 'a 1))
```
---
    1

### calls the thunk for a missing key

```scheme
(Assoc opt-get-or-else (fn () 99) 'z (list 'a 1))
```
---
    99

### does not run the thunk when the key is present

```scheme
(Assoc opt-get-or-else (fn () (error "boom")) 'a (list 'a 1))
```
---
    1

### keeps a present 0 without calling the thunk

```scheme
(Assoc opt-get-or-else (fn () 99) 'a (list 'a 0))
```
---
    0

## let-opts

### binds from a plist source with defaults

```scheme
(let-opts (list 'a 1) ((a 0) (b 9)) (list a b))
```
---
    (1 9)

### binds from an alist source

```scheme
(let-opts (list (pair 'a 1)) ((a 0)) a)
```
---
    1

### default is lazy: not evaluated when the option is present

```scheme
(let-opts (list 'a 1) ((a (error "boom"))) a)
```
---
    1

### (name key default) binds a renamed key when present

```scheme
(let-opts (list 'bg-color "red") ((bg bg-color "black")) bg)
```
---
    "red"

### (name key default) uses the default when the renamed key is absent

```scheme
(let-opts () ((bg bg-color "black")) bg)
```
---
    "black"

### a bare name defaults to nil

```scheme
(let-opts (list 'x 5) (x y) (list x (null? y)))
```
---
    (5 #t)

### a later default can reference an earlier binding

```scheme
(let-opts () ((w 10) (h (* w 2))) h)
```
---
    20

### keeps a present 0 instead of the default

```scheme
(let-opts (list 'a 0) ((a 99)) a)
```
---
    0

