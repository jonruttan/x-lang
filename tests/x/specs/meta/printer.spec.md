# The x printer's internal contracts

boot/printer.x owns rendering end to end; the C layer keeps only the
(io write-str) OUT door.  These tests pin the internals the public io
specs cannot reach: the handler-stack walk must survive EMPTY stacks
(types whose C write handlers are gone and whose x handler is not yet
pushed -- the boot-window state), and the opaque-type handles must
resolve by NAME BYTES since they are C-static atoms, not reader symbols.

## missing-handler fallback

### an empty write stack falls to the generic form, no crash

```scheme
(do
  (def %t (%registry-assoc-rest (%print-type-of "s") (first %reflect-type-alist-cell)))
  (def %node (%reflect-step %t (%print-path-parent %print-path-write-stack)))
  (def %saved (first %node))
  (set-first! %node ())
  (def %r ((prim-ref (lit io) (lit write-to-str)) "s"))
  (set-first! %node %saved)
  (not (null? %r)))
```
---
    #t

### a path step into nil answers nil

```scheme
(null? (%reflect-step () (lit (f r f))))
```
---
    #t

## opaque handle resolution

### the six boot-registered opaque types resolve by name

ATOM is the seventh: it registers lazily on first x_mkatom and NOTHING in
the tree constructs one, so its tree is absent at boot and its push
no-ops (kept for embedders that pre-register the type).

```scheme
(map (fn (_ n) (null? (%print-handle-by-name n (first %reflect-type-alist-cell))))
     (pair "BUFFER" (pair "POINTER" (pair "PRIMITIVE"
       (pair "ITER" (pair "PROCEDURE" (pair "OPERATIVE" ())))))))
```
---
    (#f #f #f #f #f #f)

### ATOM is not boot-registered

```scheme
(null? (%print-handle-by-name "ATOM" (first %reflect-type-alist-cell)))
```
---
    #t

### reader symbols do NOT intern to type handles

```scheme
(eq? (%print-type-of (fn (_ x) x)) (lit PROCEDURE))
```
---
    #f
