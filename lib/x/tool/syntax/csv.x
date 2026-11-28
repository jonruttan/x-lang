; csv.x -- the CSV and TSV highlighting grammars
;
; x/tool/syntax's catalogue names this module for .csv and .tsv files and
; imports it the first time a file needs one of its grammars.  It registers
; csv, its fields parted by commas, and tsv, by tabs.
;
; A token is a line, and its fields are coloured by their column, the
; classes in %sxv-columns in turn from the first column, so a column reads
; down the file in one colour.  A separator is punctuation.  A field in
; double quotes holds separators, and a quote written twice is one quote of
; it.  A quoted field holding a newline ends the line there, and the line
; after it starts again from the first column.  Every line starts a token,
; so a window colours without reading from the start.

(module x/tool/syntax/csv)
(import x/type/list)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- int% str-byte-len str-byte-ref)

(def %sxv-columns
  (list (lit name) (lit string) (lit number) (lit keyword) (lit class) (lit constant)))

(def %sxv-line-bytes (list (pair 0 9) (pair 11 255) (pair -128 -1)))

(def %sxv-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer run (lit line) %sxv-line-bytes %sxv-line-bytes)
          (Lexer any (lit other)))))

(def %sxv-byte (fn (_ t i) (char->int (str-byte-ref t i))))

; The end of a quoted field whose opening quote is at i: past its closing
; quote, a doubled quote read as one of the field's bytes; n when it meets none.
(def %sxv-quoted
  (fn (self t i n)
    (match ((>= i n) n)
           ((not (= (%sxv-byte t i) 34)) (self t (int+ i 1) n))
           ((if (< (int+ i 1) n) (= (%sxv-byte t (int+ i 1)) 34) #f) (self t (int+ i 2) n))
           (#t (int+ i 1)))))

; The end of a field from i: at its separator, or the line's end.
(def %sxv-field-end
  (fn (self t i n sep)
    (match ((>= i n) n)
           ((= (%sxv-byte t i) sep) i)
           ((= (%sxv-byte t i) 34) (self t (%sxv-quoted t (int+ i 1) n) n sep))
           (#t (self t (int+ i 1) n sep)))))

; The pieces of a line from i, field k at i, onto acc in reverse; a
; carriage return before the newline is no field's.
(def %sxv-fields
  (fn (self t i n sep k acc)
    (let ((e (%sxv-field-end t i n sep)))
      (let ((cls (List ref (int% k (List length %sxv-columns)) %sxv-columns)))
        (let ((with (if (= e i) acc (pair (list i (int- e i) cls) acc))))
          (if (>= e n) with
            (self t (int+ e 1) n sep (int+ k 1) (pair (list e 1 (lit punct)) with))))))))

(def %sxv-line
  (fn (_ sep)
    (fn (_ t)
      (let ((n (str-byte-len t)))
        (let ((m (if (if (< 0 n) (= (%sxv-byte t (int- n 1)) 13) #f) (int- n 1) n)))
          (List reverse (%sxv-fields t 0 m sep 0 ())))))))

(def %sxv-grammar
  (fn (_ name sep suffix)
    (let ((g (Syntax make name (%sxv-rules) (list (pair (lit line) (%sxv-line sep))))))
      (g sync (fn (_ _ _) #t))
      (g files (list suffix))
      g)))

(Syntax register! (%sxv-grammar (lit csv) 44 ".csv"))
(Syntax register! (%sxv-grammar (lit tsv) 9 ".tsv"))

(doc (provide x/tool/syntax/csv)
  (note "Imported by x/tool/syntax the first time a .csv or .tsv file needs its grammar; (Syntax named 'csv) and (Syntax named 'tsv) load it.")
  (example "((Syntax named 'csv) spans \"id,name\\n1,\\\"a, b\\\"\\n\")" "((0 2 'name) (2 1 'punct) (3 4 'string) (8 1 'name) (9 1 'punct) (10 6 'string))")
  (example "((Syntax named 'tsv) spans \"id\\tname\\n\")" "((0 2 'name) (2 1 'punct) (3 4 'string))")
  "The CSV and TSV highlighting grammars: each column in its own colour, separators as punctuation.")
