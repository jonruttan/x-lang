# @lib x-base.x
# @weight 3

The tower's compiled analysers (`lib/x/boot/tower-compiled.x`). One probe,
`%tower-jit?`, decides whether the burst compiles at all, and each state then
compiles through a site (`lib/x/sys/swap.x`) that keeps its interpreted twin
when the lane refuses it. A twin answers what its compiled state answers, so
the other tower specs pass either way; this file tells the two apart.

Whether the lane compiles an analyser state is asked here directly, with the
mode declared and nothing taken from the tower. Where it does, the probe must
be open and every state must hold compiled code, the delimiter hook wherever the
engine exports its trampoline; where it does not, the probe must be closed. A
state image asks the probe again and brings every site up again, so this holds
for both boots.

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

Every site of the tower's is up. The delimiter hook's two sites are the next
case's, since it compiles only where the engine exports its trampoline. The
answer is the row of each site that is not up: its name, its state, and the
reason when its compile was refused.

```x
(do
  (def %delimiter?
    (fn (_ name)
      (if (eq? name (lit macro-delimit)) #t (eq? name (lit %c-macro-delimit)))))
  (def %not-up
    (fn (self rows acc)
      (if (null? rows) acc
        (self (rest rows)
          (if (if (%delimiter? (first (first rows))) #t
                (eq? (first (rest (first rows))) (lit up)))
            acc
            (pair (first rows) acc))))))
  (write (if %tower-jit?
           (if (null? (Swap rows)) (lit no-sites) (%not-up (Swap rows) ()))
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
