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
be open and every state must hold compiled code, the delimiter hook wherever the
engine exports its trampoline; where it does not, the probe must be closed. A
state image takes the rejit path, which asks the probe again, so this holds for
both boots.

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

A `global` or `push` site holds a compiled state, and a `swap` site the compiled
global it seats in the symbol type's lists. The delimiter hook's two sites are
the next case's, since it compiles only where the engine exports its
trampoline. The answer names each global that kept its twin, and the kind of
any other site that did.

```x
(do
  (def %twins
    (fn (self l acc)
      (if (null? l) acc
        (self (rest l)
          (if (if (%tower-same? (%tower-site-interp (first l)) (eval (lit macro-delimit) (module x/reader/lit-reader))) #f
                (%tower-same? (first (%tower-site-value-cell (first l)))
                              (%tower-site-interp (first l))))
            (pair (if (eq? (%tower-site-kind (first l)) (lit global))
                    (%tower-site-place (first l))
                    (%tower-site-kind (first l)))
                  acc)
            acc)))))
  (write (if %tower-jit?
           (if (null? %tower-sites) (lit no-sites) (%twins %tower-sites ()))
           ())))
```
---
    ()

### the delimiter hook compiles wherever the engine exports its trampoline

The engine is asked the way the tower asks it, with `dlsym` on the process.
Where it exports `jit_buffer_last_char` and the probe is open,
`%c-macro-delimit` is compiled code; otherwise it is the interpreted
`macro-delimit` of `x/reader/lit-reader`. That holds whether or not a cache miss has loaded the
compiler.

```x
(do
  (def %exported
    (not (null? ((prim-ref 'ffi 'dlsym) ((prim-ref 'ffi 'dlopen) () 1) "jit_buffer_last_char"))))
  (write (eq? (not (%tower-same? %c-macro-delimit (eval (lit macro-delimit) (module x/reader/lit-reader))))
              (if %tower-jit? %exported #f))))
```
---
    #t
