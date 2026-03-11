# @lib x.x

== regex literal

-- writes exact pattern
(write #/abc/)
---
#/abc/

-- writes empty pattern
(write #//)
---
#//

-- writes pattern with star
(write #/ab*c/)
---
#/ab*c/

-- writes pattern with plus
(write #/a+b/)
---
#/a+b/

-- writes pattern with optional
(write #/a?b/)
---
#/a?b/

-- writes pattern with dot
(write #/a.b/)
---
#/a.b/

-- writes pattern with escaped dot
(write #/a\.b/)
---
#/a\.b/

-- writes pattern with escaped backslash
(write #/a\\b/)
---
#/a\\b/

== regex?

-- returns t for a regex
(regex? #/abc/)
---
t

-- returns nil for a string
(if (regex? "abc") "yes" "no")
---
"no"

-- returns nil for a number
(if (regex? 42) "yes" "no")
---
"no"

== regex literal matching

-- matches exact string
(#/abc/ "abc")
---
t

-- rejects different string
(if (#/abc/ "abd") "yes" "no")
---
"no"

-- rejects partial match (input too short)
(if (#/abc/ "ab") "yes" "no")
---
"no"

-- rejects partial match (input too long)
(if (#/abc/ "abcd") "yes" "no")
---
"no"

-- matches empty pattern against empty string
(#// "")
---
t

-- rejects non-empty string against empty pattern
(if (#// "a") "yes" "no")
---
"no"

-- matches single character
(#/x/ "x")
---
t

== regex dot wildcard

-- matches any single character
(#/./ "x")
---
t

-- matches dot in middle
(#/a.c/ "abc")
---
t

-- matches dot with different char
(#/a.c/ "axc")
---
t

-- rejects dot against empty
(if (#/./ "") "yes" "no")
---
"no"

== regex star quantifier

-- matches zero occurrences
(#/ab*c/ "ac")
---
t

-- matches one occurrence
(#/ab*c/ "abc")
---
t

-- matches multiple occurrences
(#/ab*c/ "abbbc")
---
t

-- matches star at end
(#/ab*/ "abbb")
---
t

-- matches star at end zero times
(#/ab*/ "a")
---
t

-- matches only stars
(#/a*/ "aaa")
---
t

-- matches empty with star
(#/a*/ "")
---
t

== regex plus quantifier

-- matches one occurrence
(#/ab+c/ "abc")
---
t

-- matches multiple occurrences
(#/ab+c/ "abbbc")
---
t

-- rejects zero occurrences
(if (#/ab+c/ "ac") "yes" "no")
---
"no"

-- matches plus at end
(#/ab+/ "abb")
---
t

-- rejects plus with no match
(if (#/ab+/ "a") "yes" "no")
---
"no"

== regex optional quantifier

-- matches with the optional char
(#/ab?c/ "abc")
---
t

-- matches without the optional char
(#/ab?c/ "ac")
---
t

-- rejects multiple of optional
(if (#/ab?c/ "abbc") "yes" "no")
---
"no"

== regex escape sequences

-- matches literal dot
(#/a\.b/ "a.b")
---
t

-- rejects non-dot for escaped dot
(if (#/a\.b/ "axb") "yes" "no")
---
"no"

-- matches literal backslash
(#/a\\b/ "a\b")
---
t

-- matches escaped star as literal
(#/a\*b/ "a*b")
---
t

== regex backtracking

-- backtracks star for correct match
(#/a.*b/ "axxb")
---
t

-- backtracks when greedy over-consumes
(#/.*b/ "aab")
---
t

-- fails when backtracking exhausted
(if (#/a.*b/ "axx") "yes" "no")
---
"no"

== regex combined patterns

-- matches dot-star combo
(#/a.*/ "abcdef")
---
t

-- matches complex pattern
(#/a.b*c/ "axbbc")
---
t

-- matches dot-plus combo
(#/.+/ "abc")
---
t

-- rejects dot-plus on empty
(if (#/.+/ "") "yes" "no")
---
"no"

== type-name

-- returns REGEX for a regex
(type-name #/abc/)
---
"REGEX"
