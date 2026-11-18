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
;
; docs/document.md says what each node means and what a writer may rely on.

(module x/codec/document)
(import x/type/class)

(def %dc-blocks
  (lit ((heading level inlines)
        (paragraph inlines)
        (code-block text text)
        (block-quote blocks)
        (list flag start flag items)
        (thematic-break)
        (html-block text))))
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
    (match ((eq? kind (lit blocks)) #t) ((eq? kind (lit inlines)) #t) ((eq? kind (lit items)) #t) (#t #f))))
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
           (#t (%dc-each
                 (fn (_ item) (match ((%dc-list? item) (self (lit blocks) item)) (#t (list (lit list) (lit items) item))))
                 x)))))

(def-class Document ()
  (doc "The tree a reader answers and a writer takes: a list of blocks, each a list led by its name. (Document check blocks) finds the first node that is not one; (Document blocks) and (Document inlines) answer the nodes there are."
    (example "(null? (Document check (list (list 'paragraph (list \"a\" (list 'emph (list \"b\")))))))" "#t")
    (example "(Document check (list (list 'heading 7 ())))" "('heading 'level ('heading 7 ()))")
    (see check) (see blocks) (see inlines))
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
      %dc-inlines)))

(doc (provide x/codec/document Document)
  (example "(null? (Document check (list (list 'thematic-break))))" "#t")
  (note "The tree is plain lists, strings and symbols: a reader builds it with list and a writer reads it with first and rest. docs/document.md describes each node.")
  "The document tree shared by the Markdown and HTML readers and the writers, homed on the Document class.")
