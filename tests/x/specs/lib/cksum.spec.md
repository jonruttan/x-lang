# Cksum: the CRC of POSIX cksum in pure x
# @weight 8
# @timeout-scale 4

The CRC POSIX `cksum` prints, set against the system's `cksum` on the same
bytes: the check value, an empty input, bytes with NULs and high values read
by their count and in a span, and the compiled engine.

## against the system cksum

### the check value, and an empty input

```x
(do (import x/codec/cksum)
  (write (list (Cksum of "123456789") (Cksum of ""))))
```
---
    (930766865 4294967295)

### a NUL is a byte like any other

`printf 'a\0b' | cksum` gives 3560722768.

```x
(do (import x/codec/cksum)
  (def %ck-n ((prim-ref (lit str) (lit make)) 3))
  (def %ck-np ((prim-ref (lit str) (lit ->ptr)) %ck-n))
  ((prim-ref (lit ptr) (lit set!)) %ck-np 0 97 1)
  ((prim-ref (lit ptr) (lit set!)) %ck-np 1 0 1)
  ((prim-ref (lit ptr) (lit set!)) %ck-np 2 98 1)
  (write (Cksum of %ck-n 0 3)))
```
---
    3560722768

### 70000 bytes with NULs and high bytes, in a span

The bytes are i times 7 for each i, cut to a byte; the system `cksum` gave
3451499348 for all of them.  The span is the same bytes from 1000 on.

```x
(do (import x/codec/cksum)
  (def %ck-r ((prim-ref (lit str) (lit make)) 71000))
  (def %ck-p ((prim-ref (lit str) (lit ->ptr)) %ck-r))
  ((fn (self i) (when (< i 70000) (do ((prim-ref (lit ptr) (lit set!)) %ck-p (+ i 1000) (& (* i 7) 255) 1) (self (+ i 1))))) 0)
  (write (Cksum of %ck-r 1000 70000)))
```
---
    3451499348

### the compiled engine: adopted, and the same sum as the system cksum's

Past 4KB `of` builds the compiled loop (JIT); `jit!` builds it at once and
answers whether it was adopted.  The 5000 bytes are a to z over and over;
the system `cksum` gave 2456722308.

```x
(do (import x/codec/cksum)
  (def %ck-j ((prim-ref (lit str) (lit make)) 5000))
  ((fn (self i) (when (< i 5000) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %ck-j) i (+ 97 (% i 26)) 1) (self (+ i 1))))) 0)
  (write (list (Cksum jit!) (Cksum of %ck-j 0 5000) (Cksum of "123456789"))))
```
---
    (#t 2456722308 930766865)
