## sh-eval echo

### echoes a word

```sh
(do (sh-eval "echo hello") ())
```
---
    hello

### echoes multiple words

```sh
(do (sh-eval "echo hello world") ())
```
---
    hello world

### echoes empty line returns 0

```sh
(sh-eval "echo")
```
---
    0

## sh-eval builtins

### true returns 0

```sh
(sh-eval "true")
```
---
    0

### false returns 1

```sh
(sh-eval "false")
```
---
    1

### colon returns 0

```sh
(sh-eval ":")
```
---
    0

## sh-eval test

### test string equality true

```sh
(sh-eval "test hello = hello")
```
---
    0

### test string equality false

```sh
(sh-eval "test hello = world")
```
---
    1

### test string inequality true

```sh
(sh-eval "test hello != world")
```
---
    0

### test -n non-empty

```sh
(sh-eval "test -n hello")
```
---
    0

### test -z empty

```sh
(sh-eval "test -z \"\"")
```
---
    0

## sh-eval sequence

### runs two commands in sequence

```sh
(do (sh-eval "echo a; echo b") %sh-status)
```
---
    0

### last command in sequence sets status

```sh
(do (sh-eval "true; false") %sh-status)
```
---
    1

## sh-eval and-list

### and runs second if first succeeds

```sh
(do (sh-eval "true && echo yes") ())
```
---
    yes

### and skips second if first fails

```sh
(sh-eval "false && echo no")
```
---
    1

## sh-eval or-list

### or skips second if first succeeds

```sh
(sh-eval "true || echo no")
```
---
    0

### or runs second if first fails

```sh
(do (sh-eval "false || echo fallback") ())
```
---
    fallback

## sh-eval if

### if true then branch

```sh
(do (sh-eval "if true; then echo yes; fi") ())
```
---
    yes

### if false else branch

```sh
(do (sh-eval "if false; then echo yes; else echo no; fi") ())
```
---
    no

## sh-eval for

### iterates and sets variable

```sh
(do (sh-eval "for i in a b c; do :; done") (string=? (sh-getenv "i") "c"))
```
---
    t

### for loop returns 0

```sh
(sh-eval "for i in x y z; do :; done")
```
---
    0

## sh-eval variable

### expands environment variable

```sh
(do (sh-eval "export FOO=hello; echo $FOO") ())
```
---
    hello

### expands dollar-question

```sh
(do (sh-eval "true; echo $?") ())
```
---
    0

### expands dollar-question after false

```sh
(do (sh-eval "false; echo $?") ())
```
---
    1

## sh-eval external

### runs external command

```sh
(do (sh-eval "/bin/echo ext-ok") ())
```
---
    ext-ok

## sh-eval pipeline

### pipes two commands

```sh
(do (sh-eval "/bin/echo hello | /usr/bin/tr h H") ())
```
---
    Hello

## sh-eval until

### until true does not execute body

```sh
(do (sh-eval "until true; do echo bad; done") ())
```
---

### until false executes body once then stops

```sh
(do (sh-eval "export U=no; until test $U = yes; do export U=yes; done; echo $U") ())
```
---
    yes

### until returns 0

```sh
(sh-eval "until true; do :; done")
```
---
    0

## sh-eval negation

### negates true to 1

```sh
(sh-eval "! true")
```
---
    1

### negates false to 0

```sh
(sh-eval "! false")
```
---
    0

### negates pipeline

```sh
(sh-eval "! /bin/echo hello | /usr/bin/tr h H")
```
---
    1

## sh-eval case

### matches exact pattern

```sh
(do (sh-eval "case hello in hello) echo matched;; esac") ())
```
---
    matched

### matches wildcard

```sh
(do (sh-eval "case hello in *) echo caught;; esac") ())
```
---
    caught

### skips non-matching clause

```sh
(do (sh-eval "case hello in world) echo no;; hello) echo yes;; esac") ())
```
---
    yes

### returns 0 with no match

```sh
(sh-eval "case hello in world) echo no;; esac")
```
---
    0

### matches with pipe alternatives

```sh
(do (sh-eval "case dog in cat|dog|fish) echo pet;; esac") ())
```
---
    pet

### expands variable in word

```sh
(do (sh-eval "export X=hi; case $X in hi) echo found;; esac") ())
```
---
    found

## sh-eval empty

### empty input returns 0

```sh
(sh-eval "")
```
---
    0

