# Dict: the mutable hash table
# @weight 2

Content-hashed (FNV-1a), equal?-compared keys: symbols, strings, integers,
chars. Class instances are identity keys: address-hashed, same?-compared.
`(import x/type/dict)` in each test -- Dict is not in the x-core boot.

## construction

### make yields an empty dict

```x
(do (import x/type/dict) ((Dict make) empty?))
```
---
    #t

### an instance from generic new fails loudly at first USE (constructor adjudication)

The generic allocator once built a dict that SEGFAULTED on set!; a quiet
new->make alias then hid two different operations behind one name. Now
generic new builds an inert instance and the %slot guard raises the
teaching kind-'state Err the moment it is used -- no fake refusal method
in the help listing, the guard sits at the point of harm.

```x
(do (import x/type/dict)
  (guard (e (list (Err kind-of e) ((Dict make) empty?)))
    ((Dict new) set! 'a 1)))
```
---
    ('state #t)

### an uninitialized instance fails loudly, not at the raw slot layer

```x
(do (import x/type/dict)
  ((new-from Dict ()) get 'a))
```
---
    Error: #<err:state Dict: uninitialized instance (use Dict make / from-*)>

### from-plist is the simplest literal shape

```x
(do (import x/type/dict)
  ((Dict from-plist (list 'a 1 'b 2)) get 'b))
```
---
    2

### from-plist rejects an odd-length plist

```x
(do (import x/type/dict)
  (Dict from-plist (list 'a 1 'b)))
```
---
    Error: #<err:value Dict from-plist: odd-length plist>

### from-bindings takes the let shape

```x
(do (import x/type/dict)
  ((Dict from-bindings (list (list 'a 1) (list 'b 2))) get 'a))
```
---
    1

### every shape converts back out: ->plist and ->bindings

```x
(do (import x/type/dict)
  (let ((d (Dict from-plist (list 'a 1))))
    (list (d ->plist) (d ->bindings))))
```
---
    (('a 1) (('a 1)))

### from-alist loads an alist

```x
(do (import x/type/dict)
  ((Dict from-alist (list (pair 'a 1) (pair 'b 2))) get 'b))
```
---
    2

### from-alist: later duplicates overwrite

```x
(do (import x/type/dict)
  ((Dict from-alist (list (pair 'a 1) (pair 'a 9))) get 'a))
```
---
    9

## set! / get

### roundtrips a symbol key

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! 'k 42) (d get 'k)))
```
---
    42

### STRING keys work (the Assoc eq? gap this class closes)

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! "name" "x-lang") (d get "name")))
```
---
    "x-lang"

### distinct-but-equal string keys hit the same entry

```x
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d set! (Str8 append "na" "me") 1)
    (d get "name")))
```
---
    1

### integer keys

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! 7 "seven") (d get 7)))
```
---
    "seven"

### char keys

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! #\a 1) (d get #\a)))
```
---
    1

### set! overwrites an existing key

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! 'k 1) (d set! 'k 2) (d get 'k)))
```
---
    2

### set! chains

```x
(do (import x/type/dict)
  ((((Dict make) set! 'a 1) set! 'b 2) get 'a))
```
---
    1

### get misses with nil

```x
(do (import x/type/dict)
  (null? ((Dict make) get 'missing)))
```
---
    #t

### unhashable keys error loudly

```x
(do (import x/type/dict)
  ((Dict make) set! (list 1 2) "v"))
```
---
    Error: #<err:type Dict: unhashable key -- use a symbol, string, integer, char, or class instance>

## get-or (presence-based)

### returns the default for an absent key

```x
(do (import x/type/dict)
  ((Dict make) get-or 99 'z))
```
---
    99

### get-or-else is the lazy twin: the thunk runs only on a miss

```x
(do (import x/type/dict)
  (let ((d (Dict make)) (calls 0))
    (d set! 'a 1)
    (let ((hit (d get-or-else (fn () (do (set! calls (+ calls 1)) 99)) 'a)))
      (list hit (d get-or-else (fn () (do (set! calls (+ calls 1)) 99)) 'z) calls))))
```
---
    (1 99 1)

### returns a stored nil, not the default

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! 'k ()) (null? (d get-or 99 'k))))
```
---
    #t

## has? / del! / length

### has? sees a stored key

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! "k" 1) (d has? "k")))
```
---
    #t

### has? rejects an absent key

```x
(do (import x/type/dict)
  (if ((Dict make) has? "k") "y" "n"))
```
---
    "n"

### del! removes an entry

```x
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d set! 'k 1) (d del! 'k)
    (list (d has? 'k) (d length))))
```
---
    (#f 0)

### del! on an absent key is a no-op

```x
(do (import x/type/dict)
  (let ((d (Dict make))) (d set! 'a 1) (d del! 'z) (d length)))
```
---
    1

### length tracks entries

```x
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d set! 'a 1) (d set! 'b 2) (d set! 'a 3)
    (d length)))
```
---
    2

## collisions and resize

### a one-bucket table still behaves (everything collides)

```x
(do (import x/type/dict)
  (let ((d (Dict make 1)))
    (d set! 'a 1) (d set! 'b 2) (d set! "c" 3)
    (list (d get 'a) (d get 'b) (d get "c") (d length))))
```
---
    (1 2 3 3)

### entries survive growth past the load factor

```x
(do (import x/type/dict)
  (let ((d (Dict make 2)))
    (List for-each (fn (_ i) (d set! i (* i 10))) (List range 0 20))
    (list (d length) (d get 0) (d get 19) (d has? 20))))
```
---
    (20 0 190 #f)

## extraction

### ->alist snapshots the entries

```x
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d set! 'a 1)
    (let ((snap (d ->alist)))
      (d set! 'a 2)
      (list (rest (first snap)) (d get 'a)))))
```
---
    (1 2)

### keys and vals

```x
(do (import x/type/dict)
  (let ((d (Dict make)))
    (d set! 'a 1)
    (list (d keys) (d vals))))
```
---
    (('a) (1))

### for-each visits every entry

```x
(do (import x/type/dict)
  (let ((d (Dict make)) (sum (pair 0 ())))
    (d set! 'a 1) (d set! 'b 2)
    (d for-each (fn (_ e) (%set-first! sum (+ (first sum) (rest e)))))
    (first sum)))
```
---
    3

## instance identity keys

Class instances are identity keys: hashed by address (stable -- the
mark-sweep GC frees in place, and a keyed instance is rooted by its own
bucket entry), compared with same? (strict identity), never equal? (which
would recurse into the field box and loop on cyclic instances).

### equal-but-distinct instances are distinct keys

```x
(do (import x/type/dict)
  (def-class P () x y)
  (let ((a (P new x 1 y 2)) (b (P new x 1 y 2)) (d (Dict make)))
    (d set! a "first")
    (d set! b "second")
    (list (d get a) (d get b) (d length))))
```
---
    ("first" "second" 2)

### del! removes only the given instance

```x
(do (import x/type/dict)
  (def-class P () x)
  (let ((a (P new x 1)) (b (P new x 1)) (d (Dict make)))
    (d set! a 'a) (d set! b 'b)
    (d del! a)
    (list (d has? a) (d has? b) (d length))))
```
---
    (#f #t 1)

### cyclic instances are safe keys (eq?, not equal?)

```x
(do (import x/type/dict)
  (def-class N () v next)
  (let ((a (N new v 1)) (b (N new v 2)) (d (Dict make)))
    (a next b) (b next a)
    (d set! a 'a) (d set! b 'b)
    (list (d get a) (d get b))))
```
---
    ('a 'b)

### instance keys survive the resize rehash

```x
(do (import x/type/dict) (import x/type/list)
  (def-class P () v)
  (let ((ks (List map (fn (_ i) (P new v i)) (List range 0 20)))
        (d (Dict make)))
    (List for-each (fn (_ k) (d set! k (k v))) ks)
    (list (d length)
          (List all? (fn (_ k) (equal? (d get k) (k v))) ks))))
```
---
    (20 #t)

## map

### maps values, keeping the keys

```x
(do (import x/type/dict)
  (let ((d ((Dict from-plist (list 'a 1 'b 2)) map (fn (_ e) (* (rest e) 10)))))
    (list (d get 'a) (d get 'b))))
```
---
    (10 20)

### the callback receives the whole entry, so the key is available

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1)) map (fn (_ e) (first e))) get 'a))
```
---
    'a

### the source dict is not mutated

```x
(do (import x/type/dict)
  (let ((d (Dict from-plist (list 'a 1))))
    (d map (fn (_ e) 99))
    (d get 'a)))
```
---
    1

### the result is a Dict, not an alist

```x
(do (import x/type/dict) (Dict dict? ((Dict from-plist (list 'a 1)) map (fn (_ e) 0))))
```
---
    #t

### mapping an empty dict gives an empty dict

```x
(do (import x/type/dict) (((Dict make) map (fn (_ e) 0)) empty?))
```
---
    #t

### keys cannot collapse -- every source key survives

```x
(do (import x/type/dict)
  (((Dict from-plist (list 'a 1 'b 2 'c 3)) map (fn (_ e) 0)) length))
```
---
    3
