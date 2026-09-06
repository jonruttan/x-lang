# @lib ../tests/x/lib/pin.x

# @weight 1
# pin: the manifest and the release manifest, interpreted as data

One of six files that were tools/pin.spec.md, one 25-second job, cut
along the fixture chains they share (tests/x/lib/pin.x makes the trees
every file needs).  The manifest (pin.xon) is DATA: forms are read with the
ordinary reader and interpreted against a closed vocabulary, never
evaluated; the wrapper probe and end-to-end arming are smoked by
tools/check/pin-smoke.sh (make check-pin).

## pin: manifest interpretation (x/tool/pin)

The timeout scale is the budget this file always used: it shared a
three-file bucket, and a bucket's budget is the base times its files, so
its 25 serial seconds -- sync and check run end to end, spawning as they
go -- had 180 to finish in.  One file per job (the image boot) gave it 60,
and CI's ubuntu runner under parallel load killed it at that line.

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
