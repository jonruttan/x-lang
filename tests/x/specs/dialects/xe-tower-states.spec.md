# @lib xe.x
# @requires native/jit
# @weight 6

The tower's compiled analyser states take the compile.

A compile that fails is not an error here: the state's entry on Compiled's
list installs the interpreted twin, so the state keeps working.  The entry
also says that its compile failed, and that is what these cases read.  These five are written with
`match`, which the assembler lane lowers as of #714.

## the states are compiled, not their twins

### none of the five falls back to its interpreted twin

```x
(def %state-of (fn (_ name) ((Compiled named name) state)))
(write (list (%state-of (lit dec-int))
             (%state-of (lit dec-frac))
             (%state-of (lit cx-real-int))
             (%state-of (lit cx-real-frac))
             (%state-of (lit cx-imag-int))))
```
---
    ('compiled 'compiled 'compiled 'compiled 'compiled)

### and the binding in the module's frame is the compiled version of its entry

```x
(def %seated?
  (fn (_ env name) (same? (eval name env) ((Compiled named name) compiled))))
(write (list (%seated? (module x/num/decimal) (lit dec-int))
             (%seated? (module x/num/complex) (lit cx-real-int))))
```
---
    (#t #t)

### and the numbers those states read come back whole

```x
(write (list 1.5d 12d 1+2i 3.5+1.5i 1/2 2.5))
```
---
    (1.5d 12d 1+2i 3.5+1.5i 1/2 2.5)
