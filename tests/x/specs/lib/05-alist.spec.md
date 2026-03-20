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
(do (def al (list (pair (lit a) 1))) (assoc-get-or 99 (lit a) al))
```
---
    1

### returns default when key missing

```scheme
(do (def al (list (pair (lit a) 1))) (assoc-get-or 99 (lit z) al))
```
---
    99

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
    (a b)

## assoc-vals

### returns list of values

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-vals al))
```
---
    (1 2)

## assoc-map

### applies function to all values

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit a) (assoc-map inc al)))
```
---
    2

## assoc-filter

### filters entries by predicate

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (assoc-filter (fn (e) (> (rest e) 1)) al)))
```
---
    1

## assoc-merge

### merges two alists

```scheme
(do (def a (list (pair (lit x) 1))) (def b (list (pair (lit y) 2))) (length (assoc-merge a b)))
```
---
    2

## assoc-pick

### selects entries by key list

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (assoc-pick (list (lit a) (lit c)) al)))
```
---
    2

## assoc-omit

### removes entries by key list

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (assoc-omit (list (lit a)) al)))
```
---
    2

## from-pairs

### converts list of lists to alist

```scheme
(do (def al (from-pairs (list (list (lit a) 1) (list (lit b) 2)))) (assoc-get (lit a) al))
```
---
    1

## to-pairs

### converts alist to list of lists

```scheme
(do (def al (list (pair (lit a) 1))) (first (first (to-pairs al))))
```
---
    a

## evolve

### transforms values by matching keys

```scheme
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (assoc-get (lit a) (evolve (list (pair (lit a) inc)) al)))
```
---
    2

