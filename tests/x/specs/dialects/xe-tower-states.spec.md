# @lib xe.x
# @requires native/jit
# @weight 6

The tower's compiled analyser states take the compile.

A refused compile is not an error here: `%tower-asm-only` wraps it in a
guard and answers the interpreted twin, so the state keeps working and
nothing says it stopped being compiled.  That silence is how x-python's
tokenizer JIT sat refused for months.  These five are written with
`match`, which the assembler lane lowers as of #714; the check is that
the module's binding is no longer the twin its site would fall back to.

## the states are compiled, not their twins

### none of the five falls back to its interpreted twin

```x
(def %site-of
  (fn (_ name)
    ((fn (self l)
       (if (null? l) ()
         (if (eq? (%tower-site-place (first l)) name) (first l) (self (rest l)))))
     %tower-sites)))
(def %compiled?
  (fn (_ env name)
    (not (same? (eval name env) (%tower-site-interp (%site-of name))))))
(write (list (%compiled? (module x/num/decimal) (lit dec-int))
             (%compiled? (module x/num/decimal) (lit dec-frac))
             (%compiled? (module x/num/complex) (lit cx-real-int))
             (%compiled? (module x/num/complex) (lit cx-real-frac))
             (%compiled? (module x/num/complex) (lit cx-imag-int))))
```
---
    (#t #t #t #t #t)

### and the numbers those states read come back whole

```x
(write (list 1.5d 12d 1+2i 3.5+1.5i 1/2 2.5))
```
---
    (1.5d 12d 1+2i 3.5+1.5i 1/2 2.5)
