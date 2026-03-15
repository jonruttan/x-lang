# String stress tests

## string-append stress

### append many strings

```scheme
(define (repeat s n) (let loop ((i n) (acc "")) (if (= i 0) acc (loop (- i 1) (string-append acc s))))) (string-length (repeat "ab" 500))
```
---
    1000

## string->list stress

### large string to list

```scheme
(length (string->list (make-string 2000 #\x)))
```
---
    2000

## string round-trip stress

### list->string -> string->list identity

```scheme
(define (iota-chars n) (let loop ((i 0) (acc '())) (if (= i n) (reverse acc) (loop (+ i 1) (cons (integer->char (+ 65 (modulo i 26))) acc))))) (let ((chars (iota-chars 1000))) (equal? (string->list (list->string chars)) chars))
```
---
    #t

## substring stress

### many substrings

```scheme
(define s (make-string 1000 #\a)) (let loop ((i 0) (count 0)) (if (= i 500) count (loop (+ i 1) (+ count (string-length (substring s i (+ i 2)))))))
```
---
    1000
