# Object System

Message-passing objects: `(obj selector args...)`. The selector is a literal
member name (no quote needed) -- a method wins, otherwise it is a field that
`(obj f)` reads and `(obj f v)` writes. `new` takes literal field names.

## def-class / new

### a method reads fields via (self x)

```x
(do
  (def-class Point () x y
    (method dist (self) (+ (self x) (self y))))
  (def p (new Point x 3 y 4))
  (p dist))
```
---
    7

### a field reads via dispatch, defaulting to nil

```x
(do
  (def-class Box () v)
  (null? ((new Box) v)))
```
---
    #t

### getter then setter

```x
(do
  (def-class P () x)
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
  (def-class Counter () n
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
  (def-class Secret () code
    (method code (self) 'hidden)            ; public getter hides the field
    (method raw (self) (member 'code)))      ; method-internal raw access
  (def s (new Secret code 42))
  (list (s code) (s raw)))
```
---
    ((lit hidden) 42)

### raw field access is not available from outside the object

```x
(do
  (def-class P () x)
  (def p (new P x 5))
  (guard (e 'blocked) (%member p 'x)))
```
---
    (lit blocked)

## inheritance

### a subclass inherits a parent method

```x
(do
  (def-class A () (method greet (self) 42))
  (def-class B (extends A))
  ((new B) greet))
```
---
    42

### an override can call super

```x
(do
  (def-class A () v
    (method total (self) (self v)))
  (def-class B (extends A) w
    (method total (self) (+ (super self total) (self w))))
  ((new B v 10 w 5) total))
```
---
    15

## introspection

### object? and instance-of? walk the inheritance chain

```x
(do
  (def-class A ())
  (def-class B (extends A))
  (list (object? (new A)) (instance-of? (new B) A) (instance-of? (new A) B)))
```
---
    (#t #t #f)

### class-name returns the class symbol

```x
(do
  (def-class Widget ())
  (class-name (new Widget)))
```
---
    (lit Widget)

### class-parent returns the extended class, nil at the root

```x
(do
  (def-class A ())
  (def-class B (extends A))
  (list (same? (class-parent B) A) (null? (class-parent A))))
```
---
    (#t #t)

## write handler

### instances print as #<Class field=value ...>

```x
(do
  (def-class Point () x y)
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
  (def-class P () x (method g (self) (self x)))
  ((P new x 7) g))
```
---
    7

### static methods are inherited

```x
(do
  (def-class Base () (static (method greet (self) 'hi)))
  (def-class Sub (extends Base))
  (Sub greet))
```
---
    (lit hi)

### class? distinguishes classes from instances; classes print as #<class N>

```x
(do
  (def-class Widget ())
  (list (class? Widget) (class? (new Widget)) (class-name Widget)))
```
---
    (#t #f (lit Widget))

## errors

### an unknown member on an instance is an error

```x
(do
  (def-class P () x)
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
  (def-class P () x)
  (def p (new P x 9))
  (list (p x) (p 'x)))
```
---
    (9 9)

### instances have independent field state

```x
(do
  (def-class P () x)
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
  (def-class P () x
    (method double (self) (* 2 (self get)))
    (method get (self) (self x)))
  ((new P x 5) double))
```
---
    10

### method-internal (set-member! 'f v) writes the member raw

```x
(do
  (def-class P () x
    (method reset (self) (set-member! 'x 0) self)
    (method get (self) (member 'x)))
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
  (def-class B (extends A))
  (def-class C (extends B))
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

## member defaults and descriptions

### an instance member's value defaults to its declaration

```x
(do
  (def-class C () (n 5))
  ((new C) n))
```
---
    5

### new overrides a member's default

```x
(do
  (def-class C () (n 5))
  ((new C n 9) n))
```
---
    9

### a member description does not affect its value

```x
(do
  (def-class C () (n 5 "the running count"))
  (def-class K () (static (LIMIT 100 "max before reset")))
  (list ((new C) n) (K LIMIT)))
```
---
    (5 100)

## super correctness

### super from an inherited method resolves to the defining class's parent

```x
(do
  (def-class A () (method m (self) 1))
  (def-class B (extends A) (method m (self) (+ 10 (super self m))))
  (def-class C (extends B))
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

### the removed (fields ...) wrapper is a helpful error

```x
(guard (e 'bad-form) (def-class P () (fields x)))
```
---
    (lit bad-form)

### class-of requires an instance, not a class

```x
(do
  (def-class C ())
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
  (def-class P () x (method get (self) (self x)))
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

## new-from -- construct from a data store

`new-from` is the applicative counterpart to the `new` operative: its store is
evaluated (it is a `fn` arg) and the values are used as-is, never re-evaluated.
It accepts an alist `((k . v) ...)` or a flat plist `(k v ...)`.

### new-from reads a quoted plist

```x
(do
  (def-class Point () x y)
  (def p (new-from Point '(x 3 y 4)))
  (list (p x) (p y)))
```
---
    (3 4)

### new-from reads a quoted alist

```x
(do
  (def-class Point () x y)
  (def p (new-from Point '((x . 3) (y . 4))))
  (list (p x) (p y)))
```
---
    (3 4)

### new-from uses values as-is (no re-evaluation)

```x
(do
  (def-class Box () v)
  ((new-from Box (list (lit v) (list 1 2 3))) v))
```
---
    (1 2 3)

### new-from falls back to declared defaults for absent keys

```x
(do
  (def-class Point () (x 0) (y 0))
  ((new-from Point '(x 7)) y))
```
---
    0

### new also accepts a dotted-alist inline form

```x
(do
  (def-class Point () x y)
  ((new Point (x . 3) (y . 4)) x))
```
---
    3

### quoting new's member names errors cleanly (use bare names)

```x
(do
  (def-class Point () x y)
  (guard (e (lit caught)) (new Point 'x 1 'y 2)))
```
---
    (lit caught)

### a malformed new-from store errors cleanly (caught, not a crash)

```x
(do
  (def-class Point () x y)
  (guard (e (lit caught)) (new-from Point 'notalist)))
```
---
    (lit caught)
