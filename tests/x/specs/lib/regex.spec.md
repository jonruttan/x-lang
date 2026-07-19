
## capture groups (#23)

### setup: regex loads in its own block (the begin-wrap rule)

```scheme
(do (import x/type/regex) #t)
```
---
    #t

### groups extract by number, 0 = whole match, sorted

```scheme
(Regex match-groups "on 2026-07-19 ok" (Regex compile "([0-9]+)-([0-9]+)-([0-9]+)"))
```
---
    ((0 . "2026-07-19") (1 . "2026") (2 . "07") (3 . "19"))

### an unmatched alternative's group is ABSENT (presence door)

```scheme
(let ((g (Regex match-groups "b" (Regex compile "(a)|(b)"))))
  (list (assoc-has? 1 g) (assoc-get 2 g)))
```
---
    (#f "b")

### a group under a quantifier keeps its last iteration

```scheme
(assoc-get 1 (Regex match-groups "abab" (Regex compile "(ab)+")))
```
---
    "ab"

### nested groups number in open order

```scheme
(Regex match-groups "xy" (Regex compile "((x)(y))"))
```
---
    ((0 . "xy") (1 . "xy") (2 . "x") (3 . "y"))

### no match is nil

```scheme
(null? (Regex match-groups "nope" (Regex compile "[0-9]+")))
```
---
    #t

### lazy quantifiers capture minimally

```scheme
(assoc-get 1 (Regex match-groups "<a><b>" (Regex compile "<(.+?)>")))
```
---
    "a"

## $N replacement (#23)

### $N reorders captures

```scheme
(Regex replace-all "2026-07-19" "$3/$2/$1" (Regex compile "([0-9]+)-([0-9]+)-([0-9]+)"))
```
---
    "19/07/2026"

### $0 is the whole match; $$ escapes; a missing group is empty

```scheme
(list (Regex replace "ab" "[$0]" (Regex compile "ab"))
      (Regex replace-all "cost" "$$9" (Regex compile "cost"))
      (Regex replace "ab" "[$5]" (Regex compile "ab")))
```
---
    ("[ab]" "$9" "[]")

### a function replacement still receives the matched text

```scheme
(Regex replace-all "a1b22" (fn (_ m) (Str8 append "<" m ">")) (Regex compile "[0-9]+"))
```
---
    "a<1>b<22>"
