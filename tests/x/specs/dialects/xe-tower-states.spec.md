# @lib xe.x
# @requires native/jit
# @weight 6

The tower's compiled analyser states take the compile.

A refused compile is not an error here: `%tower-asm-only` wraps it in a
guard and answers the interpreted twin, so the state keeps working and
nothing says it stopped being compiled.  That silence is how x-python's
tokenizer JIT sat refused for months.  These five are written with
`match`, which the assembler lane lowers as of #714; the check is that
the global is no longer the twin it would fall back to.

## the states are compiled, not their twins

### none of the five falls back to its interpreted twin

```x
(write (list (same? %dec-int %dec-int-interp)
             (same? %dec-frac %dec-frac-interp)
             (same? %cx-real-int %cx-real-int-interp)
             (same? %cx-real-frac %cx-real-frac-interp)
             (same? %cx-imag-int %cx-imag-int-interp)))
```
---
    (#f #f #f #f #f)

### and the numbers those states read come back whole

```x
(write (list 1.5d 12d 1+2i 3.5+1.5i 1/2 2.5))
```
---
    (1.5d 12d 1+2i 3.5+1.5i 1/2 2.5)
