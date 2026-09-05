# Conformance: a value carries its base's type (profile `core`)

Allocation stamps a value with the type registered in the base that
allocates it: the kind's type is found in that base's type-alist, or
built and filed there. Dispatch reads the value's stamp, not the base
it is evaluated in.

The type word is found by probing, not by a committed offset: it is the
header word two values of one kind share and a value of another kind
does not. The word holds the type's address, which `ptr ->int` of
`obj ->ptr` on an alist entry's rest reproduces.

### values from different bases carry different stamps

covers: base/make base/eval obj/->ptr ptr/ref-word

Two values a child base allocates share one stamp, and it is not the
host's.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %prw (%coord (lit ptr) (lit ref-word)))
(def %bmake (%coord (lit base) (lit make)))
(def %beval (%coord (lit base) (lit eval)))
(def a 7)
(def c 9)
(def %same-w (fn (_ x y i) (eq? (%prw (%o2p x) i) (%prw (%o2p y) i))))
(def %tslot
  (fn (self i)
    (match ((eq? i 48) (error "type-word-not-found"))
           ((match ((%same-w a c i) (match ((%same-w a "zz" i) #f) (#t #t))) (#t #f)) i)
           (#t (self (+ i 8))))))
(def ts (%tslot 0))
(def %tw (fn (_ o) (%prw (%o2p o) ts)))
(def b (%bmake))
(def v1 (%beval b (lit (+ 2 3))))
(def v2 (%beval b (lit (+ 4 5))))
(def hostv (+ 1 2))
(match ((eq? v1 5) ()) (#t (error "child-eval-broken")))
(match ((eq? (%tw v1) (%tw v2)) ()) (#t (error "child-stamps-disagree")))
(match ((eq? (%tw v1) (%tw hostv)) (error "SHARED-STAMP")) (#t (error "PER-BASE-STAMP")))
```
---
    *** ERROR: PER-BASE-STAMP

### the stamp is registered in the allocating base

covers: base/make base/eval obj/->ptr ptr/ref-word ptr/->int

A value's type word is the address of a type filed in the allocating
base's type-alist — the child's in the child's, the host's in the
host's, and the child's in neither's parent.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %prw (%coord (lit ptr) (lit ref-word)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %bmake (%coord (lit base) (lit make)))
(def %beval (%coord (lit base) (lit eval)))
(def a 7)
(def c 9)
(def %same-w (fn (_ x y i) (eq? (%prw (%o2p x) i) (%prw (%o2p y) i))))
(def %tslot
  (fn (self i)
    (match ((eq? i 48) (error "type-word-not-found"))
           ((match ((%same-w a c i) (match ((%same-w a "zz" i) #f) (#t #t))) (#t #f)) i)
           (#t (self (+ i 8))))))
(def ts (%tslot 0))
(def %tw (fn (_ o) (%prw (%o2p o) ts)))
(def b (%bmake))
(def v1 (%beval b (lit (+ 2 3))))
(def hostv (+ 1 2))
(def %tal (fn (_ bb) (first (%walk (rest (rest (%assoc (lit type-alist) %base-paths))) bb))))
(def %mem (fn (self al w) (match ((eq? al ()) #f) ((eq? (%p2i (%o2p (rest (first al)))) w) #t) (#t (self (rest al) w)))))
(match ((%mem (%tal (%base)) (%tw hostv)) ()) (#t (error "host-stamp-unregistered")))
(match ((%mem (%tal b) (%tw v1)) ()) (#t (error "child-stamp-unregistered")))
(match ((%mem (%tal (%base)) (%tw v1)) (error "CHILD-IN-HOST-ALIST")) (#t (error "DISJOINT-STAMPS")))
```
---
    *** ERROR: DISJOINT-STAMPS

### dispatch follows the stamp

covers: type/make type/make-instance base/make base/eval eval

A made type's instance answers its `eval` handler in whichever base
evaluates it.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def %bmake (%coord (lit base) (lit make)))
(def %beval (%coord (lit base) (lit eval)))
(def h (%tmake "CONF-STAMP" (pair (pair (lit eval) (op (x) e 41)) ())))
(def i (%minst h 7))
(def b (%bmake))
(match ((eq? (%beval b i) 41) (error "STAMP-GOVERNS")) (#t (error "BASE-GOVERNS")))
```
---
    *** ERROR: STAMP-GOVERNS
