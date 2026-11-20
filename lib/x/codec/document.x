; codec/document.x -- Document: the tree a reader answers and a writer takes.
;
; A document is a list of blocks.  x/codec/markdown and x/codec/html answer
; one, x/tui/page lays one out, and (Markdown html) writes one; a reader or
; writer of another format meets them here.  A node is a list led by its
; name, then its parts in the order the tables below give them, each part
; named for what it holds:
;
;   blocks    a list of block nodes
;   inlines   a list of strings (text) and inline nodes
;   items     a list of items, each a list of blocks
;   text      a string
;   title     a string, or nil for none
;   flag      #t or #f
;   level     an integer, 1 to 6
;   start     an integer, or nil for none
;   symbol    a symbol
;   options   a list
;   form      a list, or nil for none
;   aligns    a list, each left, center, right, or nil for none
;   rows      a list of rows, each a list of cells, each a list of inlines
;
; docs/document.md says what each node means and what a writer may rely on.
;
; The class also names the formats the library reads and writes, and reads
; or writes a document in one by its name: (Document read FORMAT TEXT)
; answers (TITLE . BLOCKS) and (Document write FORMAT BLOCKS) the file.

(module x/codec/document)
(import x/type/class)
(import x/core/list)

(import x/core/doors str-byte-len)

(def %dc-blocks
  (lit ((heading level inlines)
        (paragraph inlines)
        (code-block text text)
        (block-quote blocks)
        (list flag start flag items)
        (thematic-break)
        (html-block text)
        (table flag aligns rows))))
(def %dc-inlines
  (lit ((emph inlines)
        (strong inlines)
        (code text)
        (softbreak)
        (hardbreak)
        (link text title inlines)
        (image text title inlines)
        (html-inline text)
        (field symbol title title flag options form))))

; The entry of TABLE led by NAME, or nil.
(def %dc-entry
  (fn (self name table)
    (match ((null? table) ())
           ((eq? name (first (first table))) (first table))
           (#t (self name (rest table))))))
; Whether L is nil or pairs that end in nil.
(def %dc-list? (fn (self l) (match ((null? l) #t) ((pair? l) (self (rest l))) (#t #f))))
; The first fault F answers over the list L, or nil.
(def %dc-each
  (fn (self f l)
    (match ((null? l) ())
           (#t ((fn (_ r) (match ((null? r) (self f (rest l))) (#t r))) (f (first l)))))))
(def %dc-nested?
  (fn (_ kind)
    (match ((eq? kind (lit blocks)) #t) ((eq? kind (lit inlines)) #t) ((eq? kind (lit items)) #t) ((eq? kind (lit rows)) #t) (#t #f))))
; Whether X is a sound part of the kind KIND, a kind that holds no nodes.
(def %dc-leaf?
  (fn (_ kind x)
    (match ((eq? kind (lit text)) (str? x))
           ((eq? kind (lit title)) (match ((null? x) #t) (#t (str? x))))
           ((eq? kind (lit flag)) (boolean? x))
           ((eq? kind (lit level)) (match ((number? x) (match ((< x 1) #f) ((< 6 x) #f) (#t #t))) (#t #f)))
           ((eq? kind (lit start)) (match ((null? x) #t) (#t (number? x))))
           ((eq? kind (lit symbol)) (symbol? x))
           ((eq? kind (lit options)) (%dc-list? x))
           ((eq? kind (lit form)) (%dc-list? x))
           ((eq? kind (lit aligns))
             (match ((%dc-list? x)
                      (null? (%dc-each (fn (_ a) (match ((null? a) ()) ((eq? a (lit left)) ())
                                                       ((eq? a (lit center)) ()) ((eq? a (lit right)) ()) (#t a)))
                                       x)))
                    (#t #f)))
           (#t #f))))
; The fault in V, the part of kind KIND of the node X, or nil.
(def %dc-part
  (fn (_ walk kind v x)
    (match ((%dc-nested? kind) (match ((%dc-list? v) (walk kind v)) (#t (list (first x) kind x))))
           ((%dc-leaf? kind v) ())
           (#t (list (first x) kind x)))))
; The first fault in the parts VALS of the node X against their KINDS, or nil.
(def %dc-parts
  (fn (self walk kinds vals x)
    (match ((null? kinds) (match ((null? vals) ()) (#t (list (first x) (lit parts) x))))
           ((null? vals) (list (first x) (lit parts) x))
           (#t ((fn (_ r) (match ((null? r) (self walk (rest kinds) (rest vals) x)) (#t r)))
                (%dc-part walk (first kinds) (first vals) x))))))
; The first fault in X as a node of TABLE, or nil.  KIND, block or inline,
; names the fault of a node the table does not hold.
(def %dc-node
  (fn (_ walk table kind x)
    (match ((%dc-list? x)
             (match ((null? x) (list kind (lit name) x))
                    (#t ((fn (_ e)
                           (match ((null? e) (list kind (lit name) x))
                                  (#t (%dc-parts walk (rest e) (rest x) x))))
                         (%dc-entry (first x) table)))))
           (#t (list kind (lit name) x)))))
; The first fault in the list X of the kind KIND (blocks, inlines or items),
; or nil.
(def %dc-walk
  (fn (self kind x)
    (match ((eq? kind (lit blocks)) (%dc-each (fn (_ b) (%dc-node self %dc-blocks (lit block) b)) x))
           ((eq? kind (lit inlines))
             (%dc-each (fn (_ i) (match ((str? i) ()) (#t (%dc-node self %dc-inlines (lit inline) i)))) x))
           ((eq? kind (lit rows))
             (%dc-each
               (fn (_ row)
                 (match ((%dc-list? row)
                          (%dc-each (fn (_ cell) (match ((%dc-list? cell) (self (lit inlines) cell))
                                                       (#t (list (lit table) (lit rows) cell))))
                                    row))
                        (#t (list (lit table) (lit rows) row))))
               x))
           (#t (%dc-each
                 (fn (_ item) (match ((%dc-list? item) (self (lit blocks) item)) (#t (list (lit list) (lit items) item))))
                 x)))))


; --- formats -----------------------------------------------------------------
;
; Each format the library reads and writes: its name, then the endings a
; file's name gives it by.  A reader or writer is imported when it is first
; asked for, so the tree's definition loads none of them.
(def %dc-formats
  (lit (("markdown" (".md" ".markdown" ".mdown"))
        ("html" (".html" ".htm"))
        ("pdf" (".pdf"))
        ("text" (".txt" ".text")))))

(def %dc-unknown (fn (_ format) (Err raise (lit value) "Document: no such format" format)))
; The name of the format whose endings hold one NAME ends with, or nil.
(def %dc-ending
  (fn (self name formats)
    (match ((null? formats) ())
           ((List any? (fn (_ e) (Str8 ends? e name)) (first (rest (first formats)))) (first (first formats)))
           (#t (self name (rest formats))))))
(def %dc-plain
  (fn (self inlines)
    (Str8 join ""
      (List map
        (fn (_ x)
          (def t (match ((str? x) ()) (#t (first x))))
          (match ((str? x) x)
                 ((eq? t (lit code)) (List ref 1 x))
                 ((match ((eq? t (lit softbreak)) #t) (#t (eq? t (lit hardbreak)))) " ")
                 ((match ((eq? t (lit link)) #t) (#t (eq? t (lit image)))) (self (List ref 3 x)))
                 ((match ((eq? t (lit emph)) #t) (#t (eq? t (lit strong)))) (self (List ref 1 x)))
                 ((eq? t (lit field)) (match ((str? (List ref 3 x)) (List ref 3 x)) (#t "")))
                 (#t "")))
        inlines))))
(def %dc-title
  (fn (_ blocks)
    ((fn (_ h) (match ((null? h) ()) (#t (%dc-plain (List ref 2 h)))))
     (List find (fn (_ b) (eq? (first b) (lit heading))) blocks))))
(def %dc-escaped
  (fn (_ text) (Str8 replace "<" "&lt;" (Str8 replace ">" "&gt;" (Str8 replace "&" "&amp;" text)))))
(def %dc-whole (fn (_ s) (list s 0 (str-byte-len s))))
(def %dc-read-markdown
  (fn (_ s)
    (import x/codec/markdown)
    (pair () (Markdown parse s))))
(def %dc-read-html
  (fn (_ s)
    (import x/codec/html)
    (pair (Html title s) (Html parse s))))
(def %dc-read-pdf
  (fn (_ s n)
    (import x/codec/pdf-text)
    (pair (PdfText title s n) (PdfText parse s n))))
(def %dc-read
  (fn (_ format s n)
    (match
      ((str=? format "markdown") (%dc-read-markdown s))
      ((str=? format "html") (%dc-read-html s))
      ((str=? format "pdf") (%dc-read-pdf s n))
      ((str=? format "text") (pair () (match ((str=? s "") ()) (#t (list (list (lit code-block) "" s))))))
      (#t (%dc-unknown format)))))
(def %dc-write-markdown
  (fn (_ blocks)
    (import x/codec/markdown-write)
    (%dc-whole (MarkdownWrite text blocks))))
(def %dc-write-html
  (fn (_ blocks title)
    (import x/codec/markdown)
    (%dc-whole
      (Str8 append "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>"
        (%dc-escaped (match ((null? title) "") (#t title)))
        "</title>\n</head>\n<body>\n" (Markdown html blocks) "</body>\n</html>\n"))))
(def %dc-write-pdf
  (fn (_ blocks title)
    (import x/codec/pdf-write)
    (match ((null? title) (PdfWrite bytes blocks)) (#t (PdfWrite bytes blocks title)))))
(def %dc-write-text
  (fn (_ blocks width)
    (import x/tui/page)
    ((fn (_ page)
       (%dc-whole
         (Str8 join ""
           (List map (fn (_ i) (Str8 append (Str8 trim-right (Page line-text page i)) "\n"))
                     (List range 0 (Page count page))))))
     (Page markdown blocks width))))
(def %dc-write
  (fn (_ format blocks title width)
    (match
      ((str=? format "markdown") (%dc-write-markdown blocks))
      ((str=? format "html") (%dc-write-html blocks title))
      ((str=? format "pdf") (%dc-write-pdf blocks title))
      ((str=? format "text") (%dc-write-text blocks width))
      (#t (%dc-unknown format)))))

(def-class Document ()
  (doc "The tree a reader answers and a writer takes: a list of blocks, each a list led by its name. (Document check blocks) finds the first node that is not one; (Document blocks) and (Document inlines) answer the nodes there are. (Document formats) names the formats the library reads and writes, and (Document read) and (Document write) read or write a document in one by its name."
    (example "(null? (Document check (list (list 'paragraph (list \"a\" (list 'emph (list \"b\")))))))" "#t")
    (example "(Document check (list (list 'heading 7 ())))" "('heading 'level ('heading 7 ()))")
    (see check) (see blocks) (see inlines) (see formats) (see read) (see write))
  (static
    (method check (self (param blocks LIST "A document: a list of blocks"))
      (doc "The first fault in a document, or nil when every node is sound. A fault is (NAME PART NODE): the node's name, the part of it that does not hold what its table entry names, and the node. PART is parts for a node with too few or too many parts, and name, under the NAME block or inline, for a node the table does not hold; (document blocks X) is a document that is no list."
        (returns LIST "nil, or (NAME PART NODE)")
        (example "(null? (Document check (list (list 'paragraph (list (list 'link \"/u\" () (list \"x\")))))))" "#t")
        (example "(Document check (list (list 'paragraph (list (list 'bold (list \"x\"))))))" "('inline 'name ('bold (\"x\")))")
        (example "(Document check (list (list 'code-block \"x\")))" "('code-block 'parts ('code-block \"x\"))"))
      (match ((%dc-list? blocks) (%dc-walk (lit blocks) blocks))
             (#t (list (lit document) (lit blocks) blocks))))
    (method blocks (self)
      (doc "The block nodes: each entry a node's name, then the kind of each of its parts in order."
        (returns LIST "((NAME KIND...) ...)")
        (example "(first (Document blocks))" "('heading 'level 'inlines)"))
      %dc-blocks)
    (method inlines (self)
      (doc "The inline nodes, as (Document blocks) answers the block nodes. A string among inlines is text and has no entry."
        (returns LIST "((NAME KIND...) ...)")
        (example "(first (Document inlines))" "('emph 'inlines)"))
      %dc-inlines)
    (method formats (self)
      (doc "The formats (Document read) reads and (Document write) writes: each entry a format's name, then the endings a file's name gives it by."
        (returns LIST "((NAME ENDINGS) ...)")
        (example "(List map first (Document formats))" "(\"markdown\" \"html\" \"pdf\" \"text\")"))
      %dc-formats)
    (method format (self (param name STRING "A file's name")
                         . (param bytes STRING "Optionally the file's first bytes"))
      (doc "The name of a file's format: pdf for bytes that begin with a PDF's signature, else the format whose endings hold the name's, whatever its case, or nil for a name no format claims."
        (returns ANY "A format's name, or nil")
        (example "(list (Document format \"a/Notes.MD\") (Document format \"x.bin\" \"%PDF-1.4\") (null? (Document format \"x.bin\")))" "(\"markdown\" \"pdf\" #t)"))
      (match ((match ((null? bytes) #f) (#t (Str8 starts? "%PDF-" (first bytes)))) "pdf")
             (#t (%dc-ending (Str8 downcase name) %dc-formats))))
    (method title (self (param blocks LIST "A document's blocks"))
      (doc "The text of the document's first heading, its marks left off, or nil when it has none."
        (returns ANY "The title, or nil")
        (example "(Document title (list (list 'paragraph (list \"p\")) (list 'heading 2 (list \"A \" (list 'emph (list \"b\"))))))" "\"A b\""))
      (%dc-title blocks))
    (method read (self (param format STRING "A format's name, from (Document formats)")
                       (param s STRING "The file's text or bytes")
                       . (param length INTEGER "How many bytes; default s's length to its first NUL"))
      (doc "A file read as a document: (TITLE . BLOCKS), the title the format's own, an HTML page's <title> or a PDF's /Title, and nil for a format with none or a file without. Markdown is read by x/codec/markdown, HTML by x/codec/html and a PDF by x/codec/pdf-text; text is one code block that keeps its lines. Raises a label 'value for a format not among (Document formats)."
        (returns LIST "(TITLE . BLOCKS)")
        (example "(Document read \"markdown\" \"# Hi\")" "(() ('heading 1 (\"Hi\")))")
        (example "(Document read \"html\" \"<title>T</title><p>a <b>b</b>\")" "(\"T\" ('paragraph (\"a \" ('strong (\"b\")))))")
        (example "(Document read \"text\" \"a\\n b\\n\")" "(() ('code-block \"\" \"a\\n b\\n\"))"))
      (%dc-read format s (match ((null? length) (str-byte-len s)) (#t (first length)))))
    (method write (self (param format STRING "A format's name, from (Document formats)")
                        (param blocks LIST "A document's blocks")
                        . (param more ANY "Optionally the title, then the columns of text; nil and 80 unless given"))
      (doc "A document written in a format: the file as (BUF START LENGTH), a string for every format but one that holds bytes past text. Markdown is written by x/codec/markdown-write and a PDF by x/codec/pdf-write; HTML is a page of what (Markdown html) writes under the title; text is the document laid out as x/tui/page lays it, a line no wider than the columns. A title of nil is the document's first heading. Raises a label 'value for a format not among (Document formats)."
        (returns LIST "(BUF START LENGTH)")
        (example "(first (Document write \"markdown\" (list (list 'heading 1 (list \"Hi\")))))" "\"# Hi\\n\"")
        (example "(first (Document write \"text\" (list (list 'paragraph (list \"one two three\"))) () 10))" "\"one two\\nthree\\n\"")
        (example "(first (Document write \"html\" (list (list 'paragraph (list \"p\"))) \"A & B\"))" "\"<!DOCTYPE html>\\n<html>\\n<head>\\n<meta charset=\\\"utf-8\\\">\\n<title>A &amp; B</title>\\n</head>\\n<body>\\n<p>p</p>\\n</body>\\n</html>\\n\""))
      ((fn (_ title width)
         (%dc-write format blocks (match ((null? title) (%dc-title blocks)) (#t title)) width))
       (match ((null? more) ()) (#t (first more)))
       (match ((null? more) 80) ((null? (rest more)) 80) (#t (first (rest more))))))))

(doc (provide x/codec/document Document)
  (example "(null? (Document check (list (list 'thematic-break))))" "#t")
  (note "The tree is plain lists, strings and symbols: a reader builds it with list and a writer reads it with first and rest. docs/document.md describes each node.")
  "The document tree shared by the Markdown and HTML readers and the writers, homed on the Document class.")
