# Conformance: objects, pointers and raw memory (profile `core`)

The reflection substrate. Under decision L1 every engine must be word-addressable
and ship its own layout descriptors, because x-lang's `lib/x/boot/reflect.x` reads
object header words directly and `lib/x/boot/data.x` sizes a word by round-tripping
2^32 through a pointer cast. These are the instructions that makes that possible,
and an engine that cannot supply them cannot boot the library at all.

The casts (`obj/->ptr`, `ptr/->obj`, `int/->ptr`, `ptr/->int`) are tagged `ffi` in
the ISA alongside `dlopen`, but they are a different capability -- see
`tools/contract/features.x`, which splits that tag three ways. `lib/x/boot` reaches
these six and never reaches the foreign door.

### an object round-trips through a pointer

covers: obj/->ptr ptr/->obj

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %p2o (%coord (lit ptr) (lit ->obj)))
(def p (pair 3 4))
(%ok (same? (%p2o (%o2p p)) p))
```
---
    *** ERROR: ok

### a pointer round-trips through an integer

covers: ptr/->int int/->ptr

This is the round-trip `data.x` sizes a word with, and the reason word-size and
fixnum-width cannot diverge: an engine whose integer cannot hold a pointer loses
the address here rather than reporting an error.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %i2p (%coord (lit int) (lit ->ptr)))
(def %p2o (%coord (lit ptr) (lit ->obj)))
(def p (pair 5 6))
(%ok (same? (%p2o (%i2p (%p2i (%o2p p)))) p))
```
---
    *** ERROR: ok

### obj eq? and same? answer on identity

covers: obj/eq? obj/same?

```x
(def %oeq (%coord (lit obj) (lit eq?)))
(def %osame (%coord (lit obj) (lit same?)))
(def p (pair 1 2))
(def q (pair 1 2))
(%ok (match ((%osame p p) (match ((%osame p q) ()) (#t 1))) (#t ())))
```
---
    *** ERROR: ok

### a word written through a pointer reads back

covers: ptr/set-word! ptr/ref-word

```x
(def %mk (%coord (lit str) (lit make)))
(def %s2p (%coord (lit str) (lit ->ptr)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def p (%s2p (%mk 32)))
(%setw p 0 12345)
(%ok (= (%refw p 0) 12345))
```
---
    *** ERROR: ok

### a byte written through a pointer reads back at its own offset

covers: ptr/set! ptr/ref

Each offset is written before it is read: `(str make N)` is not promised to return
zeroed memory, and a case that asserted a neighbouring byte was 0 would be testing
the allocator's mood rather than the primitives.

```x
(def %mk (%coord (lit str) (lit make)))
(def %s2p (%coord (lit str) (lit ->ptr)))
(def %set (%coord (lit ptr) (lit set!)))
(def %ref (%coord (lit ptr) (lit ref)))
(def p (%s2p (%mk 32)))
(%set p 3 200 1)
(%set p 4 7 1)
(%ok (match ((= (%ref p 3 1) 200) (= (%ref p 4 1) 7)) (#t ())))
```
---
    *** ERROR: ok

### a widening read is LITTLE-ENDIAN

covers: ptr/ref

The engine reads `width` bytes into the low end of a zeroed machine integer, so a
4-byte read of the bytes 1,0,0,0 is 1 rather than 16777216. This is a HOST
property, not a choice: on a big-endian machine the same primitive would answer
differently, which is why `tools/contract/constraints.x` records an `endian`
constraint for every module that decodes a C struct this way.

```x
(def %mk (%coord (lit str) (lit make)))
(def %s2p (%coord (lit str) (lit ->ptr)))
(def %set (%coord (lit ptr) (lit set!)))
(def %ref (%coord (lit ptr) (lit ref)))
(def p (%s2p (%mk 32)))
(%set p 0 1 1)
(%set p 1 0 1)
(%set p 2 0 1)
(%set p 3 0 1)
(%ok (= (%ref p 0 4) 1))
```
---
    *** ERROR: ok

### malloc'd memory is writable and freeable

covers: mem/alloc mem/free mem/set

```x
(def %alloc (%coord (lit mem) (lit alloc)))
(def %free (%coord (lit mem) (lit free)))
(def %memset (%coord (lit mem) (lit set)))
(def %ref (%coord (lit ptr) (lit ref)))
(def p (%alloc 16))
(%memset p 65 16)
(def v (%ref p 5 1))
(%free p)
(%ok (= v 65))
```
---
    *** ERROR: ok

### memory copies and compares

covers: mem/copy mem/cmp

```x
(def %alloc (%coord (lit mem) (lit alloc)))
(def %free (%coord (lit mem) (lit free)))
(def %memset (%coord (lit mem) (lit set)))
(def %copy (%coord (lit mem) (lit copy)))
(def %cmp (%coord (lit mem) (lit cmp)))
(def a (%alloc 8))
(def b (%alloc 8))
(%memset a 7 8)
(%memset b 9 8)
(%copy b a 8)
(def same (%cmp a b 8))
(%free a)
(%free b)
(%ok (= same 0))
```
---
    *** ERROR: ok

### type of reports a type object, and it is stable per type

covers: type/of

```x
(def %tof (%coord (lit type) (lit of)))
(%ok (match ((same? (%tof 1) (%tof 2)) (match ((same? (%tof 1) (%tof (pair 1 2))) ()) (#t 1))) (#t ())))
```
---
    *** ERROR: ok

## The object-model constructors

### obj make needs a REGISTERED type handle, and answers an object of that type

covers: obj/make

`(obj make HANDLE N)` allocates an object with N slots, and the handle must be a
type the base knows: the primitive looks it up in the base's type alist and
answers nil when it is not there. That is why a bare `(obj make 2)` yields
nothing -- there is no type to make an instance OF. This is the raw allocator
`type/make-instance` is built over.

```x
(def %mkt (%coord (lit type) (lit make)))
(def %omake (%coord (lit obj) (lit make)))
(def %tof (%coord (lit type) (lit of)))
(def T (%mkt "OBJTEST" ()))
(%ok (match ((eq? (%omake T 2) ()) ()) (#t (same? (%tof (%omake T 2)) T))))
```
---
    *** ERROR: ok

### make-callable turns a raw pointer into a PRIM

covers: obj/make-callable

The JIT's door: compile machine code, take its address, and hand it back as
something the evaluator will call. The contract asserted here is what it
PRODUCES -- an object of the same type as a primitive, not a pointer and not nil.

The result is deliberately not called. A callable made this way must follow the
engine's own primitive calling convention, and `strlen` does not; wrapping it is
safe, calling it would not be. `lib/x/tool/compile.x` wraps code it emitted for
that convention, which is the only correct use.

```x
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def %mkcall (%coord (lit obj) (lit make-callable)))
(def %tof (%coord (lit type) (lit of)))
(def p (%dlsym (%dlopen () 1) "strlen"))
(%ok (same? (%tof (%mkcall p)) (%tof %tof)))
```
---
    *** ERROR: ok

## obj ref on a freshly made object -- not defined here

`(obj make HANDLE N)` nils its slots, but reading one back through `obj ref`
before anything is stored crashes this engine rather than answering nil. That may
be a defect or it may be an unstated precondition; either way a conformance case
must not pin it until which one is known, and the reflective accessors the library
actually uses (lib/x/boot/reflect.x) replace this primitive anyway.
