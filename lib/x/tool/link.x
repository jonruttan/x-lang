; link.x -- Sections, symbols and relocations: the link library.
;
; A compiler writes one OBJECT for each unit it compiles, and a linker lays
; the objects out as one program: it puts the sections of one name end to
; end, finds what each name stands for, and writes every place that took a
; name's value.  The state-image loader and the assembler's byte cache do
; the same with records of their own; this is the shape of it, with the
; encodings left to the caller, whose backend knows them.
;
;   object   (SECTIONS SYMBOLS RELOCS)
;   section  (NAME ALIGN SIZE BYTES)     NAME a symbol, text or data; BYTES
;                                        a string of SIZE bytes, or () for
;                                        all zero.  SIZE is the count: a
;                                        string's own length stops at a
;                                        NUL, and code holds many
;   symbol   (NAME SECTION OFFSET SCOPE) NAME a string; SECTION a section's
;                                        name, or () for a name the object
;                                        takes and does not define; SCOPE
;                                        global, or local to the object
;   reloc    (SECTION OFFSET KIND NAME ADDEND)
;                                        the place OFFSET bytes into SECTION
;                                        takes NAME's value and ADDEND, as
;                                        KIND says; KIND is the caller's,
;                                        read by its patcher alone
;
; An object file is the object's records, then its bytes: the first line
; names the format, the form of the records (2 binary, 1 text) and how long
; they are, so a reader takes the records with one read and each section's
; bytes with another.  Binary records are read by a Lexer, a token a
; record; text ones are what a person reads.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
(module x/tool/link)

(import x/type/dict)
(import x/sys/file)
(import x/codec/xon)
(import x/core/logic equal?)
(import x/reader/lexer)
(import x/core/doors char->int int+ int- int* int% int& int< int= int->ptr io-write-to-str mem-copy obj-same? ptr->int
  ptr-ref ptr-ref-word ptr-set! ptr-set-word! str->sym str-byte-ref
  str->ptr str-byte-len str-make)

(def %mem-set (prim-ref (lit mem) (lit set)))

(def %link-round
  (fn (_ n align) (let ((m (int+ n (int- align 1)))) (int- m (int% m align)))))

(def %link-refuse
  (fn (_ what) (Err raise (lit link) (Str8 append "link: " what) ())))

; the entry under KEY in ALIST, by eq?, or nil
(def %link-assq
  (fn (self key es)
    (if (null? es) () (if (eq? key (first (first es))) (first es) (self key (rest es))))))

; --- the symbol tables ---------------------------------------------------------
; GLOBALS, a Dict from a name to (OBJECT SECTION . OFFSET), the object's
; index among OBJECTS; and LOCALS, one entry an object, a Dict of the same
; shape or () when the object has no local, in object order.  A global
; defined twice refuses.
(def %link-tables
  (fn (_ objects)
    (def globals (Dict make))
    (def go
      (fn (self os i acc)
        (if (null? os) (pair globals (%reverse acc))
          (let ((locals ()))
            (%for-each
              (fn (_ s)
                (def name (first s))
                (def section (first (rest s)))
                (def offset (first (rest (rest s))))
                (def scope (first (rest (rest (rest s)))))
                (unless (null? section)
                  (if (eq? scope (lit local))
                    (do (if (null? locals) (set! locals (Dict make)))
                        (locals set! name (pair i (pair section offset))))
                    (do (if (globals has? name)
                          (%link-refuse (Str8 append name " defined twice")))
                        (globals set! name (pair i (pair section offset)))))))
              (first (rest (first os))))
            (self (rest os) (int+ i 1) (pair locals acc))))))
    (go objects 0 ())))

; the entry for NAME as object I sees it: its own local first, else the
; global; nil for neither
(def %link-lookup
  (fn (_ tables i name)
    (def locals (List ref i (rest tables)))
    (def own (if (null? locals) () (locals get name)))
    (if (null? own) ((first tables) get name) own)))

(doc (def link-undefined
  (fn (_ objects)
    (def tables (%link-tables objects))
    (def seen (Dict make))
    (def go
      (fn (self os i acc)
        (if (null? os) (%reverse acc)
          (self (rest os) (int+ i 1)
            ((fn (self2 rs acc2)
               (if (null? rs) acc2
                 (let ((name (first (rest (rest (rest (first rs)))))))
                   (self2 (rest rs)
                     (if (if (seen has? name) #t (not (null? (%link-lookup tables i name))))
                       acc2
                       (do (seen set! name #t) (pair name acc2)))))))
             (first (rest (rest (first os)))) acc)))))
    (go objects 0 ())))
  (param objects LIST "Objects, each (SECTIONS SYMBOLS RELOCS)")
  (returns LIST "The names the objects' relocations take that no object defines, each once, in order of first use")
  (example "(import x/tool/link link-undefined) (link-undefined (list (list () () (list (list 'text 0 'abs \"puts\" 0)))))" "(\"puts\")")
  (example "(import x/tool/link link-undefined) (link-undefined (list (list (list (list 'text 1 2 \"ab\")) (list (list \"main\" 'text 0 'global)) (list (list 'text 0 'abs \"main\" 0) (list 'text 1 'abs \"exit\" 0)))))" "(\"exit\")")
  "The names a link of OBJECTS would be missing: what a runtime object has to define, or a library has to supply, before link.")

; --- the layout ------------------------------------------------------------------
; Every section of one name, end to end in object order, each at its
; alignment: (NAMES SIZES . PLANS), NAMES the output sections in order of
; first appearance, SIZES a Dict from a name to (ALIGN . SIZE), and PLANS
; one entry an object, ((SECTION . BASE) ...) where each of its sections
; starts in the output section
(def %link-layout
  (fn (_ objects)
    (def order ())
    (def sizes (Dict make))
    (def plan-of
      (fn (self ss plan)
        (if (null? ss) plan
          (let ((s (first ss)))
            (def name (first s))
            (def align (first (rest s)))
            (def size (first (rest (rest s))))
            (def cur (sizes get-or (pair 1 0) name))
            (def base (%link-round (rest cur) align))
            (unless (sizes has? name) (set! order (pair name order)))
            (sizes set! name
              (pair (if (int< (first cur) align) align (first cur)) (int+ base size)))
            (self (rest ss) (pair (pair name base) plan))))))
    (def plans (%map (fn (_ o) (plan-of (first o) ())) objects))
    (pair (%reverse order) (pair sizes plans))))

(doc (def link
  (fn (_ objects addresses patch)
    (def tables (%link-tables objects))
    (def layout (%link-layout objects))
    (def names (first layout))
    (def sizes (first (rest layout)))
    (def plans (rest (rest layout)))
    (def address (Dict make))
    (%for-each (fn (_ e) (address set! (first e) (rest e)))
      (addresses (%map (fn (_ n) (pair n (rest (sizes get n)))) names)))
    ; one zeroed buffer an output section, (PTR . STRING), in a Dict
    (def buffers (Dict make))
    (%for-each
      (fn (_ n)
        (def size (rest (sizes get n)))
        (def s (str-make (if (int= size 0) 1 size)))
        (def p (str->ptr s))
        (%mem-set p 0 (if (int= size 0) 1 size))
        (buffers set! n (pair p s)))
      names)
    ; each object's bytes, at its sections' bases
    (def pour
      (fn (self os ps)
        (unless (null? os)
          (do (%for-each
                (fn (_ s)
                  (def bytes (first (rest (rest (rest s)))))
                  (unless (null? bytes)
                    (mem-copy
                      (int->ptr (int+ (ptr->int (first (buffers get (first s))))
                                      (rest (%link-assq (first s) (first ps)))))
                      (str->ptr bytes) (first (rest (rest s))))))
                (first (first os)))
              (self (rest os) (rest ps))))))
    (pour objects plans)
    ; the value of NAME as object I takes it: its address
    (def value-of
      (fn (_ i name)
        (def e (%link-lookup tables i name))
        (if (null? e) (%link-refuse (Str8 append "undefined symbol: " name)))
        (def section (first (rest e)))
        (int+ (address get section)
          (int+ (rest (%link-assq section (List ref (first e) plans))) (rest (rest e))))))
    ; every relocation, through PATCH.  An object's sections are found once,
    ; each (NAME PTR BASE ADDRESS), and a name's value is asked for when the
    ; name is not the one the relocation before took: an object read from
    ; binary records has each name's relocations together.
    (def apply
      (fn (self os ps i)
        (unless (null? os)
          (do (def placed
                (%map (fn (_ e)
                        (list (first e) (first (buffers get (first e))) (rest e) (address get (first e))))
                  (first ps)))
              (def last (pair () 0))
              (%for-each
                (fn (_ r)
                  (def at (%link-assq (first r) placed))
                  (def offset (int+ (first (rest (rest at))) (first (rest r))))
                  (def name (first (rest (rest (rest r)))))
                  (unless (obj-same? name (first last))
                    (do (%set-rest! last (value-of i name))
                        (%set-first! last name)))
                  (patch (first (rest at)) offset (first (rest (rest r)))
                    (int+ (rest last) (first (rest (rest (rest (rest r))))))
                    (int+ (first (rest (rest (rest at)))) offset)))
                (first (rest (rest (first os)))))
              (self (rest os) (rest ps) (int+ i 1))))))
    (apply objects plans 0)
    ; the globals, each at its place in the output
    (def symbols (Dict make))
    ((first tables) for-each
      (fn (_ entry)
        (def e (rest entry))
        (def section (first (rest e)))
        (def offset (int+ (rest (%link-assq section (List ref (first e) plans))) (rest (rest e))))
        (symbols set! (first entry) (list section offset (int+ (address get section) offset)))))
    (list
      (%map (fn (_ n) (list n (address get n) (rest (sizes get n)) (rest (buffers get n)))) names)
      symbols)))
  (param objects LIST "Objects, each (SECTIONS SYMBOLS RELOCS), in link order: the sections of one name go end to end in this order")
  (param addresses CALLABLE "Given ((NAME . SIZE) ...) for the output sections, answers ((NAME . ADDRESS) ...): where each will be")
  (param patch CALLABLE "Called (patch PTR OFFSET KIND VALUE SITE) for each relocation: the output section's bytes, where in them the place is, the relocation's kind, the value it takes (its name's address and the addend), and the place's own address")
  (returns LIST "(SECTIONS SYMBOLS): the output sections, each (NAME ADDRESS SIZE BYTES), and a Dict from each global's name to (SECTION OFFSET ADDRESS)")
  (example "(import x/tool/link link) (first (first (link (list (list (list (list 'text 1 2 \"ab\")) (list (list \"main\" 'text 0 'global)) ())) (fn (_ ss) (List map (fn (_ s) (pair (first s) 4096)) ss)) (fn (_ p o k v s) ()))))" "('text 4096 2 \"ab\")")
  (example "(import x/tool/link link) ((first (rest (link (list (list (list (list 'text 1 2 \"ab\")) (list (list \"main\" 'text 0 'global)) ()) (list (list (list 'text 4 3 \"cde\")) (list (list \"f\" 'text 0 'global)) ())) (fn (_ ss) (List map (fn (_ s) (pair (first s) 4096)) ss)) (fn (_ p o k v s) ())))) get \"f\")" "('text 4 4100)")
  (example "(import x/tool/link link) (let ((seen ())) (link (list (list (list (list 'text 1 4 \"abcd\")) (list (list \"main\" 'text 0 'global)) (list (list 'text 2 'abs \"main\" 1)))) (fn (_ ss) (List map (fn (_ s) (pair (first s) 4096)) ss)) (fn (_ p o k v s) (set! seen (list o k v s)))) seen)" "(2 'abs 4097 4098)")
  "Link OBJECTS: lay their sections out, resolve every name, and patch every place that takes one.  A name no object defines, or one defined twice, refuses.")

; --- object files ------------------------------------------------------------------
; The first line, padded to 32 bytes: the format, its version and how
; many bytes of text follow it.  A reader takes the line with one read of
; a known length.
(def %link-first-line
  (fn (_ version n)
    (def head (Str8 append "x-object " (io-write-to-str version) " " (io-write-to-str n)))
    (Str8 append head (Str8 sub 0 (int- 31 (str-byte-len head)) (str-make 31)) "\n")))

; FORM as text the reader takes back: a symbol bare, a string quoted and
; escaped as the printer does it, a number as it is, nil as (), a list
; in parentheses.  The printer itself is not used for the whole: a core
; base's prints a symbol quoted.
(def %link-emit
  (fn (self form)
    (match
      ((null? form) "()")
      ((symbol? form) (symbol->str form))
      ((pair? form)
        (Str8 append "(" (Str8 join " " (%map self form)) ")"))
      (#t (io-write-to-str form)))))

; --- binary records ------------------------------------------------------------
; An object file's records in the form a Lexer reads (x/reader/lexer's
; record rule): one token a record, where text is one a word.  A record is
; a tag byte, fixed bytes, and runs that end on a byte with bit 7 set, so
; a name is its bytes and then 255, and has no byte past 127 itself.
;
;   S  align:4 size:4 bytes?:1  NAME 255          a section
;   K  TEXT 255                                   a relocation kind, as text
;   Y  section:1 scope:1 offset:4 length:1  NAME 255  SITE...
;                                                 a name: the symbol it is
;                                                 here, and every place
;                                                 that takes its value
;   SITE  flag:1 section:1 kind:2 offset:4 addend:8
;
; Sections and kinds are named by their place among the S and K records,
; which come first.  A Y record's section is 255 for a name the object
; does not define, and its scope 0 global, 1 local, 2 for a name that is
; taken and is no symbol of the object.  A site's flag has bit 7 on the
; last and bit 6 on one that stands for none.  Integers are little-endian;
; an addend is the word, its sign filling the bytes above it.
(def %link-word-bytes (if (int= %word-size 8) 8 4))

(def %link-7bit?
  (fn (_ s)
    (def n (str-byte-len s))
    ((fn (self i)
       (if (int= i n) #t
         (if (int< (char->int (str-byte-ref s i)) 128) (self (int+ i 1)) #f)))
     0)))

; where KEY is among the entries of L, each a list KEY leads
(def %link-place
  (fn (self key l i)
    (if (null? l) (%link-refuse "a relocation names a section the object has not")
      (if (eq? key (first (first l))) i (self key (rest l) (int+ i 1))))))

(def %link-at (fn (_ p at) (int->ptr (int+ (ptr->int p) at))))

; element I of L
(def %link-nth (fn (self l i) (if (int= i 0) (first l) (self (rest l) (int- i 1)))))

; S and then 255 at AT in P; answers the offset after them
(def %link-put-name
  (fn (_ p at s)
    (def n (str-byte-len s))
    (unless (int= n 0) (mem-copy (%link-at p at) (str->ptr s) n))
    (ptr-set! p (int+ at n) 255 1)
    (int+ at (int+ n 1))))

; N bytes at AT in P, as a string
(def %link-take
  (fn (_ p at n)
    (def s (str-make (if (int= n 0) 1 n)))
    (if (int= n 0) ""
      (do (mem-copy (str->ptr s) (%link-at p at) n) s))))

; What OBJECT's records name: (KINDS . NAMES).  KINDS is each relocation
; kind once, in order of first use, (KIND INDEX TEXT).  NAMES is one entry
; a Y record, (NAME SECTION SCOPE OFFSET SITES): the object's symbols in
; order, then each name that is taken and is no symbol.  SECTION is its
; place among the sections or 255, SCOPE the record's byte or () for a
; scope with none, and SITES every place that takes the name's value,
; (SECTION OFFSET KIND ADDEND), in the order the relocations came.
(def %link-names
  (fn (_ object)
    (def sections (first object))
    (def kinds (pair () 0))
    (def kind-of
      (fn (_ k)
        (def hit
          ((fn (self l) (if (null? l) () (if (equal? k (first (first l))) (first l) (self (rest l)))))
           (first kinds)))
        (if (null? hit)
          (let ((i (rest kinds)))
            (%set-first! kinds (pair (list k i (%link-emit k)) (first kinds)))
            (%set-rest! kinds (int+ i 1))
            i)
          (first (rest hit)))))
    ; a name's sites, newest first, in a cell whose rest says it was taken
    (def sites (Dict make))
    (def order (pair () ()))
    (%for-each
      (fn (_ r)
        (def name (first (rest (rest (rest r)))))
        (def cell (sites get name))
        (def site
          (list (%link-place (first r) sections 0) (first (rest r)) (kind-of (first (rest (rest r))))
                (first (rest (rest (rest (rest r)))))))
        (if (null? cell)
          (do (sites set! name (pair (list site) ()))
              (%set-first! order (pair name (first order))))
          (%set-first! cell (pair site (first cell)))))
      (first (rest (rest object))))
    (def take
      (fn (_ name)
        (def cell (sites get name))
        (if (null? cell) ()
          (let ((s (%reverse (first cell))))
            (%set-first! cell ())
            (%set-rest! cell #t)
            s))))
    (def symbols
      (%map (fn (_ s)
              (def scope (first (rest (rest (rest s)))))
              (list (first s)
                (if (null? (first (rest s))) 255 (%link-place (first (rest s)) sections 0))
                (match ((eq? scope (lit global)) 0) ((eq? scope (lit local)) 1) (#t ()))
                (first (rest (rest s)))
                (take (first s))))
        (first (rest object))))
    (def others
      (%map (fn (_ name) (list name 255 2 0 (take name)))
        (List filter (fn (_ name) (not (eq? (rest (sites get name)) #t))) (%reverse (first order)))))
    (pair (%reverse (first kinds)) (List append symbols others))))

; whether the records can hold these sections, kinds and names
(def %link-binary?
  (fn (_ sections kinds names)
    (if (List all? (fn (_ s) (%link-7bit? (symbol->str (first s)))) sections)
      (if (List all? (fn (_ k) (%link-7bit? (first (rest (rest k))))) kinds)
        (List all?
          (fn (_ y)
            (if (null? (first (rest (rest y)))) #f
              (if (int< (str-byte-len (first y)) 256) (%link-7bit? (first y)) #f)))
          names)
        #f)
      #f)))

(def %link-site-bytes 16)

; how many bytes the records of these take
(def %link-block-size
  (fn (_ sections kinds names)
    (int+
      (List fold (fn (_ acc s) (int+ acc (int+ 11 (str-byte-len (symbol->str (first s)))))) 0 sections)
      (int+
        (List fold (fn (_ acc k) (int+ acc (int+ 2 (str-byte-len (first (rest (rest k))))))) 0 kinds)
        (List fold
          (fn (_ acc y)
            (def n (List length (first (rest (rest (rest (rest y)))))))
            (int+ acc
              (int+ 9 (int+ (str-byte-len (first y)) (int* %link-site-bytes (if (int= n 0) 1 n))))))
          0 names)))))

; SITES at AT in P, the last flagged, or one that stands for none; answers
; the offset after them
(def %link-put-sites
  (fn (self p at sites)
    (if (null? sites)
      (do (ptr-set! p at 192 1) (int+ at %link-site-bytes))
      (let ((s (first sites)) (addend (first (rest (rest (rest (first sites)))))))
        (ptr-set! p at (if (null? (rest sites)) 128 0) 1)
        (ptr-set! p (int+ at 1) (first s) 1)
        (ptr-set! p (int+ at 2) (first (rest (rest s))) 2)
        (ptr-set! p (int+ at 4) (first (rest s)) 4)
        (ptr-set-word! p (int+ at 8) addend)
        (when (if (int< %link-word-bytes 8) (int< addend 0) #f)
          (ptr-set! p (int+ at 12) -1 4))
        (if (null? (rest sites)) (int+ at %link-site-bytes)
          (self p (int+ at %link-site-bytes) (rest sites)))))))

; the Y record of Y at AT in P; answers the offset after it
(def %link-put-named
  (fn (_ p at y)
    (ptr-set! p at 89 1)
    (ptr-set! p (int+ at 1) (first (rest y)) 1)
    (ptr-set! p (int+ at 2) (first (rest (rest y))) 1)
    (ptr-set! p (int+ at 3) (first (rest (rest (rest y)))) 4)
    (ptr-set! p (int+ at 7) (str-byte-len (first y)) 1)
    (%link-put-sites p (%link-put-name p (int+ at 8) (first y))
      (first (rest (rest (rest (rest y))))))))

; OBJECT's records as (SIZE . BLOCK), or () when it has a name, a kind or a
; scope the records cannot hold: such an object is written as text.
(def %link-block
  (fn (_ object)
    (def sections (first object))
    (def found (%link-names object))
    (def kinds (first found))
    (def names (rest found))
    (if (%link-binary? sections kinds names)
      (let ((size (%link-block-size sections kinds names)))
        (def block (str-make (if (int= size 0) 1 size)))
        (def p (str->ptr block))
        (%mem-set p 0 (if (int= size 0) 1 size))
        (def at (pair 0 ()))
        (%for-each
          (fn (_ s)
            (def a (first at))
            (ptr-set! p a 83 1)
            (ptr-set! p (int+ a 1) (first (rest s)) 4)
            (ptr-set! p (int+ a 5) (first (rest (rest s))) 4)
            (ptr-set! p (int+ a 9) (if (null? (first (rest (rest (rest s))))) 0 1) 1)
            (%set-first! at (%link-put-name p (int+ a 10) (symbol->str (first s)))))
          sections)
        (%for-each
          (fn (_ k)
            (ptr-set! p (first at) 75 1)
            (%set-first! at (%link-put-name p (int+ (first at) 1) (first (rest (rest k))))))
          kinds)
        (%for-each (fn (_ y) (%set-first! at (%link-put-named p (first at) y))) names)
        (pair size block))
      ())))

; The Lexer the records are read with, made at the first read.
(def %link-lexer (pair () ()))
(def %link-records
  (fn (_)
    (when (null? (first %link-lexer))
      (%set-first! %link-lexer
        (Lexer make
          (list (Lexer record (lit record)
                  (list (pair "S" (lit ((bytes 9) (units 1 128))))
                        (pair "K" (lit ((units 1 128))))
                        (pair "Y" (lit ((bytes 7) (units 1 128) (units 16 128))))))))))
    (first %link-lexer)))

; The object the SIZE bytes of BLOCK are the records of, its sections'
; bytes not yet read: (SECTIONS SYMBOLS RELOCS), each section (NAME ALIGN
; SIZE BYTES?) with BYTES? whether the file holds its bytes.  The
; relocations come grouped by name, in the order the names were written.
(def %link-unblock
  (fn (_ block size)
    (def tokens ((%link-records) read-span block 0 size))
    (def sections (pair () ()))
    (def kinds (pair () ()))
    (def symbols (pair () ()))
    (def relocs (pair () ()))
    (def read (pair 0 ()))
    (%for-each
      (fn (_ t)
        (def p (str->ptr (first (rest t))))
        (def len (first (rest (rest t))))
        (def tag (ptr-ref p 0 1))
        (%set-first! read (int+ (first read) len))
        (match
          ((int= tag 83)
            (%set-first! sections
              (pair (list (str->sym (%link-take p 10 (int- len 11))) (ptr-ref p 1 4) (ptr-ref p 5 4)
                          (int= (ptr-ref p 9 1) 1))
                (first sections))))
          ((int= tag 75)
            (%set-first! kinds (pair (first (Xon parse (%link-take p 1 (int- len 2)))) (first kinds))))
          (#t
            (do
              ; the first record of a name: the tables before it are whole
              (when (null? (rest sections))
                (%set-rest! sections (%reverse (first sections)))
                (%set-rest! kinds (%reverse (first kinds))))
              (def name (%link-take p 8 (ptr-ref p 7 1)))
              (def scope (ptr-ref p 2 1))
              (def section (ptr-ref p 1 1))
              (unless (int= scope 2)
                (%set-first! symbols
                  (pair (list name (if (int= section 255) () (first (%link-nth (rest sections) section)))
                              (ptr-ref p 3 4) (if (int= scope 0) (lit global) (lit local)))
                    (first symbols))))
              (%set-first! relocs
                ((fn (self u acc)
                   (def flag (ptr-ref p u 1))
                   (def more
                     (if (int= 0 (int& flag 64))
                       (pair (list (first (%link-nth (rest sections) (ptr-ref p (int+ u 1) 1))) (ptr-ref p (int+ u 4) 4)
                                   (%link-nth (rest kinds) (ptr-ref p (int+ u 2) 2)) name (ptr-ref-word p (int+ u 8)))
                         acc)
                       acc))
                   (if (int= 0 (int& flag 128)) (self (int+ u 16) more) more))
                 (int+ 9 (ptr-ref p 7 1)) (first relocs)))))))
      tokens)
    (unless (int= (first read) size) (%link-refuse "an object file's records are damaged"))
    (list (if (null? (rest sections)) (%reverse (first sections)) (rest sections))
          (%reverse (first symbols)) (%reverse (first relocs)))))

(doc (def link-write!
  (fn (_ path object . form)
    (def sections (first object))
    (def block
      (if (if (null? form) #f (eq? (first form) (lit text))) () (%link-block object)))
    (def text
      (if (null? block)
        (Str8 join "\n"
          (%map %link-emit
            (List append
              (%map (fn (_ s)
                      (def bytes (first (rest (rest (rest s)))))
                      (list (lit section) (first s) (first (rest s)) (first (rest (rest s)))
                        (if (null? bytes) 0 (first (rest (rest s))))))
                sections)
              (List append
                (%map (fn (_ s) (pair (lit symbol) s)) (first (rest object)))
                (%map (fn (_ r) (pair (lit reloc) r)) (first (rest (rest object))))))))
        ()))
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420))
    (if (int< fd 0) (%link-refuse (Str8 append "cannot write " path)))
    (if (null? block)
      (do (File write fd (%link-first-line 1 (str-byte-len text)) 32)
          (File write fd text (str-byte-len text)))
      (do (File write fd (%link-first-line 2 (first block)) 32)
          (unless (int= (first block) 0) (File write fd (rest block) (first block)))))
    (%for-each
      (fn (_ s)
        (def bytes (first (rest (rest (rest s)))))
        (unless (null? bytes) (File write fd bytes (first (rest (rest s))))))
      sections)
    (File close fd)
    ()))
  (param path STRING "Where to write")
  (param object LIST "The object, (SECTIONS SYMBOLS RELOCS)")
  (param form SYMBOL "Optionally text, for records a person can read")
  (returns NIL "")
  (sample "(link-write! \"unit.xo\" object)" "the object file, its records binary")
  (sample "(link-write! \"unit.xo\" object 'text)" "the same object, its records text")
  "Write OBJECT as an object file at PATH.  Its records are binary, which link-read takes in a fraction of the time text takes, unless FORM is text or a name, a relocation kind or a scope has no binary form (a byte past 127, a scope that is neither global nor local): then they are text.")

; N bytes from FD, as a string; fewer end the file early.  A read of a
; file answers all it was asked for, so one read is the rule and the
; pieces of a short one are joined.
(def %link-read-bytes
  (fn (_ fd n)
    (def go
      (fn (self left pieces)
        (if (int< 0 left)
          (let ((buf (str-make left)))
            (def got (File read fd buf left))
            (if (int< got 1) (%link-refuse "an object file ends early"))
            (self (int- left got)
              (pair (if (int= got left) buf (Str8 sub 0 got buf)) pieces)))
          (if (null? (rest pieces)) (first pieces) (Str8 join "" (%reverse pieces))))))
    (go n ())))

(doc (def link-read
  (fn (_ path)
    (def fd (File open path (lit rdonly)))
    (if (int< fd 0) (%link-refuse (Str8 append "cannot read " path)))
    (def line (Xon parse (%link-read-bytes fd 32)))
    (if (if (null? line) #t (not (eq? (first line) (lit x-object))))
      (%link-refuse (Str8 append path " is not an object file")))
    (def version (first (rest line)))
    (def n (first (rest (rest line))))
    ; the object, each section's bytes still to read: (NAME ALIGN SIZE BYTES?)
    (def object
      (match
        ((int= version 2)
          (if (int= n 0) (list () () ()) (%link-unblock (%link-read-bytes fd n) n)))
        ((int= version 1)
          (let ((forms (Xon parse (%link-read-bytes fd n))))
            (list
              (%map (fn (_ f)
                      (list (first (rest f)) (first (rest (rest f))) (first (rest (rest (rest f))))
                        (not (int= (first (rest (rest (rest (rest f))))) 0))))
                (List filter (fn (_ f) (eq? (first f) (lit section))) forms))
              (%map rest (List filter (fn (_ f) (eq? (first f) (lit symbol))) forms))
              (%map rest (List filter (fn (_ f) (eq? (first f) (lit reloc))) forms)))))
        (#t (%link-refuse (Str8 append path " is an object file of a version this library does not read")))))
    (def sections
      (%map (fn (_ s)
              (list (first s) (first (rest s)) (first (rest (rest s)))
                (if (first (rest (rest (rest s)))) (%link-read-bytes fd (first (rest (rest s)))) ())))
        (first object)))
    (File close fd)
    (pair sections (rest object))))
  (param path STRING "An object file link-write! wrote")
  (returns LIST "The object, (SECTIONS SYMBOLS RELOCS)")
  (sample "(link-read \"unit.xo\")" "the object link-write! wrote there, (SECTIONS SYMBOLS RELOCS), each section's bytes read back")
  "Read the object file at PATH, its records binary or text.  From binary records the relocations come grouped by the name each takes, the names in the order they were written and each name's relocations in theirs; link resolves a name once for the group.")

(doc (provide x/tool/link link link-undefined link-write! link-read)
  (example "(import x/tool/link link-undefined) (link-undefined (list (list () () (list (list 'data 0 'abs \"table\" 0)))))" "(\"table\")")
  "Sections, symbols and relocations: lay objects out as one program, resolve and patch every name, and read and write object files.")
