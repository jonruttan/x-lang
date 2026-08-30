# Csv codec: RFC 4180 parse and emit (#372)
# @weight 1

Tables are rows of field STRINGS -- parse never guesses types. Quoted
fields carry commas, doubled quotes, and newlines; rows end at LF, CRLF,
or CR; strict per #61 on malformed quoting and record widths. The
records tier keys alists by the header row's strings ((Assoc find), the
equal?-keyed door).

## parse

### rows, quoting, escapes, embedded newlines, CRLF

```scheme
(do (import x/codec/csv)
  (list (Csv parse "a,b\n1,2\n")
        (Csv parse "a,\"b\"\"c\",d")
        (Csv parse "\"x\ny\",z\r\np,q\r\n")))
```
---
    ((("a" "b") ("1" "2")) (("a" "b\"c" "d")) (("x\ny" "z") ("p" "q")))

### empty fields, interior empty lines, empty text; a trailing newline adds no row

```scheme
(do (import x/codec/csv)
  (list (Csv parse "a,\n,b")
        (Csv parse "a\n\nb\n")
        (Csv parse "")))
```
---
    ((("a" "") ("" "b")) (("a") ("") ("b")) ())

## emit

### minimal quoting; hostile fields round-trip exactly

```scheme
(do (import x/codec/csv)
  (def rows (list (list "a,b" "c\"d" "e\nf") (list "" "plain" "q")))
  (list (Csv emit (list (list "a" "b")))
        (equal? (Csv parse (Csv emit rows)) rows)))
```
---
    ("a,b\n" #t)

## the records tier

### header-keyed alists in, explicit header order out

```scheme
(do (import x/codec/csv)
  (list (rest (Assoc find "age" (first (Csv records "name,age\nida,7\n"))))
        (Csv emit-records (list "a" "b")
             (list (list (pair "a" "1") (pair "b" "2"))))))
```
---
    ("7" "a,b\n1,2\n")

## strictness (#61)

### unclosed quotes, stray quotes, post-quote bytes, width mismatches, missing keys

```scheme
(do (import x/codec/csv)
  (list (guard (e (Err kind-of e)) (Csv parse "\"unclosed"))
        (guard (e (Err kind-of e)) (Csv parse "ab\"cd"))
        (guard (e (Err kind-of e)) (Csv parse "\"ab\"x,c"))
        (guard (e (Err kind-of e)) (Csv records "a,b\n1\n"))
        (guard (e (Err kind-of e)) (Csv emit-records (list "a") (list ())))))
```
---
    ('value 'value 'value 'value 'value)
