# Inflate JIT engine

# @weight 15
# @timeout-scale 4

The compiled codes loop behind `(Inflate jit!)`.  It is adopted only after
decoding a fixed-code and a dynamic-code stream exactly as the pure-x loop
does; these cases re-prove agreement through the class, on inputs made by the
system zlib.  `%ij-region` puts a byte list into a byte region and
`%ij-bytes` reads one back.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/inflate)
  (display (list (Inflate jit!) (Inflate jit!) ((Compiled named (lit inflate)) state))))
```
---
    (#t #t compiled)

## agreement with the system zlib through the engine

### stored, fixed and dynamic blocks, a run, and two streams end to end

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (Inflate jit!)
  (def %ij-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %ij-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %ij-round (fn (_ data level)
    (let ((z (Zlib compress data level)))
      (let ((r (Inflate zlib (%ij-region z) 0 (List length z))))
        (and (equal? (%ij-bytes (first r) (first (rest r))) data)
             (= (first (rest (rest r))) (List length z)))))))
  (write (list
    (%ij-round (List map (fn (_ i) (& (* i 7) 255)) (List range 0 300)) 0)
    (%ij-round (list 104 101 108 108 111 10) 6)
    (%ij-round (List map (fn (_ i) (+ 97 (% (+ (* i i) (/ i 7)) 23))) (List range 0 2000)) 9)
    (%ij-round (List map (fn (_ i) 0) (List range 0 1000)) 6))))
```
---
    (#t #t #t #t)

### an output that outgrows its region many times over

The driver grows the output whenever less than a match's 258 bytes are
left, and the step returns every 256 steps: 40000 bytes of a short period
cross both many times.  The data is local to a function, never a global:
the runner collects between cases, and the collector's mark recurses down
a list, so a 40000-element list left live overruns the C stack.

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (Inflate jit!)
  (def %ij-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (write
    ((fn (_)
       (def data (List map (fn (_ i) (+ 65 (% (* i 31) 26))) (List range 0 40000)))
       (def z (Zlib compress data 6))
       (def r (Inflate zlib (%ij-region z) 0 (List length z)))
       (def p ((prim-ref (lit str) (lit ->ptr)) (first r)))
       (list (first (rest r))
             ((fn (self i l) (if (null? l) #t (if (= (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) (first l)) (self (+ i 1) (rest l)) #f))) 0 data))))))
```
---
    (40000 #t)

### a stream cut short is refused through the engine too

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (Inflate jit!)
  (def %ij-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %ij-z (Zlib compress (List map (fn (_ i) (& (* i 13) 255)) (List range 0 400)) 6))
  (guard (e (e msg)) (Inflate raw (%ij-region %ij-z) 2 10)))
```
---
    "Inflate: the input ends inside the stream"

## the compiled Adler-32

### it agrees with the pure-x sum across many steps

70000 bytes: past 65521, so both sums wrap many times, and past one call's
budget of steps, so the driver runs the step again.

```x
(do (import x/codec/inflate)
  (Inflate jit!)
  (def %ij-pure (eval (lit %adler32-x) (module x/codec/inflate)))
  (def %ij-r ((prim-ref (lit str) (lit make)) 70000))
  (def %ij-p ((prim-ref (lit str) (lit ->ptr)) %ij-r))
  ((fn (self i) (when (< i 70000) (do ((prim-ref (lit ptr) (lit set!)) %ij-p i (& (* i 151) 255) 1) (self (+ i 1))))) 0)
  (write (list (= (Inflate adler32 %ij-r 70000) (%ij-pure %ij-p 70000))
               (Inflate adler32 "Wikipedia" 9))))
```
---
    (#t 300286872)
