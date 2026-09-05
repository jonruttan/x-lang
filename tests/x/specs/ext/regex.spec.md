# @lib ../tests/x/lib/regex.x
# @weight 1

## regex literal

### writes exact pattern

```x
(write #/abc/)
```
---
    #/abc/

### writes empty pattern

```x
(write #//)
```
---
    #//

### writes pattern with star

```x
(write #/ab*c/)
```
---
    #/ab*c/

### writes pattern with plus

```x
(write #/a+b/)
```
---
    #/a+b/

### writes pattern with optional

```x
(write #/a?b/)
```
---
    #/a?b/

### writes pattern with dot

```x
(write #/a.b/)
```
---
    #/a.b/

### writes pattern with escaped dot

```x
(write #/a\.b/)
```
---
    #/a\.b/

### writes pattern with escaped backslash

```x
(write #/a\\b/)
```
---
    #/a\\b/

## regex?

### returns #t for a regex

```x
(Regex regex? #/abc/)
```
---
    #t

### returns nil for a string

```x
(if (Regex regex? "abc") "yes" "no")
```
---
    "no"

### returns nil for a number

```x
(if (Regex regex? 42) "yes" "no")
```
---
    "no"

## regex literal matching

### matches exact string

```x
(#/abc/ "abc")
```
---
    #t

### rejects different string

```x
(if (#/abc/ "abd") "yes" "no")
```
---
    "no"

### rejects partial match (input too short)

```x
(if (#/abc/ "ab") "yes" "no")
```
---
    "no"

### rejects partial match (input too long)

```x
(if (#/abc/ "abcd") "yes" "no")
```
---
    "no"

### matches empty pattern against empty string

```x
(#// "")
```
---
    #t

### rejects non-empty string against empty pattern

```x
(if (#// "a") "yes" "no")
```
---
    "no"

### matches single character

```x
(#/x/ "x")
```
---
    #t

## regex dot wildcard

### matches any single character

```x
(#/./ "x")
```
---
    #t

### matches dot in middle

```x
(#/a.c/ "abc")
```
---
    #t

### matches dot with different char

```x
(#/a.c/ "axc")
```
---
    #t

### rejects dot against empty

```x
(if (#/./ "") "yes" "no")
```
---
    "no"

## regex star quantifier

### matches zero occurrences

```x
(#/ab*c/ "ac")
```
---
    #t

### matches one occurrence

```x
(#/ab*c/ "abc")
```
---
    #t

### matches multiple occurrences

```x
(#/ab*c/ "abbbc")
```
---
    #t

### greedy star at 16K characters (crash regression)

The star state collector recursed in argument position -- one C eval
frame group per matched character, NOT pattern-bounded -- so a* over a
~16K+ input crashed the C stack (the %map1 shape, fixed 2026-09-01).
Now tail accumulate, states farthest-first for free.

```x
(Regex match (Str8 make 16384 #\a) #/a*/)
```
---
    #t

### matches star at end

```x
(#/ab*/ "abbb")
```
---
    #t

### matches star at end zero times

```x
(#/ab*/ "a")
```
---
    #t

### matches only stars

```x
(#/a*/ "aaa")
```
---
    #t

### matches empty with star

```x
(#/a*/ "")
```
---
    #t

## regex plus quantifier

### matches one occurrence

```x
(#/ab+c/ "abc")
```
---
    #t

### matches multiple occurrences

```x
(#/ab+c/ "abbbc")
```
---
    #t

### rejects zero occurrences

```x
(if (#/ab+c/ "ac") "yes" "no")
```
---
    "no"

### matches plus at end

```x
(#/ab+/ "abb")
```
---
    #t

### rejects plus with no match

```x
(if (#/ab+/ "a") "yes" "no")
```
---
    "no"

## regex optional quantifier

### matches with the optional char

```x
(#/ab?c/ "abc")
```
---
    #t

### matches without the optional char

```x
(#/ab?c/ "ac")
```
---
    #t

### rejects multiple of optional

```x
(if (#/ab?c/ "abbc") "yes" "no")
```
---
    "no"

## regex escape sequences

### matches literal dot

```x
(#/a\.b/ "a.b")
```
---
    #t

### rejects non-dot for escaped dot

```x
(if (#/a\.b/ "axb") "yes" "no")
```
---
    "no"

### matches literal backslash

```x
(#/a\\b/ "a\b")
```
---
    #t

### matches escaped star as literal

```x
(#/a\*b/ "a*b")
```
---
    #t

## regex backtracking

### backtracks star for correct match

```x
(#/a.*b/ "axxb")
```
---
    #t

### backtracks when greedy over-consumes

```x
(#/.*b/ "aab")
```
---
    #t

### fails when backtracking exhausted

```x
(if (#/a.*b/ "axx") "yes" "no")
```
---
    "no"

## regex combined patterns

### matches dot-star combo

```x
(#/a.*/ "abcdef")
```
---
    #t

### matches complex pattern

```x
(#/a.b*c/ "axbbc")
```
---
    #t

### matches dot-plus combo

```x
(#/.+/ "abc")
```
---
    #t

### rejects dot-plus on empty

```x
(if (#/.+/ "") "yes" "no")
```
---
    "no"

## regex-match

### matches full string

```x
(Regex match "abbc" #/ab*c/)
```
---
    #t

### rejects partial match

```x
(if (Regex match "abc" #/ab/) "yes" "no")
```
---
    "no"

### matches empty pattern on empty string

```x
(Regex match "" #/a*/)
```
---
    #t

## regex-search

### finds match at start

```x
(Regex search "abbc" #/ab+/)
```
---
    (0 3)

### finds match in middle

```x
(Regex search "aabbc" #/b+/)
```
---
    (2 4)

### returns nil on no match

```x
(null? (Regex search "abc" #/z+/))
```
---
    #t

### finds single char match

```x
(Regex search "x" #/./)
```
---
    (0 1)

## type-name

### returns REGEX for a regex

```x
(Type name #/abc/)
```
---
    "REGEX"

## character classes

### matches character set

```x
(Regex match "abcba" #/[abc]+/)
```
---
    #t

### rejects non-member

```x
(not (Regex match "xyz" #/[abc]+/))
```
---
    #t

### matches range

```x
(Regex match "hello" #/[a-z]+/)
```
---
    #t

### negated class rejects member

```x
(not (Regex match "hello" #/[^a-z]+/))
```
---
    #t

### negated class matches non-member

```x
(Regex match "123" #/[^a-z]+/)
```
---
    #t

### class with escape

```x
(Regex match "456" #/[\d]+/)
```
---
    #t

### class with multiple escapes

```x
(Regex match "1 2 3" #/[\d\s]+/)
```
---
    #t

## shorthand classes

### digit class

```x
(Regex match "42" #/\d+/)
```
---
    #t

### word class

```x
(Regex match "hello_42" #/\w+/)
```
---
    #t

### space class

```x
(Regex match "  " #/\s+/)
```
---
    #t

### non-digit class

```x
(Regex match "abc" #/\D+/)
```
---
    #t

### non-digit rejects digits

```x
(not (Regex match "123" #/\D+/))
```
---
    #t

## groups and alternation

### alternation matches left

```x
(Regex match "foo" #/(foo|bar)/)
```
---
    #t

### alternation matches right

```x
(Regex match "bar" #/(foo|bar)/)
```
---
    #t

### alternation rejects neither

```x
(not (Regex match "baz" #/(foo|bar)/))
```
---
    #t

### nested group

```x
(Regex match "abd" #/(a(b|c)d)/)
```
---
    #t

## anchors

### start anchor

```x
(not (null? (Regex search "hello world" #/^hello/)))
```
---
    #t

### end anchor

```x
(not (null? (Regex search "hello world" #/world$/)))
```
---
    #t

### both anchors

```x
(Regex match "exact" #/^exact$/)
```
---
    #t

## counted repetition

### exact count

```x
(Regex match "aaa" #/a{3}/)
```
---
    #t

### exact count rejects too few

```x
(not (Regex match "aa" #/a{3}/))
```
---
    #t

### range count

```x
(Regex match "aaa" #/a{2,4}/)
```
---
    #t

### open-ended count

```x
(Regex match "aaaaa" #/a{2,}/)
```
---
    #t

### counted repeat at 16K characters (crash regression)

collect-from gathered its state list by recursing in argument position
-- one C eval frame group per repetition -- so a ~16K+ count crashed
the C stack (the %map1 shape, fixed 2026-09-01).  Now tail accumulate;
the states come out farthest-first, which is the order greedy try-from
wanted anyway.

```x
(Regex match (Str8 make 16384 #\a) #/a{0,16384}/)
```
---
    #t

## lazy quantifiers

### lazy star matches shortest

```x
(Regex find "aaab" #/a*?b/)
```
---
    "aaab"

### lazy plus matches shortest

```x
(Regex find "aaaa" #/a+?/)
```
---
    "a"

### greedy plus matches longest

```x
(Regex find "aaaa" #/a+/)
```
---
    "aaaa"

### lazy star at 16K characters (crash regression)

Lazy quantifiers collect the FULL state list up front too (laziness is
only the try order), so the same argument-position recursion crashed
a*? over a ~16K+ input before it ever tried a state.  The length probe
pins that the whole run of a's plus the b matched.

```x
(Str8 length (Regex find (Str8 append (Str8 make 16384 #\a) "b") #/a*?b/))
```
---
    16385

## regex-find

### finds substring

```x
(Regex find "abc123def" #/[0-9]+/)
```
---
    "123"

### returns nil on no match

```x
(null? (Regex find "abcdef" #/[0-9]+/))
```
---
    #t

## regex-find-all

### finds all matches

```x
(Regex find-all "a1b22c333" #/[0-9]+/)
```
---
    ("1" "22" "333")

### returns empty list on no match

```x
(null? (Regex find-all "abcdef" #/[0-9]+/))
```
---
    #t

## regex-replace

### replaces first match

```x
(Regex replace "a1b22c" "N" #/[0-9]+/)
```
---
    "aNb22c"

### no match returns original

```x
(Regex replace "abc" "N" #/[0-9]+/)
```
---
    "abc"

## regex-replace-all

### replaces all matches

```x
(Regex replace-all "a1b22c333" "N" #/[0-9]+/)
```
---
    "aNbNcN"

## regex-split

### splits on delimiter

```x
(Regex split "a,b,c" #/,/)
```
---
    ("a" "b" "c")

### splits on whitespace

```x
(Regex split "hello world" #/\s+/)
```
---
    ("hello" "world")

### no match returns single-element list

```x
(Regex split "abc" #/,/)
```
---
    ("abc")

## regex-match-count

### counts matches

```x
(Regex match-count "a1b22c333" #/[0-9]+/)
```
---
    3

### no matches returns zero

```x
(Regex match-count "abc" #/[0-9]+/)
```
---
    0

### single match

```x
(Regex match-count "xabcx" #/abc/)
```
---
    1

## callable replace

### replace with function

```x
(Regex replace "hello123" (method-ref Str upcase) #/[a-z]+/)
```
---
    "HELLO123"

### replace-all with function

```x
(Regex replace-all "hello123world" (method-ref Str upcase) #/[a-z]+/)
```
---
    "HELLO123WORLD"

## word boundary

### word boundary at start

```x
(Regex match "hello" #/\bhello\b/)
```
---
    #t

### word boundary rejects mid-word

```x
(Regex match "hello" #/\bello/)
```
---
    #f

### word boundary in search

```x
(Regex find "abc 123 def" #/\b[0-9]+\b/)
```
---
    "123"

### non-word-boundary matches inside

```x
(Regex match "hello" #/hel\Blo/)
```
---
    #t

## find-at

### find-at from offset

```x
(Regex find-at "abc123def456" 6 #/[0-9]+/)
```
---
    (9 12)

### find-at from zero same as search

```x
(Regex find-at "abc123" 0 #/[0-9]+/)
```
---
    (3 6)

### find-at past all matches

```x
(null? (Regex find-at "abc123" 6 #/[0-9]+/))
```
---
    #t

## find-all-pos

### returns position pairs

```x
(Regex find-all-pos "a1b22c333" #/[0-9]+/)
```
---
    ((1 2) (3 5) (6 9))

### no matches returns empty list

```x
(null? (Regex find-all-pos "abc" #/[0-9]+/))
```
---
    #t

## lazy quantifiers

### lazy-opt prefers not matching

```x
(Regex find "ab" #/a??b/)
```
---
    "ab"

### lazy star minimal

```x
(Regex find "aXXbYYb" #/a.*?b/)
```
---
    "aXXb"

### lazy plus minimal

```x
(Regex find "aXXb" #/.+?b/)
```
---
    "aXXb"

## negated class with escapes

### negated digit class

```x
(Regex find "123abc456" #/[^\d]+/)
```
---
    "abc"

### negated word class

```x
(Regex find "hello world" #/[^\w]+/)
```
---
    " "

## edge cases

### empty pattern matches empty string

```x
(Regex match "" #//)
```
---
    #t

### star on empty matches anything

```x
(Regex match "" #/a*/)
```
---
    #t

### anchored empty

```x
(Regex match "" #/^$/)
```
---
    #t

### anchored empty rejects non-empty

```x
(Regex match "x" #/^$/)
```
---
    #f


## value dispatch (method form + preserved match call)

### method form

```x
(if (null? (Regex match "aaa" #/a+/)) "no" "yes")
```
---
    "yes"

### bare match call still works

```x
(if (null? (#/a+/ "aaa")) "no" "yes")
```
---
    "yes"

### value-call split routes subject-last

```x
(#/,/ split "a,b,c")
```
---
    ("a" "b" "c")

### value-call find

```x
(#/[0-9]+/ find "abc123def")
```
---
    "123"

### value-call replace-all

```x
(#/[0-9]+/ replace-all "a1b2" "N")
```
---
    "aNbN"

### value-call match-count

```x
(#/[0-9]+/ match-count "a1b22c333")
```
---
    3

## compile

### compiles a pattern string into a usable regex

```x
(Regex find "abc123" (Regex compile "[0-9]+"))
```
---
    "123"

### a compiled regex value-dispatches like a literal

```x
((Regex compile ",") split "a,b,c")
```
---
    ("a" "b" "c")

### exec methods reject a non-REGEX instead of no-opping

```x
(Regex split "a,b" (Regex parse ","))
```
---
    Error: #<err:type Regex: expected a compiled regex -- use #/.../ or (Regex compile pattern)>
