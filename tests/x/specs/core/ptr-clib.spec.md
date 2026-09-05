# The engine's C library, through ptr
# @weight 1

Seven doors onto the engine's own C library, reached through `ptr`: the
string comparisons and searches, a bounded duplicate, and the byte-region
fill, copy and free.  Each takes and returns raw pointers; a string's bytes
are reached with `(str ->ptr)`, and text is read back with `(ptr ->str)`.

## ptr strcmp

### equal texts compare as 0

```x
((prim-ref 'ptr 'strcmp) ((prim-ref 'str '->ptr) "abc") ((prim-ref 'str '->ptr) "abc"))
```
---
    0

### the earlier text compares below 0

```x
(< ((prim-ref 'ptr 'strcmp) ((prim-ref 'str '->ptr) "abc") ((prim-ref 'str '->ptr) "abd")) 0)
```
---
    #t

## ptr strncmp

### compares only the first n bytes

```x
((prim-ref 'ptr 'strncmp) ((prim-ref 'str '->ptr) "abcX") ((prim-ref 'str '->ptr) "abcY") 3)
```
---
    0

## ptr strchr

### answers the pointer to the first occurrence of a byte

```x
((prim-ref 'ptr '->str) ((prim-ref 'ptr 'strchr) ((prim-ref 'str '->ptr) "hello") 108))
```
---
    "llo"

### answers nil when the byte is not there

```x
(null? ((prim-ref 'ptr 'strchr) ((prim-ref 'str '->ptr) "hello") 122))
```
---
    #t

## ptr strndup

### duplicates at most n bytes into a fresh block, which ptr free! releases

```x
(do
  (def %d ((prim-ref 'ptr 'strndup) ((prim-ref 'str '->ptr) "hello") 3))
  (def %text ((prim-ref 'ptr '->str) %d))
  ((prim-ref 'ptr 'free!) %d)
  %text)
```
---
    "hel"

## ptr fill!

### fills n bytes with one value and answers the pointer

```x
(do
  (def %p ((prim-ref 'ptr 'alloc) 8))
  (def %r ((prim-ref 'ptr 'fill!) %p 65 4))
  ((prim-ref 'ptr 'set!) %p 4 0 1)
  (list (same? %r %p) ((prim-ref 'ptr '->str) %p)))
```
---
    (#t "AAAA")

## ptr copy!

### copies n bytes from source to destination and answers the destination

```x
(do
  (def %p ((prim-ref 'ptr 'alloc) 8))
  ((prim-ref 'ptr 'fill!) %p 0 8)
  (def %r ((prim-ref 'ptr 'copy!) %p ((prim-ref 'str '->ptr) "xyz") 3))
  (list (same? %r %p) ((prim-ref 'ptr '->str) %p)))
```
---
    (#t "xyz")

## ptr free!

### releases a block ptr alloc gave out and answers nil

```x
(null? ((prim-ref 'ptr 'free!) ((prim-ref 'ptr 'alloc) 16)))
```
---
    #t
