# @lib ../tests/x/lib/regex.x

## regex literal

### writes exact pattern

```scheme
(write #/abc/)
```
---
    #/abc/

### writes empty pattern

```scheme
(write #//)
```
---
    #//

### writes pattern with star

```scheme
(write #/ab*c/)
```
---
    #/ab*c/

### writes pattern with plus

```scheme
(write #/a+b/)
```
---
    #/a+b/

### writes pattern with optional

```scheme
(write #/a?b/)
```
---
    #/a?b/

### writes pattern with dot

```scheme
(write #/a.b/)
```
---
    #/a.b/

### writes pattern with escaped dot

```scheme
(write #/a\.b/)
```
---
    #/a\.b/

### writes pattern with escaped backslash

```scheme
(write #/a\\b/)
```
---
    #/a\\b/

## regex?

### returns #t for a regex

```scheme
(regex? #/abc/)
```
---
    #t

### returns nil for a string

```scheme
(if (regex? "abc") "yes" "no")
```
---
    "no"

### returns nil for a number

```scheme
(if (regex? 42) "yes" "no")
```
---
    "no"

## regex literal matching

### matches exact string

```scheme
(#/abc/ "abc")
```
---
    #t

### rejects different string

```scheme
(if (#/abc/ "abd") "yes" "no")
```
---
    "no"

### rejects partial match (input too short)

```scheme
(if (#/abc/ "ab") "yes" "no")
```
---
    "no"

### rejects partial match (input too long)

```scheme
(if (#/abc/ "abcd") "yes" "no")
```
---
    "no"

### matches empty pattern against empty string

```scheme
(#// "")
```
---
    #t

### rejects non-empty string against empty pattern

```scheme
(if (#// "a") "yes" "no")
```
---
    "no"

### matches single character

```scheme
(#/x/ "x")
```
---
    #t

## regex dot wildcard

### matches any single character

```scheme
(#/./ "x")
```
---
    #t

### matches dot in middle

```scheme
(#/a.c/ "abc")
```
---
    #t

### matches dot with different char

```scheme
(#/a.c/ "axc")
```
---
    #t

### rejects dot against empty

```scheme
(if (#/./ "") "yes" "no")
```
---
    "no"

## regex star quantifier

### matches zero occurrences

```scheme
(#/ab*c/ "ac")
```
---
    #t

### matches one occurrence

```scheme
(#/ab*c/ "abc")
```
---
    #t

### matches multiple occurrences

```scheme
(#/ab*c/ "abbbc")
```
---
    #t

### matches star at end

```scheme
(#/ab*/ "abbb")
```
---
    #t

### matches star at end zero times

```scheme
(#/ab*/ "a")
```
---
    #t

### matches only stars

```scheme
(#/a*/ "aaa")
```
---
    #t

### matches empty with star

```scheme
(#/a*/ "")
```
---
    #t

## regex plus quantifier

### matches one occurrence

```scheme
(#/ab+c/ "abc")
```
---
    #t

### matches multiple occurrences

```scheme
(#/ab+c/ "abbbc")
```
---
    #t

### rejects zero occurrences

```scheme
(if (#/ab+c/ "ac") "yes" "no")
```
---
    "no"

### matches plus at end

```scheme
(#/ab+/ "abb")
```
---
    #t

### rejects plus with no match

```scheme
(if (#/ab+/ "a") "yes" "no")
```
---
    "no"

## regex optional quantifier

### matches with the optional char

```scheme
(#/ab?c/ "abc")
```
---
    #t

### matches without the optional char

```scheme
(#/ab?c/ "ac")
```
---
    #t

### rejects multiple of optional

```scheme
(if (#/ab?c/ "abbc") "yes" "no")
```
---
    "no"

## regex escape sequences

### matches literal dot

```scheme
(#/a\.b/ "a.b")
```
---
    #t

### rejects non-dot for escaped dot

```scheme
(if (#/a\.b/ "axb") "yes" "no")
```
---
    "no"

### matches literal backslash

```scheme
(#/a\\b/ "a\b")
```
---
    #t

### matches escaped star as literal

```scheme
(#/a\*b/ "a*b")
```
---
    #t

## regex backtracking

### backtracks star for correct match

```scheme
(#/a.*b/ "axxb")
```
---
    #t

### backtracks when greedy over-consumes

```scheme
(#/.*b/ "aab")
```
---
    #t

### fails when backtracking exhausted

```scheme
(if (#/a.*b/ "axx") "yes" "no")
```
---
    "no"

## regex combined patterns

### matches dot-star combo

```scheme
(#/a.*/ "abcdef")
```
---
    #t

### matches complex pattern

```scheme
(#/a.b*c/ "axbbc")
```
---
    #t

### matches dot-plus combo

```scheme
(#/.+/ "abc")
```
---
    #t

### rejects dot-plus on empty

```scheme
(if (#/.+/ "") "yes" "no")
```
---
    "no"

## regex-match

### matches full string

```scheme
(regex-match #/ab*c/ "abbc")
```
---
    #t

### rejects partial match

```scheme
(if (regex-match #/ab/ "abc") "yes" "no")
```
---
    "no"

### matches empty pattern on empty string

```scheme
(regex-match #/a*/ "")
```
---
    #t

## regex-search

### finds match at start

```scheme
(regex-search #/ab+/ "abbc")
```
---
    (0 3)

### finds match in middle

```scheme
(regex-search #/b+/ "aabbc")
```
---
    (2 4)

### returns nil on no match

```scheme
(null? (regex-search #/z+/ "abc"))
```
---
    #t

### finds single char match

```scheme
(regex-search #/./ "x")
```
---
    (0 1)

## type-name

### returns REGEX for a regex

```scheme
(type-name #/abc/)
```
---
    "REGEX"

