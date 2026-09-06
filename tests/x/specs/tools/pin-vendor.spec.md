# @lib ../tests/x/lib/pin.x

# @weight 7
# pin: project-wide vendoring and the manifest-driven front door

One of six files that were tools/pin.spec.md, one 25-second job, cut
along the fixture chains they share (tests/x/lib/pin.x makes the trees
every file needs).  The manifest (pin.xon) is DATA: forms are read with the
ordinary reader and interpreted against a closed vocabulary, never
evaluated; the wrapper probe and end-to-end arming are smoked by
tools/check/pin-smoke.sh (make check-pin).

## fixture

### the shared trees are there

```x
(display (%pin-fixture!))
```
---
    ready

## pin: project-wide vendoring and audit (Pin vendor-project / audit)

A "project" is a source tree that imports library modules.  These reuse
the fixture tree armed above: acme/one (and its transitive closure) is
what a project importing acme/one must vendor.

### a project source tree that imports acme/one

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/proj"))
  (File write-all "build/pin-spec/proj/app.x" "(import acme/one)\n(display \"hi\")\n")
  (display "ready"))
```
---
    ready

### vendor-project copies the union closure of every project import

```x
(write (Pin vendor-project "build/pin-spec/pout" "build/pin-spec/proj"))
```
---
    ("acme/one.x" "acme/two.x" "acme/one-extra.x" "acme/four.x" "acme/three.x")

### the deferred-body import is vendored too (deep closure member)

```x
(display (File exists? "build/pin-spec/pout/acme/three.x"))
```
---
    #t

### verify passes on the vendored project overlay

```x
(display (Pin verify "build/pin-spec/pout"))
```
---
    5

### audit of a complete overlay reports nothing missing

```x
(display (null? (Pin audit "build/pin-spec/pout" "build/pin-spec/proj")))
```
---
    #t

### %pin-audit-missing lists the rels absent from the overlay

```x
(write (Pin %pin-audit-missing "build/pin-spec/nowhere" (list "acme/one.x" "acme/two.x")))
```
---
    ("acme/one.x" "acme/two.x")

### audit of a half-pin names every import that falls through to the platform

```x
(do
  (Pin vendor "build/pin-spec/partial" 'acme/two)
  (Pin audit "build/pin-spec/partial" "build/pin-spec/proj")
  ())
```
---
```output
pin: audit -- 4 import(s) fall through to the platform (absent from build/pin-spec/partial):
acme/one.x
acme/one-extra.x
acme/four.x
acme/three.x
```

### an argument-less (import) in a PROJECT source is a loud error, not a crash

The project scan reads arbitrary user sources, where a half-typed
`(import)` is an ordinary typo rather than a library bug.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/badproj"))
  (File write-all "build/pin-spec/badproj/app.x" "(import)\n")
  (display (throws? (fn (_) (Pin audit "build/pin-spec/pout" "build/pin-spec/badproj")))))
```
---
    #t

### vendoring an empty closure into a fresh directory creates it

A project importing only boot-floor modules has an empty closure; dest
must still exist for the lockfile to land.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/floorproj"))
  (File write-all "build/pin-spec/floorproj/app.x" "(import x/core/list)\n")
  (write (Pin vendor-project "build/pin-spec/emptyout" "build/pin-spec/floorproj"))
  (display " ")
  (display (Pin verify "build/pin-spec/emptyout")))
```
---
    () 0

### the source scan recurses into subdirectories

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/proj/sub"))
  (File write-all "build/pin-spec/proj/sub/deep.x" "(import acme/four)\n")
  (display (Pin %pin-length (Pin %pin-x-files "build/pin-spec/proj"))))
```
---
    2

## pin: the manifest-driven front door (Pin sync / check / boot)

The older pair makes the caller carry paths the manifest already states,
and hand-vendoring module by module forces a project to name its
libraries before the code that imports them exists. These read pin.xon
and work from the code that is actually there.

### sync derives the overlay from the project's own imports

```x
(do
  (Pin %pin-mkdirs "build/pin-spec/fd/src")
  (Pin %pin-mkdirs "build/pin-spec/fd/dep")
  (File write-all "build/pin-spec/fd/pin.xon" "(root \"dep\")\n(src \"src\")\n")
  (File write-all "build/pin-spec/fd/src/app.x" "(import acme/three)\n")
  ; build/ survives between runs, and the later-import spec below adds a
  ; second source file AND vendors what it imports.  Vendor never deletes
  ; (a dropped file is the project's to remove), so without clearing both
  ; sides the NEXT run starts stage one with the second import already
  ; present and vendored, and the two stages stop being distinguishable.
  (guard (_ ()) (File unlink "build/pin-spec/fd/src/more.x"))
  (guard (_ ()) (File unlink "build/pin-spec/fd/dep/acme/four.x"))
  ; The lock too: the platform-carry-through stage below writes a lock
  ; whose boot row names a path this manifest never states, and relies on
  ; the sync after it to overwrite. A run cut between the two -- the batch
  ; timeout lands there under load -- strands that lock, and since build/
  ; survives between runs, every later run's re-sync check then reports
  ; "boot row but no (boot ...) path" until someone clears it by hand.
  (guard (_ ()) (File unlink "build/pin-spec/fd/dep.lock.xon"))
  (write (Pin sync "build/pin-spec/fd")))
```
---
    ("acme/three.x")

### the lock is named for the overlay, beside it, not inside it

```x
(display (list (File exists? "build/pin-spec/fd/dep.lock.xon")
               (File exists? "build/pin-spec/fd/dep/dep.lock.xon")))
```
---
    (#t #f)

### check is clean once synced

```x
(write (Pin check "build/pin-spec/fd"))
```
---
    ()

### a later import falls through until the next sync

```x
(do
  (File write-all "build/pin-spec/fd/src/more.x" "(import acme/four)\n")
  (write (Pin check "build/pin-spec/fd")))
```
---
    ("acme/four.x")

### re-syncing picks it up

```x
(do
  (Pin sync "build/pin-spec/fd")
  (write (Pin check "build/pin-spec/fd")))
```
---
    ()

### a sync must not unpin the language underneath it

The platform half of the lock -- release, isa, boot -- is written by the
boot verb; a sync re-derives the overlay and must carry it through
untouched, or growing an import would silently drop the language pin.

```x
(do
  (File write-all "build/pin-spec/fd/dep.lock.xon"
    (Str8 append "(release \"v9.9.9\")\n(isa \"sha256:abc\")\n"
      (Str8 append "(boot \"he.x\" \"sha256:def\")\n"
        (Str8 append "(file \"acme/three.x\" \""
          (Str8 append (Pin %pin-digest "build/pin-spec/fd/dep/acme/three.x") "\")\n")))))
  (Pin sync "build/pin-spec/fd")
  (display (Pin %pin-length (Pin %pin-platform-forms (Pin %pin-lock-forms "build/pin-spec/fd/dep")))))
```
---
    3

### the manifest must state what a verb needs

```x
(do
  (Pin %pin-mkdirs "build/pin-spec/nosrc")
  (File write-all "build/pin-spec/nosrc/pin.xon" "(root \"dep\")\n")
  (display (throws? (fn (_) (Pin sync "build/pin-spec/nosrc")))))
```
---
    #t

### the lock records the manifest's spelling, never a resolved path

A lockfile is committed. An absolute path in it is meaningless on
anyone else's machine and leaks wherever the author kept the project,
so the seed records what the manifest said -- even when sync was handed
an absolute project directory, as it is here.

```x
(display (Str8 includes? "(seed \"project:src\"" (File read-all "build/pin-spec/fd/dep.lock.xon")))
```
---
    #t
