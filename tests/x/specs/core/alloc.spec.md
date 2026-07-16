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
