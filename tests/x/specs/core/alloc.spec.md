# Allocation doors
# @weight 1

The four user-approved 2026-07-15 ISA additions: the byte-region
allocators x genuinely lacked.  (str make) is the managed default --
the GC owns the region; (mem alloc)/(mem free) is the raw pair for
header-less blocks; (buf make) wraps a string's bytes non-owning.

## str make

### allocates exactly n visible bytes

```x
(%str-length ((prim-ref 'str 'make) 64))
```
---
    64

### the region is writable through str ->ptr

```x
(do
  (def %s ((prim-ref 'str 'make) 4))
  (def %p ((prim-ref 'str '->ptr) %s))
  ((prim-ref 'ptr 'set!) %p 0 104 1)
  ((prim-ref 'ptr 'set!) %p 1 105 1)
  (%str-ref %s 0))
```
---
    #\h

### fresh per call

```x
(same? ((prim-ref 'str 'make) 8) ((prim-ref 'str 'make) 8))
```
---
    #f

## mem alloc / mem free

### a region is allocated zeroed, writable, and freeable

```x
(do
  (def %alloc (prim-ref 'mem 'alloc))
  (def %free (prim-ref 'mem 'free))
  (def %p (%alloc 16))
  (def %z ((prim-ref 'ptr 'ref) %p 3 1))
  ((prim-ref 'ptr 'set!) %p 3 42 1)
  (def %v ((prim-ref 'ptr 'ref) %p 3 1))
  (%free %p)
  (list %z %v))
```
---
    (0 42)

### mem free returns nil (side-effect contract)

```x
(do
  (def %p ((prim-ref 'mem 'alloc) 8))
  (null? ((prim-ref 'mem 'free) %p)))
```
---
    #t

## buf make

### a buffer views a string's bytes and prints its opaque form

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (display %b))
```
---
    #<buffer>

### append then read round-trips through the view

```x
(do
  (def %s ((prim-ref 'str 'make) 8))
  (def %b ((prim-ref 'buf 'make) %s))
  ((prim-ref 'buf 'append) %b #\x)
  ((prim-ref 'buf 'append) %b #\y)
  (%str-ref %s 0))
```
---
    #\x

## mem copy / cmp / set (the block ops)

### copy moves a region in one instruction

```x
(do
  (def %src ((prim-ref 'str 'make) 4))
  (def %dst ((prim-ref 'str 'make) 4))
  (def %sp ((prim-ref 'str '->ptr) %src))
  ((prim-ref 'ptr 'set!) %sp 0 104 1)
  ((prim-ref 'ptr 'set!) %sp 1 105 1)
  ((prim-ref 'mem 'copy) ((prim-ref 'str '->ptr) %dst) %sp 4)
  (%str-ref %dst 1))
```
---
    #\i

### cmp is TRUE memcmp: equality, and differences PAST a NUL are seen

Both regions get an equal NUL at byte 0, then diverge at byte 2 --
strncmp would stop at the NUL and call them equal; memcmp must not.

```x
(do
  (def %cmp (prim-ref 'mem 'cmp))
  (def %p (prim-ref 'str '->ptr))
  (def %a ((prim-ref 'str 'make) 3))
  (def %b ((prim-ref 'str 'make) 3))
  (def %r0 (%cmp (%p %a) (%p %b) 3))
  ((prim-ref 'ptr 'set!) (%p %a) 0 0 1)
  ((prim-ref 'ptr 'set!) (%p %b) 0 0 1)
  ((prim-ref 'ptr 'set!) (%p %b) 2 122 1)
  (list %r0 (%cmp (%p %a) (%p %b) 3)))
```
---
    (0 -1)

### set fills a region

```x
(do
  (def %s ((prim-ref 'str 'make) 4))
  ((prim-ref 'mem 'set) ((prim-ref 'str '->ptr) %s) 122 3)
  (list (%str-ref %s 0) (%str-ref %s 2) (%str-ref %s 3)))
```
---
    (#\z #\z #\space)

### str=? bottoms out in the block compare

```x
(list (str=? "hello" "hello") (str=? "hello" "hellp") (str=? "ab" "abc"))
```
---
    (#t #f #f)

## ptr set-word!

### a word round-trips through set-word! / ref-word

`ptr set!` writes a byte; this is its machine-word sibling, writing
sizeof(long) bytes with no bounds checking.

```x
(do
  (def %p ((prim-ref 'mem 'alloc) 32))
  ((prim-ref 'ptr 'set-word!) %p 0 123456789)
  (def %v ((prim-ref 'ptr 'ref-word) %p 0))
  ((prim-ref 'mem 'free) %p)
  %v)
```
---
    123456789

### set-word! returns the pointer it wrote through

```x
(do
  (def %p ((prim-ref 'mem 'alloc) 32))
  (def %r ((prim-ref 'ptr 'set-word!) %p 0 7))
  (def %same (eq? %r %p))
  ((prim-ref 'mem 'free) %p)
  %same)
```
---
    #t

## alloc limit!

### arming the guard returns nil (side-effect contract)

The ceiling this spec run already carries is well under the value armed
here, so raising it changes nothing the rest of the file depends on.

```x
(null? (alloc-limit! 100000000))
```
---
    #t

### evaluation continues normally under a raised ceiling

```x
(do
  (alloc-limit! 100000000)
  (List length (list 1 2 3)))
```
---
    3

## heap sweep -- deliberately not specced here

`heap sweep` frees every heap object an immediately preceding `heap mark` did
not reach. There is no correct x-level call site for it: evaluating anything in
x allocates, so between the mark and the sweep the evaluator has already built
objects the mark never saw, and sweeping frees data that is live. `heap collect`
is the pairing that IS callable, and it is specced above -- it does both halves
with nothing evaluating in between, which is precisely the property that cannot
be reconstructed from two calls.

It was covered until now by the engine's own C suite, where the two can be
driven directly with no evaluation between them. That suite is not in this tree
once the engine arrives as a released artifact, so the reason moves here, next
to the subject, rather than the coverage quietly disappearing with the sources.
