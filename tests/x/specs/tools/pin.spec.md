# @lib ../tests/x/lib/assert.x

# @weight 13
## pin: manifest interpretation (x/tool/pin)

The manifest (pin.xon) is DATA: forms are read with the ordinary reader
(`%pin-forms`) and interpreted against a closed vocabulary
(`%pin-interpret`), never evaluated.  These specs pin the pure
interpretation layer; the wrapper probe and end-to-end arming are smoked
by tools/check/pin-smoke.sh (make check-pin).

### loading the module without an announced manifest is a no-op

```x
(do
  (import x/tool/pin)
  (display "loaded"))
```
---
    loaded

### a relative root resolves against the manifest's directory

```x
(do
  (import x/tool/pin)
  (display (first (Pin %pin-interpret (Pin %pin-forms "(root \"deps\")") "/proj"))))
```
---
    /proj/deps

### an absolute root passes through unchanged

```x
(do
  (import x/tool/pin)
  (display (first (Pin %pin-interpret (Pin %pin-forms "(root \"/opt/deps\")") "/proj"))))
```
---
    /opt/deps

### roots keep manifest order

```x
(do
  (import x/tool/pin)
  (display (first (rest (Pin %pin-interpret (Pin %pin-forms "(root \"a\") (root \"b\")") "/p")))))
```
---
    /p/b

### manifest comments are skipped

```x
(do
  (import x/tool/pin)
  (display (first (Pin %pin-interpret (Pin %pin-forms "; a comment
(root \"deps\")") "/p"))))
```
---
    /p/deps

### an unknown form is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(evil \"x\")") "/p")))))
```
---
    #t

### a bare (non-list) form is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(root \"a\") stray") "/p")))))
```
---
    #t

### a non-string root argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(root 42)") "/p")))))
```
---
    #t

### a missing root argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(root)") "/p")))))
```
---
    #t

### an extra root argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(root \"a\" \"b\")") "/p")))))
```
---
    #t

### a boot form is accepted and contributes no root

The wrapper consumes `(boot "FILE")` (the entry must be chosen before
the pipe exists); the loader only shape-checks it.

```x
(do
  (import x/tool/pin)
  (display (first (Pin %pin-interpret (Pin %pin-forms "(boot \"boot/xe.x\") (root \"deps\")") "/proj"))))
```
---
    /proj/deps

### a manifest of only a boot form arms nothing

```x
(do
  (import x/tool/pin)
  (display (null? (Pin %pin-interpret (Pin %pin-forms "(boot \"boot/xe.x\")") "/proj"))))
```
---
    #t

### a non-string boot argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(boot 42)") "/p")))))
```
---
    #t

### a missing boot argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(boot)") "/p")))))
```
---
    #t

### an extra boot argument is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(boot \"a\" \"b\")") "/p")))))
```
---
    #t

### an allow-release-skew form is accepted and contributes no root

The manifest's second wrapper-consumed form (#435): it waives the
boot-time release pairing refusal for this project, so like `(boot ...)`
it is decided before the pipe exists and the loader only shape-checks it.

```x
(do
  (import x/tool/pin)
  (display (null? (Pin %pin-interpret (Pin %pin-forms "(allow-release-skew)") "/proj"))))
```
---
    #t

### allow-release-skew takes no arguments

A safety waiver that is silently ignored because it was misspelled is
worse than one that was never written, so the closed vocabulary rejects
it rather than skipping it.

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-interpret (Pin %pin-forms "(allow-release-skew \"yes\")") "/p")))))
```
---
    #t

### arming a nonexistent root directory is a loud error

```x
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (Pin %pin-arm! (list "/nonexistent-pin-root-xyz"))))))
```
---
    #t

## pin: the vendor closure walk (Pin)

A fixture module tree is built under build/pin-spec/ and armed as an
import root; the walk is purely static (fixture files are read, never
loaded).  acme/one imports acme/two (which imports the boot-floor
x/core/list), pulls a ./-relative sibling (which imports acme/four),
and hides an import of acme/three inside a deferred fn body.

### fixture tree

```x
(do
  (import x/tool/pin)
  (guard (_ ()) (File mkdir "build"))
  (guard (_ ()) (File mkdir "build/pin-spec"))
  (guard (_ ()) (File mkdir "build/pin-spec/lib0"))
  (guard (_ ()) (File mkdir "build/pin-spec/lib0/acme"))
  (File write-all "build/pin-spec/lib0/acme/one.x"
    "(import acme/two)\n(include-once \"./one-extra.x\")\n(def %acme-deferred (fn (_) (import acme/three)))\n(provide acme/one)\n")
  (File write-all "build/pin-spec/lib0/acme/one-extra.x" "(import acme/four)\n")
  (File write-all "build/pin-spec/lib0/acme/two.x"
    "(import x/core/list)\n(provide acme/two)\n")
  (File write-all "build/pin-spec/lib0/acme/three.x" "(provide acme/three)\n")
  (File write-all "build/pin-spec/lib0/acme/four.x" "(provide acme/four)\n")
  (File write-all "build/pin-spec/lib0/acme/bad.x" "(include-once (computed))\n")
  (import-path! "build/pin-spec/lib0")
  (display "ready"))
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

## pin: the release manifest and fetch plumbing (hermetic)

### the release URL layout

```x
(display (Pin %pin-url "https://host/dl" "v1.2.3" "xe.x"))
```
---
    https://host/dl/v1.2.3/xe.x

### a release manifest parses to its parts

```x
(do
  (def %pin-spec-m (Pin %pin-release-parse (Pin %pin-forms
    "(release \"v1\") (isa \"sha256:aa\") (file \"xe.x\" \"sha256:bb\")")))
  ; %pin-assoc was retired for the canonical %assoc-get (#227)
  (display (%assoc-get 'release %pin-spec-m))
  (display " ")
  (display (Pin %pin-release-file "xe.x" (%assoc-get 'files %pin-spec-m))))
```
---
    v1 sha256:bb

### a release manifest's payload fingerprint parses

The release fingerprint (#435): one digest over everything the release
ships as library.  `isa` is the C surface and is byte-identical across
releases, so it can say "compatible" but never "same release"; this row
is what tells two releases apart.

```x
(do
  (def %pin-spec-p (Pin %pin-release-parse (Pin %pin-forms
    "(release \"v1\") (isa \"sha256:aa\") (payload \"sha256:cc\")")))
  (display (%assoc-get 'payload %pin-spec-p)))
```
---
    sha256:cc

### a release manifest without a payload row still parses

Every release published before #435 has no such row, and unpinning those
projects to fix a fingerprint they never had would be the worse trade --
so the fact is optional and reads back as nil.

```x
(do
  (def %pin-spec-q (Pin %pin-release-parse (Pin %pin-forms
    "(release \"v1\") (isa \"sha256:aa\")")))
  (display (null? (%assoc-get 'payload %pin-spec-q))))
```
---
    #t

### a non-string payload is a loud error

```x
(display (throws? (fn (_) (Pin %pin-release-parse (Pin %pin-forms "(release \"v1\") (payload 42)")))))
```
---
    #t

### a manifest without (release ...) is a loud error

```x
(display (throws? (fn (_) (Pin %pin-release-parse (Pin %pin-forms "(isa \"sha256:aa\")")))))
```
---
    #t

### an unknown release-manifest form is a loud error

```x
(display (throws? (fn (_) (Pin %pin-release-parse (Pin %pin-forms "(evil \"x\")")))))
```
---
    #t

### a file absent from the release manifest is a loud error

```x
(display (throws? (fn (_) (Pin %pin-release-file "nope.x" (list (pair "xe.x" "sha256:bb"))))))
```
---
    #t

### an absent command reports 127 (the print-the-URLs fallback's trigger)

```x
(display (Proc run! (list "no-such-command-pin-spec-xyz")))
```
---
    127

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

## pin: versioned imports vendor the chosen file (GH #214)

### a constraint import is resolved at sync time and vendored at its versioned rel

The scanner routes (import-version-once NAME "SPEC") through the boot
layer's own resolver, so the overlay receives the concrete file the
constraint selects -- here the newest 1.3.*.

```x
(do
  (guard (_ ()) (File mkdir "build/pin-spec/vfix"))
  (guard (_ ()) (File mkdir "build/pin-spec/vfix/acme"))
  (File write-all "build/pin-spec/vfix/acme/vd.x" "(provide acme/vd)\n")
  (File write-all "build/pin-spec/vfix/acme/vd@1.3.x" "(provide acme/vd)\n")
  (File write-all "build/pin-spec/vfix/acme/vd@1.3.1.x" "(provide acme/vd)\n")
  (import-path! "build/pin-spec/vfix")
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
