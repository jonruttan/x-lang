; codec/csv.x -- Csv: RFC 4180 parse and emit.
;
; The value mapping: a table is a LIST OF ROWS, each row a list of field
; STRINGS -- parse never guesses types (a "3" stays a string; the caller
; converts). The records tier reads the first row as headers and hands
; back one alist per data row, string-keyed -- (Assoc find), the
; equal?-keyed entry door, is the lookup that matches.
;
; Parsing is a single byte-level pass (the json.x pattern): quoted fields
; may hold commas, quotes ("" escapes), and newlines; rows end at LF,
; CRLF, or lone CR; a trailing newline yields no phantom row; an interior
; empty line is one empty field. Strict per #61 -- no silent repair:
;   - an unclosed quote at end of input raises kind-'value
;   - a quote inside an unquoted field raises (RFC: such fields MUST be
;     quoted; Python's reader silently keeps it -- we refuse)
;   - bytes between a closing quote and the next separator raise
;   - records with a width unlike the header row raise
; Emission quotes minimally (only fields holding , " CR or LF), doubles
; quotes, joins rows with LF, and ends with a trailing LF.
;
; Comma is THE separator (RFC 4180); no delimiter option until a caller
; needs one. Fields are strings, so the x-lib NUL ruling applies as
; everywhere: bytes past a NUL are unobservable.
;
; Zero top-level %-globals (new-file budget 0); helpers are method-local.

(import x/type/class)
(import x/core/list)
(import x/type/assoc)

(def-class Csv ()
  (doc "RFC 4180 csv: (Csv parse text) -> rows of field strings; (Csv emit rows) -> text; (Csv records text) / (Csv emit-records headers records) ride the header row as string-keyed alists."
    (example "(Csv parse \"a,b\\n1,2\\n\")" "((\"a\" \"b\") (\"1\" \"2\"))")
    (example "(Csv emit (list (list \"a\" \"b,c\")))" "\"a,\\\"b,c\\\"\\n\"")
    (see parse) (see records))
  (static
    (method parse (self (param text STRING "csv text"))
      (doc "Parse csv text into a list of rows, each a list of field strings. Quoted fields carry commas, doubled quotes, and newlines; rows end at LF/CRLF/CR; a trailing newline adds no row. Raises kind-'value on an unclosed quote, a quote inside an unquoted field, or bytes after a closing quote (#61: no silent repair)."
        (returns LIST "Rows of field strings")
        (example "(Csv parse \"a,\\\"b\\\"\\\"c\\\",d\")" "((\"a\" \"b\\\"c\" \"d\"))"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Csv parse: " what) text)))
      (def n (%blen text))
      (def %b (fn (_ i) (%c->i (%bref text i))))
      (def %fin (fn (_ facc) (bytes->str (%reverse facc))))
      ; state: start (at a field boundary), plain, quoted, closed (just
      ; past a closing quote). Bytes: , 44  " 34  LF 10  CR 13.
      (let go ((i 0) (facc ()) (row ()) (rows ()) (state (lit start)))
        (match
          ((= i n)
            (match
              ((eq? state (lit quoted)) (%bad "unclosed quote at end of input"))
              ; nothing pending after the last row terminator: done
              ((if (eq? state (lit start)) (null? row) #f) (%reverse rows))
              (#t (%reverse (pair (%reverse (pair (%fin facc) row)) rows)))))
          (#t
            (let ((c (%b i)))
              (match
                ; --- quoted field body ---
                ((eq? state (lit quoted))
                  (match
                    ((= c 34)
                      (if (if (< (+ i 1) n) (= (%b (+ i 1)) 34) #f)
                        (go (+ i 2) (pair 34 facc) row rows (lit quoted))
                        (go (+ i 1) facc row rows (lit closed))))
                    (#t (go (+ i 1) (pair c facc) row rows (lit quoted)))))
                ; --- separators (start / plain / closed all agree) ---
                ((= c 44)
                  (go (+ i 1) () (pair (%fin facc) row) rows (lit start)))
                ((if (= c 13) (if (< (+ i 1) n) (= (%b (+ i 1)) 10) #f) #f)
                  (go (+ i 2) () ()
                      (pair (%reverse (pair (%fin facc) row)) rows) (lit start)))
                ((if (= c 10) #t (= c 13))
                  (go (+ i 1) () ()
                      (pair (%reverse (pair (%fin facc) row)) rows) (lit start)))
                ; --- past a closing quote: only separators are legal ---
                ((eq? state (lit closed))
                  (%bad "bytes after a closing quote"))
                ; --- field start ---
                ((eq? state (lit start))
                  (if (= c 34)
                    (go (+ i 1) facc row rows (lit quoted))
                    (go (+ i 1) (pair c facc) row rows (lit plain))))
                ; --- unquoted field body ---
                ((= c 34) (%bad "quote inside an unquoted field"))
                (#t (go (+ i 1) (pair c facc) row rows (lit plain)))))))))

    (method emit (self (param rows LIST "Rows of field strings"))
      (doc "Render rows as csv text: fields holding a comma, quote, CR, or LF are quoted with doubled quotes; rows join with LF and the text ends with one."
        (returns STRING "csv text, LF row endings, trailing LF")
        (example "(Csv emit (list (list \"a\" \"b\") (list \"1,5\" \"x\\\"y\\\"\")))" "\"a,b\\n\\\"1,5\\\",\\\"x\\\"\\\"y\\\"\\\"\\\"\\n\""))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %field (fn (_ s)
        (def m (%blen s))
        (def needs?
          (let scan ((i 0))
            (match
              ((= i m) #f)
              ((let ((c (%c->i (%bref s i))))
                 (or (= c 44) (or (= c 34) (or (= c 10) (= c 13))))) #t)
              (#t (scan (+ i 1))))))
        (if (not needs?) s
          (bytes->str
            (pair 34
              (%reverse
                (let esc ((i 0) (acc ()))
                  (match
                    ((= i m) (pair 34 acc))
                    (#t
                      (let ((c (%c->i (%bref s i))))
                        (esc (+ i 1)
                             (if (= c 34) (pair 34 (pair 34 acc))
                               (pair c acc)))))))))))))
      (List fold
        (fn (_ acc row)
          (Str8 append acc
            (match
              ((null? row) "")
              (#t (List fold (fn (_ racc f) (Str8 append racc "," (%field f)))
                    (%field (first row)) (rest row))))
            "\n"))
        "" rows))

    (method records (self (param text STRING "csv text whose first row is the header"))
      (doc "Parse csv text whose FIRST row names the columns: one string-keyed alist per data row, in header order -- (Assoc find), the equal?-keyed door, is the matching lookup. Raises kind-'value when a data row's width differs from the header's (#61)."
        (returns LIST "((header . value) ...) alists, one per data row")
        (example "(rest (Assoc find \"age\" (first (Csv records \"name,age\\nida,7\\n\"))))" "\"7\""))
      (def rows (Csv parse text))
      (match
        ((null? rows) ())
        (#t
          (let ((headers (first rows)))
            (let ((width (List length headers)))
              (List map
                (fn (_ row)
                  (match
                    ((not (= (List length row) width))
                      (Err raise (lit value) "Csv records: row width differs from the header row" row))
                    (#t (List zip-with (fn (_ h v) (pair h v)) headers row))))
                (rest rows)))))))

    (method emit-records (self (param headers LIST "Column names, in output order")
                               (param records LIST "String-keyed alists, one per row"))
      (doc "Render records as csv text under an explicit header row: each record supplies every header's value ((Assoc find), equal?-keyed); a missing key raises kind-'value (#61)."
        (returns STRING "csv text: the header row, then one row per record")
        (example "(Csv emit-records (list \"a\" \"b\") (list (list (pair \"a\" \"1\") (pair \"b\" \"2\"))))" "\"a,b\\n1,2\\n\""))
      (Csv emit
        (pair headers
          (List map
            (fn (_ rec)
              (List map
                (fn (_ h)
                  (let ((e (Assoc find h rec)))
                    (match
                      ((null? e)
                        (Err raise (lit value) (Str8 append "Csv emit-records: record is missing header " h) rec))
                      (#t (rest e)))))
                headers))
            records))))))

(doc (provide x/codec/csv Csv)
  (note "Tables are rows of field STRINGS -- parse never guesses types. Comma is the separator (RFC 4180); strict on malformed quoting per #61. The records tier keys alists by the header strings.")
  "RFC 4180 csv parse/emit, homed on the Csv class.")
