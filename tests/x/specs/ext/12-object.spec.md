# Object System

Message-passing objects: `(obj selector args...)`. The selector is a literal
member name (no quote needed) -- a method wins, otherwise it is a field that
`(obj f)` reads and `(obj f v)` writes. `new` takes literal field names.

## def-class / new

### a method reads fields via (self x)

```x
(do
  (def-class Point () (fields x y)
    (method dist (self) (+ (self x) (self y))))
  (def p (new Point x 3 y 4))
  (p dist))
```
---
    7

### a field reads via dispatch, defaulting to nil

```x
(do
  (def-class Box () (fields v))
  (null? ((new Box) v)))
```
---
    #t

### getter then setter

```x
(do
  (def-class P () (fields x))
  (def p (new P x 5))
  (p x 10)
  (p x))
```
---
    10

## field mutation

### a method mutates state with (self f v)

```x
(do
  (def-class Counter () (fields n)
    (method bump (self) (self n (+ (self n) 1)))
    (method val (self) (self n)))
  (def c (new Counter n 0))
  (c bump)
  (c bump)
  (c bump)
  (c val))
```
---
    3

## method overrides field

### a method shadows a field; a method can still reach the raw value

```x
(do
  (def-class Secret () (fields code)
    (method code (self) 'hidden)            ; public getter hides the field
    (method raw (self) (field 'code)))      ; method-internal raw access
  (def s (new Secret code 42))
  (list (s code) (s raw)))
```
---
    ((lit hidden) 42)

### raw field access is not available from outside the object

```x
(do
  (def-class P () (fields x))
  (def p (new P x 5))
  (guard (e 'blocked) (%field p 'x)))
```
---
    (lit blocked)

## inheritance

### a subclass inherits a parent method

```x
(do
  (def-class A () (fields) (method greet (self) 42))
  (def-class B (extends A) (fields))
  ((new B) greet))
```
---
    42

### an override can call super

```x
(do
  (def-class A () (fields v)
    (method total (self) (self v)))
  (def-class B (extends A) (fields w)
    (method total (self) (+ (super self total) (self w))))
  ((new B v 10 w 5) total))
```
---
    15

## introspection

### object? and instance-of? walk the inheritance chain

```x
(do
  (def-class A () (fields))
  (def-class B (extends A) (fields))
  (list (object? (new A)) (instance-of? (new B) A) (instance-of? (new A) B)))
```
---
    (#t #t #f)

### class-name returns the class symbol

```x
(do
  (def-class Widget () (fields))
  (class-name (new Widget)))
```
---
    (lit Widget)

## write handler

### instances print as #<Class field=value ...>

```x
(do
  (def-class Point () (fields x y))
  (write (new Point x 1 y 2)))
```
---
    #<Point x=1 y=2>

## classes are objects

### static methods and a class-wide member

```x
(do
  (def-class Math ()
    (static (base 10)
      (method square (self n) (* n n))
      (method scaled (self n) (* n (self base)))))
  (list (Math square 5) (Math scaled 3) (Math base)))
```
---
    (25 30 10)

### a class-wide member is mutable

```x
(do
  (def-class Counter ()
    (static (n 0) (method bump (self) (self n (+ (self n) 1)))))
  (Counter bump)
  (Counter bump)
  (Counter n))
```
---
    2

### (Class new ...) instantiates, like the global new

```x
(do
  (def-class P () (fields x) (method g (self) (self x)))
  ((P new x 7) g))
```
---
    7

### static methods are inherited

```x
(do
  (def-class Base () (static (method greet (self) 'hi)))
  (def-class Sub (extends Base) (fields))
  (Sub greet))
```
---
    (lit hi)

### class? distinguishes classes from instances; classes print as #<class N>

```x
(do
  (def-class Widget () (fields))
  (list (class? Widget) (class? (new Widget)) (class-name Widget)))
```
---
    (#t #f (lit Widget))

## errors

### an unknown member on an instance is an error

```x
(do
  (def-class P () (fields x))
  (guard (e 'no-member) ((new P x 1) bogus)))
```
---
    (lit no-member)

### an unknown static member on a class is an error

```x
(do
  (def-class C () (static (n 1)))
  (guard (e 'no-static) (C bogus)))
```
---
    (lit no-static)

### super with no parent method is an error

```x
(do
  (def-class A () (method m (self) (super self nope)))
  (guard (e 'no-super) ((new A) m)))
```
---
    (lit no-super)

## edge cases

### a quoted selector is unwrapped: (obj 'name) equals (obj name)

```x
(do
  (def-class P () (fields x))
  (def p (new P x 9))
  (list (p x) (p 'x)))
```
---
    (9 9)

### instances have independent field state

```x
(do
  (def-class P () (fields x))
  (def a (new P x 1))
  (def b (new P x 2))
  (a x 100)
  (list (a x) (b x)))
```
---
    (100 2)

### a method calls another method via self

```x
(do
  (def-class P () (fields x)
    (method double (self) (* 2 (self get)))
    (method get (self) (self x)))
  ((new P x 5) double))
```
---
    10

### method-internal (set-field! 'f v) writes the field raw

```x
(do
  (def-class P () (fields x)
    (method reset (self) (set-field! 'x 0) self)
    (method get (self) (field 'x)))
  (def p (new P x 99))
  (p reset)
  (p get))
```
---
    0

## deeper inheritance

### method lookup and instance-of? span a three-level chain

```x
(do
  (def-class A () (method who (self) 'a))
  (def-class B (extends A) (fields))
  (def-class C (extends B) (fields))
  (def c (new C))
  (list (c who) (instance-of? c A)))
```
---
    ((lit a) #t)

## classes as namespaces

### class-of returns the callable class; statics work through it

```x
(do
  (def-class K () (static (tag 'kk)))
  ((class-of (new K)) tag))
```
---
    (lit kk)

### class-wide members hold strings and symbols

```x
(do
  (def-class App () (static (label "x-lang") (kind 'lang)))
  (list (App label) (App kind)))
```
---
    ("x-lang" (lit lang))

## super correctness

### super from an inherited method resolves to the defining class's parent

```x
(do
  (def-class A () (fields) (method m (self) 1))
  (def-class B (extends A) (fields) (method m (self) (+ 10 (super self m))))
  (def-class C (extends B) (fields))
  ((new C) m))
```
---
    11

### super outside an instance method is an error

```x
(do
  (def-class C () (static (method s (self) (super self x))))
  (guard (e 'bad-super) (C s)))
```
---
    (lit bad-super)

## validation and guards

### an unknown def-class body form is an error

```x
(guard (e 'bad-form) (def-class P () (feilds x)))
```
---
    (lit bad-form)

### class-of requires an instance, not a class

```x
(do
  (def-class C () (fields))
  (guard (e 'not-inst) (class-of C)))
```
---
    (lit not-inst)

## method-ref (method as a value)

### a static method becomes a callable usable with map

```x
(do
  (def-class M () (static (method dbl (self n) (* n 2))))
  (map (method-ref M dbl) (list 1 2 3)))
```
---
    (2 4 6)

### method-ref forwards multiple args

```x
(do
  (def-class M () (static (method add3 (self a b c) (+ a b c))))
  ((method-ref M add3) 10 20 30))
```
---
    60

### method-ref works on an instance method

```x
(do
  (def-class P () (fields x) (method get (self) (self x)))
  ((method-ref (new P x 7) get)))
```
---
    7

### a bare zero-arg static call still runs (not turned into a value)

```x
(do
  (def-class K () (static (n 0) (method bump (self) (self n (+ (self n) 1)))))
  (K bump)
  (K bump)
  (K n))
```
---
    2
