# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

`lib/x/tool/obj-compiled.x` compiles `(obj ref)`, `(obj set!)` and `null?`
through compile-asm and installs each into its own closure object, so a
holder bound before the import calls the compiled version.  All three stay
entries of Compiled's list, switched to interpreted before a state image is
written.

## the doors

### all three are compiled on import

```x
(do (import x/tool/obj-compiled)
  (import x/tool/compiled)
  (write (list ((Compiled named (lit obj-ref)) state)
               ((Compiled named (lit obj-set!)) state)
               ((Compiled named (lit null?)) state))))
```
---
    ('compiled 'compiled 'compiled)

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
