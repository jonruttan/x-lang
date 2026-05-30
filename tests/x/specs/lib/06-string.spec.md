## str-empty?

### true for empty string

```scheme
(str-empty? "")
```
---
    #t

### false for non-empty

```scheme
(if (str-empty? "hi") "y" "n")
```
---
    "n"

## str-join

### joins with separator

```scheme
(str-join ", " (list "a" "b" "c"))
```
---
    "a, b, c"

### joins single element

```scheme
(str-join ", " (list "a"))
```
---
    "a"

### joins empty list

```scheme
(str-join ", " ())
```
---
    ""

## str-repeat

### repeats a string

```scheme
(str-repeat "ab" 3)
```
---
    "ababab"

### repeats zero times

```scheme
(str-repeat "ab" 0)
```
---
    ""

## str-contains?

### finds substring

```scheme
(str-contains? "ll" "hello")
```
---
    #t

### returns nil for missing

```scheme
(if (str-contains? "xyz" "hello") "y" "n")
```
---
    "n"

### empty substring always found

```scheme
(str-contains? "" "hello")
```
---
    #t

## str-starts?

### true when starts with prefix

```scheme
(str-starts? "he" "hello")
```
---
    #t

### false for non-prefix

```scheme
(if (str-starts? "lo" "hello") "y" "n")
```
---
    "n"

## str-ends?

### true when ends with suffix

```scheme
(str-ends? "lo" "hello")
```
---
    #t

### false for non-suffix

```scheme
(if (str-ends? "he" "hello") "y" "n")
```
---
    "n"

## str-reverse

### reverses a string

```scheme
(str-reverse "hello")
```
---
    "olleh"

### reverses empty string

```scheme
(str-reverse "")
```
---
    ""

### reverses by code point

```scheme
(str-reverse "héllo€")
```
---
    "€olléh"


## str

### concatenates strings

```scheme
(str "hello" " " "world")
```
---
    "hello world"

### single string

```scheme
(str "abc")
```
---
    "abc"

### empty strings

```scheme
(str "" "x" "")
```
---
    "x"

### many arguments

```scheme
(str "a" "b" "c" "d")
```
---
    "abcd"

## make-str

### creates string of spaces

```scheme
(make-str 3)
```
---
    "   "

### creates string of specific char

```scheme
(make-str 4 ("x" 0))
```
---
    "xxxx"

## str-pad-left

### pads shorter string

```scheme
(str-pad-left "hi" 5 (" " 0))
```
---
    "   hi"

### no padding if already long enough

```scheme
(str-pad-left "hello" 3 (" " 0))
```
---
    "hello"

## str->list

### converts string to char list

```scheme
(length (str->list "abc"))
```
---
    3

### decodes UTF-8 code points

```scheme
(str->list "$¢€")
```
---
    (#\$ #\¢ #\€)

### code points carry the right integer values

```scheme
(map char->integer (str->list "$¢€"))
```
---
    (36 162 8364)

### round-trips through list->str

```scheme
(list->str (str->list "$¢£¥€¤"))
```
---
    "$¢£¥€¤"

## str-upcase

### uppercases a string

```scheme
(str-upcase "hello")
```
---
    "HELLO"

## str-downcase

### lowercases a string

```scheme
(str-downcase "HELLO")
```
---
    "hello"

## str<?

### less than

```scheme
(str<? "abc" "abd")
```
---
    #t

### not less than

```scheme
(if (str<? "abd" "abc") "y" "n")
```
---
    "n"

## str>?

### greater than

```scheme
(str>? "abd" "abc")
```
---
    #t

## str<=?

### less or equal

```scheme
(str<=? "abc" "abc")
```
---
    #t

## str>=?

### greater or equal

```scheme
(str>=? "abc" "abc")
```
---
    #t

## str-ci=?

### case insensitive equal

```scheme
(str-ci=? "Hello" "hello")
```
---
    #t

### case insensitive not equal

```scheme
(if (str-ci=? "Hello" "world") "y" "n")
```
---
    "n"

## str-ci<?

### case insensitive less

```scheme
(str-ci<? "abc" "DEF")
```
---
    #t

## str-ci>?

### case insensitive greater

```scheme
(str-ci>? "DEF" "abc")
```
---
    #t

## str-ci<=?

### case insensitive less or equal

```scheme
(str-ci<=? "abc" "ABC")
```
---
    #t

## str-ci>=?

### case insensitive greater or equal

```scheme
(str-ci>=? "ABC" "abc")
```
---
    #t

## str-trim

### trims whitespace

```scheme
(str-trim "  hello  ")
```
---
    "hello"

## str-trim-left

### trims left whitespace

```scheme
(str-trim-left "  hello  ")
```
---
    "hello  "

## str-trim-right

### trims right whitespace

```scheme
(str-trim-right "  hello  ")
```
---
    "  hello"

## str-split

### splits by separator

```scheme
(str-split "," "a,b,c")
```
---
    ("a" "b" "c")

### splits with no match

```scheme
(str-split "," "abc")
```
---
    ("abc")
