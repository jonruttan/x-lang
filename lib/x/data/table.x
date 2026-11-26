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
;   (Table read 'csv text)       the first row names the columns; a tab
;                                after the text reads tab-separated text
;   (t write 'csv)               the table as csv text
;
;   (t names)  (t extent)        the names; the rows and the columns
;   (t column 'age)              one Column
;   (t row 0)                    one row's values, in column order
;   (t select '(age))            a Table of those columns
;   (t filter 'age pred)         the rows where pred answers true of age
;   (t filter mask)              the rows where the mask is not 0, as
;                                (t filter ((t column 'age) greater 30))
;   (t sort 'age)                the rows in the order of age
;   (t matrix '(age height))     those columns as an f64 Matrix
;   (t put 'bmi values)          the table with that column added or replaced
;   (t derive 'bmi '(weight height) f)   put, the values f answers of the
;                                named columns' values, row by row
;   (t remove 'age)  (t rename 'age 'years)
;   (t split 'city)              each distinct city with the table of its rows
;   (t aggregate 'city specs)    a table with a row for each distinct city
;                                and a column for each summary asked for
;   (t join other 'city)         each row with the rows of other of its city;
;                                'left or 'full after it keeps the rows
;                                with no partner, their other values missing
;
; A Column of numbers also answers add, sub, mul, div, min and max,
; element by element as a Tensor's do, and any Column answers map.
;
; filter and sort find the rows to keep as a list of row numbers, once,
; and each column is then gathered by it: a column of numbers by its
; Tensor's gather.
;
; A missing value is a NaN in a column of numbers and nil in a column of
; encoding any; an empty csv field and a nil among numbers read as one.
; missing and present answer masks of them and fill-missing replaces
; them.  The statistics do not skip a missing number: they answer a NaN.
; sort puts the rows with a missing value last, and split and aggregate
; make one category of them.
;
; A mask is a column of 1.0 and 0.0, as a Column's less, greater, at-most,
; at-least, equal and differ answer one: filter keeps the rows where a
; mask is not 0, and reads the mask without making a value of each row.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/data/table)
(import x/type/class)
(import x/type/list)
(import x/type/vector)
(import x/core/doors io-display-to-str str->sym type-of)
(import x/num/float Float float? float-of f-div f-eq f-lt)
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
    (see add) (see sub) (see mul) (see div) (see map)
    (see missing) (see present) (see fill-missing))

  encoding   ; a Tensor's encoding, or any
  data       ; a rank-1 Tensor, or for any a Vector

  (static
    (method from (self (param values LIST|VECTOR|Tensor|Column "The values, in order"))
      (doc "A column of the values. A Tensor is kept as it is; a list or a Vector of integers and Floats becomes a Tensor, of f64 unless every one is an integer; any other becomes a column of encoding any. A nil among numbers is a missing value: the column is f64 and holds a NaN there. In a column of encoding any a nil is the missing value."
        (returns Column "The column")
        (example "((Column from '(1.5 2.5)) ->list)" "(1.5 2.5)")
        (example "((Column from (list 1.5 () 4.0)) encoding)" "'f64")
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
      (match
        ((not (pair? lst)) (self %of-any lst))
        ((%numbers? lst) (self %of-tensor (Tensor from lst)))
        ((self %numbers-or-nil? lst)
          (let ((nan (self %nan)))
            (self %of-tensor (Tensor from (List map (fn (_ x) (if (null? x) nan x)) lst) (lit f64)))))
        (#t (self %of-any lst))))

    ; A missing number: a NaN.
    (method %nan (self) (f-div (float-of 0) (float-of 0)))

    ; #t where every element of LST is a number or nil, and one is a number.
    (method %numbers-or-nil? (self lst)
      (let go ((left lst) (seen #f))
        (match
          ((null? left) seen)
          ((null? (first left)) (go (rest left) seen))
          ((if (number? (first left)) #t (float? (first left))) (go (rest left) #t))
          (#t #f))))

    (method %of-any (self lst)
      (new-from self (list (lit encoding) (lit any) (lit data) (Vector from-list lst)))))

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

  (method min (self . (param other Column|Tensor|NUMBER "Optional: a column of the same size, or a number"))
    (doc "Given other, the lesser, element by element, as a Tensor's min answers it: of two masks, the rows both keep, as mul is. Given nothing, the least of the values."
      (returns Column|NUMBER "A column of the lesser values, or the least value")
      (example "(((Column from '(1.5 2.5)) min 2.0) ->list)" "(1.5 2.0)")
      (example "((Column from '(2.5 1.5 4.0)) min)" "1.5"))
    (if (null? other)
      ((self tensor) min)
      (Column from ((self tensor) min (self %operand (first other))))))
  (method max (self . (param other Column|Tensor|NUMBER "Optional: a column of the same size, or a number"))
    (doc "Given other, the greater, element by element, as a Tensor's max answers it: of two masks, the rows either keeps. Given nothing, the greatest of the values."
      (returns Column|NUMBER "A column of the greater values, or the greatest value")
      (example "(((Column from '(1.5 2.5)) max 2.0) ->list)" "(2.0 2.5)")
      (example "((Column from '(2.5 1.5 4.0)) max)" "4.0"))
    (if (null? other)
      ((self tensor) max)
      (Column from ((self tensor) max (self %operand (first other))))))

  ; The mask of WHICH against OTHER, with the operands changed over where
  ; SWAP.  A column of numbers asks its Tensor.  A column of encoding any
  ; answers equal and differ by equal?, against a value or a column of its
  ; size, and has no order.
  (method %compare (self which other swap)
    (if (eq? (field (lit encoding)) (lit any))
      (let ((mine (self ->list)) (one (float-of 1)) (zero (float-of 0))
            (column? (if (object? other) (instance-of? other Column) #f)))
        (if (if (eq? which (lit equal)) #f (not (eq? which (lit differ))))
          (Err raise (lit value) "Column: a column of encoding any has no order" which) ())
        (if (if column? (not (= (other size) (self size))) #f)
          (Err raise (lit value) "Column: the columns differ in size" (list (self size) (other size))) ())
        (let ((yes (if (eq? which (lit equal)) one zero)) (no (if (eq? which (lit equal)) zero one)))
          (Column from
            (Tensor from
              (if column?
                (List map (fn (_ a b) (if (equal? a b) yes no)) mine (other ->list))
                (List map (fn (_ a) (if (equal? a other) yes no)) mine))
              (lit f64)))))
      (Column from ((self tensor) %compare which (self %operand other) swap))))

  (method less (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "A mask: a column of 1.0 where the value is less than other's and 0.0 where it is not, as a Tensor's less answers it. Table filter keeps the rows where a mask is not 0; mul of two masks is the rows both keep, max the rows either keeps, and a mask's sum is how many it keeps."
      (known-as "lt" "less than")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) less 2.5) ->list)" "(1.0 0.0 0.0)"))
    (self %compare (lit less) other #f))
  (method greater (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "A mask: 1.0 where the value is greater than other's and 0.0 where it is not."
      (known-as "gt" "greater than")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) greater 2.5) ->list)" "(0.0 0.0 1.0)"))
    (self %compare (lit less) other #t))
  (method at-most (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "A mask: 1.0 where the value is less than other's or equal to it and 0.0 where it is not."
      (known-as "le" "lte" "less than or equal")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) at-most 2.5) ->list)" "(1.0 1.0 0.0)"))
    (self %compare (lit at-most) other #f))
  (method at-least (self (param other Column|Tensor|NUMBER "A column of the same size, or a number"))
    (doc "A mask: 1.0 where the value is greater than other's or equal to it and 0.0 where it is not."
      (known-as "ge" "gte" "greater than or equal")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) at-least 2.5) ->list)" "(0.0 1.0 1.0)"))
    (self %compare (lit at-most) other #t))
  (method equal (self (param other ANY "A column of the same size, or a value"))
    (doc "A mask: 1.0 where the value equals other's and 0.0 where it does not. A column of encoding any answers by equal?."
      (known-as "eq" "equal to")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) equal 2.5) ->list)" "(0.0 1.0 0.0)")
      (example "(((Column from '(\"Ann\" \"Bo\")) equal \"Bo\") ->list)" "(0.0 1.0)"))
    (self %compare (lit equal) other #f))
  (method differ (self (param other ANY "A column of the same size, or a value"))
    (doc "A mask: 1.0 where the value does not equal other's and 0.0 where it does. A column of encoding any answers by equal?."
      (known-as "ne" "neq" "not equal")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from '(1.5 2.5 4.0)) differ 2.5) ->list)" "(1.0 0.0 1.0)"))
    (self %compare (lit differ) other #f))

  ; --- missing values ----------------------------------------------------------
  ; (fn (_ v) -> BOOL), true of a value of this column that is missing: nil
  ; for encoding any, a NaN for f64 and f32, and nothing for the rest.
  (method %missing-test (self)
    (let ((enc (field (lit encoding))))
      (match
        ((eq? enc (lit any)) (fn (_ v) (null? v)))
        ((if (eq? enc (lit f64)) #t (eq? enc (lit f32))) (fn (_ v) (not (f-eq v v))))
        (#t (fn (_ v) #f)))))

  (method missing (self)
    (doc "A mask: 1.0 where the value is missing and 0.0 where it is not. A missing number is a NaN, and in a column of encoding any the missing value is nil. The statistics of a column with a missing number answer a NaN; filter by present first to leave the missing rows out."
      (known-as "isna" "isnull" "is null")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from (list 1.5 () 4.0)) missing) ->list)" "(0.0 1.0 0.0)"))
    (if (eq? (field (lit encoding)) (lit any))
      (let ((one (float-of 1)) (zero (float-of 0)))
        (Column from (Tensor from (List map (fn (_ v) (if (null? v) one zero)) (self ->list)) (lit f64))))
      (let ((t (field (lit data)))) (Column from (t differ t)))))
  (method present (self)
    (doc "A mask: 1.0 where the value is not missing and 0.0 where it is, as missing reads it."
      (known-as "notna" "notnull" "is not null")
      (returns Column "An f64 column of 1.0 and 0.0")
      (example "(((Column from (list 1.5 () 4.0)) present) ->list)" "(1.0 0.0 1.0)"))
    (if (eq? (field (lit encoding)) (lit any))
      (let ((one (float-of 1)) (zero (float-of 0)))
        (Column from (Tensor from (List map (fn (_ v) (if (null? v) zero one)) (self ->list)) (lit f64))))
      (let ((t (field (lit data)))) (Column from (t equal t)))))
  (method fill-missing (self (param value ANY "What stands where a value is missing: a number for a column of numbers"))
    (doc "The column with value where a value is missing, and every other value as it is."
      (known-as "fillna" "coalesce")
      (returns Column "A column with no missing value; self where none is missing")
      (example "(((Column from (list 1.5 () 4.0)) fill-missing 0.0) ->list)" "(1.5 0.0 4.0)"))
    (if (eq? (field (lit encoding)) (lit any))
      (Column from (List map (fn (_ v) (if (null? v) value v)) (self ->list)))
      (let ((t (field (lit data))))
        (let ((places (Tensor %unpack-rows ((t differ t) %mask-packed))))
          (if (null? places) self
            (let ((out (t copy)))
              (List map (fn (_ i) (out set! i value)) places)
              (Column from out)))))))

  (method map (self (param f CALLABLE "Called with each value"))
    (doc "The column of what f answers of each value, in order. Its encoding is read from the answers, as from reads it."
      (returns Column "A column of the answers")
      (example "(((Column from '(\"Ann\" \"Bo\")) map (fn (_ s) (equal? s \"Bo\"))) ->list)" "(#f #t)")
      (example "(((Column from '(1.5 2.5)) map (fn (_ x) (< 2 x))) ->list)" "(#f #t)"))
    (Column from (List map f (self ->list))))

  ; The values at the row numbers of ROWS, as a column of this encoding:
  ; a Tensor's by its gather, a copy of each value's bytes, and a
  ; Vector's by reading each.
  ; The rows in the order of the values under <, packed, where Tensor's
  ; order kernel answers; () where it does not, and for encoding any.
  (method %order-packed (self)
    (if (eq? (field (lit encoding)) (lit any)) () ((field (lit data)) %order-packed)))

  ; The rows parted by value where Tensor's kernels answer, as its %runs
  ; gives them; () where they do not, and for encoding any.
  (method %runs (self)
    (if (eq? (field (lit encoding)) (lit any)) () ((field (lit data)) %runs)))

  ; COUNT values from START, with no check: a view of the tensor for a
  ; column of numbers, a copy of those values for encoding any.
  (method %rows (self start count)
    (let ((data (field (lit data))))
      (if (eq? (field (lit encoding)) (lit any))
        (Column %of-any
          (let go ((k (+ start count -1)) (acc ()))
            (if (< k start) acc (go (- k 1) (pair (Vector ref k data) acc)))))
        (new-from Column (list (lit encoding) (field (lit encoding)) (lit data) (data %rows start count))))))

  ; Each value as a field of text: a string as it is, a missing value
  ; empty, and any other as it prints.
  (method %fields (self)
    (let ((gone? (self %missing-test)))
      (List map
        (fn (_ v) (match ((gone? v) "") ((str? v) v) (#t (io-display-to-str v))))
        (self ->list))))

  ; The values at ROWS, and a missing value where a row is nil.
  (method %take-or-missing (self rows)
    (if (List any? (fn (_ i) (null? i)) rows)
      (let ((values (if (eq? (field (lit encoding)) (lit any)) (field (lit data)) (Vector from-list (self ->list)))))
        (Column from (List map (fn (_ i) (if (null? i) () (Vector ref i values))) rows)))
      (self %take rows (Tensor %pack-rows rows))))

  ; PACKED is ROWS, each a row of this column, from (Tensor %pack-rows ROWS).
  (method %take (self rows packed)
    (if (eq? (field (lit encoding)) (lit any))
      (let ((v (field (lit data))))
        (Column %of-any (List map (fn (_ i) (Vector ref i v)) rows)))
      (Column %of-tensor ((field (lit data)) %gather-packed packed))))

  (method sum (self)
    (doc "The sum of the values." (returns NUMBER "The sum")
      (example "((Column from '(1.5 2.5)) sum)" "4.0"))
    ((self tensor) sum))
  (method mean (self)
    (doc "The mean of the values." (returns FLOAT "The mean")
      (example "((Column from '(1.5 2.5)) mean)" "2.0"))
    ((self tensor) mean))
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
    (see from) (see read) (see write) (see formats) (see names) (see extent) (see column) (see row)
    (see select) (see filter) (see sort) (see matrix) (see ->list)
    (see put) (see derive) (see remove) (see rename) (see split) (see aggregate) (see join))

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

    (method formats (self)
      (doc "The formats (Table read) reads and a table's write writes."
        (returns LIST "The formats' names")
        (example "(Table formats)" "('csv)"))
      (list (lit csv)))

    ; FORMAT as one of formats' names: a symbol as it is, a string made one.
    (method %format (self format)
      (let ((name (match ((symbol? format) format) ((str? format) (str->sym format)) (#t ()))))
        (if (if (null? name) #f (List includes? name (self formats))) name
          (Err raise (lit value) "Table: no such format" format))))

    (method read (self (param format SYMBOL|STRING "A format's name, from (Table formats)")
                       (param text STRING "The table's text")
                       . (param separator STRING "Optional, for csv: the character between fields, a comma by default"))
      (doc "A table read from text in a format. csv: the first row names the columns; a column whose every field reads as a number becomes f64, and any other holds its fields as strings; an empty field is a missing value, a NaN in a column of numbers and nil in a column of strings. With a tab for the separator it reads tab-separated text."
        (known-as "read_csv" "read csv" "tsv" "tab-separated")
        (returns Table "The table")
        (example "(((Table read 'csv \"name,age\\nida,7\\nbo,9\\n\") column 'age) ->list)" "(7.0 9.0)")
        (example "((((Table read 'csv \"name,age\\nida,7\\nbo,\\n\") column 'age) missing) ->list)" "(0.0 1.0)")
        (example "((Table read \"csv\" \"name|age\\nida|7\\n\" \"|\") names)" "('name 'age)"))
      (self %format format)
      (self %read-csv text (if (null? separator) "," (first separator))))

    (method %read-csv (self text separator)
      (import x/codec/csv)
      (let ((parsed (Csv parse-by separator text)))
        (if (null? parsed) (Err raise (lit value) "Table read: the text has no row of names" text) ())
        (let ((width (List length (first parsed))))
          (List map
            (fn (_ record)
              (if (= (List length record) width) ()
                (Err raise (lit value) "Table read: a row's width differs from the names'" record)))
            (rest parsed))
          (self %of (List map %name (first parsed))
                    (if (null? (rest parsed))
                      (List map (fn (_ n) (Column from ())) (first parsed))
                      (List map (fn (_ fields) (Column from (self %read fields)))
                                (%transpose (rest parsed))))))))

    ; FIELDS as Floats where every one that is not empty reads as a number
    ; and one does, else as they are; an empty field is nil either way.
    (method %read (self fields)
      (let ((text (fn (_) (List map (fn (_ s) (if (equal? s "") () s)) fields))))
        (let go ((left fields) (acc ()) (seen #f))
          (match
            ((null? left) (if seen (List reverse acc) (text)))
            ((equal? (first left) "") (go (rest left) (pair () acc) seen))
            (#t
              (let ((x (guard (e ()) (float-of (first left)))))
                (if (float? x) (go (rest left) (pair x acc) #t) (text))))))))

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
        (new-from self (list (lit names) names (lit columns) columns (lit rows) rows))))

    ; A table of COLUMNS under NAMES, each of ROWS values, with no check:
    ; for a caller whose columns are a table's own, cut alike.
    (method %of-parts (self names columns rows)
      (new-from self (list (lit names) names (lit columns) columns (lit rows) rows))))

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

  (method filter (self (param name SYMBOL|STRING|Column|Tensor "The column the rows are judged by, or a mask: a column or rank-1 tensor of a number for each row")
                       . (param pred CALLABLE "With a column's name: called with that column's value in a row; true keeps the row"))
    (doc "The table of the rows kept, in their order. Given a column's name and pred, the rows where pred answers true of that column's value. Given a mask, such as a Column's greater answers, the rows where its number is not 0."
      (returns Table "A table of the rows kept")
      (example "((((Table from '((age (31.0 45.0 28.0)) (name (\"Ann\" \"Bo\" \"Cy\")))) filter 'age (fn (_ a) (< 30 a))) column 'name) ->list)" "(\"Ann\" \"Bo\")")
      (example "(let ((t (Table from '((age (31.0 45.0 28.0)) (name (\"Ann\" \"Bo\" \"Cy\")))))) (((t filter ((t column 'age) greater 30)) column 'name) ->list))" "(\"Ann\" \"Bo\")"))
    (if (null? pred)
      (let ((mask (if (if (object? name) (instance-of? name Column) #f) (name tensor) name)))
        (if (if (object? mask) (instance-of? mask Tensor) #f) ()
          (Err raise (lit type) "Table filter: a mask is a Column or a Tensor" name))
        (if (equal? (mask extent) (list (field (lit rows)))) ()
          (Err raise (lit value) "Table filter: a mask has a number for each row" (mask extent)))
        (self %take-packed (mask %mask-packed)))
      (let ((pred (first pred)))
        (self %take
          (let go ((values ((self column name) ->list)) (i 0) (acc ()))
            (match
              ((null? values) (List reverse acc))
              ((pred (first values)) (go (rest values) (+ i 1) (pair i acc)))
              (#t (go (rest values) (+ i 1) acc))))))))

  (method sort (self (param name SYMBOL|STRING "The column the rows are ordered by")
                     . (param before CALLABLE "Optional: called with two values, true where the first comes strictly first; < by default"))
    (doc "The table with its rows in the order of the named column, least first. Rows whose values are equal keep their order. Rows whose value is missing come last, in their own order, and before is not called with one. A column < does not order, as one of strings, takes a before of its own."
      (known-as "arrange" "order by")
      (returns Table "A table of the rows in order")
      (example "((((Table from '((age (31.0 45.0 28.0)) (name (\"Ann\" \"Bo\" \"Cy\")))) sort 'age) column 'name) ->list)" "(\"Cy\" \"Ann\" \"Bo\")")
      (example "((((Table from '((age (31.0 45.0 28.0)))) sort 'age (fn (_ a b) (< b a))) column 'age) ->list)" "(45.0 31.0 28.0)"))
    (let ((packed (if (null? before) ((self column name) %order-packed) ()))
          (before (if (null? before) < (first before))))
      (if (null? packed)
        ; HERE is each value not missing with its row, GONE the rows of the rest
        (let ((gone? ((self column name) %missing-test)))
          (let go ((values ((self column name) ->list)) (i 0) (here ()) (gone ()))
            (match
              ((null? values)
                (self %take
                  (List append
                    (List map rest (List sort (fn (_ a b) (before (first a) (first b))) (List reverse here)))
                    (List reverse gone))))
              ((gone? (first values)) (go (rest values) (+ i 1) here (pair i gone)))
              (#t (go (rest values) (+ i 1) (pair (pair (first values) i) here) gone)))))
        (self %take-packed packed))))

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
  ; come, and the rows each stands at: (ORDER . CATEGORIES).  A column of
  ; numbers is parted by Tensor's kernels where they answer: ORDER is the
  ; rows in the order of the values, packed, and each category is (VALUE
  ; START . COUNT), its rows the COUNT in ORDER from START, in their own
  ; order.  Else ORDER is () and each category is (VALUE . ROWS), the rows
  ; a list: found in a hashed table where the values have keys, one lookup
  ; a row, and where they have none by %categories-walk.  The rows whose
  ; value is missing are one category, under the last such value.
  (method %categories (self name)
    (let ((column (self column name)))
      (let ((runs (column %runs)))
        (if (null? runs)
          (pair () (self %categories-parted column))
          (pair (first runs) (List map (fn (_ r) (pair (column ref (first r)) (rest r))) (rest runs)))))))

  ; Column SOURCE's values for each category of CATS, from %categories,
  ; as a Column each.  PICKS is each category's (ROWS . PACKED) where the
  ; categories came as lists, and () where they came in an order: then
  ; SOURCE is gathered once in that order, and each category's Column is
  ; its range of it.
  (method %pieces (self source cats picks)
    (if (null? (first cats))
      (List map (fn (_ p) (source %take (first p) (rest p))) picks)
      (let ((sorted (source %take
                      (if (eq? (source encoding) (lit any)) (Tensor %unpack-rows (first cats)) ())
                      (first cats))))
        (List map (fn (_ c) (sorted %rows (first (rest c)) (rest (rest c)))) (rest cats)))))

  ; Each category's (ROWS . PACKED), made once for every column, where the
  ; categories came as lists; () where they came in an order.
  (method %picks (self cats)
    (if (null? (first cats))
      (List map (fn (_ c) (pair (rest c) (Tensor %pack-rows (rest c)))) (rest cats))
      ()))

  ; ((VALUE . ROWS) ...) for COLUMN's values.  Where one is missing, the
  ; values that are not are parted on their own, their rows put back to
  ; the column's, and the missing rows' category takes its place by the
  ; row it first comes at.
  (method %categories-parted (self column)
    (let ((values (column ->list)) (gone? (column %missing-test)))
      (if (List any? gone? values)
        (let go ((left values) (i 0) (here ()) (gone ()) (value ()))
          (match
            ((null? left)
              (let ((at (Vector from-list (List reverse (List map rest here)))))
                (List sort (fn (_ a b) (< (first (rest a)) (first (rest b))))
                  (pair (pair value (List reverse gone))
                        (List map (fn (_ c) (pair (first c) (List map (fn (_ r) (Vector ref r at)) (rest c))))
                                  (self %categories-listed (List reverse (List map first here))))))))
            ((gone? (first left)) (go (rest left) (+ i 1) here (pair i gone) (first left)))
            (#t (go (rest left) (+ i 1) (pair (pair (first left) i) here) gone value))))
        (self %categories-listed values))))

  ; ((VALUE . ROWS) ...) for VALUES, by a hashed table or by the walk.
  (method %categories-listed (self values)
    (import x/type/dict)
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
                      (if (null? had) (pair (pair k (first left)) seen) seen))))))))))

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
    (doc "Each distinct value of the named column with the table of the rows that have it, in the order the values first come. Rows keep their order. The rows whose value is missing make one such table, under a missing value."
      (known-as "group by" "partition by")
      (returns LIST "((VALUE . TABLE) ...)")
      (example "(List map first ((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 28.0)))) split 'city))" "(\"Ely\" \"Ayr\")")
      (example "(((rest (first ((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 28.0)))) split 'city))) column 'age) ->list)" "(31.0 28.0)"))
    (let ((cats (self %categories name)) (names (field (lit names))))
      (let ((picks (self %picks cats)))
        ; each column's pieces, a category's columns then the list of those
        (let ((pieces (%transpose (List map (fn (_ c) (self %pieces c cats picks)) (field (lit columns))))))
          (List map (fn (_ v cols) (pair (first v) (Table %of-parts names cols ((first cols) size))))
            (rest cats) pieces)))))

  (method aggregate (self (param name SYMBOL|STRING "The column whose distinct values make the rows")
                          (param specs LIST "A list for each column made: its name, the column it is worked out from, and a function called with that column's values for one distinct value, as a Column"))
    (doc "A table with a row for each distinct value of the named column, in the order the values first come: that column, then a column for each spec, holding what its function answers of the source column's values among the rows with that value. The rows whose value is missing make one row of it."
      (known-as "group by" "summarize" "summarise")
      (returns Table "A table of the named column and a column for each spec")
      (example "(((Table from '((city (\"Ely\" \"Ayr\" \"Ely\")) (age (31.0 45.0 29.0)))) aggregate 'city (list (list 'mean-age 'age (fn (_ c) (c mean))))) ->list)" "(('city (\"Ely\" \"Ayr\")) ('mean-age (30.0 45.0)))"))
    (let ((name (%name name)) (cats (self %categories name)))
      (let ((picks (self %picks cats)))
        (Table %of
          (pair name (List map (fn (_ s) (%name (first s))) specs))
          (pair (Column from (List map first (rest cats)))
                (List map
                  (fn (_ s)
                    (let ((f (List ref 2 s)))
                      (Column from (List map f (self %pieces (self column (List ref 1 s)) cats picks)))))
                  specs))))))

  (method join (self (param other Table "The table whose rows are paired with self's")
                     (param on SYMBOL|STRING|LIST "The name of the column both tables are matched by, or a list of such names")
                     . (param keep SYMBOL "Optional: left keeps every row of self, and full every row of both; by default only rows with a partner are kept"))
    (doc "The table of self's rows, each paired with the rows of other whose values under on equal its own: self's columns, then other's columns but the ones matched by. A row is paired with every partner it has, in other's order, and the rows come in self's order. A row with no partner is left out unless keep says otherwise: with left it is kept with missing values for other's columns, and with full other's rows with no partner follow as well, with missing values for self's. A row whose value under on is missing has no partner. A column other than on with one name in both tables is refused."
      (known-as "merge" "inner join" "left join" "outer join")
      (returns Table "A table of the paired rows")
      (example "(((Table from '((city (\"Ely\" \"Ayr\")) (age (31.0 45.0)))) join (Table from '((city (\"Ayr\" \"Oban\")) (pop (46.0 8.0)))) 'city) ->list)" "(('city (\"Ayr\")) ('age (45.0)) ('pop (46.0)))")
      (example "((((Table from '((city (\"Ely\" \"Ayr\")) (age (31.0 45.0)))) join (Table from '((city (\"Ayr\" \"Oban\")) (pop (46.0 8.0)))) 'city 'left) column 'city) ->list)" "(\"Ely\" \"Ayr\")"))
    (let ((keys (List map %name (if (if (pair? on) #t (null? on)) on (list on))))
          (keep (if (null? keep) () (first keep))))
      (if (null? keys) (Err raise (lit value) "Table join: no column to match by" on) ())
      (if (if (null? keep) #t (if (eq? keep (lit left)) #t (eq? keep (lit full)))) ()
        (Err raise (lit value) "Table join: keep is left or full" keep))
      (let ((mine (field (lit names)))
            (theirs (List filter (fn (_ n) (not (List includes? n keys))) (other names))))
        (List map
          (fn (_ n) (if (List includes? n mine) (Err raise (lit value) "Table join: a column's name is in both tables" n) ()))
          theirs)
        (let ((pairs (self %join-pairs other keys keep)))
          (let ((left (List map first pairs)) (right (List map rest pairs)))
            (Table %of (List append mine theirs)
              (List append
                (List map
                  (fn (_ n)
                    (if (List includes? n keys)
                      (self %join-key (self column n) (other column n) pairs)
                      ((self column n) %take-or-missing left)))
                  mine)
                (List map (fn (_ n) ((other column n) %take-or-missing right)) theirs))))))))

  ; A column matched by, for PAIRS: self's value where the pair has a row
  ; of self, and other's where it has none.
  (method %join-key (self mine theirs pairs)
    (if (List any? (fn (_ p) (null? (first p))) pairs)
      (let ((a (Vector from-list (mine ->list))) (b (Vector from-list (theirs ->list))))
        (Column from
          (List map (fn (_ p) (if (null? (first p)) (Vector ref (rest p) b) (Vector ref (first p) a))) pairs)))
      (mine %take-or-missing (List map first pairs))))

  ; ((MINE . THEIRS) ...): each row of self with each row of OTHER that has
  ; its values under KEYS, in self's order and then other's.  With KEEP a
  ; row of self with no partner is paired with nil, and with KEEP full
  ; the rows of OTHER with no partner follow, nil before each.
  (method %join-pairs (self other keys keep)
    (import x/type/dict)
    (let ((n (field (lit rows))) (m (first (other extent))))
      (let ((ids (self %join-ids other keys (+ n m))) (partners (Dict make)) (met (Dict make)))
        ; other's rows under each id, in their order
        (let go ((j (- m 1)))
          (if (< j 0) ()
            (let ((id (Vector ref (+ n j) ids)))
              (if (< id 0) () (partners set! id (pair j (partners get id))))
              (go (- j 1)))))
        (let ((paired
                (let go ((i (- n 1)) (acc ()))
                  (if (< i 0) acc
                    (let ((id (Vector ref i ids)))
                      (let ((found (if (< id 0) () (partners get id))))
                        (if (null? found) () (met set! id #t))
                        (go (- i 1)
                            (match
                              ((null? found) (if (null? keep) acc (pair (pair i ()) acc)))
                              (#t (List append (List map (fn (_ j) (pair i j)) found) acc))))))))))
          (if (eq? keep (lit full))
            (List append paired
              (let go ((j (- m 1)) (acc ()))
                (if (< j 0) acc
                  (let ((id (Vector ref (+ n j) ids)))
                    (go (- j 1) (if (if (< id 0) #f (met get id)) acc (pair (pair () j) acc)))))))
            paired)))))

  ; A number for each row of self and then of OTHER, TOTAL in all, the
  ; same for two rows where their values under KEYS are equal, and -1 for
  ; a row with a missing value under one.  Each key's values, self's and
  ; other's together, are parted as split parts them, and a row's number
  ; is made of its category's place under each key.
  (method %join-ids (self other keys total)
    (import x/type/dict)
    (let go ((left keys) (ids ()))
      (if (null? left) (Vector from-list ids)
        (let ((column (Column from (List append ((self column (first left)) ->list) ((other column (first left)) ->list)))))
          (let ((cats (self %categories-parted column)) (gone? (column %missing-test)) (place (Dict make)))
            (let number ((cats cats) (k 0))
              (if (null? cats) ()
                (let ((mark (if (gone? (first (first cats))) -1 k)))
                  (List map (fn (_ row) (place set! row mark)) (rest (first cats)))
                  (number (rest cats) (+ k 1)))))
            (let ((numbers (List map (fn (_ row) (place get row)) (List range 0 total))) (count (List length cats)))
              (go (rest left)
                  (if (null? ids) numbers
                    (List map (fn (_ a b) (if (if (< a 0) #t (< b 0)) -1 (+ (* a count) b))) ids numbers)))))))))

  (method write (self (param format SYMBOL|STRING "A format's name, from (Table formats)")
                      . (param separator STRING "Optional, for csv: the character between fields, a comma by default"))
    (doc "The table as text in a format. csv: a row of the columns' names, then a row for each of the table's; a number is written as it prints and a string as it is, quoted where it holds the separator, a quote or a line's end; a missing value is an empty field. (Table read) reads the text back, but for a string that is empty, which comes back missing, and a column of strings that all read as numbers, which comes back as numbers. With a tab for the separator it writes tab-separated text."
      (known-as "to_csv" "write csv" "tsv" "tab-separated")
      (returns STRING "The text")
      (example "((Table from '((name (\"Ann\" \"Bo\")) (age (31.0 45.0)))) write 'csv)" "\"name,age\\nAnn,31.0\\nBo,45.0\\n\""))
    (Table %format format)
    (import x/codec/csv)
    (Csv emit-by (if (null? separator) "," (first separator))
      (pair (List map (fn (_ n) (symbol->str n)) (field (lit names)))
            (%transpose (List map (fn (_ c) (c %fields)) (field (lit columns)))))))

  (method ->list (self)
    (doc "The table as from takes it: a list for each column, its name and then its values."
      (returns LIST "((NAME VALUES) ...)")
      (example "((Table from '((age (31.0 45.0)) (name (\"Ann\" \"Bo\")))) ->list)" "(('age (31.0 45.0)) ('name (\"Ann\" \"Bo\")))"))
    (List map (fn (_ n c) (list n (c ->list))) (field (lit names)) (field (lit columns))))

  ; The table of the rows at the row numbers of ROWS.
  ; %take for rows already packed; the list of them is made only where a
  ; column of encoding any reads by it.
  (method %take-packed (self packed)
    (let ((columns (field (lit columns))))
      (let ((rows (if (List any? (fn (_ c) (eq? (c encoding) (lit any))) columns) (Tensor %unpack-rows packed) ())))
        (Table %of (field (lit names)) (List map (fn (_ c) (c %take rows packed)) columns)))))

  ; ROWS are rows of this table, which every caller here makes by counting
  ; them.  They are packed once, and each column of numbers gathers by that.
  (method %take (self rows)
    (let ((packed (Tensor %pack-rows rows)))
      (Table %of (field (lit names))
                 (List map (fn (_ c) (c %take rows packed)) (field (lit columns))))))))

(doc (provide x/data/table Table Column)
  "Tables of named columns, as values: a Table is read from lists or csv text, written as csv text, and answers its columns, rows, a selection of columns, the rows a column's value passes, the rows in a column's order, and columns as a Matrix, a table with a column put, derived, removed or renamed, its rows parted or summarized by a column's distinct values, and its rows paired with another table's by a column they share; a Column of numbers answers its statistics, its arithmetic and its comparisons, each a mask of the rows that pass."
  (example "(((Table read 'csv \"name,age\\nida,7\\nbo,9\\n\") column 'age) mean)" "8.0"))
