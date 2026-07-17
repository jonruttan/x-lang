## assoc-get

### retrieves value by key

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit b) al))
```
---
    2

### returns nil for missing key

```scheme
(do (def al (list (pair (lit a) 1))) (null? (assoc-get (lit z) al)))
```
---
    #t

### retrieves value from first entry

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit a) al))
```
---
    1

## assoc-get-or

### returns value when key exists

```scheme
(do (def al (list (pair (lit a) 1))) (Assoc get-or 99 (lit a) al))
```
---
    1

### returns default when key missing

```scheme
(do (def al (list (pair (lit a) 1))) (Assoc get-or 99 (lit z) al))
```
---
    99

### returns a stored nil, not the default

```scheme
(do (def al (list (pair (lit a) ()))) (null? (Assoc get-or 99 (lit a) al)))
```
---
    #t

### stored #f is not the default either

```scheme
(do (def al (list (pair (lit a) #f))) (Assoc get-or 99 (lit a) al))
```
---
    #f

## assoc-has?

### returns #t when key exists

```scheme
(do (def al (list (pair (lit a) 1))) (assoc-has? (lit a) al))
```
---
    #t

### returns nil when key missing

```scheme
(do (def al (list (pair (lit a) 1))) (if (assoc-has? (lit z) al) "y" "n"))
```
---
    "n"

### finds key after first entry

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-has? (lit b) al))
```
---
    #t

## assoc-put

### adds key-value pair

```scheme
(do (def al (list (pair (lit a) 1))) (assoc-get (lit b) (assoc-put (lit b) 2 al)))
```
---
    2

## assoc-del

### removes key from alist

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (assoc-del (lit a) al)))
```
---
    1

### returns same length when key not present

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (assoc-del (lit z) al)))
```
---
    2

### removes key not at head

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (null? (assoc-get (lit b) (assoc-del (lit b) al))))
```
---
    #t

## assoc-keys

### returns list of keys

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-keys al))
```
---
    ((lit a) (lit b))

## assoc-vals

### returns list of values

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (Assoc vals al))
```
---
    (1 2)

## assoc-map

### applies function to all values

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit a) (Assoc map (method-ref Num inc) al)))
```
---
    2

## assoc-filter

### filters entries by predicate

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (Assoc filter (fn (_ e) (> (rest e) 1)) al)))
```
---
    1

## assoc-merge

### merges two alists

```scheme
(do (def a (list (pair (lit x) 1))) (def b (list (pair (lit y) 2))) (length (Assoc merge a b)))
```
---
    2

## assoc-pick

### selects entries by key list

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (Assoc pick (list (lit a) (lit c)) al)))
```
---
    2

## assoc-omit

### removes entries by key list

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (Assoc omit (list (lit a)) al)))
```
---
    2

## from-pairs

### converts list of lists to alist

```scheme
(do (def al (Assoc from-pairs (list (list (lit a) 1) (list (lit b) 2)))) (assoc-get (lit a) al))
```
---
    1

## to-pairs

### converts alist to list of lists

```scheme
(do (def al (list (pair (lit a) 1))) (first (first (Assoc to-pairs al))))
```
---
    (lit a)

## evolve

### transforms values by matching keys

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit a) (Assoc evolve (list (pair (lit a) (method-ref Num inc))) al)))
```
---
    2

## opt-get-or

### returns the value for a present key (plist)

```scheme
(Assoc opt-get-or 99 (lit a) (list (lit a) 1))
```
---
    1

### returns the default for a missing key

```scheme
(Assoc opt-get-or 99 (lit z) (list (lit a) 1))
```
---
    99

### reads from an alist store

```scheme
(Assoc opt-get-or 99 (lit a) (list (pair (lit a) 1)))
```
---
    1

### keeps a present 0 instead of the default

```scheme
(Assoc opt-get-or 99 (lit a) (list (lit a) 0))
```
---
    0

## opt-get-or-else

### returns the value for a present key

```scheme
(Assoc opt-get-or-else (fn () 99) (lit a) (list (lit a) 1))
```
---
    1

### calls the thunk for a missing key

```scheme
(Assoc opt-get-or-else (fn () 99) (lit z) (list (lit a) 1))
```
---
    99

### does not run the thunk when the key is present

```scheme
(Assoc opt-get-or-else (fn () (error "boom")) (lit a) (list (lit a) 1))
```
---
    1

### keeps a present 0 without calling the thunk

```scheme
(Assoc opt-get-or-else (fn () 99) (lit a) (list (lit a) 0))
```
---
    0

## let-opts

### binds from a plist source with defaults

```scheme
(let-opts (list (lit a) 1) ((a 0) (b 9)) (list a b))
```
---
    (1 9)

### binds from an alist source

```scheme
(let-opts (list (pair (lit a) 1)) ((a 0)) a)
```
---
    1

### default is lazy: not evaluated when the option is present

```scheme
(let-opts (list (lit a) 1) ((a (error "boom"))) a)
```
---
    1

### (name key default) binds a renamed key when present

```scheme
(let-opts (list (lit bg-color) "red") ((bg bg-color "black")) bg)
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
(let-opts (list (lit x) 5) (x y) (list x (null? y)))
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
(let-opts (list (lit a) 0) ((a 99)) a)
```
---
    0

