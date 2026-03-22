## string-empty?

### true for empty string

```scheme
(string-empty? "")
```
---
    #t

### false for non-empty

```scheme
(if (string-empty? "hi") "y" "n")
```
---
    "n"

## string-join

### joins with separator

```scheme
(string-join ", " (list "a" "b" "c"))
```
---
    "a, b, c"

### joins single element

```scheme
(string-join ", " (list "a"))
```
---
    "a"

### joins empty list

```scheme
(string-join ", " ())
```
---
    ""

## string-repeat

### repeats a string

```scheme
(string-repeat "ab" 3)
```
---
    "ababab"

### repeats zero times

```scheme
(string-repeat "ab" 0)
```
---
    ""

## string-contains?

### finds substring

```scheme
(string-contains? "ll" "hello")
```
---
    #t

### returns nil for missing

```scheme
(if (string-contains? "xyz" "hello") "y" "n")
```
---
    "n"

### empty substring always found

```scheme
(string-contains? "" "hello")
```
---
    #t

## string-starts?

### true when starts with prefix

```scheme
(string-starts? "he" "hello")
```
---
    #t

### false for non-prefix

```scheme
(if (string-starts? "lo" "hello") "y" "n")
```
---
    "n"

## string-ends?

### true when ends with suffix

```scheme
(string-ends? "lo" "hello")
```
---
    #t

### false for non-suffix

```scheme
(if (string-ends? "he" "hello") "y" "n")
```
---
    "n"

## string-reverse

### reverses a string

```scheme
(string-reverse "hello")
```
---
    "olleh"

### reverses empty string

```scheme
(string-reverse "")
```
---
    ""


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

## make-string

### creates string of spaces

```scheme
(make-string 3)
```
---
    "   "

### creates string of specific char

```scheme
(make-string 4 ("x" 0))
```
---
    "xxxx"

## string-pad-left

### pads shorter string

```scheme
(string-pad-left "hi" 5 (" " 0))
```
---
    "   hi"

### no padding if already long enough

```scheme
(string-pad-left "hello" 3 (" " 0))
```
---
    "hello"

## string->list

### converts string to char list

```scheme
(length (string->list "abc"))
```
---
    3

## string-upcase

### uppercases a string

```scheme
(string-upcase "hello")
```
---
    "HELLO"

## string-downcase

### lowercases a string

```scheme
(string-downcase "HELLO")
```
---
    "hello"

## string<?

### less than

```scheme
(string<? "abc" "abd")
```
---
    #t

### not less than

```scheme
(if (string<? "abd" "abc") "y" "n")
```
---
    "n"

## string>?

### greater than

```scheme
(string>? "abd" "abc")
```
---
    #t

## string<=?

### less or equal

```scheme
(string<=? "abc" "abc")
```
---
    #t

## string>=?

### greater or equal

```scheme
(string>=? "abc" "abc")
```
---
    #t

## string-ci=?

### case insensitive equal

```scheme
(string-ci=? "Hello" "hello")
```
---
    #t

### case insensitive not equal

```scheme
(if (string-ci=? "Hello" "world") "y" "n")
```
---
    "n"

## string-ci<?

### case insensitive less

```scheme
(string-ci<? "abc" "DEF")
```
---
    #t

## string-ci>?

### case insensitive greater

```scheme
(string-ci>? "DEF" "abc")
```
---
    #t

## string-ci<=?

### case insensitive less or equal

```scheme
(string-ci<=? "abc" "ABC")
```
---
    #t

## string-ci>=?

### case insensitive greater or equal

```scheme
(string-ci>=? "ABC" "abc")
```
---
    #t

## string-trim

### trims whitespace

```scheme
(string-trim "  hello  ")
```
---
    "hello"

## string-trim-left

### trims left whitespace

```scheme
(string-trim-left "  hello  ")
```
---
    "hello  "

## string-trim-right

### trims right whitespace

```scheme
(string-trim-right "  hello  ")
```
---
    "  hello"

## string-split

### splits by separator

```scheme
(string-split "," "a,b,c")
```
---
    ("a" "b" "c")

### splits with no match

```scheme
(string-split "," "abc")
```
---
    ("abc")
