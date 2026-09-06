# @lib ../tests/x/lib/pin.x

# @weight 7
# pin: the lockfile

One of six files that were tools/pin.spec.md, one 25-second job, cut
along the fixture chains they share (tests/x/lib/pin.x makes the trees
every file needs).  The manifest (pin.xon) is DATA: forms are read with the
ordinary reader and interpreted against a closed vocabulary, never
evaluated; the wrapper probe and end-to-end arming are smoked by
tools/check/pin-smoke.sh (make check-pin).

## fixture

### the shared trees are there, and acme/one is vendored to out

The lockfile cases read what the closure walk vendors; the same call
(tools/pin-closure.spec.md) makes it here so this file needs no other.

```x
(do (%pin-fixture!) (Pin vendor "build/pin-spec/out" 'acme/one) (display "ready"))
```
---
    ready

## pin: the lockfile (Pin verify)

### vendor writes the lockfile

```x
(display (File exists? "build/pin-spec/out.lock.xon"))
```
---
    #t

### verify passes on a fresh vendor, counting the files

```x
(display (Pin verify "build/pin-spec/out"))
```
---
    5

### a modified vendored file fails verify

```x
(do
  (File write-all "build/pin-spec/out/acme/two.x" "(tampered)\n")
  (display (throws? (fn (_) (Pin verify "build/pin-spec/out")))))
```
---
    #t

### re-vendoring restores verification

```x
(do
  (Pin vendor "build/pin-spec/out" 'acme/one)
  (display (Pin verify "build/pin-spec/out")))
```
---
    5

### an unlisted file in the overlay fails verify (a rogue shadow)

```x
(do
  (File write-all "build/pin-spec/out/acme/rogue.x" "(evil)\n")
  (def %pin-spec-r (throws? (fn (_) (Pin verify "build/pin-spec/out"))))
  (File unlink "build/pin-spec/out/acme/rogue.x")
  (display %pin-spec-r))
```
---
    #t

### a ./.. include normalises, so the lock key matches the tree walk

An overlay rel is a lockfile KEY and a copy target, not just something
to open, so `..` has to collapse here — `acme/../shared.x` and the tree
walk's `shared.x` name one file and never compared equal.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/lib0/up"))
  (File write-all "build/pin-spec/lib0/up/mod.x"
    "(include-once \"./../up-shared.x\")\n(provide up/mod)\n")
  (File write-all "build/pin-spec/lib0/up-shared.x" "(def %up-shared 1)\n")
  (write (Pin vendor "build/pin-spec/upout" 'up/mod))
  (display " verify=")
  (display (Pin verify "build/pin-spec/upout")))
```
---
    ("up/mod.x" "up-shared.x") verify=2

### an include climbing out of the overlay is a loud error

Enough `..` and the copy target resolves outside dest entirely — neither
absolute nor root-relative, so the other guards miss it.

```x
(do
  (File write-all "build/pin-spec/lib0/acme/escape.x"
    "(include-once \"./../../escapee.x\")\n(provide acme/escape)\n")
  (display (throws? (fn (_) (Pin closure 'acme/escape)))))
```
---
    #t

### a garbage lockfile is a loud error

```x
(do
  (Pin %pin-mkdirs "build/pin-spec/out2")
  (File write-all "build/pin-spec/out2.lock.xon" "(evil)\n")
  (display (throws? (fn (_) (Pin verify "build/pin-spec/out2")))))
```
---
    #t
