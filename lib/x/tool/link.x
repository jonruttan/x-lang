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
; An object file is the object's records as text, then its bytes: the
; first line names the format and how long the text is, so a reader takes
; the text with one read and each section's bytes with another.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
(module x/tool/link)

(import x/type/dict)
(import x/sys/file)
(import x/codec/xon)
(import x/core/doors int+ int- int% int< int= int->ptr io-write-to-str mem-copy ptr->int
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
    ; every relocation, through PATCH
    (def apply
      (fn (self os ps i)
        (unless (null? os)
          (do (%for-each
                (fn (_ r)
                  (def section (first r))
                  (def base (rest (%link-assq section (first ps))))
                  (def offset (int+ base (first (rest r))))
                  (def kind (first (rest (rest r))))
                  (def name (first (rest (rest (rest r)))))
                  (def addend (first (rest (rest (rest (rest r))))))
                  (patch (first (buffers get section)) offset kind
                    (int+ (value-of i name) addend)
                    (int+ (address get section) offset)))
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
  "Link OBJECTS: lay their sections out, resolve every name, and patch every place that takes one.  A name no object defines, or one defined twice, refuses.")

; --- object files ------------------------------------------------------------------
; The first line, padded to 32 bytes: the format, its version and how
; many bytes of text follow it.  A reader takes the line with one read of
; a known length.
(def %link-first-line
  (fn (_ n)
    (def head (Str8 append "x-object 1 " (io-write-to-str n)))
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

(doc (def link-write!
  (fn (_ path object)
    (def sections (first object))
    (def forms
      (%map (fn (_ s)
              (def bytes (first (rest (rest (rest s)))))
              (list (lit section) (first s) (first (rest s)) (first (rest (rest s)))
                (if (null? bytes) 0 (first (rest (rest s))))))
        sections))
    (def forms2
      (%map (fn (_ s) (pair (lit symbol) s)) (first (rest object))))
    (def forms3
      (%map (fn (_ r) (pair (lit reloc) r)) (first (rest (rest object)))))
    (def text
      (Str8 join "\n"
        (%map %link-emit (List append forms (List append forms2 forms3)))))
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420))
    (if (int< fd 0) (%link-refuse (Str8 append "cannot write " path)))
    (File write fd (%link-first-line (str-byte-len text)) 32)
    (File write fd text (str-byte-len text))
    (%for-each
      (fn (_ s)
        (def bytes (first (rest (rest (rest s)))))
        (unless (null? bytes) (File write fd bytes (first (rest (rest s))))))
      sections)
    (File close fd)
    ()))
  (param path STRING "Where to write")
  (param object LIST "The object, (SECTIONS SYMBOLS RELOCS)")
  (returns NIL "")
  "Write OBJECT as an object file at PATH.")

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
    (def forms (Xon parse (%link-read-bytes fd (first (rest (rest line))))))
    (def sections
      (%map (fn (_ f)
              (def n (first (rest (rest (rest (rest f))))))
              (list (first (rest f)) (first (rest (rest f))) (first (rest (rest (rest f))))
                (if (int= n 0) () (%link-read-bytes fd n))))
        (List filter (fn (_ f) (eq? (first f) (lit section))) forms)))
    (File close fd)
    (list sections
      (%map rest (List filter (fn (_ f) (eq? (first f) (lit symbol))) forms))
      (%map rest (List filter (fn (_ f) (eq? (first f) (lit reloc))) forms)))))
  (param path STRING "An object file link-write! wrote")
  (returns LIST "The object, (SECTIONS SYMBOLS RELOCS)")
  "Read the object file at PATH.")

(doc (provide x/tool/link link link-undefined link-write! link-read)
  "Sections, symbols and relocations: lay objects out as one program, resolve and patch every name, and read and write object files.")
