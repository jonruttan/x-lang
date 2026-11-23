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

### sort answers the same once the kernels are compiled, equal values in their order

```x
(import x/data/table) (import x/num/tensor)
(let ((t (Table from '((age (31.0 45.0 28.0 45.0 -2.5 31.0 0.0)) (name ("a" "b" "c" "d" "e" "f" "g"))
                       (n (1.0 2.0 3.0 4.0 5.0 6.0 7.0)))))
      (two (Table from '((x (2.0 1.0)))))
      (one (Table from '((x (2.0))))))
  (let ((run (fn (_) (list (((t sort 'age) column 'name) ->list) (((t sort 'age) column 'n) ->list)
                           (((t select '(n age)) sort 'age) ->list)
                           (((t sort 'age (fn (_ a b) (< b a))) column 'name) ->list)
                           ((two sort 'x) ->list) ((one sort 'x) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run)) (first before) (List ref 3 before)))))
```
---
    (#t ("e" "g" "c" "a" "f" "b" "d") ("b" "d" "a" "f" "c" "g" "e"))

## Column arithmetic and map

### add, sub, mul and div, by a column or by a number

```x
(import x/data/table)
(let ((a (Column from '(3.0 5.0))) (b (Column from '(2.0 4.0))))
  (list ((a add b) ->list) ((a sub b) ->list) ((a mul b) ->list) ((a div b) ->list)
        ((a add 1.5) ->list) ((a mul 2.0) ->list) (a ->list)))
```
---
    ((5.0 9.0) (1.0 1.0) (6.0 20.0) (1.5 1.25) (4.5 6.5) (6.0 10.0) (3.0 5.0))

### map answers a column of what the function answers, its encoding read from them

```x
(import x/data/table)
(let ((names (Column from '("Ann" "Bo"))) (nums (Column from '(1.5 2.5))))
  (list ((names map (fn (_ s) (equal? s "Bo"))) ->list)
        ((nums map (fn (_ x) (Float * x x))) ->list)
        ((nums map (fn (_ x) (Float * x x))) encoding)
        ((nums map (fn (_ x) (< 2 x))) encoding)))
```
---
    ((#f #t) (2.25 6.25) 'f64 'any)

### arithmetic on a column of encoding any is refused

```x
(import x/data/table)
(guard (e (Err label e)) ((Column from '("Ann")) add 1.0))
```
---
    'value

## Adding and changing columns

### put adds a new column last, and replaces one where it stands

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0)) (name ("Ann" "Bo"))))))
  (let ((added (t put 'city '("Ely" "Ayr")))
        (replaced (t put 'age '(1.0 2.0))))
    (list (added names) (added row 0)
          (replaced names) (replaced row 0)
          (t names) (t row 0))))
```
---
    (('age 'name 'city) (31.0 "Ann" "Ely") ('age 'name) (1.0 "Ann") ('age 'name) (31.0 "Ann"))

### put takes a Column, so a column worked out from others goes straight in

```x
(import x/data/table)
(let ((t (Table from '((w (8.0 18.0)) (h (2.0 3.0))))))
  (((t put 'r ((t column 'w) div ((t column 'h) mul (t column 'h)))) column 'r) ->list))
```
---
    (2.0 2.0)

### derive calls a function with each row's values of the named columns

```x
(import x/data/table)
(let ((t (Table from '((w (8.0 18.0)) (h (2.0 3.0)) (name ("Ann" "Bo"))))))
  (list (((t derive 'r '(w h) (fn (_ w h) (Float / w (Float * h h)))) column 'r) ->list)
        (((t derive 'big '(w) (fn (_ w) (< 10 w))) column 'big) ->list)
        ((t derive 'big '(w) (fn (_ w) (< 10 w))) names)
        (((t derive 'w '(w) (fn (_ w) (Float * w 2.0))) column 'w) ->list)))
```
---
    ((2.0 2.0) (#f #t) ('w 'h 'name 'big) (16.0 36.0))

### remove and rename

```x
(import x/data/table)
(let ((t (Table from '((age (31.0)) (name ("Ann")) (city ("Ely"))))))
  (list ((t remove 'name) names) ((t remove 'name) row 0)
        ((t rename 'age 'years) names) (((t rename 'age "years") column 'years) ->list)
        (t names)))
```
---
    (('age 'city) (31.0 "Ely") ('years 'name 'city) (31.0) ('age 'name 'city))

### a column of the wrong length, an unknown name, a name taken, and derive of no columns are refused

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0)) (name ("Ann" "Bo"))))))
  (list (guard (e (Err label e)) (t put 'city '("Ely")))
        (guard (e (Err label e)) (t remove 'height))
        (guard (e (Err label e)) (t rename 'height 'h))
        (guard (e (Err label e)) (t rename 'age 'name))
        (guard (e (Err label e)) (t derive 'x '() (fn (_) 1.0)))
        (guard (e (Err label e)) (t derive 'x '(height) (fn (_ h) h)))))
```
---
    ('value 'value 'value 'value 'value 'value)

## Parting and summarizing by a column

### split answers each distinct value with the table of its rows, in first-seen order

```x
(import x/data/table)
(let ((t (Table from '((city ("Ely" "Ayr" "Ely" "Usk")) (age (31.0 45.0 28.0 60.0))))))
  (let ((parts (t split 'city)))
    (list (List map first parts)
          (List map (fn (_ p) (((rest p) column 'age) ->list)) parts)
          (List map (fn (_ p) ((rest p) names)) parts)
          (t extent))))
```
---
    (("Ely" "Ayr" "Usk") ((31.0 28.0) (45.0) (60.0)) (('city 'age) ('city 'age) ('city 'age)) (4 2))

### aggregate answers a row for each distinct value and a column for each spec

```x
(import x/data/table)
(let ((t (Table from '((city ("Ely" "Ayr" "Ely" "Usk")) (age (31.0 45.0 29.0 60.0)) (pay (10.0 20.0 30.0 40.0))))))
  (let ((a (t aggregate 'city
             (list (list 'mean-age 'age (fn (_ c) (c mean)))
                   (list 'top-pay 'pay (fn (_ c) (c greatest)))
                   (list 'total-pay 'pay (fn (_ c) (c sum)))))))
    (list (a names) (a extent) (a ->list))))
```
---
    (('city 'mean-age 'top-pay 'total-pay) (3 4) (('city ("Ely" "Ayr" "Usk")) ('mean-age (30.0 45.0 60.0)) ('top-pay (30.0 20.0 40.0)) ('total-pay (40.0 20.0 40.0))))

### the distinct values may be numbers, and a summary may be any value

```x
(import x/data/table)
(let ((t (Table from '((year (2020.0 2021.0 2020.0)) (name ("Ann" "Bo" "Cy"))))))
  (let ((a (t aggregate 'year (list (list 'names 'name (fn (_ c) (c ->list)))))))
    (list ((a column 'year) ->list) ((a column 'year) encoding) ((a column 'names) ->list))))
```
---
    ((2020.0 2021.0) 'f64 (("Ann" "Cy") ("Bo")))

### whole numbers, numbers with fractions, and values of mixed kinds all part the same way

```x
(import x/data/table)
(let ((whole (Table from '((k (3.0 1.0 3.0 2.0 1.0)) (v (1.0 2.0 3.0 4.0 5.0)))))
      (parts (Table from '((k (0.5 1.5 0.5)) (v (1.0 2.0 3.0)))))
      (mixed (Table from (list (list 'k (list "a" () "a" 2.5 ())) (list 'v '(1.0 2.0 3.0 4.0 5.0))))))
  (let ((sums (fn (_ t) ((t aggregate 'k (list (list 's 'v (fn (_ c) (c sum))))) ->list))))
    (list (sums whole) (sums parts) (sums mixed))))
```
---
    ((('k (3.0 1.0 2.0)) ('s (4.0 7.0 4.0))) (('k (0.5 1.5)) ('s (4.0 2.0))) (('k ("a" () 2.5)) ('s (4.0 7.0 4.0))))

### many distinct values come in first-seen order, each with all its rows

```x
(import x/data/table)
(let ((keys (List map (fn (_ i) (Float from (% (* i 7) 50))) (List range 0 200))))
  (let ((t (Table from (list (list 'k keys) (list 'one (List map (fn (_ i) 1.0) keys))))))
    (let ((a (t aggregate 'k (list (list 'n 'one (fn (_ c) (c sum)))))))
      (list (a extent)
            (List take 4 ((a column 'k) ->list))
            ((a column 'n) least) ((a column 'n) greatest) ((a column 'n) sum)))))
```
---
    ((50 2) (0.0 7.0 14.0 21.0) 4.0 4.0 200.0)

### a count of the rows with each value

```x
(import x/data/table)
(let ((t (Table from '((city ("Ely" "Ayr" "Ely")) (age (31.0 45.0 28.0))))))
  (List map (fn (_ n) (= n 2))
    (((t aggregate 'city (list (list 'rows 'age (fn (_ c) (c size))))) column 'rows) ->list)))
```
---
    (#t #f)

### no specs answers the distinct values alone, and a table of no rows answers none

```x
(import x/data/table)
(let ((t (Table from '((city ("Ely" "Ayr" "Ely"))))) (none (Table from-csv "city,age\n")))
  (list ((t aggregate 'city ()) ->list)
        (none split 'city)
        ((none aggregate 'city (list (list 'mean-age 'age (fn (_ c) (c mean))))) extent)))
```
---
    ((('city ("Ely" "Ayr"))) () (0 2))

### a column the table does not have is refused, as the one parted by or as a source

```x
(import x/data/table)
(let ((t (Table from '((city ("Ely" "Ayr")) (age (31.0 45.0))))))
  (list (guard (e (Err label e)) (t split 'height))
        (guard (e (Err label e)) (t aggregate 'height ()))
        (guard (e (Err label e)) (t aggregate 'city (list (list 'm 'height (fn (_ c) (c mean))))))
        (guard (e (Err label e)) (t aggregate 'city (list (list 'city 'age (fn (_ c) (c mean))))))))
```
---
    ('value 'value 'value 'value)

### split and aggregate answer the same once the kernels are compiled

```x
(import x/data/table) (import x/num/tensor)
(let ((t (Table from '((k (2.5 1.0 2.5 -3.0 1.0 2.5 0.25)) (name ("a" "b" "c" "d" "e" "f" "g"))
                       (n (1.0 2.0 3.0 4.0 5.0 6.0 7.0)))))
      (one (Table from '((k (4.0)) (n (9.0))))))
  (let ((run (fn (_) (list (List map (fn (_ c) (list (first c) ((rest c) ->list))) (t split 'k))
                           (List map (fn (_ c) (list (first c) ((rest c) ->list))) ((t select '(k n)) split 'k))
                           ((t aggregate 'k (list (list 'total 'n (fn (_ c) (c sum)))
                                                  (list 'first-name 'name (fn (_ c) (first (c ->list)))))) ->list)
                           (List map first (t split 'name))
                           ((one aggregate 'k (list (list 'total 'n (fn (_ c) (c sum))))) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run)) (List ref 2 before)))))
```
---
    (#t (('k (2.5 1.0 -3.0 0.25)) ('total (10.0 7.0 4.0 7.0)) ('first-name ("a" "b" "d" "g"))))

## Masks

### a column's comparisons answer masks, columns of 1.0 and 0.0

```x
(import x/data/table)
(let ((c (Column from '(1.5 2.5 4.0))))
  (list (List map (fn (_ m) (m ->list))
          (list (c less 2.5) (c greater 2.5) (c at-most 2.5) (c at-least 2.5) (c equal 2.5) (c differ 2.5)
                (c less (Column from '(2.0 2.0 5.0)))))
        ((c less 2.5) encoding)))
```
---
    (((1.0 0.0 0.0) (0.0 0.0 1.0) (1.0 1.0 0.0) (0.0 1.0 1.0) (0.0 1.0 0.0) (1.0 0.0 1.0) (1.0 0.0 1.0)) 'f64)

### a column of encoding any answers equal and differ, against a value or a column

```x
(import x/data/table)
(let ((c (Column from '("Ann" "Bo" "Cy"))))
  (list ((c equal "Bo") ->list) ((c differ "Bo") ->list) ((c equal (Column from '("Ann" "Bo" "Di"))) ->list)))
```
---
    ((0.0 1.0 0.0) (1.0 0.0 1.0) (1.0 1.0 0.0))

### filter keeps the rows where a mask is not 0; mul is both masks, max either, and sum the count

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0 28.0 52.0)) (name ("Ann" "Bo" "Cy" "Di")) (height (1.5 1.75 1.5 2.0))))))
  (let ((age (t column 'age)) (height (t column 'height))
        (names (fn (_ t) ((t column 'name) ->list))))
    (list (names (t filter (age greater 30)))
          (names (t filter ((age greater 30) mul (height less 2))))
          (names (t filter ((age less 30) max (height equal 2))))
          (names (t filter ((t column 'name) equal "Bo")))
          (names (t filter ((age greater 30) tensor)))
          ((t filter (age greater 99)) extent)
          ((age greater 30) sum))))
```
---
    (("Ann" "Bo" "Di") ("Ann" "Bo") ("Cy" "Di") ("Bo") ("Ann" "Bo" "Di") (0 3) 3.0)

### a mask keeps the rows a function keeps, before and once the kernels are compiled

```x
(import x/data/table) (import x/num/tensor)
(let ((t (Table from '((k (2.5 1.0 2.5 -3.0 1.0 2.5 0.25)) (name ("a" "b" "c" "d" "e" "f" "g"))))))
  (let ((run (fn (_) ((t filter ((t column 'k) at-least 1)) ->list)))
        (by-function ((t filter 'k (fn (_ k) (not (< k 1)))) ->list)))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before by-function) (equal? before (run)) (((t filter ((t column 'k) at-least 1)) column 'name) ->list)))))
```
---
    (#t #t ("a" "b" "c" "e" "f"))

### an order on a column of encoding any, a mask of another size, and a mask that is neither a Column nor a Tensor are refused

```x
(import x/data/table)
(let ((t (Table from '((age (31.0 45.0)) (name ("Ann" "Bo"))))))
  (list (guard (e (Err label e)) ((t column 'name) less "Bo"))
        (guard (e (Err label e)) ((t column 'name) equal (Column from '("Ann"))))
        (guard (e (Err label e)) (t filter ((Column from '(1.0 2.0 3.0)) greater 1)))
        (guard (e (Err label e)) (t filter 'age))))
```
---
    ('value 'value 'value 'type)

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
(list ((Doc entry 'Table) known-as) ((Doc entry 'Table/sort) known-as)
      ((Doc entry 'Table/derive) known-as) ((Doc entry 'Table/put) known-as))
```
---
    (("DataFrame" "data frame") ("arrange" "order by") ("mutate" "transform") ("assign" "with column"))
