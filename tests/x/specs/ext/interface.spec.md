# Interface (contract) enforcement
# @weight 1

A class declares the methods its concrete subclasses must provide with
`(interface …)`. The declaring class is abstract; a concrete subclass is checked
at `def-class` time and must implement every inherited interface method (as an
instance OR static method). A miss errors at definition, not at call time.

### an interface-declaring class is abstract and defines fine

```x
(do (def-class Drawable () (interface draw)) (class? Drawable))
```
---
    #t

### a subclass that implements the interface (instance method) defines fine

```x
(do
  (def-class Drawable () (interface draw))
  (def-class Square (extends Drawable) (method draw (self) "[]"))
  (class? Square))
```
---
    #t

### a subclass that implements it as a static method also passes

```x
(do
  (def-class Codec () (interface encode))
  (def-class Hex (extends Codec) (static (method encode (self x) x)))
  (class? Hex))
```
---
    #t

### a concrete subclass missing an interface method is rejected at def-class

```x
(guard (e "rejected")
  (do
    (def-class Shape () (interface area))
    (def-class Circle (extends Shape))
    "accepted"))
```
---
    "rejected"
