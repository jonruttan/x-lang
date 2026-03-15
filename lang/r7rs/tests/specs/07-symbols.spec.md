## symbol?

### symbol? on symbol

```scheme
(symbol? (quote foo))
```
---
    #t

### symbol? on string

```scheme
(not (symbol? "foo"))
```
---
    #t

### symbol? on number

```scheme
(not (symbol? 42))
```
---
    #t

### symbol? on list

```scheme
(not (symbol? (list 1 2)))
```
---
    #t

### symbol? on boolean

```scheme
(not (symbol? #t))
```
---
    #t

## symbol=?

### symbol=? same symbols

```scheme
(symbol=? (quote a) (quote a))
```
---
    #t

### symbol=? different symbols

```scheme
(not (symbol=? (quote a) (quote b)))
```
---
    #t

## symbol conversion

### symbol->string

```scheme
(symbol->string (quote hello))
```
---
    "hello"

### string->symbol

```scheme
(eq? (string->symbol "hello") (quote hello))
```
---
    #t

### roundtrip symbol->string->symbol

```scheme
(eq? (string->symbol (symbol->string (quote foo))) (quote foo))
```
---
    #t

