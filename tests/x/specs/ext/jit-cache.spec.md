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
case that reaches for the cache without compiling first says `import`
outright. The cache is a module of its own, and the five internals these
cases drive are bound once from its frame by the first case below; the slurp
chunk is a variable the loader reads, so the case that moves it does so in
the module's frame.

That makes the KEY the whole correctness story. x-lang#590 was a cache key
blind to engine identity serving ABI-stale objects that silently misread
numbers — `2.5` came back as `2` followed by the symbol `.5`. A wrong answer
is the only failure that matters here; a missed hit merely costs a recompile,
which is what the cache was avoiding anyway. These cases pin both halves:
that a hit is the same function, and that everything else misses.

## the internals, reached through the module

### the five functions these cases drive, bound from the module's frame

```x
(do
  (import x/tool/asm-cache)
  (def %ac (fn (_ name) (eval name (module x/tool/asm-cache))))
  (def %asm-cache-text (%ac (lit %asm-cache-text)))
  (def %asm-cache-load (%ac (lit %asm-cache-load)))
  (def %asm-cache-path (%ac (lit %asm-cache-path)))
  (def %asm-cache-creat (%ac (lit %asm-cache-creat)))
  (def %asm-cache-put (%ac (lit %asm-cache-put)))
  (write (list (procedure? %asm-cache-text) (procedure? %asm-cache-load) (procedure? %asm-cache-path)
               (procedure? %asm-cache-creat) (procedure? %asm-cache-put)))
  (newline))
```
---
    (#t #t #t #t #t)

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
LOADER has to publish them too, in the layout the assembler uses — label as a
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

## size is not a reason to miss

The first cache stood aside above 128 nodes, and its slurp read one 64KB
buffer and called a full one a miss. Both were sized for the boot's
analysers (9 to 42 nodes, entries of a few hundred bytes), and both turned
away exactly the expression that hurt most: sha256-jit's 12,241-node fill
body compiled for nine seconds in every process that digested more than
64KB, with its 82KB record file sitting in the cache, unread past the first
64KB. The key text is spelled by the C `write-to-str` door and hashed by
FNV, both linear, so the probe is a fixed small fraction of a compile at any
size -- there is no size at which standing aside pays.

### a body well past the old node cap is keyed, and its second compile is a load

Three hundred nodes, generated: an unrolled chain of adds. `%asm-cache-load`
answering a callable is the proof the entry was stored and read back whole.

```scheme
(do
  (def %chain (fn (self i acc) (if (= i 0) acc (self (- i 1) (list '+ 1 acc)))))
  (def %e (list 'fn '(_ x) (%chain 150 'x)))
  (def %t (%asm-cache-text %e () #f))
  (def %f (compile-asm %e))
  (def %g (%asm-cache-load %t (%asm-cache-path %t) ()))
  (write (list (%f 2) (if (null? %g) 'miss (%g 2))))
  (newline))
```
---
    (152 152)

### an entry longer than one read round loads whole

The slurp reads in rounds of `%asm-cache-slurp-chunk`; a full round grows the
buffer and reads on. Shrinking the round to 64 bytes makes even a tiny entry
take several, and a hit under that setting is a hit on an 82KB entry under the
default.

```scheme
(do
  (def %e '(fn (_ x) (+ x 40)))
  (def %t (%asm-cache-text %e () #f))
  (compile-asm %e)
  (def %saved (%ac (lit %asm-cache-slurp-chunk)))
  (eval (lit (set! %asm-cache-slurp-chunk 64)) (module x/tool/asm-cache))
  (def %g (%asm-cache-load %t (%asm-cache-path %t) ()))
  (eval (list (lit set!) (lit %asm-cache-slurp-chunk) %saved) (module x/tool/asm-cache))
  (write (if (null? %g) 'miss (%g 2)))
  (newline))
```
---
    42

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

### the fvar table's layout is part of the key

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

The arithmetic sits on the third param because analyser mode's leading two are
object params, and arithmetic on one of those refuses (jit-fvar-mode.spec.md).
This case needs a body legal in both worlds, so that the two modes are told
apart by their key rather than by one of them failing to compile.

```scheme
(do
  (def %src '(fn (_ a b n) (+ n 1)))
  (def %fv (list (pair 'k 1)))
  (compile-asm %src %fv #t)
  (display ((compile-asm %src %fv #f) 0 0 41)))
```
---
    42

### an entry that is not one misses rather than answering

Anything at the path that is not this format — a truncated write, a file from
an older layout, junk — has to read as absent. The magic is checked before a
single byte is trusted.

```scheme
(do
  (import x/tool/asm-cache) (import x/sys/file)
  (def %junk-tmp (File temp "/tmp/x-asm-spec-junk-"))
  (File close (first %junk-tmp))
  (def %junk-at (rest %junk-tmp))
  (def %fd (%asm-cache-creat (Str8 append %junk-at ".asm")))
  (%asm-cache-put %fd "this is not a cache entry at all" 32)
  (write (%asm-cache-load "any key" %junk-at ()))
  (File unlink (Str8 append %junk-at ".asm"))
  (File unlink %junk-at)
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

## where the entries live

### X_ASM_CACHE_DIR names the directory, and /tmp is the default

Unset or empty, the entries live in /tmp, which every engine on the machine
shares. A process that keeps its compiles apart -- a gate that needs a cold
boot, a run that must leave other runs' entries alone -- names a directory of
its own. The variable is read on each compile, so an entry stored while it is
set is found in that directory and not in /tmp. The body carries this
process's id, so no other process has stored an entry for it.

```x
(do
  (def %dir-pcall (%ac (lit %asm-cache-pcall)))
  (def %dir-sym (fn (_ name) ((%ac (lit %asm-cache-dlsym)) (%ac (lit %asm-cache-lib)) name)))
  (def %dir-pid (Sys getpid))
  (def %dir-path (Str append "/tmp/jit-cache-spec-" ((%ac (lit %asm-cache-wts)) %dir-pid)))
  (%dir-pcall (%dir-sym "mkdir") %dir-path 448)
  (def %dir-e (list 'fn '(_ x) (list '+ 'x %dir-pid)))
  (def %dir-t (%asm-cache-text %dir-e () #f))
  (Sys setenv "X_ASM_CACHE_DIR" %dir-path)
  (def %dir-at (%asm-cache-path %dir-t))
  (compile-asm %dir-e)
  (def %dir-hit (%asm-cache-load %dir-t %dir-at ()))
  (Sys setenv "X_ASM_CACHE_DIR" "")
  (def %dir-empty (%asm-cache-path %dir-t))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (def %dir-home (%asm-cache-path %dir-t))
  (def %dir-miss (%asm-cache-load %dir-t %dir-home ()))
  (%dir-pcall (%dir-sym "unlink") (Str append %dir-at ".bin"))
  (%dir-pcall (%dir-sym "unlink") (Str append %dir-at ".asm"))
  (%dir-pcall (%dir-sym "rmdir") %dir-path)
  (write (list (Str8 match-at? (Str append %dir-path "/x-asm-") 0 %dir-at)
               (if (null? %dir-hit) 'miss (= (%dir-hit 0) %dir-pid))
               (str=? %dir-empty %dir-home)
               (Str8 match-at? "/tmp/x-asm-" 0 %dir-home)
               %dir-miss))
  (newline))
```
---
    (#t #t #t #t ())

## an entry is held in the heap

Every entry a process stores or loads is kept in the heap as well: the code
in an object whose payload is words, and its relocation sites as a table.
Nothing in a held entry is an address, so a state image carries it, and a
process booted from that image pours from what it holds.

### with its files gone, a second compile answers from the held entry

The directory is this case's own and the body carries this process's id. The
second compile finds no file, and stores none: the file loader still misses
after it.

```x
(do
  (def %held-pcall (%ac (lit %asm-cache-pcall)))
  (def %held-sym (fn (_ name) ((%ac (lit %asm-cache-dlsym)) (%ac (lit %asm-cache-lib)) name)))
  (def %held-pid (Sys getpid))
  (def %held-path (Str append "/tmp/jit-cache-held-" ((%ac (lit %asm-cache-wts)) %held-pid)))
  (%held-pcall (%held-sym "mkdir") %held-path 448)
  (def %held-e (list 'fn '(_ x) (list '- 'x %held-pid)))
  (def %held-t (%asm-cache-text %held-e () #f))
  (Sys setenv "X_ASM_CACHE_DIR" %held-path)
  (def %held-at (%asm-cache-path %held-t))
  (def %held-f (compile-asm %held-e))
  (%held-pcall (%held-sym "unlink") (Str append %held-at ".bin"))
  (%held-pcall (%held-sym "unlink") (Str append %held-at ".asm"))
  (def %held-g (compile-asm %held-e))
  (def %held-file (%asm-cache-load %held-t %held-at ()))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (def %held-rmdir (%held-pcall (%held-sym "rmdir") %held-path))
  (write (list (%held-f %held-pid) (%held-g %held-pid) (same? %held-f %held-g)
               %held-file %held-rmdir))
  (newline))
```
---
    (0 0 #f () 0)

### a held entry is its size, and a code object of whole words

```x
(do
  (def %held-entry ((%ac (lit %asm-cache-held-find)) %held-t (%ac (lit %asm-cache-held))))
  (def %held-size (first (rest %held-entry)))
  (def %held-words (%obj-ref (first (rest (rest %held-entry))) 0))
  (write (list (= %held-size %asm-last-size)
               (<= %held-size (* %word-size %held-words))
               (< (* %word-size %held-words) (+ %held-size %word-size))))
  (newline))
```
---
    (#t #t #t)

### a load patches its sites with the compiled patcher, or the x walk, the same

A compile leaves the process holding the compiled patcher, adopted only after
it agreed with the x walk. A load through it and a load through the walk
answer alike.

```x
(do
  (def %pt-e '(fn (_ x) (* x 5)))
  (def %pt-f (compile-asm %pt-e ()))
  (def %pt-t (%asm-cache-text %pt-e ()))
  (def %pt-cell (%ac (lit %asm-cache-patcher-cell)))
  (def %pt-native (first %pt-cell))
  (def %pt-g (%asm-cache-load %pt-t (%asm-cache-path %pt-t) ()))
  (%set-first! %pt-cell #f)
  (def %pt-h (%asm-cache-load %pt-t (%asm-cache-path %pt-t) ()))
  (%set-first! %pt-cell %pt-native)
  (write (list (if (null? %pt-native) 'none (if (eq? %pt-native #f) 'none 'compiled))
               (%pt-f 7) (%pt-g 7) (%pt-h 7)))
  (newline))
```
---
    ('compiled 35 35 35)

## groups: many entries in one file

A caller that compiles the same set of functions in every process groups them
under a key: `(compile asm-cache-group)` runs a thunk with its compiles noted
and keeps their entries in one file, which a later process loads into the heap
before the thunk runs. These cases use a directory of their own and bodies
carrying this process's id.

### a group keeps the entries it noted in one file, and a later run is served from it

The heap's entries are dropped and the per-entry files deleted, which is what
a fresh process with only the group file sees. Both compiles then answer from
the entries the group file loaded: neither is compiled or stored again, so the
per-entry files stay gone.

```x
(do
  (def %grp-door (prim-ref 'compile 'asm-cache-group))
  (def %grp-pcall (%ac (lit %asm-cache-pcall)))
  (def %grp-sym (fn (_ name) ((%ac (lit %asm-cache-dlsym)) (%ac (lit %asm-cache-lib)) name)))
  (def %grp-pid (Sys getpid))
  (def %grp-path (Str append "/tmp/jit-cache-group-" ((%ac (lit %asm-cache-wts)) %grp-pid)))
  (%grp-pcall (%grp-sym "mkdir") %grp-path 448)
  (Sys setenv "X_ASM_CACHE_DIR" %grp-path)
  (def %grp-a (list 'fn '(_ x) (list '+ 'x %grp-pid)))
  (def %grp-b (list 'fn '(_ x) (list '* 'x %grp-pid)))
  (def %grp-key (Str append "spec-" ((%ac (lit %asm-cache-wts)) %grp-pid)))
  (def %grp-run (fn (_) (%grp-door %grp-key (fn (_) (list (compile-asm %grp-a) (compile-asm %grp-b))))))
  (%grp-run)
  (def %grp-file (Str append %grp-path "/" "x-asmg-"))
  (def %grp-gpath ((%ac (lit %asm-cache-group-path)) %grp-key))
  (def %grp-unlink-entry (fn (_ e)
    (def at (%asm-cache-path (%asm-cache-text e () #f)))
    (%grp-pcall (%grp-sym "unlink") (Str append at ".bin"))
    (%grp-pcall (%grp-sym "unlink") (Str append at ".asm"))))
  (%grp-unlink-entry %grp-a)
  (%grp-unlink-entry %grp-b)
  (eval '(set! %asm-cache-held ()) (module x/tool/asm-cache))
  (def %grp-fs (%grp-run))
  (def %grp-a-file (%asm-cache-load (%asm-cache-text %grp-a () #f) (%asm-cache-path (%asm-cache-text %grp-a () #f)) ()))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (write (list (= ((first %grp-fs) 2) (+ 2 %grp-pid)) (= ((first (rest %grp-fs)) 2) (* 2 %grp-pid))
               (Str8 match-at? %grp-file 0 %grp-gpath)
               %grp-a-file))
  (newline))
```
---
    (#t #t #t ())

### a group file from other entries misses, and is written again

A group file whose entries no compile asks for is loaded, held and passed
over: the compile misses, is compiled and stored, and the group is rewritten
with the entry it did note.

```x
(do
  (Sys setenv "X_ASM_CACHE_DIR" %grp-path)
  (def %grp-c (list 'fn '(_ x) (list '- 'x %grp-pid)))
  (def %grp-f (%grp-door %grp-key (fn (_) (compile-asm %grp-c))))
  (eval '(set! %asm-cache-held ()) (module x/tool/asm-cache))
  (def %grp-texts ((%ac (lit %asm-cache-group-load!)) %grp-gpath))
  (def %grp-c-at (%asm-cache-path (%asm-cache-text %grp-c () #f)))
  (%grp-pcall (%grp-sym "unlink") (Str append %grp-c-at ".bin"))
  (%grp-pcall (%grp-sym "unlink") (Str append %grp-c-at ".asm"))
  (%grp-pcall (%grp-sym "unlink") %grp-gpath)
  (def %grp-rmdir (%grp-pcall (%grp-sym "rmdir") %grp-path))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (write (list (%grp-f %grp-pid) (List length %grp-texts)
               (str=? (first %grp-texts) (%asm-cache-text %grp-c () #f)) %grp-rmdir))
  (newline))
```
---
    (0 1 #t 0)

### a group met again while its entries are held reads no file

The same group run twice in one heap: the second run finds its entries still
held and neither reads nor writes the group file, so a file deleted between
the runs stays deleted.  With the held entries dropped, as in a fresh process,
the group is read from its file again -- there is none -- and written anew.

```x
(do
  (Sys setenv "X_ASM_CACHE_DIR" %grp-path)
  (%grp-pcall (%grp-sym "mkdir") %grp-path 448)
  (def %grp-d (list 'fn '(_ x) (list '+ 'x (+ 1 %grp-pid))))
  (def %grp-again (fn (_) (%grp-door "spec-again" (fn (_) (compile-asm %grp-d)))))
  (def %grp-apath ((%ac (lit %asm-cache-group-path)) "spec-again"))
  (def %grp-there? (fn (_) (= 0 (%grp-pcall (%grp-sym "access") %grp-apath 0))))
  (%grp-again)
  (def %grp-made (%grp-there?))
  (%grp-pcall (%grp-sym "unlink") %grp-apath)
  (def %grp-f2 (%grp-again))
  (def %grp-held-run (%grp-there?))
  (eval '(set! %asm-cache-held ()) (module x/tool/asm-cache))
  (%grp-again)
  (def %grp-fresh-run (%grp-there?))
  (def %grp-d-at (%asm-cache-path (%asm-cache-text %grp-d () #f)))
  (%grp-pcall (%grp-sym "unlink") (Str append %grp-d-at ".bin"))
  (%grp-pcall (%grp-sym "unlink") (Str append %grp-d-at ".asm"))
  (%grp-pcall (%grp-sym "unlink") %grp-apath)
  (def %grp-rmdir2 (%grp-pcall (%grp-sym "rmdir") %grp-path))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (write (list %grp-made (= (%grp-f2 2) (+ 3 %grp-pid)) %grp-held-run %grp-fresh-run %grp-rmdir2))
  (newline))
```
---
    (#t #t #f #t 0)

### a raise inside the thunk closes the group and reaches the caller

```x
(do
  (def %grp-r (guard (e (lit raised)) (%grp-door "spec-raise" (fn (_) (Err raise 'value "inside" ())))))
  (write (list %grp-r (first (%ac (lit %asm-cache-group-open)))))
  (newline))
```
---
    ('raised ())

### groups do not nest: an inner group runs in the outer one

```x
(do
  (def %grp-n (%grp-door "spec-outer" (fn (_) (%grp-door "spec-inner" (fn (_) (lit inner))))))
  (%grp-pcall (%grp-sym "unlink") ((%ac (lit %asm-cache-group-path)) "spec-outer"))
  (write %grp-n)
  (newline))
```
---
    'inner
