# Dict: the mutable hash table

Content-hashed (FNV-1a), equal?-compared keys: symbols, strings, integers,
chars. Class instances are identity keys: address-hashed, eq?-compared.
`(import x/type/dict)` in each test -- Dict is not in the x-core boot.

## construction

### make yields an empty dict

```scheme
(do (import x/type/dict) ((Dict make) empty?))
```
---
    #t

### an instance from generic new fails loudly at first USE (constructor adjudication)

The generic allocator once built a dict that SEGFAULTED on put!; a quiet
new->make alias then hid two different operations behind one name. Now
generic new builds an inert instance and the %slot guard raises the
teaching kind-'state Err the moment it is used -- no fake refusal method
in the help listing, the guard sits at the point of harm.

```scheme
(do (import x/type/dict)
  (guard (e (list (Err kind-of e) ((Dict make) empty?)))
    ((Dict new) put! 'a 1)))
```
---
    ('state #t)

### an uninitialized instance fails loudly, not at the raw slot layer

```scheme
(do (import x/type/dict)
  ((new-from Dict ()) get 'a))
```
---
    Error: #<err:state Dict: uninitialized instance (use Dict make / from-*)>

### from-plist is the simplest literal shape

```scheme
(do (import x/type/dict)
  ((Dict from-plist (list 'a 1 'b 2)) get 'b))
```
---
    2

### from-plist rejects an odd-length plist

```scheme
(do (import x/type/dict)
  (Dict from-plist (list 'a 1 'b)))
```
---
    Error: #<err:value Dict from-plist: odd-length plist>

### from-bindings takes the let shape

```scheme
(do (import x/type/dict)
  ((Dict from-bindings (list (list 'a 1) (list 'b 2))) get 'a))
```
---
    1

### every shape converts back out: ->plist and ->bindings

```scheme
(do (import x/type/dict)
  (let ((d (Dict from-plist (list 'a 1))))
    (list (d ->plist) (d ->bindings))))
```
---
    (('a 1) (('a 1)))

### from-alist loads an alist

```scheme
(do (import x/type/dict)
  ((Dict from-alist (list (pair 'a 1) (pair 'b 2))) get 'b))
```
---
    2

### from-alist: later duplicates overwrite

```scheme
(do (import x/type/dict)
  ((Dict from-alist (list (pair 'a 1) (pair 'a 9))) get 'a))
```
---
    9

## put! / get

### roundtrips a symbol key

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! 'k 42) (d get 'k)))
```
---
    42

### STRING keys work (the Assoc eq? gap this class closes)

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! "name" "x-lang") (d get "name")))
```
---
    "x-lang"

### distinct-but-equal string keys hit the same entry

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d put! (Str8 append "na" "me") 1)
    (d get "name")))
```
---
    1

### integer keys

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! 7 "seven") (d get 7)))
```
---
    "seven"

### char keys

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! #\a 1) (d get #\a)))
```
---
    1

### put! overwrites an existing key

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! 'k 1) (d put! 'k 2) (d get 'k)))
```
---
    2

### put! chains

```scheme
(do (import x/type/dict)
  ((((Dict make) put! 'a 1) put! 'b 2) get 'a))
```
---
    1

### get misses with nil

```scheme
(do (import x/type/dict)
  (null? ((Dict make) get 'missing)))
```
---
    #t

### unhashable keys error loudly

```scheme
(do (import x/type/dict)
  ((Dict make) put! (list 1 2) "v"))
```
---
    Error: #<err:type Dict: unhashable key -- use a symbol, string, integer, char, or class instance>

## get-or (presence-based)

### returns the default for an absent key

```scheme
(do (import x/type/dict)
  ((Dict make) get-or 99 'z))
```
---
    99

### get-or-else is the lazy twin: the thunk runs only on a miss

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)) (calls 0))
    (d put! 'a 1)
    (let ((hit (d get-or-else (fn () (do (set! calls (+ calls 1)) 99)) 'a)))
      (list hit (d get-or-else (fn () (do (set! calls (+ calls 1)) 99)) 'z) calls))))
```
---
    (1 99 1)

### returns a stored nil, not the default

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! 'k ()) (null? (d get-or 99 'k))))
```
---
    #t

## has? / del! / length

### has? sees a stored key

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! "k" 1) (d has? "k")))
```
---
    #t

### has? rejects an absent key

```scheme
(do (import x/type/dict)
  (if ((Dict make) has? "k") "y" "n"))
```
---
    "n"

### del! removes an entry

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d put! 'k 1) (d del! 'k)
    (list (d has? 'k) (d length))))
```
---
    (#f 0)

### del! on an absent key is a no-op

```scheme
(do (import x/type/dict)
  (let ((d (Dict make))) (d put! 'a 1) (d del! 'z) (d length)))
```
---
    1

### length tracks entries

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d put! 'a 1) (d put! 'b 2) (d put! 'a 3)
    (d length)))
```
---
    2

## collisions and resize

### a one-bucket table still behaves (everything collides)

```scheme
(do (import x/type/dict)
  (let ((d (Dict make 1)))
    (d put! 'a 1) (d put! 'b 2) (d put! "c" 3)
    (list (d get 'a) (d get 'b) (d get "c") (d length))))
```
---
    (1 2 3 3)

### entries survive growth past the load factor

```scheme
(do (import x/type/dict)
  (let ((d (Dict make 2)))
    (List for-each (fn (_ i) (d put! i (* i 10))) (List range 0 20))
    (list (d length) (d get 0) (d get 19) (d has? 20))))
```
---
    (20 0 190 #f)

## extraction

### ->alist snapshots the entries

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d put! 'a 1)
    (let ((snap (d ->alist)))
      (d put! 'a 2)
      (list (rest (first snap)) (d get 'a)))))
```
---
    (1 2)

### keys and vals

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d put! 'a 1)
    (list (d keys) (d vals))))
```
---
    (('a) (1))

### for-each visits every entry

```scheme
(do (import x/type/dict)
  (let ((d (Dict make)) (sum (pair 0 ())))
    (d put! 'a 1) (d put! 'b 2)
    (d for-each (fn (_ e) (%set-first! sum (+ (first sum) (rest e)))))
    (first sum)))
```
---
    3

## instance identity keys

Class instances are identity keys: hashed by address (stable -- the
mark-sweep GC frees in place, and a keyed instance is rooted by its own
bucket entry), compared with eq?, never equal? (which would recurse into
the field box and loop on cyclic instances).

### equal-but-distinct instances are distinct keys

```scheme
(do (import x/type/dict)
  (def-class P () x y)
  (let ((a (P new x 1 y 2)) (b (P new x 1 y 2)) (d (Dict make)))
    (d put! a "first")
    (d put! b "second")
    (list (d get a) (d get b) (d length))))
```
---
    ("first" "second" 2)

### del! removes only the given instance

```scheme
(do (import x/type/dict)
  (def-class P () x)
  (let ((a (P new x 1)) (b (P new x 1)) (d (Dict make)))
    (d put! a 'a) (d put! b 'b)
    (d del! a)
    (list (d has? a) (d has? b) (d length))))
```
---
    (#f #t 1)

### cyclic instances are safe keys (eq?, not equal?)

```scheme
(do (import x/type/dict)
  (def-class N () v next)
  (let ((a (N new v 1)) (b (N new v 2)) (d (Dict make)))
    (a next b) (b next a)
    (d put! a 'a) (d put! b 'b)
    (list (d get a) (d get b))))
```
---
    ('a 'b)

### instance keys survive the resize rehash

```scheme
(do (import x/type/dict) (import x/type/list)
  (def-class P () v)
  (let ((ks (List map (fn (_ i) (P new v i)) (List range 0 20)))
        (d (Dict make)))
    (List for-each (fn (_ k) (d put! k (k v))) ks)
    (list (d length)
          (List all? (fn (_ k) (equal? (d get k) (k v))) ks))))
```
---
    (20 #t)
