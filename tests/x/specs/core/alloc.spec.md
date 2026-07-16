# Allocation doors

The four user-approved 2026-07-15 ISA additions: the byte-region
allocators x genuinely lacked.  (str make) is the managed default --
the GC owns the region; (mem alloc)/(mem free) is the raw pair for
header-less blocks; (buf make) wraps a string's bytes non-owning.

## str make

### allocates exactly n visible bytes

```scheme
(str-length ((prim-ref (lit str) (lit make)) 64))
```
---
    64

### the region is writable through str ->ptr

```scheme
(do
  (def %s ((prim-ref (lit str) (lit make)) 4))
  (def %p ((prim-ref (lit str) (lit ->ptr)) %s))
  ((prim-ref (lit ptr) (lit set!)) %p 0 104 1)
  ((prim-ref (lit ptr) (lit set!)) %p 1 105 1)
  (str-ref %s 0))
```
---
    #\h

### fresh per call

```scheme
(same? ((prim-ref (lit str) (lit make)) 8) ((prim-ref (lit str) (lit make)) 8))
```
---
    #f

## mem alloc / mem free

### a region is allocated zeroed, writable, and freeable

```scheme
(do
  (def %alloc (prim-ref (lit mem) (lit alloc)))
  (def %free (prim-ref (lit mem) (lit free)))
  (def %p (%alloc 16))
  (def %z ((prim-ref (lit ptr) (lit ref)) %p 3 1))
  ((prim-ref (lit ptr) (lit set!)) %p 3 42 1)
  (def %v ((prim-ref (lit ptr) (lit ref)) %p 3 1))
  (%free %p)
  (list %z %v))
```
---
    (0 42)

### mem free returns nil (side-effect contract)

```scheme
(do
  (def %p ((prim-ref (lit mem) (lit alloc)) 8))
  (null? ((prim-ref (lit mem) (lit free)) %p)))
```
---
    #t

## buf make

### a buffer views a string's bytes and prints its opaque form

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (display %b))
```
---
    #<buffer>

### append then read round-trips through the view

```scheme
(do
  (def %s ((prim-ref (lit str) (lit make)) 8))
  (def %b ((prim-ref (lit buf) (lit make)) %s))
  ((prim-ref (lit buf) (lit append)) %b #\x)
  ((prim-ref (lit buf) (lit append)) %b #\y)
  (str-ref %s 0))
```
---
    #\x

## mem copy / cmp / set (the block ops)

### copy moves a region in one instruction

```scheme
(do
  (def %src ((prim-ref (lit str) (lit make)) 4))
  (def %dst ((prim-ref (lit str) (lit make)) 4))
  (def %sp ((prim-ref (lit str) (lit ->ptr)) %src))
  ((prim-ref (lit ptr) (lit set!)) %sp 0 104 1)
  ((prim-ref (lit ptr) (lit set!)) %sp 1 105 1)
  ((prim-ref (lit mem) (lit copy)) ((prim-ref (lit str) (lit ->ptr)) %dst) %sp 4)
  (str-ref %dst 1))
```
---
    #\i

### cmp is TRUE memcmp: equality, and differences PAST a NUL are seen

Both regions get an equal NUL at byte 0, then diverge at byte 2 --
strncmp would stop at the NUL and call them equal; memcmp must not.

```scheme
(do
  (def %cmp (prim-ref (lit mem) (lit cmp)))
  (def %p (prim-ref (lit str) (lit ->ptr)))
  (def %a ((prim-ref (lit str) (lit make)) 3))
  (def %b ((prim-ref (lit str) (lit make)) 3))
  (def %r0 (%cmp (%p %a) (%p %b) 3))
  ((prim-ref (lit ptr) (lit set!)) (%p %a) 0 0 1)
  ((prim-ref (lit ptr) (lit set!)) (%p %b) 0 0 1)
  ((prim-ref (lit ptr) (lit set!)) (%p %b) 2 122 1)
  (list %r0 (%cmp (%p %a) (%p %b) 3)))
```
---
    (0 -1)

### set fills a region

```scheme
(do
  (def %s ((prim-ref (lit str) (lit make)) 4))
  ((prim-ref (lit mem) (lit set)) ((prim-ref (lit str) (lit ->ptr)) %s) 122 3)
  (list (str-ref %s 0) (str-ref %s 2) (str-ref %s 3)))
```
---
    (#\z #\z #\space)

### str=? bottoms out in the block compare

```scheme
(list (str=? "hello" "hello") (str=? "hello" "hellp") (str=? "ab" "abc"))
```
---
    (#t #f #f)
