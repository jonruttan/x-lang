# @lib ../tests/x/lib/pin.x

# @weight 2
# pin: the vendor closure walk

One of six files that were tools/pin.spec.md, one 25-second job, cut
along the fixture chains they share (tests/x/lib/pin.x makes the trees
every file needs).  The manifest (pin.xon) is DATA: forms are read with the
ordinary reader and interpreted against a closed vocabulary, never
evaluated; the wrapper probe and end-to-end arming are smoked by
tools/check/pin-smoke.sh (make check-pin).

## pin: the vendor closure walk (Pin)

A fixture module tree is built under build/pin-spec/ and armed as an
import root; the walk is purely static (fixture files are read, never
loaded).  acme/one imports acme/two (which imports the boot-floor
x/core/list), pulls a ./-relative sibling (which imports acme/four),
and hides an import of acme/three inside a deferred fn body.

### fixture tree

```x
(display (%pin-fixture!))
```
---
    ready

### the closure: transitive imports, ./ siblings, deferred-body imports; the boot floor excluded

```x
(write (Pin closure 'acme/one))
```
---
    ("acme/one.x" "acme/two.x" "acme/one-extra.x" "acme/four.x" "acme/three.x")

### vendor copies the closure into the overlay layout

```x
(do
  (Pin vendor "build/pin-spec/out" 'acme/one)
  (display (File exists? "build/pin-spec/out/acme/one-extra.x")))
```
---
    #t

### the vendored copy is byte-identical to its source

```x
(display (str=? (File read-all "build/pin-spec/out/acme/two.x")
                (File read-all "build/pin-spec/lib0/acme/two.x")))
```
---
    #t

### the boot floor is never copied

```x
(display (File exists? "build/pin-spec/out/x/core/list.x"))
```
---
    #f

### a boot-floor seed is refused (the pin boundary)

```x
(display (throws? (fn (_) (Pin vendor "build/pin-spec/out" 'x/core/list))))
```
---
    #t

### a computed include path in the closure is a loud error

```x
(display (throws? (fn (_) (Pin closure 'acme/bad))))
```
---
    #t

### an argument-less (import) in scanned source is a loud error, not a crash

`(first (rest form))` on a form with no argument derefs nil, so the
argument check has to precede the shape check that used to reach for it.

```x
(do
  (File write-all "build/pin-spec/lib0/acme/noimp.x" "(import)\n(provide acme/noimp)\n")
  (display (throws? (fn (_) (Pin closure 'acme/noimp)))))
```
---
    #t

### an argument-less (include-once) in scanned source is a loud error, not a crash

```x
(do
  (File write-all "build/pin-spec/lib0/acme/noinc.x" "(include-once)\n(provide acme/noinc)\n")
  (display (throws? (fn (_) (Pin closure 'acme/noinc)))))
```
---
    #t
