# @lib ../tests/x/lib/stream.x

Stream (`lib/x/sys/stream.x`) redirects output by pushing/popping the base's
`fileout` fd -- pure X, no syscall. These cases exercise the syscall-free
surface: construction, the redirect plumbing, and restore. The file-backed
methods (`to-file`, `write`, `with-output-to-file`) need the x-or dialect and
are verified separately.

The redirect cases deliberately retarget output to the *current* fd, so nothing
actually moves -- they pin down the plumbing (set / run-thunk / restore / return
value) without performing real I/O.

## stream: construction

### to-fd wraps the given fd

```scheme
(do
  (def s (Stream to-fd 7))
  (eq? (s fd) 7))
```
---
    #t

### a wrapped fd is not owned -- close is a no-op returning nil

```scheme
(do
  (def s (Stream to-fd 7))
  (null? (s close)))
```
---
    #t

### stdout / stderr convenience constructors carry fd 1 / 2

```scheme
(and (eq? ((Stream stdout) fd) 1)
     (eq? ((Stream stderr) fd) 2))
```
---
    #t

## stream: redirect plumbing

### with-output-to-fd runs the thunk and returns its value

```scheme
(Stream with-output-to-fd (Stream output-fd) (fn (_) 42))
```
---
    42

### with-output-to-fd restores the previous output fd afterward

```scheme
(do
  (def before (Stream output-fd))
  (Stream with-output-to-fd before (fn (_) ()))
  (eq? (Stream output-fd) before))
```
---
    #t

### (s with thunk) redirects through the stream and returns the thunk's value

```scheme
(do
  (def s (Stream to-fd (Stream output-fd)))
  (s with (fn (_) 99)))
```
---
    99
