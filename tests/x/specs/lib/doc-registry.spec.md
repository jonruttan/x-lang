# @weight 1

The documentation registry as data. `help` and `apropos` print the same
entries; these cases read them as records.

## entry

### a method's entry, a field per part

```x
(let ((e (Doc entry 'Str8/split)))
  (list (e name)
        (str? (e desc))
        (first (e returns))
        (List map first (e params))
        (first (rest (first (e params))))))
```
---
    ('Str8/split #t 'LIST ('sep 's) 'STRING)

### an example is a pair of strings, expression then result

```x
(let ((ex (first ((Doc entry 'Str8/split) examples))))
  (list (str? (first ex)) (str? (rest ex))))
```
---
    (#t #t)

### a string names the same entry as the symbol

```x
(eq? ((Doc entry "Str8/split") name) ((Doc entry 'Str8/split) name))
```
---
    #t

### a module's entry has a summary and no parameters

```x
(let ((e (Doc entry 'x/core/math)))
  (list (str? (e desc)) (null? (e params)) (null? (e returns))))
```
---
    (#t #t #t)

### sees, notes and samples are read as written

```x
(list ((Doc entry 'prim-ref) sees)
      (not (null? ((Doc entry 'help) notes)))
      (not (null? ((Doc entry 'Lang/register!) samples))))
```
---
    (('prim-reg!) #t #t)

### a name nothing is documented under answers ()

```x
(null? (Doc entry 'no-such-name-zz))
```
---
    #t

### a doc form filed in the session is read back

```x
(do
  (doc (def doc-registry-tmp (fn (_ (param n INTEGER "A number")) n))
    (returns INTEGER "The number")
    (example "(doc-registry-tmp 3)" "3")
    "Identity, documented here.")
  (let ((e (Doc entry 'doc-registry-tmp)))
    (list (e desc) (e params) (e returns) (e examples))))
```
---
    ("Identity, documented here." (('n 'INTEGER "A number")) ('INTEGER "The number") (("(doc-registry-tmp 3)" . "3")))

## names

### every documented name, sorted, each once

```x
(let ((n (Doc names)))
  (list (List includes? 'Str8/split n)
        (List includes? 'x/core/math n)
        (Str8 <? (symbol->str (first n)) (symbol->str (first (rest n))))
        (= (List length n) (List length (List distinct n)))
        (< 500 (List length n))))
```
---
    (#t #t #t #t #t)

### the names apropos answers are among them

```x
(let ((n (Doc names)))
  (List all? (fn (_ s) (List includes? s n)) (apropos "split")))
```
---
    #t
