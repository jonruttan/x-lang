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
(Regex regex? #/abc/)
```
---
    #t

### returns nil for a string

```scheme
(if (Regex regex? "abc") "yes" "no")
```
---
    "no"

### returns nil for a number

```scheme
(if (Regex regex? 42) "yes" "no")
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
(Regex match #/ab*c/ "abbc")
```
---
    #t

### rejects partial match

```scheme
(if (Regex match #/ab/ "abc") "yes" "no")
```
---
    "no"

### matches empty pattern on empty string

```scheme
(Regex match #/a*/ "")
```
---
    #t

## regex-search

### finds match at start

```scheme
(Regex search #/ab+/ "abbc")
```
---
    (0 3)

### finds match in middle

```scheme
(Regex search #/b+/ "aabbc")
```
---
    (2 4)

### returns nil on no match

```scheme
(null? (Regex search #/z+/ "abc"))
```
---
    #t

### finds single char match

```scheme
(Regex search #/./ "x")
```
---
    (0 1)

## type-name

### returns REGEX for a regex

```scheme
(Type name #/abc/)
```
---
    "REGEX"

## character classes

### matches character set

```scheme
(Regex match #/[abc]+/ "abcba")
```
---
    #t

### rejects non-member

```scheme
(not (Regex match #/[abc]+/ "xyz"))
```
---
    #t

### matches range

```scheme
(Regex match #/[a-z]+/ "hello")
```
---
    #t

### negated class rejects member

```scheme
(not (Regex match #/[^a-z]+/ "hello"))
```
---
    #t

### negated class matches non-member

```scheme
(Regex match #/[^a-z]+/ "123")
```
---
    #t

### class with escape

```scheme
(Regex match #/[\d]+/ "456")
```
---
    #t

### class with multiple escapes

```scheme
(Regex match #/[\d\s]+/ "1 2 3")
```
---
    #t

## shorthand classes

### digit class

```scheme
(Regex match #/\d+/ "42")
```
---
    #t

### word class

```scheme
(Regex match #/\w+/ "hello_42")
```
---
    #t

### space class

```scheme
(Regex match #/\s+/ "  ")
```
---
    #t

### non-digit class

```scheme
(Regex match #/\D+/ "abc")
```
---
    #t

### non-digit rejects digits

```scheme
(not (Regex match #/\D+/ "123"))
```
---
    #t

## groups and alternation

### alternation matches left

```scheme
(Regex match #/(foo|bar)/ "foo")
```
---
    #t

### alternation matches right

```scheme
(Regex match #/(foo|bar)/ "bar")
```
---
    #t

### alternation rejects neither

```scheme
(not (Regex match #/(foo|bar)/ "baz"))
```
---
    #t

### nested group

```scheme
(Regex match #/(a(b|c)d)/ "abd")
```
---
    #t

## anchors

### start anchor

```scheme
(not (null? (Regex search #/^hello/ "hello world")))
```
---
    #t

### end anchor

```scheme
(not (null? (Regex search #/world$/ "hello world")))
```
---
    #t

### both anchors

```scheme
(Regex match #/^exact$/ "exact")
```
---
    #t

## counted repetition

### exact count

```scheme
(Regex match #/a{3}/ "aaa")
```
---
    #t

### exact count rejects too few

```scheme
(not (Regex match #/a{3}/ "aa"))
```
---
    #t

### range count

```scheme
(Regex match #/a{2,4}/ "aaa")
```
---
    #t

### open-ended count

```scheme
(Regex match #/a{2,}/ "aaaaa")
```
---
    #t

## lazy quantifiers

### lazy star matches shortest

```scheme
(Regex find #/a*?b/ "aaab")
```
---
    "aaab"

### lazy plus matches shortest

```scheme
(Regex find #/a+?/ "aaaa")
```
---
    "a"

### greedy plus matches longest

```scheme
(Regex find #/a+/ "aaaa")
```
---
    "aaaa"

## regex-find

### finds substring

```scheme
(Regex find #/[0-9]+/ "abc123def")
```
---
    "123"

### returns nil on no match

```scheme
(null? (Regex find #/[0-9]+/ "abcdef"))
```
---
    #t

## regex-find-all

### finds all matches

```scheme
(Regex find-all #/[0-9]+/ "a1b22c333")
```
---
    ("1" "22" "333")

### returns empty list on no match

```scheme
(null? (Regex find-all #/[0-9]+/ "abcdef"))
```
---
    #t

## regex-replace

### replaces first match

```scheme
(Regex replace #/[0-9]+/ "a1b22c" "N")
```
---
    "aNb22c"

### no match returns original

```scheme
(Regex replace #/[0-9]+/ "abc" "N")
```
---
    "abc"

## regex-replace-all

### replaces all matches

```scheme
(Regex replace-all #/[0-9]+/ "a1b22c333" "N")
```
---
    "aNbNcN"

## regex-split

### splits on delimiter

```scheme
(Regex split #/,/ "a,b,c")
```
---
    ("a" "b" "c")

### splits on whitespace

```scheme
(Regex split #/\s+/ "hello world")
```
---
    ("hello" "world")

### no match returns single-element list

```scheme
(Regex split #/,/ "abc")
```
---
    ("abc")

## regex-count

### counts matches

```scheme
(Regex count #/[0-9]+/ "a1b22c333")
```
---
    3

### no matches returns zero

```scheme
(Regex count #/[0-9]+/ "abc")
```
---
    0

### single match

```scheme
(Regex count #/abc/ "xabcx")
```
---
    1

## callable replace

### replace with function

```scheme
(Regex replace #/[a-z]+/ "hello123" (method-ref Str upcase))
```
---
    "HELLO123"

### replace-all with function

```scheme
(Regex replace-all #/[a-z]+/ "hello123world" (method-ref Str upcase))
```
---
    "HELLO123WORLD"

## word boundary

### word boundary at start

```scheme
(Regex match #/\bhello\b/ "hello")
```
---
    #t

### word boundary rejects mid-word

```scheme
(Regex match #/\bello/ "hello")
```
---
    #f

### word boundary in search

```scheme
(Regex find #/\b[0-9]+\b/ "abc 123 def")
```
---
    "123"

### non-word-boundary matches inside

```scheme
(Regex match #/hel\Blo/ "hello")
```
---
    #t

## find-at

### find-at from offset

```scheme
(Regex find-at #/[0-9]+/ "abc123def456" 6)
```
---
    (9 12)

### find-at from zero same as search

```scheme
(Regex find-at #/[0-9]+/ "abc123" 0)
```
---
    (3 6)

### find-at past all matches

```scheme
(null? (Regex find-at #/[0-9]+/ "abc123" 6))
```
---
    #t

## find-all-pos

### returns position pairs

```scheme
(Regex find-all-pos #/[0-9]+/ "a1b22c333")
```
---
    ((1 2) (3 5) (6 9))

### no matches returns empty list

```scheme
(null? (Regex find-all-pos #/[0-9]+/ "abc"))
```
---
    #t

## lazy quantifiers

### lazy-opt prefers not matching

```scheme
(Regex find #/a??b/ "ab")
```
---
    "ab"

### lazy star minimal

```scheme
(Regex find #/a.*?b/ "aXXbYYb")
```
---
    "aXXb"

### lazy plus minimal

```scheme
(Regex find #/.+?b/ "aXXb")
```
---
    "aXXb"

## negated class with escapes

### negated digit class

```scheme
(Regex find #/[^\d]+/ "123abc456")
```
---
    "abc"

### negated word class

```scheme
(Regex find #/[^\w]+/ "hello world")
```
---
    " "

## edge cases

### empty pattern matches empty string

```scheme
(Regex match #// "")
```
---
    #t

### star on empty matches anything

```scheme
(Regex match #/a*/ "")
```
---
    #t

### anchored empty

```scheme
(Regex match #/^$/ "")
```
---
    #t

### anchored empty rejects non-empty

```scheme
(Regex match #/^$/ "x")
```
---
    #f


## value dispatch (method form + preserved match call)

### method form

```scheme
(if (null? (Regex match #/a+/ "aaa")) "no" "yes")
```
---
    "yes"

### bare match call still works

```scheme
(if (null? (#/a+/ "aaa")) "no" "yes")
```
---
    "yes"
