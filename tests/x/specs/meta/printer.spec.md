# The x printer's internal contracts

boot/printer.x owns rendering end to end; the C layer keeps only the
(io write-str) OUT door.  These tests pin the internals the public io
specs cannot reach: the handler-stack walk must survive EMPTY stacks
(types whose C write handlers are gone and whose x handler is not yet
pushed -- the boot-window state), and the opaque-type handles must
resolve by NAME BYTES since they are C-static atoms, not reader symbols.

## missing-handler fallback

### an empty write stack falls to the opaque form, no crash

The probe runs under a SENTINEL guard and the stack is restored
UNCONDITIONALLY before asserting: if the probe raises, re-raising before
the restore would leave STRING's write stack empty for the whole batch,
cascading every later string-rendering test.

```scheme
(do
  (def %t (%registry-assoc-rest (%print-type-of "s") (first %reflect-type-alist-cell)))
  (def %node (%reflect-step %t (%reflect-path-parent %print-path-write-stack)))
  (def %saved (first %node))
  (%set-first! %node ())
  (def %r (guard (e ()) ((prim-ref 'io 'write-to-str) "s")))
  (%set-first! %node %saved)
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

## cross-base dispatch

Handler resolution is OWN-TREE-FIRST (the type word is the tree pointer,
as C's x_obj_type dispatch was), with the name-keyed alist lookup as the
fallback.  Own-tree serves custom types registered in OTHER bases -- their
handlers travel with the instance; the fallback serves child-base built-ins,
whose bare trees share interned name atoms with the parent's handler-bearing
trees.

### a child-registered type's write handler dispatches from the parent

```scheme
(do
  (def %xb (Base make))
  (def %xb-t (Base make-type %xb "XB-T"
    (list (pair 'write (fn (_ o) (display "<child-ok>"))))))
  (Base bind %xb 'xb-t %xb-t)
  (Base bind %xb 'mi (prim-ref 'type 'make-instance))
  (def %xb-i (Base eval %xb (lit (mi xb-t 5))))
  (display %xb-i))
```
---
    <child-ok>

## opaque handle resolution

### the six boot-registered opaque types resolve by name

ATOM is the seventh: it registers lazily on first x_mkatom and NOTHING in
the tree constructs one, so its tree is absent at boot and its push
no-ops (kept for embedders that pre-register the type).

```scheme
(List map (fn (_ n) (null? (%print-handle-by-name n (first %reflect-type-alist-cell))))
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

## non-navigable type tags (the base sentinel)

A raw child base's type slot holds x_eval_obj -- a static ATOM whose
bytes are "BASE", never a registered pair tree.  (type name) must answer
the tag's own bytes, exactly as the C branch returned the raw tag:
stepping the name path through an atom with the UNCHECKED first/rest
reads its payload as a pair pointer, which is how the REPL echo of a
fresh base segfaulted mid-#<obj: (the opaque form calls type-name for
the label).  (Base make) wraps the raw base in an instance now, so these
pins reach through the catalog for the raw object.

### a base's sentinel type tag answers its bytes, not a navigation

```scheme
((prim-ref 'type 'name) ((prim-ref 'base 'make)))
```
---
    "BASE"

### a raw base renders as the bounded opaque form

```scheme
((prim-ref 'io 'display-to-str) ((prim-ref 'base 'make)))
```
---
    "#<obj:BASE>"

### a sentinel-typed operator is data, not a navigation (head position)

The same tag guard in C's x_type_list_eval: an operator whose type tag
is not a pair tree has no call slot to walk, so the form answers itself
as data -- exactly the nil-call-slot contract -- instead of reading the
tag's payload as pair pointers (the (b eval ...) segfault).

```scheme
(do (def %rawb ((prim-ref 'base 'make)))
    (pair? (%rawb eval 1)))
```
---
    #t

### a type-handle operator is data too

```scheme
(pair? ((%print-type-of 0) 1))
```
---
    #t

### reader symbols do NOT intern to type handles

```scheme
(eq? (%print-type-of (fn (_ x) x)) 'PROCEDURE)
```
---
    #f

## to-str contracts

### to-str returns a FRESH string, never the source object

```scheme
(do (def %s "abc")
    (same? ((prim-ref 'io 'display-to-str) %s) %s))
```
---
    #f

### to-str of a boolean is fresh per call

```scheme
(same? ((prim-ref 'io 'display-to-str) #t)
       ((prim-ref 'io 'display-to-str) #t))
```
---
    #f

### to-str nests: a handler rendering to a string mid-capture

```scheme
(do
  (def %wts (prim-ref 'io 'write-to-str))
  (def %t (%registry-assoc-rest (%print-type-of 0) (first %reflect-type-alist-cell)))
  (def %node (%reflect-step %t (%reflect-path-parent %print-path-write-stack)))
  (def %saved (first %node))
  (%set-first! %node
    (pair (fn (_ o) (do (%print-emit "[") (%print-emit (%wts "in")) (%print-emit "]")))
          %saved))
  (def %r (guard (e 'err) (%wts 42)))
  (%set-first! %node %saved)
  %r)
```
---
    "[\"in\"]"

### write-to-str survives a 12k-element list (tail join)

Re-armed after the allocation-disease cure (fold/%as-list once-only
normalization, arithmetic fast paths, lean cond/or/named-let): the
per-element cost fell ~6.7x and this render measures 1.85GB RSS /
8.6s on Linux under a 4GB cap (2026-07-16) -- OOM-killing 16GB CI
runners before the cure.  It pins the TAIL join: the old non-tail
round segfaulted at ~10k elements.

```scheme
(do
  (def %build (fn (self n acc) (match ((eq? n 0) acc) (#t (self (- n 1) (pair n acc))))))
  (str? ((prim-ref 'io 'write-to-str) (%build 12000 ()))))
```
---
    #t

### an error mid-render restores the sink and propagates

```scheme
(do
  (def %wts (prim-ref 'io 'write-to-str))
  (def %t (%registry-assoc-rest (%print-type-of 0) (first %reflect-type-alist-cell)))
  (def %node (%reflect-step %t (%reflect-path-parent %print-path-write-stack)))
  (def %saved (first %node))
  (%set-first! %node (pair (fn (_ o) (error 'render-boom)) %saved))
  (def %r (guard (e e) (%wts 42)))
  (%set-first! %node %saved)
  (display %r) (display " ") (display 7))
```
---
    render-boom 7

## handler-less cell instances

### render the bounded #<obj:NAME> form, never a data word

```scheme
(do
  (def %h ((prim-ref 'type 'make) "GHOST" ()))
  (display ((prim-ref 'obj 'make) %h 0)))
```
---
    #<obj:GHOST>

## the C-raised error atom prints its message (#54)

x_eval_error delivers a nil-typed atom whose string is the base's error
scratch buffer. The printer's generic sentinel form rendered the BUFFER
POINTER -- every C-raised error printed as the same #<ATOM:0x..>, zero
diagnostic signal with the message sitting right there in the atom. The
printer now identity-tests that one atom (reached via the error-str layout
path) and emits its bytes. (error "msg") delivers a real STRING and never
took this path.

### uncaught unbound symbol shows the diagnostic

```scheme
nosuchsym
```
---
    Error: Unbound SYMBOL 'nosuchsym'

### display and write of a caught error show the message

```scheme
(do (display (guard (e e) nosuchsym)) (display " / ") (write (guard (e e) nosuchsym)))
```
---
    Unbound SYMBOL 'nosuchsym' / Unbound SYMBOL 'nosuchsym'

### two different C-raised errors are distinguishable

```scheme
(do
  (def a (%str-append "" (guard (e e) nosuchsym)))
  (def b (%str-append "" (guard (e e) (list 1 . 5))))
  (list (str=? a b) (Str8 includes? "improper" b)))
```
---
    (#f #t)

### x-level (error msg) still delivers the string itself

```scheme
(guard (e e) (error "custom boom"))
```
---
    "custom boom"

### other sentinel atoms still render generically

```scheme
(Str8 starts? "#<ATOM:0x" (%display-to-str (Type of 0)))
```
---
    #t
