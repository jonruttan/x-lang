# Proc (x/sys/proc) and the Sys signal surface

# @weight 6
Argv-based child processes.  The status convention carries three
distinguishable outcomes: the child's exit code, 127 for exec-never-
happened, 128+N for death by signal N.

## proc: run! status convention

### a normal exit code comes back as itself

```x
(do
  (import x/sys/proc)
  (display (Proc run! (list "/bin/sh" "-c" "exit 3"))))
```
---
    3

### an absent command is 127, the exec-failure convention

```x
(do
  (import x/sys/proc)
  (display (Proc run! (list "/nonexistent-command-proc-spec"))))
```
---
    127

### a signal-killed child is 128+N, not a fake success

```x
(do
  (import x/sys/proc)
  (display (Proc run! (list "/bin/sh" "-c" "kill -TERM $$"))))
```
---
    143

## proc: capture

### stdout comes back with the status

```x
(do
  (import x/sys/proc)
  (def %r (Proc capture (list "/bin/sh" "-c" "printf 'a b'; exit 7")))
  (display (first %r))
  (display " ")
  (display (rest %r)))
```
---
    7 a b

### output larger than one read chunk is drained, not deadlocked

```x
(do
  (import x/sys/proc)
  ; 200000 bytes: bigger than the 64K read chunk and any pipe buffer --
  ; a parent that waited before draining would block forever here.
  ; Text bytes on purpose: capture's contract is C-string text (bytes
  ; past a NUL are unobservable -- the x-lib string ruling).
  (def %r (Proc capture (list "/bin/sh" "-c" "head -c 200000 /dev/zero | tr '\\0' 'a'")))
  (display (first %r))
  (display " ")
  (display (Str8 length (rest %r))))
```
---
    0 200000

## sys: signal surface

### an ignored signal does not kill the process

```x
(do
  (Sys signal (Sys sigint) (Sys sig-ign))
  (Sys kill (Sys getpid) (Sys sigint))
  (Sys signal (Sys sigint) (Sys sig-dfl))
  (display "alive"))
```
---
    alive

## run-with! / capture-with (#364)

### env overrides reach the child

```x
(do (import x/sys/proc)
  (rest (Proc capture-with (list (pair 'env (list (pair "X364" "yes"))))
              (list "/bin/sh" "-c" "printf %s $X364"))))
```
---
    "yes"

### cwd applies in the child; an unusable cwd is 126, not a wrong-dir exec

```x
(do (import x/sys/proc)
  (list (first (Proc capture-with (list (pair 'cwd "/")) (list "/bin/sh" "-c" "pwd")))
        (rest (Proc capture-with (list (pair 'cwd "/")) (list "/bin/sh" "-c" "printf %s $PWD")))
        (Proc run-with! (list (pair 'cwd "/definitely-not-a-dir")) (list "/bin/true"))))
```
---
    (0 "/" 126)

### a child-side failure dies as 125 -- never a second interpreter

Any catchable error between fork and exec must END the child: an escaped
child shares the parent's stdin and re-runs the remaining program,
forking again per spawn form -- the fork bomb that OOM-killed the CI
runner. An unconvertible env value errors inside the child's prep; the
guard turns it into a hard exit 125.

```x
(do
  (import x/sys/proc)
  (Proc run-with! (list (pair 'env (list (pair "X364" (list 1 2))))) (list "/bin/sh" "-c" "exit 0")))
```
---
    125
