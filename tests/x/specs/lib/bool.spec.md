## BOOL: the singletons as a real type (#101)

#t and #f are C-static satoms claimed at boot by an x-defined BOOL type via
(obj retag!). Everything identity-based must be bit-for-bit unchanged; what
changes is that the type system can finally SEE them.

### the singletons carry the BOOL type

```scheme
(list (Type name (Type of #t)) (Type name (Type of #f)))
```
---
    ("BOOL" "BOOL")

### the #52 boolean residual is closed -- arithmetic refuses

```scheme
(list (guard (e (e msg)) (+ #t 1)) (guard (e (Err kind-of e)) (< #f 3))
      (guard (e (lit R)) (* #t 2)))
```
---
    ("no + for BOOL" 'type 'R)

### everything identity-based is untouched

```scheme
(list #t #f (if #t 1 2) (if #f 1 2) (if () 1 2) (if 0 1 2)
      (not #f) (eq? #t #t) (eq? #t #f) (eq? #t 1) (boolean? #t) (boolean? 3))
```
---
    (#t #f 1 2 2 1 #t #t #f #f #t #f)

### match keeps #t as the default clause; dict still refuses boolean keys

```scheme
(do (import x/type/dict)
  (list (match (#f 1) (#t 42))
        (guard (e (Err kind-of e)) ((Dict make) set! #t 1))))
```
---
    (42 'type)

### printing round-trips

```scheme
(list (Str8 append "" (%display-to-str #t)) (Str8 append "" (%display-to-str #f)))
```
---
    ("#t" "#f")
