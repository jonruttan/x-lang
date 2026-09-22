# @lib x-base.x
# @weight 3

The tower's compiled analysers (`lib/x/boot/tower-compiled.x`). One probe,
`%tower-jit?`, decides whether the burst compiles at all, and each state then
compiles through a site that keeps its interpreted twin when the lane refuses
it. Both fallbacks are silent -- a twin answers what its compiled state
answers -- so the other tower specs pass either way; this file tells the two
apart.

Whether the lane compiles an analyser state is asked here directly, with the
mode declared and nothing taken from the tower. Where it does, the probe must
be open and every state must hold compiled code; where it does not, the probe
must be closed. A state image takes the rejit path, which asks the probe again,
so this holds for both boots.

## the burst compiles wherever the lane compiles an analyser

### the probe agrees with the lane

```x
(do
  (def %lane
    (guard (_ #f)
      (do (compile-asm (lit (fn (me buffer score chr) (if (= chr 32) me ()))) () #t)
          #t)))
  (write (eq? %tower-jit? %lane)))
```
---
    #t

### every state holds compiled code

A `global` or `push` site holds a compiled state. The `swap` sites seat those
globals in the symbol type's lists, and the delimiter hook compiles only where
its trampoline is bound, so they are left out. The answer names each state that
kept its twin.

```x
(do
  (def %twins
    (fn (self l acc)
      (if (null? l) acc
        (self (rest l)
          (if (if (eq? (%tower-site-kind (first l)) (lit swap)) #f
                (%tower-same? (first (%tower-site-value-cell (first l)))
                              (%tower-site-interp (first l))))
            (pair (%tower-site-place (first l)) acc)
            acc)))))
  (write (if %tower-jit?
           (if (null? %tower-sites) (lit no-sites) (%twins %tower-sites ()))
           ())))
```
---
    ()
