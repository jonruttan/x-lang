# Json: parse and emit

Objects are Dicts, arrays are lists, null is the symbol `null`.
`(import x/codec/json)` per test -- not in the x-core boot.

## parse: scalars

### integers

```scheme
(do (import x/codec/json) (Json parse "42"))
```
---
    42

### negative integers

```scheme
(do (import x/codec/json) (Json parse "-7"))
```
---
    -7

### decimals parse as floats

```scheme
(do (import x/codec/json) (Json parse "2.5"))
```
---
    2.5

### exponents parse as floats (and keep their point, #45 R4)

```scheme
(do (import x/codec/json)
  (let ((v (Json parse "1e3"))) (list (Type name v) v)))
```
---
    ("FLOAT" 1000.0)

### true / false / null

```scheme
(do (import x/codec/json)
  (list (Json parse "true") (Json parse "false") (Json parse "null")))
```
---
    (#t #f 'null)

### strings

```scheme
(do (import x/codec/json) (Json parse "\"hello\""))
```
---
    "hello"

## parse: escapes

### quote and backslash escapes

```scheme
(do (import x/codec/json) (Json parse "\"a\\\"b\\\\c\""))
```
---
    "a\"b\\c"

### newline and tab escapes land as real bytes

```scheme
(do (import x/codec/json)
  (map (method-ref Char ->int) (str->list (Json parse "\"a\\n\\tb\""))))
```
---
    (97 10 9 98)

### unicode escape decodes to UTF-8

```scheme
(do (import x/codec/json) (Json parse "\"\\u00e9\""))
```
---
    "é"

### surrogate pairs combine

```scheme
(do (import x/codec/json)
  (StrUTF8 length (Json parse "\"\\ud83d\\ude00\"")))
```
---
    1

### raw UTF-8 passes through

```scheme
(do (import x/codec/json) (Json parse "\"café\""))
```
---
    "café"

## parse: arrays and objects

### arrays become lists in order

```scheme
(do (import x/codec/json) (Json parse "[1, 2, 3]"))
```
---
    (1 2 3)

### empty array

```scheme
(do (import x/codec/json) (null? (Json parse "[]")))
```
---
    #t

### nested arrays

```scheme
(do (import x/codec/json) (Json parse "[[1],[2,[3]]]"))
```
---
    ((1) (2 (3)))

### objects become Dicts with string keys

```scheme
(do (import x/codec/json)
  ((Json parse "{\"name\": \"x\", \"n\": 3}") get "name"))
```
---
    "x"

### empty object

```scheme
(do (import x/codec/json) ((Json parse "{}") empty?))
```
---
    #t

### nested structure end to end

```scheme
(do (import x/codec/json)
  (let ((v (Json parse "{\"xs\": [1, {\"y\": true}], \"z\": null}")))
    (list ((first (rest (v get "xs"))) get "y") (v get "z"))))
```
---
    (#t 'null)

### duplicate keys: last wins

```scheme
(do (import x/codec/json) ((Json parse "{\"a\":1,\"a\":2}") get "a"))
```
---
    2

## parse: errors

### trailing content errors

```scheme
(do (import x/codec/json) (Json parse "1 2"))
```
---
    Error: Json parse: trailing content at byte 1

### unterminated string errors

```scheme
(do (import x/codec/json) (Json parse "\"abc"))
```
---
    Error: Json parse: unterminated string at byte 4

### bad literal errors

```scheme
(do (import x/codec/json) (Json parse "nulL"))
```
---
    Error: Json parse: unknown literal at byte 0

## emit

### scalars

```scheme
(do (import x/codec/json)
  (list (Json emit 42) (Json emit #t) (Json emit #f) (Json emit 'null)))
```
---
    ("42" "true" "false" "null")

### floats emit their decimal form

```scheme
(do (import x/codec/json) (Json emit (Json parse "2.5")))
```
---
    "2.5"

### strings escape quotes and backslashes (the logo/json.x gap)

```scheme
(do (import x/codec/json) (Json emit "a\"b\\c"))
```
---
    "\"a\\\"b\\\\c\""

### control bytes escape

```scheme
(do (import x/codec/json)
  (Json emit (bytes->str (list 104 10 105))))
```
---
    "\"h\\ni\""

### lists emit as arrays

```scheme
(do (import x/codec/json) (Json emit (list 1 2 (list 3))))
```
---
    "[1,2,[3]]"

### dicts emit as objects

```scheme
(do (import x/codec/json)
  (let ((d (Dict make))) (d put! "k" 1) (Json emit d)))
```
---
    "{\"k\":1}"

### rationals refuse politely

```scheme
(do (import x/codec/json) (import x/num/rational)
  (Json emit (/ 1 2)))
```
---
    Error: Json emit: no JSON form for a rational (convert to a float first)

## roundtrips

### parse . emit is identity on compact text (single key: Dict order is unordered)

```scheme
(do (import x/codec/json)
  (Json emit (Json parse "{\"a\":[1,true,null]}")))
```
---
    "{\"a\":[1,true,null]}"

### emit . parse preserves values

```scheme
(do (import x/codec/json)
  (let ((v (Json parse (Json emit (list 1 "two" #t 'null)))))
    v))
```
---
    (1 "two" #t 'null)
