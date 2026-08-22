# Conformance: strings, symbols and bytes (profile `core`)

Reached through the catalog, not through bare names: these namespaces are
de-registered, so `(%coord (lit str) (lit make))` is the door. There is no
`str=?` at this level -- string comparison is x-lang -- so equality is asserted
byte by byte, which is also the only way to observe a string without a printer.

A str value IS a C string by ruling: bytes past a NUL are unobservable. The cases
below stay inside that contract rather than probing past it.

### byte length counts bytes

covers: str/byte-len

```scheme
(def %len (%coord (lit str) (lit byte-len)))
(%ok (= (%len "hello") 5))
```
---
    *** ERROR: ok

### byte-ref yields a character, and char->int its code point

covers: str/byte-ref char/->int

```scheme
(def %ref (%coord (lit str) (lit byte-ref)))
(def %c2i (%coord (lit char) (lit ->int)))
(%ok (match ((= (%c2i (%ref "abc" 0)) 97) (= (%c2i (%ref "abc" 2)) 99)) (#t ())))
```
---
    *** ERROR: ok

### int->char is the inverse of char->int

covers: int/->char char/->int

```scheme
(def %c2i (%coord (lit char) (lit ->int)))
(def %i2c (%coord (lit int) (lit ->char)))
(%ok (= (%c2i (%i2c 65)) 65))
```
---
    *** ERROR: ok

### append concatenates

covers: str/append

```scheme
(def %app (%coord (lit str) (lit append)))
(def %len (%coord (lit str) (lit byte-len)))
(def %ref (%coord (lit str) (lit byte-ref)))
(def %c2i (%coord (lit char) (lit ->int)))
(def s (%app "ab" "cd"))
(%ok (match ((= (%len s) 4) (= (%c2i (%ref s 2)) 99)) (#t ())))
```
---
    *** ERROR: ok

### byte-sub's third argument is a LENGTH, not an end index

covers: str/byte-sub

`(str byte-sub s START LEN)`. The distinction is invisible at offset zero, where
a length and an end index coincide -- which is how `lib/x/codec/struct.x` shipped
with `(+ off n)` where `n` was wanted, over-reading by `off` bytes for every str
and cstr field at a non-zero offset. Writing this case is what found it. The
assertion below therefore uses a NON-ZERO start, deliberately: at offset 0 both
conventions pass and the case would prove nothing.

```scheme
(def %sub (%coord (lit str) (lit byte-sub)))
(def %len (%coord (lit str) (lit byte-len)))
(def %ref (%coord (lit str) (lit byte-ref)))
(def %c2i (%coord (lit char) (lit ->int)))
(def s (%sub "hello" 2 3))
(%ok (match ((= (%len s) 3) (match ((= (%c2i (%ref s 0)) 108) (= (%c2i (%ref s 2)) 111)) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### str->sym interns -- the result is eq? to the literal symbol

covers: str/->sym

Interning is what makes the catalog's pointer comparisons correct; an engine that
returned a fresh symbol would fail here and make every lookup in the library
quietly wrong.

```scheme
(def %s2y (%coord (lit str) (lit ->sym)))
(%ok (eq? (%s2y "alpha") (lit alpha)))
```
---
    *** ERROR: ok

### sym->str recovers the name

covers: sym/->str

```scheme
(def %y2s (%coord (lit sym) (lit ->str)))
(def %len (%coord (lit str) (lit byte-len)))
(def %ref (%coord (lit str) (lit byte-ref)))
(def %c2i (%coord (lit char) (lit ->int)))
(def s (%y2s (lit abc)))
(%ok (match ((= (%len s) 3) (= (%c2i (%ref s 0)) 97)) (#t ())))
```
---
    *** ERROR: ok

### bytes->str builds a string from a byte list

covers: bytes/->str

```scheme
(def %b2s (%coord (lit bytes) (lit ->str)))
(def %len (%coord (lit str) (lit byte-len)))
(def %ref (%coord (lit str) (lit byte-ref)))
(def %c2i (%coord (lit char) (lit ->int)))
(def s (%b2s (pair 97 (pair 98 ()))))
(%ok (match ((= (%len s) 2) (= (%c2i (%ref s 1)) 98)) (#t ())))
```
---
    *** ERROR: ok

### str make allocates a writable region

covers: str/make

```scheme
(def %mk (%coord (lit str) (lit make)))
(def %p (%coord (lit str) (lit ->ptr)))
(%ok (match ((eq? (%mk 8) ()) ()) (#t (match ((eq? (%p (%mk 8)) ()) ()) (#t 1)))))
```
---
    *** ERROR: ok

### str->ptr addresses the region

covers: str/->ptr ptr/->str

```scheme
(def %p (%coord (lit str) (lit ->ptr)))
(def %p2s (%coord (lit ptr) (lit ->str)))
(def %len (%coord (lit str) (lit byte-len)))
(%ok (= (%len (%p2s (%p "round"))) 5))
```
---
    *** ERROR: ok
