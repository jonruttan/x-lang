
== sh-eval echo

-- echoes a word
(do (sh-eval "echo hello") ())
---
hello

-- echoes multiple words
(do (sh-eval "echo hello world") ())
---
hello world

-- echoes empty line returns 0
(sh-eval "echo")
---
0

== sh-eval builtins

-- true returns 0
(sh-eval "true")
---
0

-- false returns 1
(sh-eval "false")
---
1

-- colon returns 0
(sh-eval ":")
---
0

== sh-eval test

-- test string equality true
(sh-eval "test hello = hello")
---
0

-- test string equality false
(sh-eval "test hello = world")
---
1

-- test string inequality true
(sh-eval "test hello != world")
---
0

-- test -n non-empty
(sh-eval "test -n hello")
---
0

-- test -z empty
(sh-eval "test -z \"\"")
---
0

== sh-eval sequence

-- runs two commands in sequence
(do (sh-eval "echo a; echo b") %sh-status)
---
0

-- last command in sequence sets status
(do (sh-eval "true; false") %sh-status)
---
1

== sh-eval and-list

-- and runs second if first succeeds
(do (sh-eval "true && echo yes") ())
---
yes

-- and skips second if first fails
(sh-eval "false && echo no")
---
1

== sh-eval or-list

-- or skips second if first succeeds
(sh-eval "true || echo no")
---
0

-- or runs second if first fails
(do (sh-eval "false || echo fallback") ())
---
fallback

== sh-eval if

-- if true then branch
(do (sh-eval "if true; then echo yes; fi") ())
---
yes

-- if false else branch
(do (sh-eval "if false; then echo yes; else echo no; fi") ())
---
no

== sh-eval for

-- iterates and sets variable
(do (sh-eval "for i in a b c; do :; done") (string=? (sh-getenv "i") "c"))
---
t

-- for loop returns 0
(sh-eval "for i in x y z; do :; done")
---
0

== sh-eval variable

-- expands environment variable
(do (sh-eval "export FOO=hello; echo $FOO") ())
---
hello

-- expands dollar-question
(do (sh-eval "true; echo $?") ())
---
0

-- expands dollar-question after false
(do (sh-eval "false; echo $?") ())
---
1

== sh-eval external

-- runs external command
(do (sh-eval "/bin/echo ext-ok") ())
---
ext-ok

== sh-eval pipeline

-- pipes two commands
(do (sh-eval "/bin/echo hello | /usr/bin/tr h H") ())
---
Hello

== sh-eval until

-- until true does not execute body
(do (sh-eval "until true; do echo bad; done") ())
---


-- until false executes body once then stops
(do (sh-eval "export U=no; until test $U = yes; do export U=yes; done; echo $U") ())
---
yes

-- until returns 0
(sh-eval "until true; do :; done")
---
0

== sh-eval negation

-- negates true to 1
(sh-eval "! true")
---
1

-- negates false to 0
(sh-eval "! false")
---
0

-- negates pipeline
(sh-eval "! /bin/echo hello | /usr/bin/tr h H")
---
1

== sh-eval case

-- matches exact pattern
(do (sh-eval "case hello in hello) echo matched;; esac") ())
---
matched

-- matches wildcard
(do (sh-eval "case hello in *) echo caught;; esac") ())
---
caught

-- skips non-matching clause
(do (sh-eval "case hello in world) echo no;; hello) echo yes;; esac") ())
---
yes

-- returns 0 with no match
(sh-eval "case hello in world) echo no;; esac")
---
0

-- matches with pipe alternatives
(do (sh-eval "case dog in cat|dog|fish) echo pet;; esac") ())
---
pet

-- expands variable in word
(do (sh-eval "export X=hi; case $X in hi) echo found;; esac") ())
---
found

== sh-eval empty

-- empty input returns 0
(sh-eval "")
---
0
