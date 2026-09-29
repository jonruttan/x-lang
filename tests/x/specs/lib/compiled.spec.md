# Compiled: a function that has a compiled version, and the list of them
# @weight 1

An entry (`lib/x/tool/compiled.x`) is one function that has a compiled
version: its interpreted version, the function that compiles it, and the
function that installs either where it is called from. The interpreted
version is the reference. A compile that raises has failed and one that
answers the interpreted version has declined, and either way the
interpreted version stays installed and the entry says which. Every entry
is switched to interpreted before a state image is written and compiled
again after one is loaded.

The cases share one process, so each names its own entries. `%here` is the
environment the cases' names are bound in, as an operative is handed it.
The cases compile nothing: a function that answers a value stands in for a
compiler.

## the environment the cases run in

### an operative answers its caller's environment

```x
(def %here ((op () e e)))
(write (eval (lit (+ 1 2)) %here))
```
---
    3

## one entry

### an entry is compiled as it is made, and the compiled version is installed

```x
(do (import x/tool/compiled)
  (def %slow-a (fn (_ n) (+ n 1)))
  (def %place-a %slow-a)
  (def %entry-a
    (Compiled make (lit a) %slow-a
      (fn (_) (fn (_ n) (+ n 1)))
      (Compiled into-name (lit %place-a) %here)))
  (write (list (%entry-a state)
               (same? %place-a %slow-a)
               (same? %place-a (%entry-a compiled))
               (%place-a 41))))
```
---
    ('compiled #f #t 42)

### a compile that raises has failed, and the interpreted version stays installed

```x
(do (import x/tool/compiled)
  (def %slow-b (fn (_ n) (+ n 1)))
  (def %place-b %slow-b)
  (def %entry-b
    (Compiled make (lit b) %slow-b
      (fn (_) (Err raise (lit state) "no lane here" ()))
      (Compiled into-name (lit %place-b) %here)))
  (write (list (%entry-b state)
               (same? %place-b %slow-b)
               (null? (%entry-b compiled)))))
```
---
    ('failed #t #t)

### the raise's text is kept as the reason

```x
(do (import x/tool/compiled)
  (write (Str8 includes? "no lane here" ((Compiled named (lit b)) reason))))
```
---
    #t

### a compile that answers the interpreted version has declined

```x
(do (import x/tool/compiled)
  (def %slow-c (fn (_ n) (+ n 1)))
  (def %place-c %slow-c)
  (def %entry-c
    (Compiled make (lit c) %slow-c
      (fn (_) %slow-c)
      (Compiled into-name (lit %place-c) %here)))
  (write (list (%entry-c state) (same? %place-c %slow-c) (%entry-c reason))))
```
---
    ('interpreted #t "")

### a compile may answer nil, and nil is installed

```x
(do (import x/tool/compiled)
  (def %place-d 7)
  (def %entry-d
    (Compiled make (lit d) 7 (fn (_) ())
      (Compiled into-name (lit %place-d) %here)))
  (write (list (%entry-d state) %place-d)))
```
---
    ('compiled ())

### an entry that was never compiled is interpreted, with no reason

`(Compiled make ...)` compiles an entry as it makes one. One made with `new`
has not been compiled, and its state and reason are the fields' defaults.

```x
(do (import x/tool/compiled)
  (def %entry-new
    (new Compiled name (lit n) interpreted 1 compile (fn (_) 2) install (fn (_ v) v)))
  (write (list (%entry-new state) (%entry-new reason) (%entry-new compiled))))
```
---
    ('interpreted "" ())

## interpreted and compiled again

### interpret! installs the interpreted version and lets go of the compiled one

```x
(do (import x/tool/compiled)
  ((Compiled named (lit a)) interpret!)
  (write (list ((Compiled named (lit a)) state)
               (same? %place-a %slow-a)
               (null? ((Compiled named (lit a)) compiled)))))
```
---
    ('interpreted #t #t)

### compile! compiles again

```x
(do (import x/tool/compiled)
  (def %made-e 0)
  (def %place-e 0)
  (def %entry-e
    (Compiled make (lit e) 0
      (fn (_) (set! %made-e (+ %made-e 1)) %made-e)
      (Compiled into-name (lit %place-e) %here)))
  (%entry-e interpret!)
  (def %while-interpreted %place-e)
  (%entry-e compile!)
  (write (list %while-interpreted %place-e (%entry-e state))))
```
---
    (0 2 'compiled)

### an entry that failed fails again when compiled again, with its reason

```x
(do (import x/tool/compiled)
  ((Compiled named (lit b)) interpret!)
  (def %reason-interpreted ((Compiled named (lit b)) reason))
  ((Compiled named (lit b)) compile!)
  (write (list %reason-interpreted
               ((Compiled named (lit b)) state)
               (Str8 includes? "no lane here" ((Compiled named (lit b)) reason)))))
```
---
    ("" 'failed #t)

## where a version is installed

### into the first of a pair

```x
(do (import x/tool/compiled)
  (def %cells (list 1 2 3))
  (def %entry-f
    (Compiled make (lit f) 2 (fn (_) 20) (Compiled into-cell (rest %cells))))
  (def %up %cells)
  (def %shown (list (first %up) (first (rest %up)) (first (rest (rest %up)))))
  (%entry-f interpret!)
  (write (list %shown %cells)))
```
---
    ((1 20 3) (1 2 3))

### any function of one value installs

```x
(do (import x/tool/compiled)
  (def %log ())
  (def %entry-g
    (Compiled make (lit g) (lit slow) (fn (_) (lit fast))
      (fn (_ v) (set! %log (pair v %log)))))
  (%entry-g interpret!)
  (%entry-g compile!)
  (write %log))
```
---
    ('fast 'slow 'fast)

## every entry

### entries compile oldest first, so a compile finds what an earlier one made

```x
(do (import x/tool/compiled)
  (def %place-h 1)
  (def %place-i 1)
  (def %made-h 10)
  (Compiled make (lit h) 1
    (fn (_) (set! %made-h (+ %made-h 1)) %made-h)
    (Compiled into-name (lit %place-h) %here))
  (Compiled make (lit i) 1
    (fn (_) (* %place-h 2))
    (Compiled into-name (lit %place-i) %here))
  (def %first (list %place-h %place-i))
  (Compiled interpret-all!)
  (def %down (list %place-h %place-i))
  (Compiled compile-all!)
  (write (list %first %down (list %place-h %place-i))))
```
---
    ((11 22) (1 1) (12 24))

### named answers the newest entry of a name, and nil for a name no entry has

```x
(do (import x/tool/compiled)
  (def %place-j 0)
  (Compiled make (lit j) 0 (fn (_) 1) (Compiled into-name (lit %place-j) %here))
  (def %newer
    (Compiled make (lit j) 0 (fn (_) 2) (Compiled into-name (lit %place-j) %here)))
  (write (list (same? (Compiled named (lit j)) %newer)
               (null? (Compiled named (lit no-such-entry))))))
```
---
    (#t #t)

### list answers every entry, oldest first, with its state and reason

```x
(do (import x/tool/compiled)
  (def %mine
    (fn (self rows acc)
      (if (null? rows) acc
        (self (rest rows)
          (if (if (eq? (first (first rows)) (lit a)) #t
                (eq? (first (first rows)) (lit c)))
            (pair (list (first (first rows)) (first (rest (first rows)))) acc)
            acc)))))
  (write (%mine (Compiled list) ())))
```
---
    (('c 'interpreted) ('a 'compiled))

## state images

### the loader's recache compiles an interpreted entry again

The image writer switches every entry to interpreted inside the process it
images, and the loader runs the recache hooks once the image is installed.
Each entry added its own hook as it was made.

```x
(do (import x/tool/compiled)
  (def %place-k (lit slow))
  (def %entry-k
    (Compiled make (lit k) (lit slow) (fn (_) (lit fast))
      (Compiled into-name (lit %place-k) %here)))
  (Compiled interpret-all!)
  (def %down (list %place-k (%entry-k state)))
  (%image-recache!)
  (write (list %down %place-k (%entry-k state))))
```
---
    (('slow 'interpreted) 'fast 'compiled)

### an entry made on demand stays interpreted after a load, until it is sent compile!

```x
(do (import x/tool/compiled)
  (def %place-m (lit slow))
  (def %entry-m
    (Compiled make-on-demand (lit m) (lit slow) (fn (_) (lit fast))
      (Compiled into-name (lit %place-m) %here)))
  (def %made (list %place-m (%entry-m state)))
  (Compiled interpret-all!)
  (%image-recache!)
  (def %loaded (list %place-m (%entry-m state)))
  (%entry-m compile!)
  (write (list %made %loaded %place-m (%entry-m state))))
```
---
    (('fast 'compiled) ('slow 'interpreted) 'fast 'compiled)

### one of the transients switches every entry to interpreted

```x
(do (import x/tool/compiled)
  ((fn (loop l)
     (if (null? l) ()
       ((fn (_ entry)
          (if (symbol? entry) () (entry))
          (loop (rest l)))
        (first l))))
   %image-transients)
  (def %states
    ((fn (self rows acc)
       (if (null? rows) acc
         (self (rest rows)
           (if (eq? (first (rest (first rows))) (lit interpreted)) acc #f))))
     (Compiled list) #t))
  (%image-recache!)
  (write %states))
```
---
    #t
