# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

Compiling is expensive and the compiler is itself interpreted x-lang: one
`compile-asm` call costs hundreds of thousands of evals, the same the second
time, and a xenon boot pays that eleven times over. Nothing in the emitted
code is per-process except the addresses it bakes in, and those are recorded
(#598) — so the bytes can be kept, poured into a fresh buffer, and each baked
address re-encoded for the process loading them.

`compile-asm` arrives as a stub that loads this module on first call, so a
case that reaches for `%asm-cache-*` without compiling first says `import`
outright rather than leaning on the case above it having run.

That makes the KEY the whole correctness story. x-lang#590 was a cache key
blind to engine identity serving ABI-stale objects that silently misread
numbers — `2.5` came back as `2` followed by the symbol `.5`. A wrong answer
is the only failure that matters here; a missed hit merely costs a recompile,
which is what the cache was avoiding anyway. These cases pin both halves:
that a hit is the same function, and that everything else misses.

## a hit is the same function

### a loaded function answers what the compiled one answered

The whole round trip in one case: compile, which stores, then load the entry
back and call it. Same argument, same answer.

```scheme
(do
  (def %e '(fn (_ x) (* x 3)))
  (def %f (compile-asm %e ()))
  (def %t (%asm-cache-text %e ()))
  (def %g (%asm-cache-load %t (%asm-cache-path %t) ()))
  (write (list (%f 7) (if (null? %g) 'missed (%g 7))))
  (newline))
```
---
    (21 21)

### two functions never answer for each other

The property a hash-named cache has to have. Both entries exist at once, and
each key finds its own — not the one that happened to be stored last.

```scheme
(do
  (def %e1 '(fn (_ x) (- x 1)))
  (def %e2 '(fn (_ x) (- x 2)))
  (compile-asm %e1 ())
  (compile-asm %e2 ())
  (def %t1 (%asm-cache-text %e1 ()))
  (def %t2 (%asm-cache-text %e2 ()))
  (def %g1 (%asm-cache-load %t1 (%asm-cache-path %t1) ()))
  (def %g2 (%asm-cache-load %t2 (%asm-cache-path %t2) ()))
  (write (list (if (null? %g1) 'missed (%g1 10))
               (if (null? %g2) 'missed (%g2 10))))
  (newline))
```
---
    (9 8)

### a load publishes the same facts a compile does

`%asm-last-relocs` and `%asm-last-size` are how anything downstream learns
what was just produced. A warm cache never loads asm-compile.x at all, so the
LOADER has to publish them too, in the shape the assembler uses — kind as a
symbol, a trampoline's name as the dlsym string.

```scheme
(do
  (def %e '(fn (_ x) (+ x 41)))
  (def %t (%asm-cache-text %e ()))
  (compile-asm %e ())
  (def %size %asm-last-size)
  (set! %asm-last-size 0)
  (set! %asm-last-relocs ())
  (def %g (%asm-cache-load %t (%asm-cache-path %t) ()))
  (def %every (fn (self p xs) (if (null? xs) #t (if (p (first xs)) (self p (rest xs)) #f))))
  (write (list (= %asm-last-size %size)
               (> (%length %asm-last-relocs) 0)
               (%every (fn (_ r) (eq? (first (rest r)) 'trampoline)) %asm-last-relocs)
               (%every (fn (_ r) (str? (first (rest (rest r))))) %asm-last-relocs)))
  (newline))
```
---
    (#t #t #t #t)

## everything else misses

### the key carries the engine and the machine

These are native bytes against one engine's ABI on one machine. A key that
does not say which is #590 waiting to happen again, so the identity is not
merely hashed in — it is in the text the entry stores and the load compares.

```scheme
(do
  (import x/tool/asm-cache)
  (def %t (%asm-cache-text '(fn (_ x) x) ()))
  (write (list (Str8 match-at? x-machine 0 %t)
               (Str8 match-at? x-release (Str8 length x-machine) %t)))
  (newline))
```
---
    (#t #t)

### the fvar table's shape is part of the key

The emitted code is not a function of the source alone. Within analyser mode
a name absent from the table is read as a parameter while a name
present-but-nil is emitted as a literal zero with no relocation at all --
different bodies for one source text, so different keys.

```scheme
(do
  (import x/tool/asm-cache)
  (def %e '(fn (_ x) x))
  (write (list (str=? (%asm-cache-text %e () #f) (%asm-cache-text %e '((y . 1)) #t))
               (str=? (%asm-cache-text %e '((y . 1)) #t) (%asm-cache-text %e '((y . ())) #t))
               (str=? (%asm-cache-text %e '((y . 1)) #t) (%asm-cache-text %e '((z . 1)) #t))))
  (newline))
```
---
    (#f #f #f)

### the calling world is part of the key in its own right

It used to be readable off the fvar table -- empty meant an integer function
whose result is boxed, non-empty meant an analyser returning an object -- and
is not any more, because an integer function may carry an fvar naming a callee
it calls (#603). One source text and one fvar table now name two bodies, and
the key has to say which.

```scheme
(do
  (import x/tool/asm-cache)
  (def %e '(fn (_ x) x))
  (write (str=? (%asm-cache-text %e '((y . 1)) #f) (%asm-cache-text %e '((y . 1)) #t)))
  (newline))
```
---
    #f

### an analyser entry is not served to an integer-mode compile

The key case that matters, run end to end rather than on the key text: compile
the analyser first so ITS entry is the one sitting in the cache, then ask for
the identical source and the identical fvar table as an integer function. An
integer function boxes its result; an analyser's would come back raw.

```scheme
(do
  (def %src '(fn (_ n) (+ n 1)))
  (def %fv (list (pair 'k 1)))
  (compile-asm %src %fv)
  (display ((compile-asm %src %fv #f) 41)))
```
---
    42

### an entry that is not one misses rather than answering

Anything at the path that is not this format — a truncated write, a file from
an older layout, junk — has to read as absent. The magic is checked before a
single byte is trusted.

```scheme
(do
  (import x/tool/asm-cache)
  (def %fd (%asm-cache-creat "/tmp/x-asm-spec-junk.asm"))
  (%asm-cache-put %fd "this is not a cache entry at all" 32)
  (write (%asm-cache-load "any key" "/tmp/x-asm-spec-junk" ()))
  (newline))
```
---
    ()

### an entry whose stored key disagrees misses

The filename is a 64-bit hash, and a hash is an invitation to collide. The
whole key text is stored in the entry and compared before the bytes are used,
so a collision costs a recompile instead of handing back a function compiled
from different source — which is the failure, not the cost.

```scheme
(do
  (def %e '(fn (_ x) (* x 5)))
  (def %t (%asm-cache-text %e ()))
  (compile-asm %e ())
  (write (%asm-cache-load (Str append %t "-not-the-same") (%asm-cache-path %t) ()))
  (newline))
```
---
    ()

### an absent entry misses

The ordinary cold case, and the one every other miss is spelled as.

```scheme
(do (import x/tool/asm-cache)
    (write (%asm-cache-load "absent" "/tmp/x-asm-spec-no-such-entry" ())))
```
---
    ()
