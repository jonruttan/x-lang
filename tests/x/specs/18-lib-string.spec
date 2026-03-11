
== string-empty?

-- true for empty string
(string-empty? "")
---
t

-- false for non-empty
(if (string-empty? "hi") "y" "n")
---
"n"

== string-join

-- joins with separator
(string-join ", " (list "a" "b" "c"))
---
"a, b, c"

-- joins single element
(string-join ", " (list "a"))
---
"a"

-- joins empty list
(string-join ", " ())
---
""

== string-repeat

-- repeats a string
(string-repeat "ab" 3)
---
"ababab"

-- repeats zero times
(string-repeat "ab" 0)
---
""

== string-contains?

-- finds substring
(string-contains? "ll" "hello")
---
t

-- returns nil for missing
(if (string-contains? "xyz" "hello") "y" "n")
---
"n"

-- empty substring always found
(string-contains? "" "hello")
---
t

== string-starts?

-- true when starts with prefix
(string-starts? "he" "hello")
---
t

-- false for non-prefix
(if (string-starts? "lo" "hello") "y" "n")
---
"n"

== string-ends?

-- true when ends with suffix
(string-ends? "lo" "hello")
---
t

-- false for non-suffix
(if (string-ends? "he" "hello") "y" "n")
---
"n"

== string-reverse

-- reverses a string
(string-reverse "hello")
---
"olleh"

-- reverses empty string
(string-reverse "")
---
""
