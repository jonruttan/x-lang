# @lib ../tests/x/lib/pin.x

# @weight 4
# pin: versioned imports, their observability, init, overlays, and own modules

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

## pin: versioned imports vendor the chosen file (GH #214)

### a constraint import is resolved at sync time and vendored at its versioned rel

The scanner routes (import-version-once NAME "SPEC") through the boot
layer's own resolver, so the overlay receives the concrete file the
constraint selects -- here the newest 1.3.*.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/vproj"))
  (File write-all "build/pin-spec/vproj/app.x" "(import-version-once acme/vd \"1.3.*\")\n")
  (write (Pin vendor-project "build/pin-spec/vout" "build/pin-spec/vproj")))
```
---
    ("acme/vd@1.3.1.x")

### a computed version spec is a loud error, like every computed argument

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/vproj2"))
  (File write-all "build/pin-spec/vproj2/app.x" "(import-version-once acme/vd (spec))\n")
  (display (throws? (fn (_) (Pin vendor-project "build/pin-spec/vout2" "build/pin-spec/vproj2")))))
```
---
    #t

## pin: version observability (Pin resolve / unused)

### resolve is the dry run of a versioned import

Same fixture as the vendoring section: vd.x, vd@1.3.x, vd@1.3.1.x under
build/pin-spec/vfix. Exact takes the named file; the prefix takes the
newest satisfying -- without loading either.

```x
(display (list (Str8 ends? "vd@1.3.x" (Pin resolve 'acme/vd "1.3"))
               (Str8 ends? "vd@1.3.1.x" (Pin resolve 'acme/vd "1.3.*"))))
```
---
    (#t #t)

### unused lists exactly what nothing selects -- the safe-removal answer

The project imports "1.3.*" (selects 1.3.1). Unselected: the bare vd.x
(no bare import anywhere) and the shadowed vd@1.3.x. Removal of either is
provably resolution-neutral; the selected 1.3.1 is not listed.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/uproj"))
  ; build/ survives between runs and the next spec adds bare.x, which
  ; would protect vd.x here -- clear it so both stages stay distinct.
  (guard (_ ()) (File unlink "build/pin-spec/uproj/bare.x"))
  (File write-all "build/pin-spec/uproj/app.x" "(import-version-once acme/vd \"1.3.*\")\n")
  (write (List map (fn (_ p) (Path basename p)) (Pin unused "build/pin-spec/uproj"))))
```
---
    ("vd.x" "vd@1.3.x")

### a bare import protects the bare file

```x
(do
  (File write-all "build/pin-spec/uproj/bare.x" "(import acme/vd)\n")
  (write (List map (fn (_ p) (Path basename p)) (Pin unused "build/pin-spec/uproj"))))
```
---
    ("vd@1.3.x")

## pin: the starter manifest (Pin init)

### init writes a manifest the loader accepts, and returns its path

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/initproj"))
  ; build/ survives between runs and init refuses to overwrite -- clear
  ; the prior run's manifest so this stage is the same on every run.
  (guard (_ ()) (File unlink "build/pin-spec/initproj/pin.xon"))
  (Pin init "build/pin-spec/initproj")
  (display (null? (Pin %pin-interpret
                    (Pin %pin-forms (File read-all "build/pin-spec/initproj/pin.xon"))
                    "build/pin-spec/initproj"))))
```
---
    #f

### init refuses to overwrite

```x
(display (throws? (fn (_) (Pin init "build/pin-spec/initproj"))))
```
---
    #t

### the entry symbol picks the boot line's dialect

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/initxe"))
  (guard (_ ()) (File unlink "build/pin-spec/initxe/pin.xon"))
  (Pin init "build/pin-spec/initxe" 'xe)
  (display (Str8 includes? "(boot \"boot/xe.x\")"
                 (File read-all "build/pin-spec/initxe/pin.xon"))))
```
---
    #t

### the manifest init writes drives the other verbs

```x
(do
  (File write-all "build/pin-spec/initproj/app.x" "(import acme/two)\n")
  (write (Pin sync "build/pin-spec/initproj")))
```
---
    ("acme/two.x")

### the no-manifest error names the way out

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/noman"))
  (display (throws? (fn (_) (Pin sync "build/pin-spec/noman")))))
```
---
    #t

## pin: a declared-but-empty overlay is livable (GH #217)

Git cannot carry an empty directory, so surviving a clone needs
deps/.gitkeep -- and verify used to reject the placeholder as tampering.
The two requirements were jointly unsatisfiable. Dotfiles are outside
the module layout, so outside the threat: no module name resolves to
one.

### the placeholder passes check; an unlisted module file still fails

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/empty"))
  (guard (_ ()) (File mkdir "build/pin-spec/empty/deps"))
  (guard (_ ()) (File unlink "build/pin-spec/empty/deps/rogue.x"))
  (File write-all "build/pin-spec/empty/pin.xon" "(root \"deps\")\n(src \"src\")\n")
  (guard (_ ()) (File mkdir "build/pin-spec/empty/src"))
  (File write-all "build/pin-spec/empty/deps/.gitkeep" "")
  (File write-all "build/pin-spec/empty/deps.lock.xon" "(release \"v9.9.9\")\n")
  (write (Pin check "build/pin-spec/empty")))
```
---
    ()

### the skip is dotfiles only -- a rogue module file is still tampering

```x
(do
  (File write-all "build/pin-spec/empty/deps/rogue.x" "(evil)\n")
  (display (throws? (fn (_) (Pin check "build/pin-spec/empty")))))
```
---
    #t

## pin: sync never vendors the project's own modules (#223)

A manifest may list the project itself as a root -- its modules are
already in the repo, versioned; that is what the root declares.  Sync
arms those roots for its scan (so the closure walk resolves them even
unarmed), walks their files for imports (their PLATFORM deps must
land), and vendors only what resolves to the platform.

### own modules are walked but not vendored; their platform deps land

```x
(do
  (Pin %pin-mkdirs "build/pin-spec/own/src")
  (Pin %pin-mkdirs "build/pin-spec/own/ownmod")
  (Pin %pin-mkdirs "build/pin-spec/own/dep")
  (File write-all "build/pin-spec/own/pin.xon"
    "(root \"dep\")\n(root \".\")\n(src \"src\")\n")
  (File write-all "build/pin-spec/own/src/app.x"
    "(import acme/three)\n(import ownmod/util)\n")
  (File write-all "build/pin-spec/own/ownmod/util.x"
    "(import acme/four)\n(provide ownmod/util)\n")
  (write (Pin sync "build/pin-spec/own")))
```
---
    ("acme/three.x" "acme/four.x")

### the project's own module is NOT in the overlay

```x
(display (File exists? "build/pin-spec/own/dep/ownmod/util.x"))
```
---
    #f

### re-sync is stable: same answer, still no self-copy

```x
(do
  (write (Pin sync "build/pin-spec/own"))
  (display " ")
  (display (File exists? "build/pin-spec/own/dep/ownmod/util.x")))
```
---
    ("acme/three.x" "acme/four.x") #f

### check runs clean end to end on a project with own-module roots

`check` is the CI verb, and its audit half walks the same closure sync
does: it must resolve own-module imports (not die on them) and never
report a module the repo itself carries as a half-pin.

```x
(write (Pin check "build/pin-spec/own"))
```
---
    ()
