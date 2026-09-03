# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

A 64-bit immediate is how the assembler names anything outside the code it
is emitting: a `jit_*` trampoline resolved by dlsym, an fvar's object
pointer, the self-call trampoline cell. Every one of those is an address
valid only in the process that compiled — which is exactly what stops the
emitted bytes from being reused anywhere else.

Recording each site as `(offset kind name)` is what makes them reusable: the
bytes can be poured into a fresh buffer and each immediate re-encoded for the
process loading them. These cases pin the two halves — that the sites are
recorded, and that re-encoding one actually changes what the code does.

## recording the sites

### a compiled function reports where its trampoline addresses landed

Every call the lane emits goes through a dlsym'd address, so even a trivial
integer function has several. The record names the SYMBOL, never the
address: the address is the very thing that is wrong in another process.

```scheme
(do
  (def %f (compile-asm '(fn (_ x) (+ x 1)) ()))
  (def %every (fn (self p xs) (if (null? xs) #t (if (p (first xs)) (self p (rest xs)) #f))))
  (write (list (> (%length %asm-last-relocs) 0)
               (%every (fn (_ r) (eq? (first (rest r)) 'trampoline)) %asm-last-relocs)
               (%every (fn (_ r) (str? (first (rest (rest r))))) %asm-last-relocs)
               (> %asm-last-size 0)))
  (newline))
```
---
    (#t #t #t #t)

### every recorded offset lies inside the emitted code

An offset past the end would relocate into whatever followed the buffer.

```scheme
(do
  (def %f (compile-asm '(fn (_ x) (+ x 1)) ()))
  (def %every (fn (self p xs) (if (null? xs) #t (if (p (first xs)) (self p (rest xs)) #f))))
  (write (%every (fn (_ r) (and (>= (first r) 0) (< (first r) %asm-last-size)))
                 %asm-last-relocs))
  (newline))
```
---
    #t

## re-encoding a site

### relocating an immediate changes what the code returns

The proof that a record is enough to rebuild with: emit a function that
returns a baked constant, relocate that one site, and the function returns
the new value. Relocation happens BEFORE `asm-finalize!` on purpose — that
call mprotects the page R+X, and a write afterwards is a segfault, not an
error, so a loader must pour, relocate, then protect.

```scheme
(do
  (def %a (asm-new 256))
  (def %site (asm-pos %a))
  (asm-load-imm64! %a x0 3735928559)
  (asm-emit! %a 'ret)
  (asm-reloc-apply! %a %site 81985529216486895)
  (def %fn (asm-finalize! %a))
  (write (= ((prim-ref 'ptr 'call) %fn) 81985529216486895))
  (newline))
```
---
    #t

### a site relocated to its own value is a no-op

Re-encoding must reproduce the original bytes exactly when the value is
unchanged, or a cache that reloads into the same process would corrupt code
it only meant to rewrite in place.

```scheme
(do
  (def %a (asm-new 256))
  (def %site (asm-pos %a))
  (asm-load-imm64! %a x0 1311768467463790320)
  (asm-emit! %a 'ret)
  (asm-reloc-apply! %a %site 1311768467463790320)
  (def %fn (asm-finalize! %a))
  (write (= ((prim-ref 'ptr 'call) %fn) 1311768467463790320))
  (newline))
```
---
    #t

## surviving the collector

### the records survive a collection while the builder is alive

The records live in a slot on the ASM object, and between recording a site
and reading it back there is nothing else holding them — so whether they
survive is entirely a question of whether the mark hook can see that slot.
It could not: `asm-new` makes seven slots and `set-units!` declared six, from
the commit that added the relocations slot. One collection turned three
records into a single nil, and the first thing to hold them across an
allocation got `(() ...)` and segfaulted writing it.

Forcing the collection is the whole point of the case — the defect is not
that the records are wrong, it is that a collection landing in the wrong
place makes them wrong, which is invisible until something allocates at the
wrong moment.

```scheme
(do
  (import x/sys/gc)
  (def %a (asm-new 4096))
  (asm-reloc! %a 0 'trampoline "jit_mkint")
  (asm-reloc! %a 16 'fvar 'y)
  (asm-reloc! %a 32 'self-cell ())
  (Heap collect)
  (write (asm-relocs %a))
  (newline))
```
---
    ((0 'trampoline "jit_mkint") (16 'fvar 'y) (32 'self-cell ()))
