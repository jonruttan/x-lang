# @weight 1

Where a form was read. The reader stamps the first cell of each form it
reads with a line and a file id; `Source` reads the stamps, the registry of
included files, and the reader's live position. The fixture is
`tests/x/lib/source-fixture.x`: its quoted form sits on line 7, its
closure's body form on line 10, and its position capture on line 12.

## line and file

### a quoted form from an included file: its line and the file's path

```x
(do (include-once "tests/x/lib/source-fixture.x")
    (list (Source line source-fixture-form) (Source file source-fixture-form)))
```
---
    (7 "tests/x/lib/source-fixture.x")

### a closure's first body form, read through Fn body

```x
(do (include-once "tests/x/lib/source-fixture.x")
    (list (Source line (first (Fn body source-fixture-fn)))
          (Source file (first (Fn body source-fixture-fn)))))
```
---
    (10 "tests/x/lib/source-fixture.x")

### a form built at run time carries no stamp

```x
(list (Source line (list 1 2)) (Source file (list 1 2)) (Source line (pair 1 2)))
```
---
    (() () ())

### a form read from standard input has a line and no file

```x
(let ((q (lit (a b))))
  (list (< 0 (Source line q)) (Source file q)))
```
---
    (#t "")

## path and files

### standard input, a filed id, and an id nothing filed

```x
(do (include-once "tests/x/lib/source-fixture.x")
    (list (Source path 0)
          (Source path (first (List find (fn (_ e) (str=? (rest e) "tests/x/lib/source-fixture.x")) (Source files))))
          (Source path 999999)))
```
---
    ("" "tests/x/lib/source-fixture.x" ())

### every included file, integer ids ascending, the library's files among them

```x
(let ((f (Source files)))
  (list (number? (first (first f)))
        (< (first (first f)) (first (first (rest f))))
        (List any? (fn (_ e) (str=? (rest e) "lib/x/core/fn.x")) f)))
```
---
    (#t #t #t)

## here

### while a file loads, the file and the line of the form being evaluated

```x
(do (include-once "tests/x/lib/source-fixture.x")
    source-fixture-here)
```
---
    ("tests/x/lib/source-fixture.x" . 12)

### at the prompt, standard input and a positive line

```x
(let ((h (Source here)))
  (list (first h) (< 0 (rest h))))
```
---
    ("" #t)
