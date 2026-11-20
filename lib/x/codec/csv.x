; codec/csv.x -- Csv: RFC 4180 parse and emit.
;
; The value mapping: a table is a LIST OF ROWS, each row a list of field
; STRINGS -- parse never guesses types (a "3" stays a string; the caller
; converts). The records profile reads the first row as headers and hands
; back one alist per data row, string-keyed -- (Assoc find), the
; equal?-keyed entry door, is the lookup that matches.
;
; Parsing reads the tokens of x/reader/lexer (the json.x pattern): quoted fields
; may hold commas, quotes ("" escapes), and newlines; rows end at LF,
; CRLF, or lone CR; a trailing newline yields no phantom row; an interior
; empty line is one empty field. Strict per #61 -- no silent repair:
;   - an unclosed quote at end of input raises a label 'value
;   - a quote inside an unquoted field raises (RFC: such fields MUST be
;     quoted; Python's reader silently keeps it -- we refuse)
;   - bytes between a closing quote and the next separator raise
;   - records with a width unlike the header row raise
; Emission quotes minimally (only fields holding , " CR or LF), doubles
; quotes, joins rows with LF, and ends with a trailing LF.
;
; Comma is the separator (RFC 4180). parse-by and emit-by take another: one
; byte below 128 that is not a quote, a CR or an LF -- a tab, a semicolon,
; a bar. Fields are strings, so the x-lib NUL ruling applies as everywhere:
; bytes past a NUL are unobservable.
;
; Zero top-level %-globals (new-file budget 0); helpers are method-local.

(module x/codec/csv)
(import x/type/class)
(import x/core/list)
(import x/type/assoc)
(import x/reader/lexer)
(import x/core/doors char->int str-byte-len str-byte-ref str-byte-sub)

(def-class Csv ()
  (doc "RFC 4180 csv: (Csv parse text) -> rows of field strings; (Csv emit rows) -> text; (Csv parse-by sep text) / (Csv emit-by sep rows) the same with another separator; (Csv records text) / (Csv emit-records headers records) ride the header row as string-keyed alists."
    (example "(Csv parse \"a,b\\n1,2\\n\")" "((\"a\" \"b\") (\"1\" \"2\"))")
    (example "(Csv emit (list (list \"a\" \"b,c\")))" "\"a,\\\"b,c\\\"\\n\"")
    (see parse) (see parse-by) (see records))
  (static
    ; The lexers, one for each separator parsed with, made on its first parse
    ; and kept: an alist of (SEPARATOR-BYTE . LEXER) in the cell's first.  A
    ; plain field is a run of every byte but the separator, " CR and LF (high
    ; bytes either way the engine hands them over); CR and LF are each a
    ; newline; a quoted field is quote to quote, no escape byte, so a doubled
    ; quote arrives as two quoted tokens side by side; a quote no closing
    ; quote follows is a stray byte.  The end text is a newline: it ends the
    ; last row, and is never a row of its own.
    (%lexer-cell (pair () ()))
    ; The separator's byte, or a raise when SEP is not one a field can be told
    ; from: more or less than one byte, a high byte, a quote, a CR or an LF.
    (method %sep-byte (self sep)
      (def c (if (= (str-byte-len sep) 1) (char->int (str-byte-ref sep 0)) -1))
      (if (or (< c 1) (or (> c 127) (or (= c 34) (or (= c 10) (= c 13)))))
        (Err raise (lit value) "Csv: the separator is one byte below 128, and not a quote or a newline" sep)
        c))
    (method %lexer (self sep)
      (def c (Csv %sep-byte sep))
      (def held
        (let find ((ls (first (Csv %lexer-cell))))
          (match
            ((null? ls) ())
            ((= (first (first ls)) c) (rest (first ls)))
            (#t (find (rest ls))))))
      ; The plain bytes: every range of them, with the one C stands in cut
      ; in two around it.
      (def %plain (fn (_)
        (let cut ((rs (list (pair 0 9) (pair 11 12) (pair 14 33) (pair 35 127))) (acc ()))
          (match
            ((null? rs) (%reverse (pair (pair -128 -1) (pair (pair 128 255) acc))))
            ((or (< c (first (first rs))) (> c (rest (first rs))))
              (cut (rest rs) (pair (first rs) acc)))
            (#t
              (cut (rest rs)
                   ((fn (_ below)
                      (if (< c (rest (first rs))) (pair (pair (+ c 1) (rest (first rs))) below) below))
                    (if (> c (first (first rs))) (pair (pair (first (first rs)) (- c 1)) acc) acc))))))))
      (if (null? held)
        ((fn (_ plain)
           ((fn (_ made)
              (%set-first! (Csv %lexer-cell) (pair (pair c made) (first (Csv %lexer-cell))))
              made)
            (Lexer make (list
              (Lexer table (lit sep) (list sep))
              (Lexer table (lit nl) (list "\n" "\r"))
              (Lexer quoted (lit q) 34 34 ())
              (Lexer run (lit f) plain plain)
              (Lexer any (lit bad)))
              "\n")))
         (%plain))
        held))

    (method parse (self (param text STRING "csv text"))
      (doc "Parse csv text into a list of rows, each a list of field strings. Quoted fields carry commas, doubled quotes, and newlines; rows end at LF/CRLF/CR; a trailing newline adds no row. Raises a label 'value on an unclosed quote, a quote inside an unquoted field, or bytes after a closing quote (#61: no silent repair)."
        (returns LIST "Rows of field strings")
        (example "(Csv parse \"a,\\\"b\\\"\\\"c\\\",d\")" "((\"a\" \"b\\\"c\" \"d\"))"))
      (Csv parse-by "," text))

    (method parse-by (self (param sep STRING "The separator: one byte below 128, not a quote, a CR or an LF")
                           (param text STRING "Text whose fields sep separates"))
      (doc "Parse text whose fields are separated by sep, as parse does text separated by commas: quoted fields carry the separator, doubled quotes and newlines. Raises a label 'value on what parse refuses, and on a separator a field cannot be told from."
        (returns LIST "Rows of field strings")
        (example "(Csv parse-by \";\" \"a;\\\"b;c\\\"\\n1;2\\n\")" "((\"a\" \"b;c\") (\"1\" \"2\"))")
        (see parse) (see emit-by))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Csv parse: " what) text)))
      ; A quoted token's text without its quotes.
      (def %inner (fn (_ q) (str-byte-sub q 1 (- (str-byte-len q) 2))))
      ; KIND is what the field in hand has been made of: none yet, a plain
      ; run, or quoted pieces, which a doubled quote joins.  A quote touching a
      ; plain run, bytes after a closing quote, and a quote no closing quote
      ; follows (the lexer's stray byte) are each refused by name.
      (let go ((ts ((Csv %lexer sep) read-str text)) (field "") (kind (lit none))
               (row ()) (rows ()))
        (if (null? ts)
          (if (if (eq? kind (lit none)) (null? row) #f)
            (%reverse rows)
            (%reverse (pair (%reverse (pair field row)) rows)))
          (let ((tag (first (first ts))) (tx (first (rest (first ts)))))
            (match
              ((eq? tag (lit sep))
                (go (rest ts) "" (lit none) (pair field row) rows))
              ; CR and LF are separate tokens, so that the appended LF never
              ; joins a trailing CR into one it cannot end; a CR with an LF
              ; straight after it is one row end.
              ((eq? tag (lit nl))
                (go (if (if (str=? tx "\r") (if (null? (rest ts)) #f
                          (if (eq? (first (first (rest ts))) (lit nl))
                            (str=? (first (rest (first (rest ts)))) "\n") #f)) #f)
                      (rest (rest ts)) (rest ts))
                    "" (lit none) ()
                    (pair (%reverse (pair field row)) rows)))
              ((eq? tag (lit q))
                (match
                  ((eq? kind (lit plain)) (%bad "quote inside an unquoted field"))
                  ((eq? kind (lit quoted))
                    (go (rest ts) (Str8 append field "\"" (%inner tx)) kind row rows))
                  (#t (go (rest ts) (%inner tx) (lit quoted) row rows))))
              ((eq? tag (lit f))
                (if (eq? kind (lit quoted)) (%bad "bytes after a closing quote")
                  (go (rest ts) tx (lit plain) row rows)))
              ((eq? kind (lit plain)) (%bad "quote inside an unquoted field"))
              (#t (%bad "unclosed quote at end of input")))))))

    (method emit (self (param rows LIST "Rows of field strings"))
      (doc "Render rows as csv text: fields holding a comma, quote, CR, or LF are quoted with doubled quotes; rows join with LF and the text ends with one."
        (returns STRING "csv text, LF row endings, trailing LF")
        (example "(Csv emit (list (list \"a\" \"b\") (list \"1,5\" \"x\\\"y\\\"\")))" "\"a,b\\n\\\"1,5\\\",\\\"x\\\"\\\"y\\\"\\\"\\\"\\n\""))
      (Csv emit-by "," rows))

    (method emit-by (self (param sep STRING "The separator: one byte below 128, not a quote, a CR or an LF")
                          (param rows LIST "Rows of field strings"))
      (doc "Render rows as text with sep between the fields, as emit does with commas: a field holding the separator, a quote, a CR or an LF is quoted with its quotes doubled."
        (returns STRING "The text, LF row endings, trailing LF")
        (example "(Csv emit-by \"|\" (list (list \"a\" \"b|c\")))" "\"a|\\\"b|c\\\"\\n\"")
        (see emit) (see parse-by))
      (def sepc (Csv %sep-byte sep))
      (def %field (fn (_ s)
        (def m (str-byte-len s))
        (def needs?
          (let scan ((i 0))
            (match
              ((= i m) #f)
              ((let ((c (char->int (str-byte-ref s i))))
                 (or (= c sepc) (or (= c 34) (or (= c 10) (= c 13))))) #t)
              (#t (scan (+ i 1))))))
        (if (not needs?) s
          (bytes->str
            (pair 34
              (%reverse
                (let esc ((i 0) (acc ()))
                  (match
                    ((= i m) (pair 34 acc))
                    (#t
                      (let ((c (char->int (str-byte-ref s i))))
                        (esc (+ i 1)
                             (if (= c 34) (pair 34 (pair 34 acc))
                               (pair c acc)))))))))))))
      (List fold
        (fn (_ acc row)
          (Str8 append acc
            (match
              ((null? row) "")
              (#t (List fold (fn (_ racc f) (Str8 append racc sep (%field f)))
                    (%field (first row)) (rest row))))
            "\n"))
        "" rows))

    (method records (self (param text STRING "csv text whose first row is the header"))
      (doc "Parse csv text whose FIRST row names the columns: one string-keyed alist per data row, in header order -- (Assoc find), the equal?-keyed door, is the matching lookup. Raises a label 'value when a data row's width differs from the header's (#61)."
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
      (doc "Render records as csv text under an explicit header row: each record supplies every header's value ((Assoc find), equal?-keyed); a missing key raises a label 'value (#61)."
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
  (example "(Csv parse \"a,b\\n1,2\\n\")" "((\"a\" \"b\") (\"1\" \"2\"))")
  (note "Tables are rows of field STRINGS -- parse never guesses types. Comma is the separator (RFC 4180), and parse-by and emit-by take another; strict on malformed quoting per #61. The records profile keys alists by the header strings.")
  "RFC 4180 csv parse/emit, homed on the Csv class.")
