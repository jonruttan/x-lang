# Sum: the checksums of sum(1) in pure x
# @weight 8
# @timeout-scale 4

BSD's and System V's checksums, set against the system's (`cksum -o 1` and
`cksum -o 2` print them) on the same bytes: the check input, an empty input,
bytes with NULs and high values read by their count and in a span, and the
compiled engines.

## against the system's

### the check input, and an empty input

```x
(do (import x/codec/sum)
  (write (list (Sum bsd "123456789") (Sum sysv "123456789") (Sum bsd "") (Sum sysv ""))))
```
---
    (53615 477 0 0)

### a NUL is a byte like any other

`printf 'a\0b'` gives 16506 and 195.

```x
(do (import x/codec/sum)
  (def %sm-n ((prim-ref (lit str) (lit make)) 3))
  (def %sm-np ((prim-ref (lit str) (lit ->ptr)) %sm-n))
  ((prim-ref (lit ptr) (lit set!)) %sm-np 0 97 1)
  ((prim-ref (lit ptr) (lit set!)) %sm-np 1 0 1)
  ((prim-ref (lit ptr) (lit set!)) %sm-np 2 98 1)
  (write (list (Sum bsd %sm-n 0 3) (Sum sysv %sm-n 0 3))))
```
---
    (16506 195)

### 70000 bytes with NULs and high bytes, in a span

The bytes are i times 7 for each i, cut to a byte, from offset 1000; the
system's gave 58803 and 12032 for them.

```x
(do (import x/codec/sum)
  (def %sm-r ((prim-ref (lit str) (lit make)) 71000))
  (def %sm-p ((prim-ref (lit str) (lit ->ptr)) %sm-r))
  ((fn (self i) (when (< i 70000) (do ((prim-ref (lit ptr) (lit set!)) %sm-p (+ i 1000) (& (* i 7) 255) 1) (self (+ i 1))))) 0)
  (write (list (Sum bsd %sm-r 1000 70000) (Sum sysv %sm-r 1000 70000))))
```
---
    (58803 12032)

### the compiled engines: adopted, and the same sums as the system's

Past 4KB `bsd` and `sysv` build their compiled loops (JIT); `jit!` builds
both at once and answers whether both were adopted.  The 5000 bytes are a
to z over and over; the system's gave 62668 and 23148.

```x
(do (import x/codec/sum)
  (def %sm-j ((prim-ref (lit str) (lit make)) 5000))
  ((fn (self i) (when (< i 5000) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %sm-j) i (+ 97 (% i 26)) 1) (self (+ i 1))))) 0)
  (write (list (Sum jit!) (Sum bsd %sm-j 0 5000) (Sum sysv %sm-j 0 5000))))
```
---
    (#t 62668 23148)
