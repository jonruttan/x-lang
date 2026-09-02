# Conformance: the machine ops through the CATALOG door (profile `core`)

The same primitives `core/arithmetic.spec.md` reaches by their bare names, reached
instead by their catalog coordinates. These are two genuinely different doors and
the library uses both: hot paths fetch `(prim-ref 'int '+)` once and call the value
directly, precisely to skip the bare binding's lookup.

An engine could plausibly bind the bare names and forget to file the coordinates,
or file them under the wrong namespace, and every test written against bare names
would still pass while every de-dispatched hot path in the library broke.

### every arithmetic coordinate is filed and agrees with its bare binding

covers: int/+ int/- int/* int// int/%

```x
(def %p (fn (self m) (%coord (lit int) m)))
(%ok (match ((= ((%p (lit +)) 2 3) (+ 2 3))
             (match ((= ((%p (lit -)) 9 4) (- 9 4))
                     (match ((= ((%p (lit *)) 6 7) (* 6 7))
                             (match ((= ((%p (lit /)) 7 2) (/ 7 2))
                                     (= ((%p (lit %)) 7 2) (% 7 2)))
                                    (#t ())))
                            (#t ())))
                    (#t ())))
            (#t ())))
```
---
    *** ERROR: ok

### every bitwise coordinate is filed and agrees with its bare binding

covers: int/& int/| int/^ int/~ int/<< int/>>

```x
(def %p (fn (self m) (%coord (lit int) m)))
(%ok (match ((= ((%p (lit &)) 12 10) (& 12 10))
             (match ((= ((%p (lit |)) 12 10) (| 12 10))
                     (match ((= ((%p (lit ^)) 12 10) (^ 12 10))
                             (match ((= ((%p (lit ~)) 0) (~ 0))
                                     (match ((= ((%p (lit <<)) 1 4) (<< 1 4))
                                             (= ((%p (lit >>)) 16 4) (>> 16 4)))
                                            (#t ())))
                                    (#t ())))
                            (#t ())))
                    (#t ())))
            (#t ())))
```
---
    *** ERROR: ok

### the comparison coordinates are filed

covers: int/< int/=

```x
(def %lt (%coord (lit int) (lit <)))
(def %eqn (%coord (lit int) (lit =)))
(%ok (match ((%lt 1 2) (match ((%eqn 2 2) (match ((%lt 2 1) ()) (#t 1))) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### call/cc is filed under ctrl as well as bound bare

covers: ctrl/call/cc

```x
(def %cc (%coord (lit ctrl) (lit call/cc)))
(%ok (= (%cc (fn (self k) (k 12))) 12))
```
---
    *** ERROR: ok
