# Csv codec: RFC 4180 parse and emit (#372)
# @weight 1

Tables are rows of field STRINGS -- parse never guesses types. Quoted
fields carry commas, doubled quotes, and newlines; rows end at LF, CRLF,
or CR; strict per #61 on malformed quoting and record widths. The
records layer keys alists by the header row's strings ((Assoc find), the
equal?-keyed door).

## parse

### rows, quoting, escapes, embedded newlines, CRLF

```x
(do (import x/codec/csv)
  (list (Csv parse "a,b\n1,2\n")
        (Csv parse "a,\"b\"\"c\",d")
        (Csv parse "\"x\ny\",z\r\np,q\r\n")))
```
---
    ((("a" "b") ("1" "2")) (("a" "b\"c" "d")) (("x\ny" "z") ("p" "q")))

### empty fields, interior empty lines, empty text; a trailing newline adds no row

```x
(do (import x/codec/csv)
  (list (Csv parse "a,\n,b")
        (Csv parse "a\n\nb\n")
        (Csv parse "")))
```
---
    ((("a" "") ("" "b")) (("a") ("") ("b")) ())

## emit

### minimal quoting; hostile fields round-trip exactly

```x
(do (import x/codec/csv)
  (def rows (list (list "a,b" "c\"d" "e\nf") (list "" "plain" "q")))
  (list (Csv emit (list (list "a" "b")))
        (equal? (Csv parse (Csv emit rows)) rows)))
```
---
    ("a,b\n" #t)

## another separator

### parse-by and emit-by: a tab, a semicolon, a bar; the separator inside quotes; a comma is then a plain byte

```x
(do (import x/codec/csv)
  (list (Csv parse-by "\t" "a\tb\n1\t2\n")
        (Csv parse-by ";" "a;\"b;c\";d,e\n")
        (Csv emit-by "|" (list (list "a" "b|c" "d,e")))
        (equal? (Csv parse-by ";" (Csv emit-by ";" (list (list "x;y" "q\"r" "")))) (list (list "x;y" "q\"r" "")))
        (Csv parse "a;b,c")))
```
---
    ((("a" "b") ("1" "2")) (("a" "b;c" "d,e")) "a|\"b|c\"|d,e\n" #t (("a;b" "c")))

### a separator a field cannot be told from is refused

```x
(do (import x/codec/csv)
  (list (guard (e (Err label e)) (Csv parse-by "" "a"))
        (guard (e (Err label e)) (Csv parse-by "::" "a"))
        (guard (e (Err label e)) (Csv parse-by "\"" "a"))
        (guard (e (Err label e)) (Csv parse-by "\n" "a"))
        (guard (e (Err label e)) (Csv emit-by "\r" (list (list "a"))))))
```
---
    ('value 'value 'value 'value 'value)

## the records layer

### header-keyed alists in, explicit header order out

```x
(do (import x/codec/csv)
  (list (rest (Assoc find "age" (first (Csv records "name,age\nida,7\n"))))
        (Csv emit-records (list "a" "b")
             (list (list (pair "a" "1") (pair "b" "2"))))))
```
---
    ("7" "a,b\n1,2\n")

## strictness (#61)

### unclosed quotes, stray quotes, post-quote bytes, width mismatches, missing keys

```x
(do (import x/codec/csv)
  (list (guard (e (Err label e)) (Csv parse "\"unclosed"))
        (guard (e (Err label e)) (Csv parse "ab\"cd"))
        (guard (e (Err label e)) (Csv parse "\"ab\"x,c"))
        (guard (e (Err label e)) (Csv records "a,b\n1\n"))
        (guard (e (Err label e)) (Csv emit-records (list "a") (list ())))))
```
---
    ('value 'value 'value 'value 'value)
