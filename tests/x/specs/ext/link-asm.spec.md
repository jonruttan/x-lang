# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

The assembler's side of a link: `asm-unresolved!` takes the patches that
name a label the assembler never placed, so the code can be finalized as a
section and the patches handed to the linker; `asm-adr-far!` takes an
address that may lie anywhere in an executable, two instructions on
arm64 (ADRP and ADD) and one on x86-64 (LEA from RIP).

The cases link two objects assembled apart -- one calls a function the
other defines -- into one buffer and run it.  The patcher hands each
relocation to the backend's own resolver with the value put back into the
buffer's own offsets, as the finalize step does for a label.

## asm-unresolved!

### the patches naming an unplaced label come out, oldest first

```x
(do
  (def a (asm-new))
  (asm-emit! a 'bl (label 'helper))
  (asm-emit! a 'b (label 'here))
  (asm-label! a 'here)
  (asm-emit! a 'bl (label 'other))
  (asm-emit! a 'ret)
  (def taken (asm-unresolved! a))
  (write (list (List map (fn (_ p) (first (rest (rest (rest p))))) taken)
               (List length ((prim-ref 'obj 'ref) a 4))))
  (asm-free! a)
  (newline))
```
---
    (('helper 'other) 1)

## a link of two objects

### a call into another object's function

Object A: `main` calls `helper` and adds one; object B: `helper` answers
41.  The patch kind carries the assembler's width and type; the patcher
calls the backend's resolver with the target as an offset in the output
buffer, which is what the resolver takes.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/core/doors ptr->int str->ptr mem-copy)
  (def %la-object
    (fn (_ emit)
      (def a (asm-new))
      (emit a)
      (def taken (asm-unresolved! a))
      (def n (asm-pos a))
      (def bytes (Str8 make n))
      (asm-finalize! a)
      (mem-copy (str->ptr bytes) ((prim-ref 'obj 'ref) a 0) n)
      (asm-free! a)
      (list (list (list 'text 4 n bytes))
            (List map (fn (_ l) (list (symbol->str (first l)) 'text (rest l) 'global)) (asm-labels a))
            (List map (fn (_ p) (list 'text (first p) (list 'patch (first (rest p)) (first (rest (rest p))))
                                      (symbol->str (first (rest (rest (rest p))))) 0))
              taken))))
  (def %a (%la-object (fn (_ a)
                     (asm-label! a 'main)
                     (asm-prologue! a)
                     (asm-emit! a 'bl (label 'helper))
                     (asm-emit! a 'add x0 x0 (imm 1))
                     (asm-epilogue! a))))
  (def %b (%la-object (fn (_ a)
                     (asm-label! a 'helper)
                     (asm-emit! a 'mov x0 (imm 41))
                     (asm-emit! a 'ret))))
  (def %out (asm-new))
  (def %la-base (ptr->int ((prim-ref 'obj 'ref) %out 0)))
  (def %resolver (List ref 2 ((prim-ref 'obj 'ref) %out 5)))
  (def %r (link (list %a %b)
            (fn (_ sizes) (list (pair 'text %la-base)))
            (fn (_ p o kind value site)
              (%resolver p o (first (rest kind)) (first (rest (rest kind))) (- value %la-base)))))
  (def %text (first (first %r)))
  (mem-copy ((prim-ref 'obj 'ref) %out 0) (str->ptr (first (rest (rest (rest %text))))) (first (rest (rest %text))))
  (def %f (asm-finalize! %out))
  (display (Ptr call %f 0 0))
  (asm-free! %out)
  (newline))
```
---
    42

## asm-adr-far!

### an address taken from anywhere, called through blr

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-adr-far! a x8 'fn40)
  (asm-emit! a 'blr x8)
  (asm-emit! a 'add x0 x0 (imm 2))
  (asm-epilogue! a)
  (asm-label! a 'fn40)
  (asm-emit! a 'mov x0 (imm 40))
  (asm-emit! a 'ret)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 0))
  (asm-free! a)
  (newline))
```
---
    42
