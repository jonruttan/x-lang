# @lib ../tests/x/lib/modfiles.x
# @weight 1
# A module in several files, from a state image

The cases boot from a state image of `tests/x/lib/modfiles.x`, which imports
a module written in two files, so the image writer loaded those files through
the loader in a fresh base before any case runs. The cases in
[module-scope.spec.md](module-scope.spec.md#a-module-in-several-files) load
the same module from source.

## the image holds the module

### its two files are one environment, as it was loaded

```x
((fn (_) (import scoped/whole whole-step! whole-read whole-plain)
   (list (whole-step!) (whole-read) (whole-plain) (eval (lit %step-by) (module scoped/whole)))))
```
---
    (1 1 6 1)

## a failure in a module's other file

### names that file and its line

```x
(do (import-path! "tests/x/fixtures/modscope")
    (guard (_ (list (Str8 ends? "scoped/broken-two-step.x" ((prim-ref (lit io) (lit error-file))))
                    ((prim-ref (lit io) (lit error-line)))))
      (import scoped/broken-two)))
```
---
    (#t 4)
