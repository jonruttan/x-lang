# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

`lib/x/tool/obj-compiled.x` compiles `(obj ref)`, `(obj set!)`, `null?`,
`and` and `or` through compile-asm and installs each into its own object, so
a holder bound before the import calls the compiled version.  x-core imports
it, so every dialect, helium included, runs the compiled versions.  All five
stay entries of Compiled's list, switched to interpreted before a state image
is written.

## the doors

### x-core has all five compiled, with no import

```x
(do (import x/tool/compiled)
  (write (List map (fn (_ name) ((Compiled named name) state))
           (list (lit obj-ref) (lit obj-set!) (lit null?) (lit and) (lit or)))))
```
---
    ('compiled 'compiled 'compiled 'compiled 'compiled)

### a door bound before the import is the compiled primitive

```x
(do (def %ref-before (prim-ref (lit obj) (lit ref)))
  (import x/tool/obj-compiled)
  (write (list (same? %ref-before (prim-ref (lit obj) (lit ref)))
               (eq? (type-of %ref-before) (type-of first)))))
```
---
    (#t #t)

### ref reads a data word and set! writes one and answers the value

```x
(do (import x/tool/obj-compiled)
  (def %ref (prim-ref (lit obj) (lit ref)))
  (def %set (prim-ref (lit obj) (lit set!)))
  (def %v (Vector make 4 0))
  (def %put (%set %v 2 (lit two)))
  (import x/tool/compiled)
  (def %slow-ref ((Compiled named (lit obj-ref)) interpreted))
  (write (list %put (%ref %v 2) (%ref %v 3) (%slow-ref %v 2)
               (first (%ref (list (list 5)) 0)))))
```
---
    ('two 'two 0 'two 5)

### interpreted again and compiled again, across a collect

```x
(do (import x/tool/obj-compiled)
  (import x/tool/compiled)
  (def %ref (prim-ref (lit obj) (lit ref)))
  (def %v (Vector make 3 (lit z)))
  (Heap collect)
  ((Compiled named (lit obj-ref)) interpret!)
  (def %slow (list (%ref %v 1) (eq? (type-of %ref) (type-of first))))
  ((Compiled named (lit obj-ref)) compile!)
  (write (list %slow (%ref %v 1) (eq? (type-of %ref) (type-of first)))))
```
---
    (('z #f) 'z #t)

### set!'s value collects, and the index evaluated before it survives

Vector build writes each slot with (obj set! v (int+ i 1) (f i)): the index
is a fresh integer, evaluated before (f i), and f here collects and then
allocates over whatever the collect freed.  The index is held in a rooted
cell, so every store lands in its own slot.

```x
(do (import x/tool/obj-compiled)
  (def %v (Vector build 3000
            (fn (_ i)
              (do (if (if (= i 1000) #t (= i 2000)) (Heap collect) ())
                  (list i (list i i))))))
  (Heap collect)
  (write (list (Vector length %v) (Vector ref 0 %v) (Vector ref 1000 %v)
               (Vector ref 2999 %v))))
```
---
    (3000 (0 (0 0)) (1000 (1000 1000)) (2999 (2999 2999)))

## null?

### null? answers as its interpreted version on every kind of value

The integer 0 and the character 0 are here because eq? compares an
immediate scalar by its value.

```x
(do (import x/tool/obj-compiled)
  (import x/tool/compiled)
  (def %slow-null ((Compiled named (lit null?)) interpreted))
  (def %vals (list () 0 (%integer->char 0) #f #t "" (lit a) (list 1) (pair () ())
                   (Vector make 0 0) null? first))
  (write (list (eq? (type-of null?) (type-of first))
               (List map null? %vals)
               (List map %slow-null %vals))))
```
---
    (#t (#t #f #f #f #f #f #f #f #f #f #f #f) (#t #f #f #f #f #f #f #f #f #f #f #f))

## and and or

### and answers as its interpreted version

```x
(do (import x/tool/obj-compiled)
  (import x/tool/compiled)
  (def %slow-and ((Compiled named (lit and)) interpreted))
  (write (list
    (list (and) (and 1) (and 1 2) (and #f 2) (and () 2) (and 1 2 3) (and 1 #f 3) (and 1 2 ()))
    (list (%slow-and) (%slow-and 1) (%slow-and 1 2) (%slow-and #f 2) (%slow-and () 2)
          (%slow-and 1 2 3) (%slow-and 1 #f 3) (%slow-and 1 2 ())))))
```
---
    ((#t 1 2 #f #f 3 #f ()) (#t 1 2 #f #f 3 #f ()))

### or answers as its interpreted version, the last operand passing through

```x
(do (import x/tool/obj-compiled)
  (import x/tool/compiled)
  (def %slow-or ((Compiled named (lit or)) interpreted))
  (write (list
    (list (or) (or 1) (or #f 2) (or () #f) (or #f ()) (or #f #f 3) (or 0 1))
    (list (%slow-or) (%slow-or 1) (%slow-or #f 2) (%slow-or () #f) (%slow-or #f ())
          (%slow-or #f #f 3) (%slow-or 0 1)))))
```
---
    ((() 1 2 #f () 3 0) (() 1 2 #f () 3 0))

### an argument past the answer is never evaluated, and locals are the caller's

```x
(do (import x/tool/obj-compiled)
  (def %n 0)
  (def %bump (fn (_ v) (set! %n (+ %n 1)) v))
  (def %skipped (list (and #f (%bump 1)) (or 1 (%bump 1)) %n))
  (def %local (fn (_ a b) (if a (list (and a b) (or b a)) (list (and a b) (or a b)))))
  (write (list %skipped (%local 5 6) (%local #f 6) (and 1 (%bump 2)) (or #f (%bump 3)) %n)))
```
---
    ((#f 1 0) (6 6) (#f 6) 2 3 2)
