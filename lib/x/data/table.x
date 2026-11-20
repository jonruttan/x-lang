; table.x -- tables of named columns, as values.
;
; A Column is a run of values of one encoding.  Where every value is an
; integer or a Float it is held as a rank-1 Tensor, of the encoding the
; Tensor gives those numbers, and answers its statistics.  Any other
; column is held as a Vector of the values as they are, its encoding any.
;
; A Table is columns of one length, each under a name, in order.  A name
; is a symbol, so finding a column compares addresses; a string given as
; a name is made a symbol.  Every operation answers a new Table or Column
; and changes none.
;
;   (Table from '((age (31.0 45.0)) (name ("Ann" "Bo"))))
;   (Table from-csv text)        the first row names the columns
;
;   (t names)  (t extent)        the names; the rows and the columns
;   (t column 'age)              one Column
;   (t row 0)                    one row's values, in column order
;   (t select '(age))            a Table of those columns
;   (t filter 'age pred)         the rows where pred answers true of age
;   (t sort 'age)                the rows in the order of age
;   (t matrix '(age height))     those columns as an f64 Matrix
;   (t put 'bmi values)          the table with that column added or replaced
;   (t derive 'bmi '(weight height) f)   put, the values f answers of the
;                                named columns' values, row by row
;   (t remove 'age)  (t rename 'age 'years)
;   (t split 'city)              each distinct city with the table of its rows
;   (t aggregate 'city specs)    a table with a row for each distinct city
;                                and a column for each summary asked for
;
; A Column of numbers also answers add, sub, mul and div, element by
; element as a Tensor's do, and any Column answers map.
;
; filter and sort find the rows to keep as a list of row numbers, once,
; and each column is then gathered by it.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/data/table)
(import x/type/class)
(import x/type/list)
(import x/type/vector)
(import x/core/doors str->sym type-of)
(import x/num/float Float float? float-of f-eq f-lt)
(import x/num/tensor)

; A name as a symbol: a symbol as it is, a string made one.
(def %name
  (fn (_ x)
    (match
      ((symbol? x) x)
      ((str? x) (str->sym x))
      (#t (Err raise (lit value) "Table: a column's name is a symbol or a string" x)))))

; #t where every element of LST is an integer or a Float.
(def %numbers?
  (fn (self lst)
    (match
      ((null? lst) #t)
      ((if (number? (first lst)) #t (float? (first lst))) (self (rest lst)))
      (#t #f))))

; The lists of LISTS turned on their side: the first of each, then the
; second of each, to the end of the first list.
(def %transpose
  (fn (_ lists)
    (if (null? lists) ()
      (let go ((lists lists) (acc ()))
        (if (null? (first lists)) (List reverse acc)
          (go (List map rest lists) (pair (List map first lists) acc)))))))

; What a value is looked up by in a hashed table, for the values of LST
; taken together: a function from a value to its key, or () where the
; values have none.  Strings, symbols and integers are their own keys;
; an integer is told by its type, since number? is true of a Float too.
; Floats that are whole, and within a thousand million of 0 so they are
; integers on any word, are keyed by that integer.  A list that mixes the
; two, or holds any other value, has none.
(def %whole-bound (float-of 1000000000))
(def %int-type (type-of 0))
(def %category-key
  (fn (_ lst)
    (let go ((left lst) (plain #t) (whole #t))
      (match
        ((null? left)
          (match (plain (fn (_ v) v)) (whole (fn (_ v) (Float ->int v))) (#t ())))
        ((if plain #f (not whole)) ())
        (#t
          (let ((v (first left)))
            (go (rest left)
                (if plain (if (str? v) #t (if (symbol? v) #t (if (null? v) #f (eq? (type-of v) %int-type)))) #f)
                (if whole
                  (if (float? v)
                    (if (f-lt v %whole-bound)
                      (if (f-lt (float-of -1000000000) v) (f-eq (float-of (Float ->int v)) v) #f)
                      #f)
                    #f)
                  #f))))))))

(def-class Column ()
  (doc "A run of values of one encoding, as a table holds under a name. Where every value is an integer or a Float it is held as a rank-1 Tensor and answers its statistics; any other column holds the values as they are, its encoding any."
    (example "((Column from '(31.0 45.0 28.0)) mean)" "34.6666666666667")
    (example "((Column from '(\"Ann\" \"Bo\")) encoding)" "'any")
    (see from) (see size) (see encoding) (see ref) (see ->list) (see tensor)
    (see add) (see sub) (see mul) (see div) (see map))

  encoding   ; a Tensor's encoding, or any
  data       ; a rank-1 Tensor, or for any a Vector

  (static
    (method from (self (param values LIST|VECTOR|Tensor|Column "The values, in order"))
      (doc "A column of the values. A Tensor is kept as it is; a list or a Vector of integers and Floats becomes a Tensor, of f64 unless every one is an integer; any other becomes a column of encoding any."
        (returns Column "The column")
        (example "((Column from '(1.5 2.5)) ->list)" "(1.5 2.5)")
        (example "((Column from '(1.5 \"two\")) encoding)" "'any"))
      (match
        ((pair? values) (self %of-list values))
        ((null? values) (self %of-list ()))
        ((if (object? values) (instance-of? values Column) #f) values)
        ((if (object? values) (instance-of? values Tensor) #f) (self %of-tensor values))
        (#t (self %of-list (Vector ->list values)))))

    (method %of-tensor (self t)
      (if (= (t rank) 1) ()
        (Err raise (lit value) "Column from: a Tensor must have rank 1" (t extent)))
      (new-from self (list (lit encoding) (t encoding) (lit data) t)))

    (method %of-list (self lst)
      (if (if (pair? lst) (%numbers? lst) #f)
        (self %of-tensor (Tensor from lst))
        (new-from self (list (lit encoding) (lit any) (lit data) (Vector from-list lst)))))

    ; A column of LST in the encoding of LIKE, which the values came from:
    ; a list of none keeps the encoding, where from would answer any.
    (method %as (self like lst)
      (match
        ((eq? (like encoding) (lit any))
          (new-from self (list (lit encoding) (lit any) (lit data) (Vector from-list lst))))
        ((null? lst) (self %of-tensor (Tensor zeros 0 (like encoding))))
        (#t (self %of-tensor (Tensor from lst (like encoding)))))))

  (method encoding (self)
    (doc "How the values are held: a Tensor's encoding, or any."
      (returns SYMBOL "The encoding")
      (example "((Column from '(1.5 2.5)) encoding)" "'f64"))
    (field (lit encoding)))

  (method size (self)
    (doc "The number of values."
      (returns INTEGER "The size")
      (example "((Column from '(1.5 2.5 4.0)) size)" "3"))
    (if (eq? (field (lit encoding)) (lit any))
      (Vector length (field (lit data)))
      ((field (lit data)) size)))

  (method ref (self (param i INTEGER "The index; negative counts from the end"))
    (doc "The value at an index."
      (returns ANY "The value")
      (example "((Column from '(\"Ann\" \"Bo\")) ref 1)" "\"Bo\""))
    (if (eq? (field (lit encoding)) (lit any))
      (Vector ref i (field (lit data)))
      ((field (lit data)) ref i)))

  (method ->list (self)
    (doc "The values as a list."
      (returns LIST "The values, in order")
      (example "((Column from '(1.5 2.5)) ->list)" "(1.5 2.5)"))
    (if (eq? (field (lit encoding)) (lit any))
      (Vector ->list (field (lit data)))
      ((field (lit data)) ->list)))

  (method tensor (self)
    (doc "The values as a rank-1 Tensor. A column of encoding any is refused."
      (returns Tensor "The Tensor the column holds, not a copy")
      (example "(((Column from '(1.5 2.5)) tensor) sum)" "4.0"))
    (if (eq? (field (lit encoding)) (lit any))
      (Err raise (lit value) "Column tensor: a column of encoding any holds no numbers" self)
      (field (lit data))))

  ; OTHER as a Tensor's arithmetic takes it: a Column's Tensor, or the
  ; number or Tensor it is.
  (method %operand (self other)
    (if (if (object? other) (instance-of? other Column) #f) (other tensor) other))

  (method add (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "The sum, element by element, as a Tensor's add answers it."
      (returns Column "A column of the sums")
      (example "(((Column from '(1.5 2.5)) add (Column from '(10.0 20.0))) ->list)" "(11.5 22.5)"))
    (Column from ((self tensor) add (self %operand other))))
  (method sub (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "The difference, self less other, element by element."
      (returns Column "A column of the differences")
      (example "(((Column from '(1.5 2.5)) sub 0.5) ->list)" "(1.0 2.0)"))
    (Column from ((self tensor) sub (self %operand other))))
  (method mul (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "The product, element by element."
      (returns Column "A column of the products")
      (example "(((Column from '(1.5 2.5)) mul 2.0) ->list)" "(3.0 5.0)"))
    (Column from ((self tensor) mul (self %operand other))))
  (method div (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "The quotient, self over other, element by element."
      (returns Column "A column of the quotients")
      (example "(((Column from '(3.0 5.0)) div (Column from '(2.0 4.0))) ->list)" "(1.5 1.25)"))
    (Column from ((self tensor) div (self %operand other))))

  (method map (self (param f CALLABLE "Called with each value"))
    (doc "The column of what f answers of each value, in order. Its encoding is read from the answers, as from reads it."
      (returns Column "A column of the answers")
      (example "(((Column from '(\"Ann\" \"Bo\")) map (fn (_ s) (equal? s \"Bo\"))) ->list)" "(#f #t)")
      (example "(((Column from '(1.5 2.5)) map (fn (_ x) (< 2 x))) ->list)" "(#f #t)"))
    (Column from (List map f (self ->list))))

  ; The values at the row numbers of ROWS, as a column of this encoding.
  (method %take (self rows)
    (let ((v (Vector from-list (self ->list))))
      (Column %as self (List map (fn (_ i) (Vector ref i v)) rows))))

  (method sum (self)
    (doc "The sum of the values." (returns NUMBER "The sum")
      (example "((Column from '(1.5 2.5)) sum)" "4.0"))
    ((self tensor) sum))
  (method mean (self)
    (doc "The mean of the values." (returns FLOAT "The mean")
      (example "((Column from '(1.5 2.5)) mean)" "2.0"))
    ((self tensor) mean))
  (method least (self)
    (doc "The least of the values." (returns NUMBER "The least")
      (example "((Column from '(2.5 1.5 4.0)) least)" "1.5"))
    ((self tensor) least))
  (method greatest (self)
    (doc "The greatest of the values." (returns NUMBER "The greatest")
      (example "((Column from '(2.5 1.5 4.0)) greatest)" "4.0"))
    ((self tensor) greatest))
  (method variance (self . (param correction INTEGER "Optional, as a Tensor's variance takes it: 1 by default, 0 for the population"))
    (doc "The variance of the values." (returns FLOAT "The variance")
      (example "((Column from '(1.0 2.0 3.0)) variance)" "1.0"))
    (if (null? correction) ((self tensor) variance) ((self tensor) variance (first correction))))
  (method deviation (self . (param correction INTEGER "Optional, as for variance"))
    (doc "The standard deviation of the values." (returns FLOAT "The deviation")
      (known-as "standard deviation" "std")
      (example "((Column from '(1.0 2.0 3.0)) deviation)" "1.0"))
    (if (null? correction) ((self tensor) deviation) ((self tensor) deviation (first correction))))
  (method quantile (self (param q NUMBER "The fraction, from 0 to 1"))
    (doc "The value with the fraction q of the values at or below it, as a Tensor's quantile answers it." (returns FLOAT "The quantile")
      (example "((Column from '(1.0 2.0 3.0 4.0)) quantile 0.25)" "1.75"))
    ((self tensor) quantile q))
  (method median (self)
    (doc "The middle of the values in order: the quantile at a half." (returns FLOAT "The median")
      (example "((Column from '(3.0 1.0 2.0)) median)" "2.0"))
    ((self tensor) median)))

(def-class Table ()
  (doc "Columns of one length, each under a name, in order: rows are observations and columns what was observed of each. A name is a symbol; a string given as one is made a symbol. Every operation answers a new Table and changes none."
    (known-as "DataFrame" "data frame")
    (example "((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) extent)" "(2 2)")
    (see from) (see from-csv) (see names) (see extent) (see column) (see row)
    (see select) (see filter) (see sort) (see matrix) (see ->list)
    (see put) (see derive) (see remove) (see rename) (see split) (see aggregate))

  names     ; the columns' names, symbols, in order
  columns   ; the Columns, in the order of the names
  rows      ; the length of every column

  (static
    (method from (self (param pairs LIST "A list for each column: its name, then its values as Column from takes them"))
      (doc "A table of the columns given, each a name and its values. Every column must have the same length, and no name may come twice."
        (returns Table "The table")
        (example "((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) names)" "('age 'name)"))
      (self %of (List map (fn (_ p) (%name (first p))) pairs)
                (List map (fn (_ p) (Column from (List ref 1 p))) pairs)))

    (method from-csv (self (param text STRING "csv text whose first row names the columns"))
      (doc "A table read from csv text, the first row naming the columns. A column whose every field reads as a number becomes f64; any other holds its fields as strings."
        (returns Table "The table")
        (example "(((Table from-csv \"name,age\\nida,7\\nbo,9\\n\") column 'age) ->list)" "(7.0 9.0)")
        (example "(((Table from-csv \"name,age\\nida,7\\nbo,9\\n\") column 'name) ->list)" "(\"ida\" \"bo\")"))
      (import x/codec/csv)
      (let ((parsed (Csv parse text)))
        (if (null? parsed) (Err raise (lit value) "Table from-csv: the text has no row of names" text) ())
        (let ((width (List length (first parsed))))
          (List map
            (fn (_ record)
              (if (= (List length record) width) ()
                (Err raise (lit value) "Table from-csv: a row's width differs from the names'" record)))
            (rest parsed))
          (self %of (List map %name (first parsed))
                    (if (null? (rest parsed))
                      (List map (fn (_ n) (Column from ())) (first parsed))
                      (List map (fn (_ fields) (Column from (self %read fields)))
                                (%transpose (rest parsed))))))))

    ; FIELDS as Floats where every one reads as a number, else as they are.
    (method %read (self fields)
      (let go ((left fields) (acc ()))
        (if (null? left) (List reverse acc)
          (let ((x (guard (e ()) (float-of (first left)))))
            (if (float? x) (go (rest left) (pair x acc)) fields)))))

    (method %of (self names columns)
      (let ((rows (if (null? columns) 0 ((first columns) size))))
        (let go ((left names) (cols columns))
          (if (null? left) ()
            (do
              (if (List includes? (first left) (rest left))
                (Err raise (lit value) "Table: a column's name comes twice" (first left)) ())
              (if (= ((first cols) size) rows) ()
                (Err raise (lit value) "Table: every column must have the same length" (first left)))
              (go (rest left) (rest cols)))))
        (new-from self (list (lit names) names (lit columns) columns (lit rows) rows)))))

  (method names (self)
    (doc "The columns' names, in order."
      (returns LIST "The names, symbols")
      (example "((Table from '((age (31.0)) (name (\"Ann\")))) names)" "('age 'name)"))
    (field (lit names)))

  (method extent (self)
    (doc "The number of rows, then of columns."
      (known-as "shape" "dim")
      (returns LIST "(ROWS COLUMNS)")
      (example "((Table from '((age (31.0 45.0 28.0)))) extent)" "(3 1)"))
    (list (field (lit rows)) (List length (field (lit names)))))

  (method column (self (param name SYMBOL|STRING "The column's name"))
    (doc "The column under a name. A name the table does not have is refused."
      (returns Column "The column")
      (example "(((Table from '((age (31.0 45.0)))) column 'age) mean)" "38.0"))
    (let ((name (%name name)))
      (let go ((names (field (lit names))) (cols (field (lit columns))))
        (match
          ((null? names) (Err raise (lit value) "Table column: the table has no column of that name" name))
          ((eq? (first names) name) (first cols))
          (#t (go (rest names) (rest cols)))))))

  (method row (self (param i INTEGER "The row's number; negative counts from the end"))
    (doc "One row's values, in the order of the columns."
      (returns LIST "The values")
      (example "((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) row 1)" "(45.0 \"Bo\")"))
    (List map (fn (_ c) (c ref i)) (field (lit columns))))

  (method select (self (param names LIST "The names of the columns to keep, in the order wanted"))
    (doc "The table of the named columns, in the order named."
      (returns Table "A table of those columns")
      (example "(((Table from '((age (31.0)) (name (\"Ann\")) (city (\"Ely\")))) select '(city age)) names)" "('city 'age)"))
    (let ((names (List map %name names)))
      (Table %of names (List map (fn (_ n) (self column n)) names))))

  (method filter (self (param name SYMBOL|STRING "The column the rows are judged by")
                       (param pred CALLABLE "Called with that column's value in a row; true keeps the row"))
    (doc "The table of the rows where pred answers true of the named column's value, in their order."
      (returns Table "A table of the rows kept")
      (example "((((Table from '((age (31.0 45.0 28.0)) (name (\"Ann\" \"Bo\" \"Cy\")))) filter 'age (fn (_ a) (< 30 a))) column 'name) ->list)" "(\"Ann\" \"Bo\")"))
    (self %take
      (let go ((values ((self column name) ->list)) (i 0) (acc ()))
        (match
          ((null? values) (List reverse acc))
          ((pred (first values)) (go (rest values) (+ i 1) (pair i acc)))
          (#t (go (rest values) (+ i 1) acc))))))

  (method sort (self (param name SYMBOL|STRING "The column the rows are ordered by")
                     . (param before CALLABLE "Optional: called with two values, true where the first comes strictly first; < by default"))
    (doc "The table with its rows in the order of the named column, least first. Rows whose values are equal keep their order. A column < does not order, as one of strings, takes a before of its own."
      (known-as "arrange" "order by")
      (returns Table "A table of the rows in order")
      (example "((((Table from '((age (31.0 45.0 28.0)) (name (\"Ann\" \"Bo\" \"Cy\")))) sort 'age) column 'name) ->list)" "(\"Cy\" \"Ann\" \"Bo\")")
      (example "((((Table from '((age (31.0 45.0 28.0)))) sort 'age (fn (_ a b) (< b a))) column 'age) ->list)" "(45.0 31.0 28.0)"))
    (let ((before (if (null? before) < (first before))))
      (self %take
        (List map rest
          (List sort (fn (_ a b) (before (first a) (first b)))
            (let go ((values ((self column name) ->list)) (i 0) (acc ()))
              (if (null? values) (List reverse acc)
                (go (rest values) (+ i 1) (pair (pair (first values) i) acc)))))))))

  (method matrix (self (param names LIST "The names of the columns, in the order wanted"))
    (doc "The named columns as an f64 Matrix, a row for each of the table's rows: what a model takes as its predictors. Every one must hold numbers."
      (returns Matrix "A fresh f64 Matrix of the table's rows by the columns named")
      (example "(((Table from '((a (1.0 2.0)) (b (3.0 4.0)))) matrix '(b a)) ->list)" "((3.0 1.0) (4.0 2.0))"))
    (import x/num/matrix)
    (if (null? names) (Err raise (lit value) "Table matrix: no column is named" names) ())
    (Matrix from
      (%transpose (List map (fn (_ n) (((self column n) tensor) ->list)) names))
      (lit f64)))

  (method put (self (param name SYMBOL|STRING "The column's name")
                    (param values LIST|VECTOR|Tensor|Column "The values, a row for each of the table's, as Column from takes them"))
    (doc "The table with the column under that name: a name the table has is replaced where it stands, a new one is added last."
      (known-as "assign" "with column")
      (returns Table "A table with that column")
      (example "(((Table from '((age (31.0 45.0)))) put 'name '(\"Ann\" \"Bo\")) names)" "('age 'name)")
      (example "((((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) put 'age '(1.0 2.0)) column 'age) ->list)" "(1.0 2.0)"))
    (let ((name (%name name)) (column (Column from values)))
      (let go ((names (field (lit names))) (cols (field (lit columns))) (kept-names ()) (kept-cols ()))
        (match
          ((null? names)
            (Table %of (List reverse (pair name kept-names)) (List reverse (pair column kept-cols))))
          ((eq? (first names) name)
            (Table %of (List append (List reverse kept-names) (pair name (rest names)))
                       (List append (List reverse kept-cols) (pair column (rest cols)))))
          (#t (go (rest names) (rest cols) (pair (first names) kept-names) (pair (first cols) kept-cols)))))))

  (method derive (self (param name SYMBOL|STRING "The name of the column made")
                       (param names LIST "The names of the columns f is called with, in order")
                       (param f CALLABLE "Called for each row with that row's value of each named column; its answer is the row's value"))
    (doc "The table with a column worked out from others: put, of what f answers of the named columns' values, row by row."
      (known-as "mutate" "transform")
      (returns Table "A table with that column")
      (example "((((Table from '((w (8.0 18.0)) (h (2.0 3.0)))) derive 'r '(w h) (fn (_ w h) (Float / w (Float * h h)))) column 'r) ->list)" "(2.0 2.0)")
      (example "((((Table from '((score (40.0 70.0)))) derive 'grade '(score) (fn (_ s) (if (< 50 s) \"pass\" \"fail\"))) column 'grade) ->list)" "(\"fail\" \"pass\")"))
    (if (null? names) (Err raise (lit value) "Table derive: no column is named" names) ())
    (let ((lists (List map (fn (_ n) ((self column n) ->list)) names)))
      (self put name
        (if (null? (rest lists))
          (List map f (first lists))
          (List map (fn (_ row) (apply f row)) (%transpose lists))))))

  (method remove (self (param name SYMBOL|STRING "The column's name"))
    (doc "The table without the column under that name. A name the table does not have is refused."
      (known-as "drop")
      (returns Table "A table of the other columns")
      (example "(((Table from '((age (31.0)) (name (\"Ann\")))) remove 'age) names)" "('name)"))
    (let ((name (%name name)))
      (self column name)
      (self select (List filter (fn (_ n) (not (eq? n name))) (field (lit names))))))

  (method rename (self (param name SYMBOL|STRING "The column's name") (param to SYMBOL|STRING "Its new name"))
    (doc "The table with one column under a new name, where it stood. A name the table does not have, or a new name it has already, is refused."
      (returns Table "A table with that column renamed")
      (example "(((Table from '((age (31.0)) (name (\"Ann\")))) rename 'age 'years) names)" "('years 'name)"))
    (let ((name (%name name)) (to (%name to)))
      (self column name)
      (Table %of (List map (fn (_ n) (if (eq? n name) to n)) (field (lit names)))
                 (field (lit columns)))))

  ; The distinct values of the named column, in the order they first
  ; come, each with the row numbers it stands at.  Where the values have
  ; keys they are found in a hashed table, one lookup a row; where they
  ; have none, by %categories-walk.
  (method %categories (self name)
    (import x/type/dict)
    (let ((values ((self column name) ->list)))
      (let ((key (%category-key values)))
        (if (null? key) (self %categories-walk values)
          (let ((rows (Dict make)))
            (let go ((left values) (i 0) (seen ()))
              (if (null? left)
                (List map (fn (_ c) (pair (rest c) (List reverse (rows get (first c)))))
                          (List reverse seen))
                (let ((k (key (first left))))
                  (let ((had (rows get k)))
                    (rows set! k (pair i had))
                    (go (rest left) (+ i 1)
                        (if (null? had) (pair (pair k (first left)) seen) seen)))))))))))

  ; The same by comparing values with equal?: the values are walked once
  ; to find the distinct ones and once for each of those.
  (method %categories-walk (self values)
    (List map
      (fn (_ key)
        (pair key
          (let go ((left values) (i 0) (acc ()))
            (match
              ((null? left) (List reverse acc))
              ((equal? (first left) key) (go (rest left) (+ i 1) (pair i acc)))
              (#t (go (rest left) (+ i 1) acc))))))
      (let go ((left values) (acc ()))
        (match
          ((null? left) (List reverse acc))
          ((List includes? (first left) acc) (go (rest left) acc))
          (#t (go (rest left) (pair (first left) acc)))))))

  (method split (self (param name SYMBOL|STRING "The column whose distinct values part the rows"))
    (doc "Each distinct value of the named column with the table of the rows that have it, in the order the values first come. Rows keep their order."
      (known-as "group by" "partition by")
      (returns LIST "((VALUE . TABLE) ...)")
      (example "(List map first ((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 28.0)))) split 'city))" "(\"Ely\" \"Ayr\")")
      (example "(((rest (first ((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 28.0)))) split 'city))) column 'age) ->list)" "(31.0 28.0)"))
    (List map (fn (_ c) (pair (first c) (self %take (rest c)))) (self %categories name)))

  (method aggregate (self (param name SYMBOL|STRING "The column whose distinct values make the rows")
                          (param specs LIST "A list for each column made: its name, the column it is worked out from, and a function called with that column's values for one distinct value, as a Column"))
    (doc "A table with a row for each distinct value of the named column, in the order the values first come: that column, then a column for each spec, holding what its function answers of the source column's values among the rows with that value."
      (known-as "group by" "summarize" "summarise")
      (returns Table "A table of the named column and a column for each spec")
      (example "(((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 29.0)))) aggregate 'city (list (list 'mean-age 'age (fn (_ c) (c mean))))) ->list)" "(('city (\"Ely\" \"Ayr\")) ('mean-age (30.0 45.0)))"))
    (let ((name (%name name)) (categories (self %categories name)))
      (Table %of
        (pair name (List map (fn (_ s) (%name (first s))) specs))
        (pair (Column from (List map first categories))
              (List map
                (fn (_ s)
                  (let ((source (self column (List ref 1 s))) (f (List ref 2 s)))
                    (Column from (List map (fn (_ c) (f (source %take (rest c)))) categories))))
                specs)))))

  (method ->list (self)
    (doc "The table as from takes it: a list for each column, its name and then its values."
      (returns LIST "((NAME VALUES) ...)")
      (example "((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) ->list)" "(('age (31.0 45.0)) ('name (\"Ann\" \"Bo\")))"))
    (List map (fn (_ n c) (list n (c ->list))) (field (lit names)) (field (lit columns))))

  ; The table of the rows at the row numbers of ROWS.
  (method %take (self rows)
    (Table %of (field (lit names))
               (List map (fn (_ c) (c %take rows)) (field (lit columns))))))

(doc (provide x/data/table Table Column)
  "Tables of named columns, as values: a Table is read from lists or csv text and answers its columns, rows, a selection of columns, the rows a column's value passes, the rows in a column's order, and columns as a Matrix, a table with a column put, derived, removed or renamed, and its rows parted or summarized by a column's distinct values; a Column of numbers answers its statistics and its arithmetic."
  (example "(((Table from-csv \"name,age\\nida,7\\nbo,9\\n\") column 'age) mean)" "8.0"))
