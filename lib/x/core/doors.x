; doors.x -- the engine's hot doors, bound once and provided by name.
;
; A door is a catalogue entry fetched with prim-ref: the C instrument
; itself, called with no closure between.  The platform's operators are
; closures over the same instruments -- `<` costs ten objects a call where
; the door costs none, `+` one -- so a hot path takes the door.  Until this
; module every such file fetched its own: 1,250 binds of the same sixty
; coordinates under as many private spellings.  Here each is bound once
; and spelled from its coordinate, NS-MEMBER, with the hyphen dropped where
; the member starts with a sign: (int +) is int+, (str byte-ref) is
; str-byte-ref, (type ?) is type?.
;
; A selective import copies the binding into the importer's own frame,
; (import x/core/doors int+ str-byte-ref), so a call through the name
; costs what a local def of it costs, measured: 0 objects for int<, 1 for
; int+.  An unscoped importer's frame is the root, so there the copy is a
; root binding, as num/tower.x's imports of the number modules are.  The
; boot files load before this module can be served and keep their own.
;
; The set is the coordinates three or more library files bound; a
; coordinate one file alone fetches stays with that file.  So does one a
; library module files into the catalogue after this module can load,
; (convert to) from x/type/convert: fetched here it would be nil.  The
; type entries x/type/struct files are in, since struct.x loads before
; doc.x and this module cannot load until after it.
(module x/core/doors)

; --- int: the C operators the number tower does not wrap ----------------
(def int+ (prim-ref (lit int) (lit +)))
(def int- (prim-ref (lit int) (lit -)))
(def int* (prim-ref (lit int) (lit *)))
(def int/ (prim-ref (lit int) (lit /)))
(def int% (prim-ref (lit int) (lit %)))
(def int< (prim-ref (lit int) (lit <)))
(def int= (prim-ref (lit int) (lit =)))
(def int& (prim-ref (lit int) (lit &)))
(def int| (prim-ref (lit int) (lit |)))
(def int<< (prim-ref (lit int) (lit <<)))
(def int>> (prim-ref (lit int) (lit >>)))
(def int->ptr (prim-ref (lit int) (lit ->ptr)))
(def int->char (prim-ref (lit int) (lit ->char)))

; --- str: bytes, regions and the byte-level views -----------------------
(def str-make (prim-ref (lit str) (lit make)))
(def str-append (prim-ref (lit str) (lit append)))
(def str-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def str-byte-len (prim-ref (lit str) (lit byte-len)))
(def str-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def str->ptr (prim-ref (lit str) (lit ->ptr)))
(def str->sym (prim-ref (lit str) (lit ->sym)))
(def char->int (prim-ref (lit char) (lit ->int)))

; --- ptr and mem: raw memory ---------------------------------------------
(def ptr-ref (prim-ref (lit ptr) (lit ref)))
(def ptr-set! (prim-ref (lit ptr) (lit set!)))
(def ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
(def ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))
(def ptr-call (prim-ref (lit ptr) (lit call)))
(def ptr->int (prim-ref (lit ptr) (lit ->int)))
(def ptr->str (prim-ref (lit ptr) (lit ->str)))
(def ptr->obj (prim-ref (lit ptr) (lit ->obj)))
(def mem-copy (prim-ref (lit mem) (lit copy)))
(def mem-cmp (prim-ref (lit mem) (lit cmp)))

; --- obj: slots and identity --------------------------------------------
(def obj-make (prim-ref (lit obj) (lit make)))
(def obj-ref (prim-ref (lit obj) (lit ref)))
(def obj-set! (prim-ref (lit obj) (lit set!)))
(def obj->ptr (prim-ref (lit obj) (lit ->ptr)))
(def obj-same? (prim-ref (lit obj) (lit same?)))

; --- type: handles, instances and the handler stacks --------------------
(def type-of (prim-ref (lit type) (lit of)))
(def type? (prim-ref (lit type) (lit ?)))
(def type-make (prim-ref (lit type) (lit make)))
(def type-make-instance (prim-ref (lit type) (lit make-instance)))
(def type-by-atom (prim-ref (lit type) (lit by-atom)))
(def type-from-cell (prim-ref (lit type) (lit from-cell)))
(def type-push-call (prim-ref (lit type) (lit push-call)))
(def type-push-op (prim-ref (lit type) (lit push-op)))
(def type-push-write (prim-ref (lit type) (lit push-write)))
(def type-push-analyse (prim-ref (lit type) (lit push-analyse)))

; --- the rest: io, buf, tok, ffi, heap, image ---------------------------
(def io-write-to-str (prim-ref (lit io) (lit write-to-str)))
(def io-display-to-str (prim-ref (lit io) (lit display-to-str)))
(def buf-tok (prim-ref (lit buf) (lit tok)))
(def buf-last-char (prim-ref (lit buf) (lit last-char)))
(def tok-read-str (prim-ref (lit tok) (lit read-str)))
(def ffi-dlopen (prim-ref (lit ffi) (lit dlopen)))
(def ffi-dlsym (prim-ref (lit ffi) (lit dlsym)))
(def heap-collect (prim-ref (lit heap) (lit collect)))
(def image-transient! (prim-ref (lit image) (lit transient!)))
(def image-recache-hook! (prim-ref (lit image) (lit recache-hook!)))

(doc (provide x/core/doors
  int+ int- int* int/ int% int< int= int& int| int<< int>> int->ptr int->char
  str-make str-append str-byte-ref str-byte-len str-byte-sub str->ptr str->sym char->int
  ptr-ref ptr-set! ptr-ref-word ptr-set-word! ptr-call ptr->int ptr->str ptr->obj mem-copy mem-cmp
  obj-make obj-ref obj-set! obj->ptr obj-same?
  type-of type? type-make type-make-instance type-by-atom type-from-cell
  type-push-call type-push-op type-push-write type-push-analyse
  io-write-to-str io-display-to-str buf-tok buf-last-char tok-read-str
  ffi-dlopen ffi-dlsym heap-collect image-transient! image-recache-hook!)
  (note "A door is the catalogue entry itself, so a call through it allocates nothing where the platform operator is a closure call: (int <) is 0 objects a call against 10 for `<`, (int +) 1 against 2 for `+`.")
  (note "A selective import, (import x/core/doors int+ str-byte-ref), copies the door into the importer's frame, where it costs what a local def costs; an unscoped importer's frame is the root.")
  (see prim-ref)
  "The engine's hot doors -- (int +), (str byte-ref), (obj ref), (ptr set!), (type of) and the rest a hot path in the library calls -- each bound once under a name spelled from its coordinate, for every module to import instead of fetching its own.")
