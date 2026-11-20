# tables of named columns (Table, Column)
# @weight 2

A `Table` is columns of one length, each under a name; a `Column` is a
run of values of one encoding. Every operation answers a new value. The
numbers in these cases are Floats, so a column's encoding is f64 on any
word.

## Columns

### numbers are held as a Tensor, any other values as they are

```x
(import x/data/table)
(list ((Column from '(1.5 2.5)) encoding)
      ((Column from '("Ann" "Bo")) encoding)
      ((Column from '(1.5 "two")) encoding)
      ((Column from ()) encoding))
```
---
    ('f64 'any 'any 'any)

### size, ref and ->list, for either kind

```x
(import x/data/table)
(let ((n (Column from '(1.5 2.5 4.0))) (s (Column from '("Ann" "Bo"))))
  (list (n size) (n ref 1) (n ref -1) (n ->list)
        (s size) (s ref 1) (s ->list)))
```
---
    (3 2.5 4.0 (1.5 2.5 4.0) 2 "Bo" ("Ann" "Bo"))

### a column of numbers answers its statistics

```x
(import x/data/table)
(let ((c (Column from '(2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0))))
  (list (c sum) (c mean) (c least) (c greatest) (c median)
        (c variance 0) (c deviation 0) (c quantile 0.5)))
```
---
    (40.0 5.0 2.0 9.0 4.5 4.0 2.0 4.5)

### a Tensor, a Vector and a Column are taken as values too

```x
(import x/data/table) (import x/num/tensor) (import x/type/vector)
(let ((c (Column from '(1.5 2.5))))
  (list ((Column from (Tensor from '(1.5 2.5))) ->list)
        ((Column from (Vector from-list '("a" "b"))) ->list)
        (same? (Column from c) c)))
```
---
    ((1.5 2.5) ("a" "b") #t)

### a column of encoding any has no Tensor

```x
(import x/data/table)
(list (guard (e (Err label e)) ((Column from '("Ann")) tensor))
      (guard (e (Err label e)) ((Column from '("Ann")) mean)))
```
---
    ('value 'value)

## Making a table

### from a list for each column: names, extent and the columns

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0)) (name ("Ann" "Bo" "Cy"))))))
  (list (t names) (t extent) ((t column 'age) ->list) ((t column 'name) ->list)))
```
---
    (('age 'name) (3 2) (31.0 45.0 28.0) ("Ann" "Bo" "Cy"))

### a name given as a string is the same name

```x
(import x/data/table)
(let ((t (Table from '(("unit price" (2.5 4.0)) (item ("pen" "cup"))))))
  (list ((t column "unit price") ->list)
        ((t column "item") ->list)
        (same? (t column 'item) (t column "item"))))
```
---
    ((2.5 4.0) ("pen" "cup") #t)

### from csv text: a column of numbers becomes f64, any other stays strings

```x
(import x/data/table)
(let ((t (Table from-csv "name,age,code\nida,7,a1\nbo,9.5,22\n")))
  (list (t names) (t extent)
        ((t column 'age) ->list) ((t column 'age) encoding)
        ((t column 'name) ->list)
        ((t column 'code) ->list)))
```
---
    (('name 'age 'code) (2 3) (7.0 9.5) 'f64 ("ida" "bo") ("a1" "22"))

### csv text of names alone is a table of no rows

```x
(import x/data/table)
(let ((t (Table from-csv "name,age\n")))
  (list (t names) (t extent)))
```
---
    (('name 'age) (0 2))

### ->list answers what from takes

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0)) (name ("Ann" "Bo"))))))
  (list (t ->list) (((Table from (t ->list)) column 'name) ->list)))
```
---
    ((('age (31.0 45.0)) ('name ("Ann" "Bo"))) ("Ann" "Bo"))

## Rows and columns

### row answers one row's values, in column order

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0)) (name ("Ann" "Bo" "Cy"))))))
  (list (t row 0) (t row -1)))
```
---
    ((31.0 "Ann") (28.0 "Cy"))

### select keeps the named columns, in the order named

```x
(import x/data/table)
(let ((t (Table from '((age (31.0)) (name ("Ann")) (city ("Ely"))))))
  (let ((s (t select '(city age))))
    (list (s names) (s row 0) (t names))))
```
---
    (('city 'age) ("Ely" 31.0) ('age 'name 'city))

### filter keeps the rows a column's value passes, in every column

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0)) (name ("Ann" "Bo" "Cy"))))))
  (let ((f (t filter 'age (fn (_ a) (< 30 a)))))
    (list (f extent) ((f column 'age) ->list) ((f column 'name) ->list)
          ((f column 'age) encoding) (t extent))))
```
---
    ((2 2) (31.0 45.0) ("Ann" "Bo") 'f64 (3 2))

### filter by a column of strings, and a filter that keeps no row

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0)) (name ("Ann" "Bo" "Cy"))))))
  (let ((one (t filter 'name (fn (_ n) (equal? n "Bo"))))
        (none (t filter 'age (fn (_ a) (< 100 a)))))
    (list (one row 0) (none extent) ((none column 'age) encoding) ((none column 'age) ->list))))
```
---
    ((45.0 "Bo") (0 2) 'f64 ())

### sort orders the rows by a column, least first, or by a before of its own

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0)) (name ("Ann" "Bo" "Cy"))))))
  (list (((t sort 'age) column 'name) ->list)
        (((t sort 'age (fn (_ a b) (< b a))) column 'name) ->list)
        ((t column 'name) ->list)))
```
---
    (("Cy" "Ann" "Bo") ("Bo" "Ann" "Cy") ("Ann" "Bo" "Cy"))

### rows whose values are equal keep their order

```x
(import x/data/table)
(let ((t (Table from '((rank (2.0 1.0 2.0 1.0)) (name ("a" "b" "c" "d"))))))
  (((t sort 'rank) column 'name) ->list))
```
---
    ("b" "d" "a" "c")

## Handing a table to a model

### matrix answers the named columns as an f64 Matrix, a row for each row

```x
(import x/data/table)
(let ((t (Table from '((a (1.0 2.0 3.0)) (b (4.0 5.0 6.0)) (name ("x" "y" "z"))))))
  (list ((t matrix '(b a)) ->list) ((t matrix '(a)) extent)))
```
---
    (((4.0 1.0) (5.0 2.0) (6.0 3.0)) (3 1))

### a table's columns fit a linear model

```x
(import x/data/table) (import x/num/model)
(let ((t (Table from-csv "height,age,weight\n1,0,3\n0,1,4\n1,1,6\n2,1,8\n")))
  (let ((f ((Model linear) fit (t matrix '(height age)) (t column 'weight))))
    (list (f intercept) ((f coefficients) ->list))))
```
---
    (1.0 (2.0 3.0))

## Refusals

### columns of different lengths, a name twice, an unknown name, a bad name, text columns as a matrix, and a ragged csv row

```x
(import x/data/table)
(let ((t (Table from '((age (31.0)) (name ("Ann"))))))
  (list (guard (e (Err label e)) (Table from '((a (1.0 2.0)) (b (1.0)))))
        (guard (e (Err label e)) (Table from '((a (1.0)) (a (2.0)))))
        (guard (e (Err label e)) (t column 'height))
        (guard (e (Err label e)) (t column 7))
        (guard (e (Err label e)) (t matrix '(name)))
        (guard (e (Err label e)) (Table from-csv "a,b\n1\n"))))
```
---
    ('value 'value 'value 'value 'value 'value)

## Other names

### other libraries' words find the table and its sort

```x
(import x/data/table)
(list ((Doc entry 'Table) known-as) ((Doc entry 'Table/sort) known-as))
```
---
    (("DataFrame" "data frame") ("arrange" "order by"))
