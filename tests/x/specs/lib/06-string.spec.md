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
