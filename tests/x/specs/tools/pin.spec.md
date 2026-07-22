# @lib ../tests/x/lib/assert.x

## pin: manifest interpretation (x/tool/pin)

The manifest (pin.xon) is DATA: forms are read with the ordinary reader
(`%pin-forms`) and interpreted against a closed vocabulary
(`%pin-interpret`), never evaluated.  These specs pin the pure
interpretation layer; the wrapper probe and end-to-end arming are smoked
by tools/pin-smoke.sh (make check-pin).

### loading the module without an announced manifest is a no-op

```scheme
(do
  (import x/tool/pin)
  (display "loaded"))
```
---
    loaded

### a relative root resolves against the manifest's directory

```scheme
(do
  (import x/tool/pin)
  (display (first (%pin-interpret (%pin-forms "(root \"deps\")") "/proj"))))
```
---
    /proj/deps

### an absolute root passes through unchanged

```scheme
(do
  (import x/tool/pin)
  (display (first (%pin-interpret (%pin-forms "(root \"/opt/deps\")") "/proj"))))
```
---
    /opt/deps

### roots keep manifest order

```scheme
(do
  (import x/tool/pin)
  (display (first (rest (%pin-interpret (%pin-forms "(root \"a\") (root \"b\")") "/p")))))
```
---
    /p/b

### manifest comments are skipped

```scheme
(do
  (import x/tool/pin)
  (display (first (%pin-interpret (%pin-forms "; a comment
(root \"deps\")") "/p"))))
```
---
    /p/deps

### an unknown form is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-interpret (%pin-forms "(evil \"x\")") "/p")))))
```
---
    #t

### a bare (non-list) form is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-interpret (%pin-forms "(root \"a\") stray") "/p")))))
```
---
    #t

### a non-string root argument is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-interpret (%pin-forms "(root 42)") "/p")))))
```
---
    #t

### a missing root argument is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-interpret (%pin-forms "(root)") "/p")))))
```
---
    #t

### an extra root argument is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-interpret (%pin-forms "(root \"a\" \"b\")") "/p")))))
```
---
    #t

### arming a nonexistent root directory is a loud error

```scheme
(do
  (import x/tool/pin)
  (display (throws? (fn (_) (%pin-arm! (list "/nonexistent-pin-root-xyz"))))))
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

```scheme
(do
  (import x/tool/pin)
  (guard (_ ()) (File mkdir "build"))
  (guard (_ ()) (File mkdir "build/pin-spec"))
  (guard (_ ()) (File mkdir "build/pin-spec/lib0"))
  (guard (_ ()) (File mkdir "build/pin-spec/lib0/acme"))
  (File spit "build/pin-spec/lib0/acme/one.x"
    "(import acme/two)\n(include-once \"./one-extra.x\")\n(def %acme-deferred (fn (_) (import acme/three)))\n(provide acme/one)\n")
  (File spit "build/pin-spec/lib0/acme/one-extra.x" "(import acme/four)\n")
  (File spit "build/pin-spec/lib0/acme/two.x"
    "(import x/core/list)\n(provide acme/two)\n")
  (File spit "build/pin-spec/lib0/acme/three.x" "(provide acme/three)\n")
  (File spit "build/pin-spec/lib0/acme/four.x" "(provide acme/four)\n")
  (File spit "build/pin-spec/lib0/acme/bad.x" "(include-once (computed))\n")
  (import-path! "build/pin-spec/lib0")
  (display "ready"))
```
---
    ready

### the closure: transitive imports, ./ siblings, deferred-body imports; the boot floor excluded

```scheme
(write (Pin closure 'acme/one))
```
---
    ("acme/one.x" "acme/two.x" "acme/one-extra.x" "acme/four.x" "acme/three.x")

### vendor copies the closure into the overlay layout

```scheme
(do
  (Pin vendor "build/pin-spec/out" 'acme/one)
  (display (File exists? "build/pin-spec/out/acme/one-extra.x")))
```
---
    #t

### the vendored copy is byte-identical to its source

```scheme
(display (str=? (File slurp "build/pin-spec/out/acme/two.x")
                (File slurp "build/pin-spec/lib0/acme/two.x")))
```
---
    #t

### the boot floor is never copied

```scheme
(display (File exists? "build/pin-spec/out/x/core/list.x"))
```
---
    #f

### a boot-floor seed is refused (the pin boundary)

```scheme
(display (throws? (fn (_) (Pin vendor "build/pin-spec/out" 'x/core/list))))
```
---
    #t

### a computed include path in the closure is a loud error

```scheme
(display (throws? (fn (_) (Pin closure 'acme/bad))))
```
---
    #t
