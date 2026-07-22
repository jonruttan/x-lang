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
