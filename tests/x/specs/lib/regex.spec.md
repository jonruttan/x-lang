# @weight 1

## capture groups (#23)

### setup: regex loads in its own block (the begin-wrap rule)

```x
(do (import x/type/regex) #t)
```
---
    #t

### groups extract by number, 0 = whole match, sorted

```x
(Regex match-groups "on 2026-07-19 ok" (Regex compile "([0-9]+)-([0-9]+)-([0-9]+)"))
```
---
    ((0 . "2026-07-19") (1 . "2026") (2 . "07") (3 . "19"))

### an unmatched alternative's group is ABSENT (presence door)

```x
(let ((g (Regex match-groups "b" (Regex compile "(a)|(b)"))))
  (list (Assoc has? 1 g) (Assoc get 2 g)))
```
---
    (#f "b")

### a group under a quantifier keeps its last iteration

```x
(Assoc get 1 (Regex match-groups "abab" (Regex compile "(ab)+")))
```
---
    "ab"

### nested groups number in open order

```x
(Regex match-groups "xy" (Regex compile "((x)(y))"))
```
---
    ((0 . "xy") (1 . "xy") (2 . "x") (3 . "y"))

### no match is nil

```x
(null? (Regex match-groups "nope" (Regex compile "[0-9]+")))
```
---
    #t

### lazy quantifiers capture minimally

```x
(Assoc get 1 (Regex match-groups "<a><b>" (Regex compile "<(.+?)>")))
```
---
    "a"

## $N replacement (#23)

### $N reorders captures

```x
(Regex replace-all "2026-07-19" "$3/$2/$1" (Regex compile "([0-9]+)-([0-9]+)-([0-9]+)"))
```
---
    "19/07/2026"

### $0 is the whole match; $$ escapes; a missing group is empty

```x
(list (Regex replace "ab" "[$0]" (Regex compile "ab"))
      (Regex replace-all "cost" "$$9" (Regex compile "cost"))
      (Regex replace "ab" "[$5]" (Regex compile "ab")))
```
---
    ("[ab]" "$9" "[]")

### a function replacement still receives the matched text

```x
(Regex replace-all "a1b22" (fn (_ m) (Str8 append "<" m ">")) (Regex compile "[0-9]+"))
```
---
    "a<1>b<22>"

## a regex literal inside a #"..." interpolation hole

### a {n,m} quantifier in a hole's regex is pattern text, not hole syntax

```x
#"[{(if (#/a{2,3}/ "aaa") "yes" "no")}]"
```
---
    "[yes]"

## character classes

### a - just before the closing ] is a literal, not a range to ]

```x
(list (Regex match "-" (Regex compile "[+-]"))
      (Regex match "12" (Regex compile "[+-]?([0-9]+)"))
      (Regex match "x 1" (Regex compile "[+-]?([0-9]+)")))
```
---
    (#t #t #f)

### a - between two characters is still a range

```x
(list (Regex match "m" (Regex compile "[a-z]"))
      (Regex match "-" (Regex compile "[a-z]")))
```
---
    (#t #f)

### a control escape is its control character, in a class and out of one

```x
(list (Regex match "\t" (Regex compile "[\\t]"))
      (Regex match "t" (Regex compile "[\\t]"))
      (Regex match "a\tb" (Regex compile "a\\tb"))
      (Regex match "atb" (Regex compile "a\\tb"))
      (Regex match "boot" (Regex compile "[^ \\t()]+")))
```
---
    (#t #f #t #f #t)

### a POSIX class inside brackets adds its characters

```x
(list (Regex match "a \tb" (Regex compile "a[[:space:]]+b"))
      (Regex match "ab" (Regex compile "a[[:space:]]*b"))
      (Regex match "Z9_" (Regex compile "[[:upper:]][[:digit:]][[:punct:]]"))
      (Regex match "x" (Regex compile "[^[:alpha:]]"))
      (Regex match "fF0" (Regex compile "[[:xdigit:]]+"))
      (Regex match "(import x/boot/he)"
                   (Regex compile "^\\(import[[:space:]]+[a-z0-9][a-z0-9_/@.-]*[[:space:]]*\\)")))
```
---
    (#t #t #t #f #t #t)
