## bytevector?

### bytevector predicate true

```scheme
(bytevector? (bytevector 1 2 3))
```
---
    #t

### bytevector predicate false

```scheme
(bytevector? (list 1 2 3))
```
---
    #f

## bytevector

### create bytevector

```scheme
(bytevector 1 2 3)
```
---
    #u8(1 2 3)

### empty bytevector

```scheme
(bytevector)
```
---
    #u8()

## make-bytevector

### make-bytevector with default fill

```scheme
(make-bytevector 3)
```
---
    #u8(0 0 0)

### make-bytevector with fill

```scheme
(make-bytevector 4 7)
```
---
    #u8(7 7 7 7)

### make-bytevector zero length

```scheme
(make-bytevector 0)
```
---
    #u8()

## bytevector-length

### length of bytevector

```scheme
(bytevector-length (bytevector 10 20 30))
```
---
    3

### length of empty bytevector

```scheme
(bytevector-length (bytevector))
```
---
    0

## bytevector-u8-ref

### ref first element

```scheme
(bytevector-u8-ref (bytevector 10 20 30) 0)
```
---
    10

### ref last element

```scheme
(bytevector-u8-ref (bytevector 10 20 30) 2)
```
---
    30

## bytevector-u8-set!

### set element

```scheme
(define bv (bytevector 1 2 3))
(bytevector-u8-set! bv 1 99)
bv
```
---
    #u8(1 99 3)

## bytevector-copy

### copy whole bytevector

```scheme
(define bv (bytevector 1 2 3 4 5))
(bytevector-copy bv)
```
---
    #u8(1 2 3 4 5)

### copy with start

```scheme
(bytevector-copy (bytevector 1 2 3 4 5) 2)
```
---
    #u8(3 4 5)

### copy with start and end

```scheme
(bytevector-copy (bytevector 1 2 3 4 5) 1 3)
```
---
    #u8(2 3)

## bytevector-copy!

### copy into target

```scheme
(define to (bytevector 0 0 0 0 0))
(define from (bytevector 10 20 30))
(bytevector-copy! to 1 from)
to
```
---
    #u8(0 10 20 30 0)

## bytevector-append

### append two bytevectors

```scheme
(bytevector-append (bytevector 1 2) (bytevector 3 4))
```
---
    #u8(1 2 3 4)

### append three bytevectors

```scheme
(bytevector-append (bytevector 1) (bytevector 2 3) (bytevector 4 5 6))
```
---
    #u8(1 2 3 4 5 6)

### append empty

```scheme
(bytevector-append (bytevector 1 2) (bytevector))
```
---
    #u8(1 2)

## utf8->string

### basic conversion

```scheme
(utf8->string (bytevector 104 101 108 108 111))
```
---
    hello

### conversion with range

```scheme
(utf8->string (bytevector 104 101 108 108 111) 1 4)
```
---
    ell

## string->utf8

### basic conversion

```scheme
(string->utf8 "hello")
```
---
    #u8(104 101 108 108 111)

### conversion with range

```scheme
(string->utf8 "hello" 1 3)
```
---
    #u8(101 108)
