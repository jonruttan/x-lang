# @lib ../tests/x/lib/pin.x

# @weight 5
# pin: lockfile provenance

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

## pin: lockfile provenance (GH #147)

One overlay legitimately holds several vendors, so the file list alone
cannot say which vendor put a file there.  Each vendor records its claim
as `(seed "NAME" "rel" ...)`; re-vendoring replaces that seed's claim.

### vendor records the seed's claim

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/lib0/prov"))
  (File write-all "build/pin-spec/lib0/prov/a.x" "(import prov/dep)\n(provide prov/a)\n")
  (File write-all "build/pin-spec/lib0/prov/dep.x" "(provide prov/dep)\n")
  (Pin vendor "build/pin-spec/prov" 'prov/a)
  (display (Str8 includes? "(seed \"prov/a\"" (File read-all "build/pin-spec/prov.lock.xon"))))
```
---
    #t

### a dependency dropped upstream leaves the lock on re-vendor

Previously it stayed in both tree and lock, still shadowing the
platform, with verify calling the pair clean because both went stale
together.

```x
(do
  (File write-all "build/pin-spec/lib0/prov/a.x" "(provide prov/a)\n")
  (write (Pin vendor "build/pin-spec/prov" 'prov/a)))
```
---
```output
pin: 1 file(s) no longer in the closure, still in build/pin-spec/prov (delete them; verify flags them as unlisted):
prov/dep.x
("prov/a.x")
```

### the orphan is then unlisted, so verify refuses it

```x
(display (throws? (fn (_) (Pin verify "build/pin-spec/prov"))))
```
---
    #t

### removing the orphan restores verification

```x
(do
  (File unlink "build/pin-spec/prov/prov/dep.x")
  (display (Pin verify "build/pin-spec/prov")))
```
---
    1

### distinct seeds still merge into one overlay

The documented workflow: repeated vendors into one overlay accumulate.
A separate overlay from the drop cycle above, so the counts here do not
depend on which spec ran last (`build/` survives between runs).

```x
(do
  (File write-all "build/pin-spec/lib0/prov/m1.x" "(provide prov/m1)\n")
  (File write-all "build/pin-spec/lib0/prov/m2.x" "(provide prov/m2)\n")
  (Pin vendor "build/pin-spec/prov2" 'prov/m1)
  (Pin vendor "build/pin-spec/prov2" 'prov/m2)
  (display (Pin verify "build/pin-spec/prov2")))
```
---
    2

### re-vendoring one seed leaves the other's files alone

```x
(do
  (Pin vendor "build/pin-spec/prov2" 'prov/m1)
  (display (Pin verify "build/pin-spec/prov2")))
```
---
    2

### entries predating provenance are kept, never silently dropped

A lockfile written before seeds existed has unattributed entries; a new
vendor into that overlay must not evict them.

```x
(do
  (Pin %pin-mkdirs "build/pin-spec/legacy/old")
  (File write-all "build/pin-spec/legacy/old/keep.x" "(def %keep 1)\n")
  (File write-all "build/pin-spec/legacy.lock.xon"
    (Str8 append "(file \"old/keep.x\" \""
      (Str8 append (Pin %pin-digest "build/pin-spec/legacy/old/keep.x") "\")\n")))
  (Pin vendor "build/pin-spec/legacy" 'prov/m1)
  (display (Pin verify "build/pin-spec/legacy")))
```
---
    2
