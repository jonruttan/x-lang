# Relative includes and the import search path

`include` / `include-once` / `require-once` / `import` resolve a path that
begins with `./` or `../` against the directory of the file currently loading.
`import` resolves a module name against a search path that is **conservative**
(only `lib` by default) and **configurable** (add roots with `import-path!`).
Plain and absolute paths keep their cwd-relative meaning, so existing
call-sites are unaffected.

These tests stay self-contained: they exercise the resolution logic and use
files already under `lib/`, so nothing depends on paths outside the repo.

## Path resolution

### ./ resolves against the including file's directory

```scheme
(str=? (%resolve-include-path "./cell.x" "app/maze") "app/maze/cell.x")
```
---
    #t

### ../ is kept for the OS to collapse

```scheme
(str=? (%resolve-include-path "../shared/x.x" "app/maze") "app/maze/../shared/x.x")
```
---
    #t

### a plain path is unchanged (cwd-relative, as before)

```scheme
(str=? (%resolve-include-path "lib/x/type/list.x" "app/maze") "lib/x/type/list.x")
```
---
    #t

### an absolute path is unchanged

```scheme
(str=? (%resolve-include-path "/etc/hosts" "app/maze") "/etc/hosts")
```
---
    #t

### a directory is everything before the last slash

```scheme
(list (str=? (%path-dir "app/maze/cell.x") "app/maze") (str=? (%path-dir "cell.x") "."))
```
---
    (#t #t)

### the top-level current directory is "." after boot

```scheme
(str=? (%include-curdir) ".")
```
---
    #t

### the dir-stack feeds the current directory into resolution

```scheme
(%include-dir-push! "lib/x/core")
(let ((%r (%resolve-include-path "./list.x" (%include-curdir))))
  (%include-dir-pop!)
  (str=? %r "lib/x/core/list.x"))
```
---
    #t

## Load transparency

### a closure defined in a loaded file sees no loader bindings

A loaded file's forms are top-level forms: `x_eval_load` strips the includer's
lexical frames (the leading FRAME run) for the duration of the load, so each
form evaluates against -- and each closure captures -- the true top-level
chain. Without this, the loader wrappers' formals (`path`, `name`, ...) are
captured by every closure a module defines and shadow the global env inside
loaded code forever.

```scheme
(do
  (include "tests/x/lib/loader-frame-fixture.x")
  (%loader-frame-probe))
```
---
    ('unbound 'unbound 'unbound 'unbound)

## Import search path

### conservative: the only default root is lib

```scheme
(str=? (%module-resolve 'x/num/random) "lib/x/num/random.x")
```
---
    #t

### configurable: import-path! adds a root, falling back to the lib default

```scheme
(import-path! "lib/x")
(list (str=? (%module-resolve 'core/list) "lib/x/core/list.x")
      (str=? (%module-resolve 'x/num/random) "lib/x/num/random.x"))
```
---
    (#t #t)

## Versioned module lines (GH #214)

A module may exist in several versions at once as sibling files: `grid.x`
(version 0 — every unversioned module), `grid@1.3.x`, `grid@1.3.1.x`. The
version is an ARGUMENT, never part of the name — every version file provides
the base name, and the registry keys it. A fixture tree is built under
build/ivspec/ and armed as an import root.

### fixture tree

```scheme
(do
  (import x/sys/file)
  (guard (_ ()) (File mkdir "build"))
  (guard (_ ()) (File mkdir "build/ivspec"))
  (guard (_ ()) (File mkdir "build/ivspec/vmod"))
  (File spit "build/ivspec/vmod/thing.x"
    "(def %thing-v \"0\")\n(provide vmod/thing %thing-v)\n")
  (File spit "build/ivspec/vmod/thing@1.3.x"
    "(def %thing-v \"1.3\")\n(provide vmod/thing %thing-v)\n")
  (File spit "build/ivspec/vmod/thing@1.3.1.x"
    "(def %thing-v \"1.3.1\")\n(provide vmod/thing %thing-v)\n")
  (File spit "build/ivspec/vmod/thing@2.x"
    "(def %thing-v \"2\")\n(provide vmod/thing %thing-v)\n")
  (import-path! "build/ivspec")
  (display "ready"))
```
---
    ready

### a prefix constraint selects the newest satisfying file — the bug-fix path

`"1.3.*"` reaches 1.3.1 the moment the patch file lands; no import site
changes. This is how fixes flow: resolution, not mutation.

```scheme
(do
  (import-version-once vmod/thing "1.3.*")
  (display %thing-v))
```
---
    1.3.1

### a satisfied re-request is a no-op; an unsatisfiable one is a loud error

The loaded 1.3.1 satisfies `"^1"` (no-op). It does not satisfy `"2"`: a
named version is a contract, so import's silent first-wins would be the
wrong answer — the mismatch errs, naming both sides.

```scheme
(do
  (import-version-once vmod/thing "^1")
  (display (guard (_ #t) (do (import-version-once vmod/thing "2") #f))))
```
---
    #t

### a bare import after a versioned load no-ops — import's own contract

```scheme
(do
  (import vmod/thing)
  (display %thing-v))
```
---
    1.3.1

### the spec must be a string literal

`3.1` the float is `3.10` the float; only a string can spell semver.

```scheme
(display (guard (_ #t) (do (import-version-once vmod/thing 1.3) #f)))
```
---
    #t

### exact means exact, not newest-within

Fresh name so the registry has no entry: `"1.3"` takes 1.3, not the 1.3.1
sitting beside it.

```scheme
(do
  (File spit "build/ivspec/vmod/exact.x"
    "(def %exact-v \"0\")\n(provide vmod/exact %exact-v)\n")
  (File spit "build/ivspec/vmod/exact@1.3.x"
    "(def %exact-v \"1.3\")\n(provide vmod/exact %exact-v)\n")
  (File spit "build/ivspec/vmod/exact@1.3.1.x"
    "(def %exact-v \"1.3.1\")\n(provide vmod/exact %exact-v)\n")
  (import-version-once vmod/exact "1.3")
  (display %exact-v))
```
---
    1.3

### star takes the newest overall; the bare file is version 0

```scheme
(do
  (File spit "build/ivspec/vmod/star.x"
    "(def %star-v \"0\")\n(provide vmod/star %star-v)\n")
  (File spit "build/ivspec/vmod/star@0.9.x"
    "(def %star-v \"0.9\")\n(provide vmod/star %star-v)\n")
  (import-version-once vmod/star "*")
  (display %star-v))
```
---
    0.9

### a versioned request for a bare-loaded module is a loud error

The bare load's version is unknowable, so no spec can be satisfied.

```scheme
(do
  (File spit "build/ivspec/vmod/plain.x"
    "(def %plain-v \"0\")\n(provide vmod/plain %plain-v)\n")
  (import vmod/plain)
  (display (guard (_ #t) (do (import-version-once vmod/plain "^1") #f))))
```
---
    #t

### nothing satisfies: the error names module and spec

```scheme
(display (guard (_ #t) (do (import-version-once vmod/thing "9.9") #f)))
```
---
    #t

## guard unwinds include state (#242)

A raise inside `(include ...)` caught by a guard OUTSIDE the include used
to leave the include's fd open and its filein/buffer/line stack entries
pushed: top-level reads then continued from the dead file's remaining
bytes, and every caught raise leaked one fd. The guard's recovery now
unwinds the three stacks to its snapshot and closes the cut-away fds.

### a caught mid-include raise does not leak the file's trailing forms

```scheme
(do (def %gi1 (guard (e 'caught) (include "tests/x/lib/guard-include-fixture.x")))
    (list %gi1 %guard-include-marker (guard (e 'unbound) %guard-include-leaked)))
```
---
    ('caught 'loaded 'unbound)

### the trailing def stays unread on the next top-level read too

```scheme
(guard (e 'still-unbound) %guard-include-leaked)
```
---
    'still-unbound

### three hundred caught raises leak no fds

```scheme
(do (def %gi-loop ())
    (set! %gi-loop (fn (_ n)
      (if (eq? n 0) 'done
        (do (guard (e ()) (include "tests/x/lib/guard-include-fixture.x"))
            (%gi-loop (- n 1))))))
    (%gi-loop 300)
    (include "tests/x/lib/guard-include-ok.x")
    %guard-include-ok)
```
---
    'ok

### a guard inside an included file keeps that file's frames

```scheme
(do (include "tests/x/lib/guard-include-inner.x")
    (list %gi-inner %gi-inner-after))
```
---
    ('inner-caught 'after)
