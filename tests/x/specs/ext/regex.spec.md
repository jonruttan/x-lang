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
(Regex match "abbc" #/ab*c/)
```
---
    #t

### rejects partial match

```scheme
(if (Regex match "abc" #/ab/) "yes" "no")
```
---
    "no"

### matches empty pattern on empty string

```scheme
(Regex match "" #/a*/)
```
---
    #t

## regex-search

### finds match at start

```scheme
(Regex search "abbc" #/ab+/)
```
---
    (0 3)

### finds match in middle

```scheme
(Regex search "aabbc" #/b+/)
```
---
    (2 4)

### returns nil on no match

```scheme
(null? (Regex search "abc" #/z+/))
```
---
    #t

### finds single char match

```scheme
(Regex search "x" #/./)
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
(Regex match "abcba" #/[abc]+/)
```
---
    #t

### rejects non-member

```scheme
(not (Regex match "xyz" #/[abc]+/))
```
---
    #t

### matches range

```scheme
(Regex match "hello" #/[a-z]+/)
```
---
    #t

### negated class rejects member

```scheme
(not (Regex match "hello" #/[^a-z]+/))
```
---
    #t

### negated class matches non-member

```scheme
(Regex match "123" #/[^a-z]+/)
```
---
    #t

### class with escape

```scheme
(Regex match "456" #/[\d]+/)
```
---
    #t

### class with multiple escapes

```scheme
(Regex match "1 2 3" #/[\d\s]+/)
```
---
    #t

## shorthand classes

### digit class

```scheme
(Regex match "42" #/\d+/)
```
---
    #t

### word class

```scheme
(Regex match "hello_42" #/\w+/)
```
---
    #t

### space class

```scheme
(Regex match "  " #/\s+/)
```
---
    #t

### non-digit class

```scheme
(Regex match "abc" #/\D+/)
```
---
    #t

### non-digit rejects digits

```scheme
(not (Regex match "123" #/\D+/))
```
---
    #t

## groups and alternation

### alternation matches left

```scheme
(Regex match "foo" #/(foo|bar)/)
```
---
    #t

### alternation matches right

```scheme
(Regex match "bar" #/(foo|bar)/)
```
---
    #t

### alternation rejects neither

```scheme
(not (Regex match "baz" #/(foo|bar)/))
```
---
    #t

### nested group

```scheme
(Regex match "abd" #/(a(b|c)d)/)
```
---
    #t

## anchors

### start anchor

```scheme
(not (null? (Regex search "hello world" #/^hello/)))
```
---
    #t

### end anchor

```scheme
(not (null? (Regex search "hello world" #/world$/)))
```
---
    #t

### both anchors

```scheme
(Regex match "exact" #/^exact$/)
```
---
    #t

## counted repetition

### exact count

```scheme
(Regex match "aaa" #/a{3}/)
```
---
    #t

### exact count rejects too few

```scheme
(not (Regex match "aa" #/a{3}/))
```
---
    #t

### range count

```scheme
(Regex match "aaa" #/a{2,4}/)
```
---
    #t

### open-ended count

```scheme
(Regex match "aaaaa" #/a{2,}/)
```
---
    #t

## lazy quantifiers

### lazy star matches shortest

```scheme
(Regex find "aaab" #/a*?b/)
```
---
    "aaab"

### lazy plus matches shortest

```scheme
(Regex find "aaaa" #/a+?/)
```
---
    "a"

### greedy plus matches longest

```scheme
(Regex find "aaaa" #/a+/)
```
---
    "aaaa"

## regex-find

### finds substring

```scheme
(Regex find "abc123def" #/[0-9]+/)
```
---
    "123"

### returns nil on no match

```scheme
(null? (Regex find "abcdef" #/[0-9]+/))
```
---
    #t

## regex-find-all

### finds all matches

```scheme
(Regex find-all "a1b22c333" #/[0-9]+/)
```
---
    ("1" "22" "333")

### returns empty list on no match

```scheme
(null? (Regex find-all "abcdef" #/[0-9]+/))
```
---
    #t

## regex-replace

### replaces first match

```scheme
(Regex replace "a1b22c" "N" #/[0-9]+/)
```
---
    "aNb22c"

### no match returns original

```scheme
(Regex replace "abc" "N" #/[0-9]+/)
```
---
    "abc"

## regex-replace-all

### replaces all matches

```scheme
(Regex replace-all "a1b22c333" "N" #/[0-9]+/)
```
---
    "aNbNcN"

## regex-split

### splits on delimiter

```scheme
(Regex split "a,b,c" #/,/)
```
---
    ("a" "b" "c")

### splits on whitespace

```scheme
(Regex split "hello world" #/\s+/)
```
---
    ("hello" "world")

### no match returns single-element list

```scheme
(Regex split "abc" #/,/)
```
---
    ("abc")

## regex-match-count

### counts matches

```scheme
(Regex match-count "a1b22c333" #/[0-9]+/)
```
---
    3

### no matches returns zero

```scheme
(Regex match-count "abc" #/[0-9]+/)
```
---
    0

### single match

```scheme
(Regex match-count "xabcx" #/abc/)
```
---
    1

## callable replace

### replace with function

```scheme
(Regex replace "hello123" (method-ref Str upcase) #/[a-z]+/)
```
---
    "HELLO123"

### replace-all with function

```scheme
(Regex replace-all "hello123world" (method-ref Str upcase) #/[a-z]+/)
```
---
    "HELLO123WORLD"

## word boundary

### word boundary at start

```scheme
(Regex match "hello" #/\bhello\b/)
```
---
    #t

### word boundary rejects mid-word

```scheme
(Regex match "hello" #/\bello/)
```
---
    #f

### word boundary in search

```scheme
(Regex find "abc 123 def" #/\b[0-9]+\b/)
```
---
    "123"

### non-word-boundary matches inside

```scheme
(Regex match "hello" #/hel\Blo/)
```
---
    #t

## find-at

### find-at from offset

```scheme
(Regex find-at "abc123def456" 6 #/[0-9]+/)
```
---
    (9 12)

### find-at from zero same as search

```scheme
(Regex find-at "abc123" 0 #/[0-9]+/)
```
---
    (3 6)

### find-at past all matches

```scheme
(null? (Regex find-at "abc123" 6 #/[0-9]+/))
```
---
    #t

## find-all-pos

### returns position pairs

```scheme
(Regex find-all-pos "a1b22c333" #/[0-9]+/)
```
---
    ((1 2) (3 5) (6 9))

### no matches returns empty list

```scheme
(null? (Regex find-all-pos "abc" #/[0-9]+/))
```
---
    #t

## lazy quantifiers

### lazy-opt prefers not matching

```scheme
(Regex find "ab" #/a??b/)
```
---
    "ab"

### lazy star minimal

```scheme
(Regex find "aXXbYYb" #/a.*?b/)
```
---
    "aXXb"

### lazy plus minimal

```scheme
(Regex find "aXXb" #/.+?b/)
```
---
    "aXXb"

## negated class with escapes

### negated digit class

```scheme
(Regex find "123abc456" #/[^\d]+/)
```
---
    "abc"

### negated word class

```scheme
(Regex find "hello world" #/[^\w]+/)
```
---
    " "

## edge cases

### empty pattern matches empty string

```scheme
(Regex match "" #//)
```
---
    #t

### star on empty matches anything

```scheme
(Regex match "" #/a*/)
```
---
    #t

### anchored empty

```scheme
(Regex match "" #/^$/)
```
---
    #t

### anchored empty rejects non-empty

```scheme
(Regex match "x" #/^$/)
```
---
    #f


## value dispatch (method form + preserved match call)

### method form

```scheme
(if (null? (Regex match "aaa" #/a+/)) "no" "yes")
```
---
    "yes"

### bare match call still works

```scheme
(if (null? (#/a+/ "aaa")) "no" "yes")
```
---
    "yes"

### value-call split routes subject-last

```scheme
(#/,/ split "a,b,c")
```
---
    ("a" "b" "c")

### value-call find

```scheme
(#/[0-9]+/ find "abc123def")
```
---
    "123"

### value-call replace-all

```scheme
(#/[0-9]+/ replace-all "a1b2" "N")
```
---
    "aNbN"

### value-call match-count

```scheme
(#/[0-9]+/ match-count "a1b22c333")
```
---
    3

## compile

### compiles a pattern string into a usable regex

```scheme
(Regex find "abc123" (Regex compile "[0-9]+"))
```
---
    "123"

### a compiled regex value-dispatches like a literal

```scheme
((Regex compile ",") split "a,b,c")
```
---
    ("a" "b" "c")

### exec methods reject a non-REGEX instead of no-opping

```scheme
(Regex split "a,b" (Regex parse ","))
```
---
    Error: #<err:type Regex: expected a compiled regex -- use #/.../ or (Regex compile pattern)>
