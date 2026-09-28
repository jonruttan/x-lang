# Swap: a slow value set aside for a faster one, and put back
# @weight 1

A site (`lib/x/sys/swap.x`) records one replacement: the seat a value sits
in, the slow twin that belongs there, and the maker of the fast value. The
twin is the reference. A maker that raises is refused and one that answers
the twin has declined, and either way the twin stays seated and the site
says which. Every site goes down before a state image is written and comes
up again after one is loaded.

The cases share one process, so each names its own sites. `%here` is the
environment the cases' names are bound in, as an operative is handed it.

## the environment the cases run in

### an operative answers its caller's environment

```x
(def %here ((op () e e)))
(write (eval (lit (+ 1 2)) %here))
```
---
    3

## one site

### a site comes up with its made value seated

```x
(do (import x/sys/swap)
  (def %slow-a (fn (_ n) (+ n 1)))
  (def %seat-a %slow-a)
  (def %site-a
    (Swap site! (lit a) %slow-a
      (fn (_) (fn (_ n) (+ n 1)))
      (Swap in-env (lit %seat-a) %here)))
  (write (list (%site-a state)
               (same? %seat-a %slow-a)
               (same? %seat-a (%site-a value))
               (%seat-a 41))))
```
---
    ('up #f #t 42)

### a maker that raises is refused, and the twin stays seated

```x
(do (import x/sys/swap)
  (def %slow-b (fn (_ n) (+ n 1)))
  (def %seat-b %slow-b)
  (def %site-b
    (Swap site! (lit b) %slow-b
      (fn (_) (Err raise (lit state) "no lane here" ()))
      (Swap in-env (lit %seat-b) %here)))
  (write (list (%site-b state)
               (same? %seat-b %slow-b)
               (null? (%site-b value)))))
```
---
    ('refused #t #t)

### the raise's text is kept as the reason

```x
(do (import x/sys/swap)
  (write (Str8 includes? "no lane here" ((Swap named (lit b)) reason))))
```
---
    #t

### a maker that answers the twin has declined

```x
(do (import x/sys/swap)
  (def %slow-c (fn (_ n) (+ n 1)))
  (def %seat-c %slow-c)
  (def %site-c
    (Swap site! (lit c) %slow-c
      (fn (_) %slow-c)
      (Swap in-env (lit %seat-c) %here)))
  (write (list (%site-c state) (same? %seat-c %slow-c) (%site-c reason))))
```
---
    ('twin #t "")

### a maker may answer nil, and nil is seated

```x
(do (import x/sys/swap)
  (def %seat-d 7)
  (def %site-d
    (Swap site! (lit d) 7 (fn (_) ())
      (Swap in-env (lit %seat-d) %here)))
  (write (list (%site-d state) %seat-d)))
```
---
    ('up ())

### a site that was never brought up is down, with no reason

`site!` brings a site up as it makes one. One made with `new` has not been
brought up, and its state and reason are the members' defaults.

```x
(do (import x/sys/swap)
  (def %site-new
    (new Swap name (lit n) twin 1 maker (fn (_) 2) seat (fn (_ v) v)))
  (write (list (%site-new state) (%site-new reason) (%site-new value))))
```
---
    ('down "" ())

## down and up

### down seats the twin and lets go of the made value

```x
(do (import x/sys/swap)
  ((Swap named (lit a)) down!)
  (write (list ((Swap named (lit a)) state)
               (same? %seat-a %slow-a)
               (null? ((Swap named (lit a)) value)))))
```
---
    ('down #t #t)

### up runs the maker again

```x
(do (import x/sys/swap)
  (def %made-e 0)
  (def %seat-e 0)
  (def %site-e
    (Swap site! (lit e) 0
      (fn (_) (set! %made-e (+ %made-e 1)) %made-e)
      (Swap in-env (lit %seat-e) %here)))
  (%site-e down!)
  (def %while-down %seat-e)
  (%site-e up!)
  (write (list %while-down %seat-e (%site-e state))))
```
---
    (0 2 'up)

### a refused site that comes up again is refused again, with its reason

```x
(do (import x/sys/swap)
  ((Swap named (lit b)) down!)
  (def %reason-down ((Swap named (lit b)) reason))
  ((Swap named (lit b)) up!)
  (write (list %reason-down
               ((Swap named (lit b)) state)
               (Str8 includes? "no lane here" ((Swap named (lit b)) reason)))))
```
---
    ("" 'refused #t)

## seats

### the first of a pair is a seat

```x
(do (import x/sys/swap)
  (def %cells (list 1 2 3))
  (def %site-f
    (Swap site! (lit f) 2 (fn (_) 20) (Swap in-cell (rest %cells))))
  (def %up %cells)
  (def %shown (list (first %up) (first (rest %up)) (first (rest (rest %up)))))
  (%site-f down!)
  (write (list %shown %cells)))
```
---
    ((1 20 3) (1 2 3))

### a seat is any function of one value

```x
(do (import x/sys/swap)
  (def %log ())
  (def %site-g
    (Swap site! (lit g) (lit slow) (fn (_) (lit fast))
      (fn (_ v) (set! %log (pair v %log)))))
  (%site-g down!)
  (%site-g up!)
  (write %log))
```
---
    ('fast 'slow 'fast)

## every site

### sites come up oldest first, so a maker finds the value an earlier one made

```x
(do (import x/sys/swap)
  (def %seat-h 1)
  (def %seat-i 1)
  (def %made-h 10)
  (Swap site! (lit h) 1
    (fn (_) (set! %made-h (+ %made-h 1)) %made-h)
    (Swap in-env (lit %seat-h) %here))
  (Swap site! (lit i) 1
    (fn (_) (* %seat-h 2))
    (Swap in-env (lit %seat-i) %here))
  (def %first (list %seat-h %seat-i))
  (Swap down!)
  (def %down (list %seat-h %seat-i))
  (Swap up!)
  (write (list %first %down (list %seat-h %seat-i))))
```
---
    ((11 22) (1 1) (12 24))

### named answers the newest site of a name, and nil for a name no site has

```x
(do (import x/sys/swap)
  (def %seat-j 0)
  (Swap site! (lit j) 0 (fn (_) 1) (Swap in-env (lit %seat-j) %here))
  (def %newer
    (Swap site! (lit j) 0 (fn (_) 2) (Swap in-env (lit %seat-j) %here)))
  (write (list (same? (Swap named (lit j)) %newer)
               (null? (Swap named (lit no-such-site))))))
```
---
    (#t #t)

### rows lists every site, oldest first, with its state and reason

```x
(do (import x/sys/swap)
  (def %mine
    (fn (self rows acc)
      (if (null? rows) acc
        (self (rest rows)
          (if (if (eq? (first (first rows)) (lit a)) #t
                (eq? (first (first rows)) (lit c)))
            (pair (list (first (first rows)) (first (rest (first rows)))) acc)
            acc)))))
  (write (%mine (Swap rows) ())))
```
---
    (('c 'twin) ('a 'up))

## state images

### the loader's recache brings a site that is down up again

The image writer puts every site down inside the process it images, and the
loader runs the recache hooks once the image is installed. Each site added
its own hook as it was made.

```x
(do (import x/sys/swap)
  (def %seat-k (lit slow))
  (def %site-k
    (Swap site! (lit k) (lit slow) (fn (_) (lit fast))
      (Swap in-env (lit %seat-k) %here)))
  (Swap down!)
  (def %down (list %seat-k (%site-k state)))
  (%image-recache!)
  (write (list %down %seat-k (%site-k state))))
```
---
    (('slow 'down) 'fast 'up)

### one of the transients puts every site down

```x
(do (import x/sys/swap)
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
           (if (eq? (first (rest (first rows))) (lit down)) acc #f))))
     (Swap rows) #t))
  (%image-recache!)
  (write %states))
```
---
    #t
