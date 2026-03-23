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

## character classes

### matches character set

```scheme
(regex-match #/[abc]+/ "abcba")
```
---
    #t

### rejects non-member

```scheme
(not (regex-match #/[abc]+/ "xyz"))
```
---
    #t

### matches range

```scheme
(regex-match #/[a-z]+/ "hello")
```
---
    #t

### negated class rejects member

```scheme
(not (regex-match #/[^a-z]+/ "hello"))
```
---
    #t

### negated class matches non-member

```scheme
(regex-match #/[^a-z]+/ "123")
```
---
    #t

### class with escape

```scheme
(regex-match #/[\d]+/ "456")
```
---
    #t

### class with multiple escapes

```scheme
(regex-match #/[\d\s]+/ "1 2 3")
```
---
    #t

## shorthand classes

### digit class

```scheme
(regex-match #/\d+/ "42")
```
---
    #t

### word class

```scheme
(regex-match #/\w+/ "hello_42")
```
---
    #t

### space class

```scheme
(regex-match #/\s+/ "  ")
```
---
    #t

### non-digit class

```scheme
(regex-match #/\D+/ "abc")
```
---
    #t

### non-digit rejects digits

```scheme
(not (regex-match #/\D+/ "123"))
```
---
    #t

## groups and alternation

### alternation matches left

```scheme
(regex-match #/(foo|bar)/ "foo")
```
---
    #t

### alternation matches right

```scheme
(regex-match #/(foo|bar)/ "bar")
```
---
    #t

### alternation rejects neither

```scheme
(not (regex-match #/(foo|bar)/ "baz"))
```
---
    #t

### nested group

```scheme
(regex-match #/(a(b|c)d)/ "abd")
```
---
    #t

## anchors

### start anchor

```scheme
(not (null? (regex-search #/^hello/ "hello world")))
```
---
    #t

### end anchor

```scheme
(not (null? (regex-search #/world$/ "hello world")))
```
---
    #t

### both anchors

```scheme
(regex-match #/^exact$/ "exact")
```
---
    #t

## counted repetition

### exact count

```scheme
(regex-match #/a{3}/ "aaa")
```
---
    #t

### exact count rejects too few

```scheme
(not (regex-match #/a{3}/ "aa"))
```
---
    #t

### range count

```scheme
(regex-match #/a{2,4}/ "aaa")
```
---
    #t

### open-ended count

```scheme
(regex-match #/a{2,}/ "aaaaa")
```
---
    #t

## lazy quantifiers

### lazy star matches shortest

```scheme
(regex-find #/a*?b/ "aaab")
```
---
    "aaab"

### lazy plus matches shortest

```scheme
(regex-find #/a+?/ "aaaa")
```
---
    "a"

### greedy plus matches longest

```scheme
(regex-find #/a+/ "aaaa")
```
---
    "aaaa"

## regex-find

### finds substring

```scheme
(regex-find #/[0-9]+/ "abc123def")
```
---
    "123"

### returns nil on no match

```scheme
(null? (regex-find #/[0-9]+/ "abcdef"))
```
---
    #t

## regex-find-all

### finds all matches

```scheme
(regex-find-all #/[0-9]+/ "a1b22c333")
```
---
    ("1" "22" "333")

### returns empty list on no match

```scheme
(null? (regex-find-all #/[0-9]+/ "abcdef"))
```
---
    #t

## regex-replace

### replaces first match

```scheme
(regex-replace #/[0-9]+/ "a1b22c" "N")
```
---
    "aNb22c"

### no match returns original

```scheme
(regex-replace #/[0-9]+/ "abc" "N")
```
---
    "abc"

## regex-replace-all

### replaces all matches

```scheme
(regex-replace-all #/[0-9]+/ "a1b22c333" "N")
```
---
    "aNbNcN"

## regex-split

### splits on delimiter

```scheme
(regex-split #/,/ "a,b,c")
```
---
    ("a" "b" "c")

### splits on whitespace

```scheme
(regex-split #/\s+/ "hello world")
```
---
    ("hello" "world")

### no match returns single-element list

```scheme
(regex-split #/,/ "abc")
```
---
    ("abc")

## regex-count

### counts matches

```scheme
(regex-count #/[0-9]+/ "a1b22c333")
```
---
    3

### no matches returns zero

```scheme
(regex-count #/[0-9]+/ "abc")
```
---
    0

### single match

```scheme
(regex-count #/abc/ "xabcx")
```
---
    1

## callable replace

### replace with function

```scheme
(regex-replace #/[a-z]+/ "hello123" str-upcase)
```
---
    "HELLO123"

### replace-all with function

```scheme
(regex-replace-all #/[a-z]+/ "hello123world" str-upcase)
```
---
    "HELLO123WORLD"

## word boundary

### word boundary at start

```scheme
(regex-match #/\bhello\b/ "hello")
```
---
    #t

### word boundary rejects mid-word

```scheme
(regex-match #/\bello/ "hello")
```
---
    #f

### word boundary in search

```scheme
(regex-find #/\b[0-9]+\b/ "abc 123 def")
```
---
    "123"

### non-word-boundary matches inside

```scheme
(regex-match #/hel\Blo/ "hello")
```
---
    #t

## find-at

### find-at from offset

```scheme
(regex-find-at #/[0-9]+/ "abc123def456" 6)
```
---
    (9 12)

### find-at from zero same as search

```scheme
(regex-find-at #/[0-9]+/ "abc123" 0)
```
---
    (3 6)

### find-at past all matches

```scheme
(null? (regex-find-at #/[0-9]+/ "abc123" 6))
```
---
    #t

## find-all-pos

### returns position pairs

```scheme
(regex-find-all-pos #/[0-9]+/ "a1b22c333")
```
---
    ((1 2) (3 5) (6 9))

### no matches returns empty list

```scheme
(null? (regex-find-all-pos #/[0-9]+/ "abc"))
```
---
    #t

## lazy quantifiers

### lazy-opt prefers not matching

```scheme
(regex-find #/a??b/ "ab")
```
---
    "ab"

### lazy star minimal

```scheme
(regex-find #/a.*?b/ "aXXbYYb")
```
---
    "aXXb"

### lazy plus minimal

```scheme
(regex-find #/.+?b/ "aXXb")
```
---
    "aXXb"

## negated class with escapes

### negated digit class

```scheme
(regex-find #/[^\d]+/ "123abc456")
```
---
    "abc"

### negated word class

```scheme
(regex-find #/[^\w]+/ "hello world")
```
---
    " "

## edge cases

### empty pattern matches empty string

```scheme
(regex-match #// "")
```
---
    #t

### star on empty matches anything

```scheme
(regex-match #/a*/ "")
```
---
    #t

### anchored empty

```scheme
(regex-match #/^$/ "")
```
---
    #t

### anchored empty rejects non-empty

```scheme
(regex-match #/^$/ "x")
```
---
    #f

