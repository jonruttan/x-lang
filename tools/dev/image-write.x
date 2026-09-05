; image-write.x -- write a state image.  docs/state-image-format.md is the
; contract; section numbers below are its.
;
;   { echo '(def %IMG-LIB "lib/x-core.x") (def %IMG-OUT "/tmp/x-core.ximg")';
;     cat tools/dev/image-write.x; } | sh x.sh -q
;
; Runs on helium.  With %IMG-LIB bound, a child base loads that library and
; the child is what gets imaged; this base is never in the picture.  Without
; it, this base images itself (a development route; the writer's own names
; come along).
;
; The image is the child's LANGUAGE STATE -- the cells base-layout.x tags
; (build ...) -- and every object reachable from them (spec 1, 2).  Nothing
; of the spine and nothing of process state is written; a reference to
; either is an external, by contract row (spec 3.4).
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(include "tools/dev/image-walk.x")
(include "tools/dev/image-name.x")
(include "engine/tools/contract/base-paths.x")

(def %IMG-LIB (guard (_ ()) (eval (lit %IMG-LIB))))
(def %IMG-OUT (guard (_ "/tmp/x.ximg") (eval (lit %IMG-OUT))))

(def %alloc  (prim-ref (lit ptr) (lit alloc)))
(def %swrite (prim-ref (lit sys) (lit write)))
(def %pcopy! (prim-ref (lit ptr) (lit copy!)))
(def %pfill! (prim-ref (lit ptr) (lit fill!)))
(def %zeroed (fn (_ n) ((fn (_ p) (do (%pfill! p 0 n) p)) (%alloc n))))
(def %put (fn (_ p i w) (do (%psw p (%int* i %word-size) w) (%int+ i 1))))
(def %addr (fn (_ o) (Ptr ->int (%o->p o))))

; --- the base to image (spec 4.2) ----------------------------------------
(def %B (if (null? %IMG-LIB) (Base wrap (%base)) (Base make)))
(def %RAW (Base raw-of %B))
; A child owns its bindings.  x-cli binds these into the root base only;
; each is re-made INSIDE the child: the two primitives from their function
; pointers, the strings copied there, args as the child's own empty list.
;  The NAME is interned by the child -- (str ->sym) evaluated inside it --
; not this base's symbol handed over as a literal, which would key the
; child's binding by an object on this base's chain.
(def %child-def!
  (fn (_ nm form)
    (%B eval (list (prim-ref (lit base) (lit def-global))
                   (list (prim-ref (lit str) (lit ->sym)) (symbol->str nm)) form))))
(def %child-prim!
  (fn (_ nm fnobj)
    (%child-def! nm (list (prim-ref (lit obj) (lit make-callable))
                          (list (lit lit) (%i->p (%word-at (%o->p fnobj) 0)))))))
(def %child-str!
  (fn (_ nm s)
    (%child-def! nm (list (prim-ref (lit str) (lit append)) "" (list (lit lit) s)))))
(if (null? %IMG-LIB) ()
  (do (%child-prim! (lit include) %raw-include)
      (guard (_ ()) (%child-prim! (lit syscall) (eval (lit syscall))))
      (%child-str! (lit x-machine) x-machine)
      (%child-str! (lit x-version) x-version)
      (%child-str! (lit x-release) x-release)
      ; The child is a BATCH: a dialect entry ends in (unless %batch? (do
      ; (%banner) (repl))), and repl/banner.x derives %batch? from args
      ; holding "--batch".  Without it the child's REPL reads this writer's
      ; own stdin and the image is never written.  One string, the child's.
      (%child-def! (lit args)
        (list (lit pair) (list (prim-ref (lit str) (lit append)) "" "--batch") (list (lit lit) ())))
      ; The path too: `include` records it in the child's file registry.
      (%B eval (list (lit include) (list (prim-ref (lit str) (lit append)) "" %IMG-LIB)))
      ; A TRANSIENT IS IMAGED AS NIL.  reflect.x's %image-transients names
      ; the globals whose value belongs to this process alone -- float.x's
      ; libm handle -- and a recache hook of the same module re-derives each
      ; once the loader has installed the image.  Cleared here, inside the
      ; child, so the walk below never meets the word.  ONE FORM, walked by
      ; the child over its own list: a version that fetched the list out
      ; and evaluated a set! per name put child objects in this base's
      ; hands between two collects, and the x-base writer died of it.
      (guard (_ ()) (%B eval (lit ((fn (self l) (if (null? l) () (do (eval (list (lit set!) (first l) ())) (self (rest l))))) %image-transients))))
      ; The child has never collected.  Its own collect, evaluated inside it.
      (%B eval (list %collect))
      ; And this base may not collect while a walk holds a cursor into the
      ; child (image-walk.x).  Walks run with the periodic collect off.
      (set! %WALK-COLLECT #f)))
;  The child is evaluated in twice more, both HERE and never after: the
; token-eof static, looked up by name, and the walk cursor -- a pair that is
; the head of the child's chain.  Every snapshot below (spine set, mark,
; write) is of the child as it is now.  An evaluation in the child after
; this point can allocate, and a collect can then free a process leaf the
; spine set recorded and hand its address to a language object.
(def %TOKEN-EOF (guard (_ ()) (%B eval (lit %token-eof))))
(def %CURSOR (if (null? %IMG-LIB) (pair 1 2) (%B eval (lit (pair 1 2)))))
(def %cursor (fn (_) %CURSOR))
(def %between (fn (_) (if %WALK-COLLECT () (%collect))))

; --- the contract, read as data (spec 1) -------------------------------------
; base-layout.x's tags are bound as operatives: inside a (build ...) subtree,
; `cell` and `slot` record the language cells.  Everything else evaluates to
; nothing; `pair` is the primitive and carries the walk.
(def %LANG ())                    ; ((name . cell|slot) ...)
(def %IN-BUILD #f)
(def %eval-all (fn (self l e) (if (null? l) () (do (eval (first l) e) (self (rest l) e)))))
(def cell (op (nm) e (do (if %IN-BUILD (set! %LANG (pair (pair nm (lit cell)) %LANG)) ()) ())))
(def slot (op (nm) e (do (if %IN-BUILD (set! %LANG (pair (pair nm (lit slot)) %LANG)) ()) ())))
(def todo (op (nm) e ()))
(def nil (op () e ()))
(def node (op (nm . kids) e (do (%eval-all kids e) ())))
(def build (op (x) e (do (set! %IN-BUILD #t) (eval x e) (set! %IN-BUILD #f) ())))
(include "engine/tools/contract/base-layout.x")
; The profile counters, the sigint flag and the line counter stay the
; loader's own.  `line` sits in the layout's build region, but the C reader
; holds its counter atom directly and counts into it: a cell swapped under
; the reader reads 0 from then on (spec 8).
(def %root-cell?
  (fn (_ nm)
    (if (eq? nm (lit sigint)) #f
      (if (eq? nm (lit line)) #f
        (not (str=? (Str8 sub 0 8 (symbol->str nm)) "profile-"))))))
(def %ROOTS ((fn (self l acc) (if (null? l) acc (self (rest l) (if (%root-cell? (first (first l))) (pair (first l) acc) acc)))) %LANG ()))

(def %step (fn (_ v s) (if (eq? s (lit f)) (first v) (rest v))))
(def %at (fn (self v steps) (if (null? steps) v (self (%step v (first steps)) (rest steps)))))
(def %row-steps
  (fn (self rows nm)
    (if (null? rows) ()
      (if (eq? (first (first rows)) nm) (rest (rest (first rows))) (self (rest rows) nm)))))
(def %base-row? (fn (_ row) (eq? (first (rest row)) (lit base))))
; A root's VALUE: a cell's is in its first slot; a slot's is what the row reaches.
(def %root-value
  (fn (_ r)
    ((fn (_ node) (if (eq? (rest r) (lit cell)) (first node) node))
     (%at %RAW (%row-steps %base-paths (first r))))))

; --- the spine set (spec 1, 3.4 kind 8) ----------------------------------------
; Every node of the base tree that is NOT a language object: the pairs of the
; tree walked structurally from the base object's data, and the process
; leaves under them.  Never descended: a root's value.  Recorded in raw
; memory (address -> 1) beside the externals table, and named by the base-rooted
; row that reaches it, when one does.
(def %HT-SIZE 262144)
(def %ht-mask (%int- %HT-SIZE 1))
(def %ht-new (fn (_) (%zeroed (* 16 %HT-SIZE))))
(def %ht-idx (fn (_ a) (%int& (%shr a 4) %ht-mask)))
(def %ht-put
  (fn (self t a v i)
    (if (eq? (%rw t (%int* (%int* i 2) %word-size)) 0)
        (do (%psw t (%int* (%int* i 2) %word-size) a)
            (%psw t (%int* (%int+ (%int* i 2) 1) %word-size) v))
      (if (eq? (%rw t (%int* (%int* i 2) %word-size)) a)
          (%psw t (%int* (%int+ (%int* i 2) 1) %word-size) v)
          (self t a v (%int& (%int+ i 1) %ht-mask))))))
(def %ht-get
  (fn (self t a i)
    (if (eq? (%rw t (%int* (%int* i 2) %word-size)) 0) 0
      (if (eq? (%rw t (%int* (%int* i 2) %word-size)) a)
          (%rw t (%int* (%int+ (%int* i 2) 1) %word-size))
          (self t a (%int& (%int+ i 1) %ht-mask))))))
(def %ht-add! (fn (_ t a v) (%ht-put t a v (%ht-idx a))))
(def %ht-find (fn (_ t a) (%ht-get t a (%ht-idx a))))

(def %SPINE (%ht-new))          ; address -> 1
(def %SPINE-LIST ())            ; every address the walk put in, for the passes below
(def %ROOT-ADDRS ((fn (self l acc) (if (null? l) acc (self (rest l) ((fn (_ v) (if (null? v) acc (pair (%addr v) acc))) (%root-value (first l)))))) %ROOTS ()))
(def %root-addr? (fn (self l a) (if (null? l) #f (if (eq? (first l) a) #t (self (rest l) a)))))
(def %spair-p? (fn (_ p) (eq? (%rw p %type-off) %reflect-spair-tw)))
;  Only ON-CHAIN nodes go in the set: an off-chain leaf under the spine (the
; sigint flag, #t, #f) is an engine static, and statics are named by role or
; type row, never as spine.
(def %spine-walk
  (fn (self p)
    (if (eq? p 0) ()
      (if (%root-addr? %ROOT-ADDRS p) ()
        (if (eq? (%rw p %heap-off) 0) ()
          (do (%ht-add! %SPINE p 1)
              (set! %SPINE-LIST (pair p %SPINE-LIST))
              (if (%spair-p? p)
                  (do (self (%word-at p 0)) (self (%word-at p 1)))
                  ())))))))
(%spine-walk (%word-at (%o->p %RAW) 0))
(%ht-add! %SPINE (%addr %RAW) 1)
; Elements of the hook and root lists may be language objects the library
; registered; they come out of the set (the list pairs stay in).
(def %unhash-list!
  (fn (self l)
    (if (null? l) ()
      (do (if (null? (first l)) () (%ht-add! %SPINE (%addr (first l)) 0))
          (self (rest l))))))
(%unhash-list! (first (%at %RAW (%row-steps %base-paths (lit heap-mark-hooks)))))
(%unhash-list! (first (%at %RAW (%row-steps %base-paths (lit heap-free-hooks)))))
(%unhash-list! (first (%at %RAW (%row-steps %base-paths (lit heap-mark-roots)))))
; Names: every base-rooted row's endpoint, plus the base object itself.
(def %SPINE-NAMES (%ht-new))    ; address -> row-name symbol (as an object address)
(def %NAME-OBJS ())             ; keeps the symbols alive
(def %name-spine!
  (fn (self rows)
    (if (null? rows) ()
      (do (if (%base-row? (first rows))
              ((fn (_ node nm)
                 (if (null? node) ()
                   (if (eq? (%ht-find %SPINE-NAMES (%addr node)) 0)
                       (do (set! %NAME-OBJS (pair nm %NAME-OBJS))
                           (%ht-add! %SPINE-NAMES (%addr node) (%addr nm)))
                       ())))
               (%at %RAW (rest (rest (first rows)))) (first (first rows)))
              ())
          (self (rest rows))))))
(%name-spine! %base-paths)
(set! %NAME-OBJS (pair (lit base) %NAME-OBJS))
(%ht-add! %SPINE-NAMES (%addr %RAW) (%addr (first %NAME-OBJS)))

; --- the engine's statics, by role and by pristine type row (spec 3.4) --------
(def %STATIC-NAMES (%ht-new))   ; address -> (kind . name) object address
(def %STATIC-OBJS ())
(def %static! (fn (_ a kind nm) (if (eq? (%ht-find %STATIC-NAMES a) 0) (do (set! %STATIC-OBJS (pair (pair kind nm) %STATIC-OBJS)) (%ht-add! %STATIC-NAMES a (%addr (first %STATIC-OBJS)))) ())))
(def %X-STATIC 6) (def %X-TYPE-STATIC 7) (def %X-BASE-ROW 8)
(%static! (%addr (first (%at %RAW (%row-steps %base-paths (lit true))))) %X-STATIC "true")
(%static! (%addr (first (%at %RAW (%row-steps %base-paths (lit false))))) %X-STATIC "false")
(%static! (%addr (first (%at %RAW (%row-steps %base-paths (lit sigint))))) %X-STATIC "sigint")
((fn (_ eof) (if (null? eof) () (%static! (%addr eof) %X-STATIC "token-eof")))
 %TOKEN-EOF)
; x_type_units_pair_obj: the units value of any type the library registered.
((fn (self al)
   (if (null? al) ()
     ((fn (_ u) (if (null? u) (self (rest al))
                  (if (%sh-static? u) (%static! (%addr u) %X-STATIC "units-pair") (self (rest al)))))
      (first (%type-units-cell (rest (first al)))))))
 (first (%at %RAW (%row-steps %base-paths (lit type-alist)))))
; A fresh base's type structs hold the engine's static handlers, name atoms
; and default units at known rows; every off-chain node found there is named
; "TYPE row".
(def %type-rows ((fn (self rows acc) (if (null? rows) acc (self (rest rows) (if (eq? (first (rest (first rows))) (lit type)) (pair (first rows) acc) acc)))) %base-paths ()))
(def %off-chain? (fn (_ o) (eq? (%rw (%o->p o) %heap-off) 0)))
(def %tname (fn (_ st) (%p->s (%i->p (%word-at (%o->p (%at st (%row-steps %base-paths (lit type-name)))) 0)))))
(def %pristine-rows!
  (fn (self st nm rows)
    (if (null? rows) ()
      (do ((fn (_ node)
             (if (null? node) ()
               (if (%off-chain? node)
                   (%static! (%addr node) %X-TYPE-STATIC
                             (Str8 append nm (Str8 append " " (symbol->str (first (first rows))))))
                   ())))
           (guard (_ ()) (%at st (rest (rest (first rows))))))
          (self st nm (rest rows))))))
(def %name-statics-of!
  (fn (self al)
    (if (null? al) ()
      (do (%pristine-rows! (rest (first al)) (%tname (rest (first al))) %type-rows)
          (self (rest al))))))
(%name-statics-of! (first (%at (Base raw-of (Base make)) (%row-steps %base-paths (lit type-alist)))))
; ... and the imaged base's own structs: a type the pristine base never
; registered (POINTER registers on first use) still holds the same statics
; at the same rows, and a static is the same object in every base.
(%name-statics-of! (first (%at %RAW (%row-steps %base-paths (lit type-alist)))))

; --- function pointers (spec 3.4 kinds 1-5), the naming image-name.x does ----
(def %MAP (%make-map %B))

; --- mark (spec 4.1) ------------------------------------------------------------
(%between)
((fn (self l) (if (null? l) () (do ((fn (_ v) (if (null? v) () (%mark! v %TRACE))) (%root-value (first l))) (self (rest l))))) %ROOTS)
;  A leaf under a cell that a root reaches is the library's, not the base's:
; module.x hangs its include-once list off the false cell.  The cells stay
; spine whatever reaches them; their traced non-cell leaves come out, as
; the hook and root list elements did above.
(def %unhash-traced-leaves!
  (fn (self l)
    (if (null? l) ()
      (do ((fn (_ a)
             (if (eq? (%ht-find %SPINE a) 1)
                 (if (%spair-p? a) () (if (%traced? a) (%ht-add! %SPINE a 0) ()))
                 ()))
           (first l))
          (self (rest l))))))
(%unhash-traced-leaves! %SPINE-LIST)

;  The traced cells of the spine -- the library holds the base's false cell,
; its registry cell, its file registry -- stay spine: the flag comes off
; them, so the write below meets nothing but language objects.
(def %untrace-spine!
  (fn (self l)
    (if (null? l) ()
      (do ((fn (_ a)
             (if (eq? (%ht-find %SPINE a) 1)
                 (if (%traced? a)
                     (%psw a %flags-off (%int& (%rw a %flags-off) (%int- (%int- 0 1) %TRACE)))
                     ())
                 ()))
           (first l))
          (self (rest l))))))
(%untrace-spine! %SPINE-LIST)
(%between)

; --- the externals table (spec 3.4), grown on first use during the emit ------------
(def %X-CAP (* 8 400000))
(def %x-p (%zeroed %X-CAP))
(def %XCUR 0)                    ; words written
(def %XCOUNT 0)
(def %XIDX (%ht-new))            ; address -> external index
(def %words-for (fn (_ n) (%int+ 1 (%shr (%int+ n 1) 3))))
(def %put-name
  (fn (_ b cur nm)
    ((fn (_ n)
       (do (%psw b (%int* cur %word-size) n)
           (%pcopy! (%i->p (%int+ (Ptr ->int b) (%int* (%int+ cur 1) %word-size))) (%i->p (%word-at (%o->p nm) 0)) n)
           (%int+ cur (%int+ 1 (%words-for n)))))
     (%blen nm))))
(def %x-new!
  (fn (_ a kind nm)
    (do (set! %XCOUNT (%int+ %XCOUNT 1))
        (%ht-add! %XIDX a %XCOUNT)
        (set! %XCUR (%put-name %x-p (%put %x-p %XCUR kind) nm))
        %XCOUNT)))
(def %x-index
  (fn (_ a kind nm) ((fn (_ i) (if (eq? i 0) (%x-new! a kind nm) i)) (%ht-find %XIDX a))))
(def %SENT 0)                    ; unnameable references, counted and described
(def %SENT-LOG ())
(def %CUR-TW 0)                  ; the type word of the object being emitted
(def %CUR-KIND 0)                ; the unit kind of the word being named
(def %describe
  (fn (_ w)
    (if (eq? %CUR-KIND 3) (list (%ty-name %CUR-TW 0) (lit foreign-unnamed) w)
    (list (%ty-name %CUR-TW 0)
          (if (eq? (%ht-find %SPINE w) 1) (lit spine-unnamed)
            (if (eq? (%rw w %heap-off) 0) (lit off-chain-unnamed)
              (if (%traced? w) (lit on-chain-traced-not-imaged) (lit on-chain-untraced))))
          (%ty-name (%rw w %type-off) w)
          w
          (if (eq? (%ht-find %SPINE w) 1) ((fn (_ nm) (if (eq? nm 0) "no-row" (symbol->str (%p->o (%i->p nm))))) (%ht-find %SPINE-NAMES w)) "-")))))
(def %sentinel!
  (fn (_ w) (do (set! %SENT (%int+ %SENT 1)) (set! %SENT-LOG (pair (%describe w) %SENT-LOG)) 0)))
; A reference: an imaged object's index; a spine node by row; a static by
; role or type row; else the sentinel (past the table, restores nil).
(def %extern-ref
  (fn (_ w)
    (if (eq? (%ht-find %SPINE w) 1)
        ((fn (_ nm) (if (eq? nm 0) (%sentinel! w) (%x-index w %X-BASE-ROW (symbol->str (%p->o (%i->p nm))))))
         (%ht-find %SPINE-NAMES w))
      ((fn (_ e) (if (eq? e 0) (%sentinel! w) (%x-index w (first (%p->o (%i->p e))) (rest (%p->o (%i->p e))))))
       (%ht-find %STATIC-NAMES w)))))
; A function pointer: catalog, bare global, dlsym, type-call, dlopen handle.
;  A type-call pointer -- a closure's call slot, the address a whole TYPE
; shares -- is the word its type's own call handler holds: a procedure is
; made with x_type_procedure_call in unit 0 and PROCEDURE's call cell wraps
; that function (x-type/procedure.c); operatives likewise.  Named by the
; type, so the loader can give it this process's function.
(def %call-word-of
  (fn (_ tw)
    (guard (_ 0)
      ((fn (_ h) (if (null? h) 0 (%word-at (%o->p h) 0)))
       (%at (%p->o (%i->p tw)) (%row-steps %base-paths (lit type-call)))))))
(def %cp-word
  (fn (_ w p)
    ((fn (_ tw)
       (if (if (eq? (%ty-kind tw) %T-HEAP) (eq? w (%call-word-of tw)) #f)
           (%x-index w %F-TYPECALL (Type name (%p->o p)))
           ()))
     (%rw p %type-off))))
; A function pointer: type-call, catalog, bare global, dlopen handle, dlsym.
(def %fn-word
  (fn (_ w p)
    ((fn (_ k)
       (if (null? k)
           ((fn (_ e)
              (if (null? e)
                  ((fn (_ nm) (if (null? nm) (%sentinel! w) (%x-index w %F-DLSYM nm))) (%dl-name w))
                (%x-index w (first e) (rest e))))
            (%map-get %MAP w))
         k))
     (%cp-word w p))))
(set! %MAP (%map-add %MAP (Ptr ->int %lib) %F-DLOPEN ""))
(set! %MAP (%map-add %MAP (%fnptr %raw-include) %F-BARE "include"))
(guard (_ ()) (set! %MAP (%map-add %MAP (%fnptr (eval (lit syscall))) %F-BARE "syscall")))
(%between)

; --- the object table and the blob (spec 3.6, 3.7) --------------------------------
(def %OBJ-CAP-WORDS 6000000)
(def %OBJ-CAP (* %word-size %OBJ-CAP-WORDS))
(def %BLOB-CAP (* %word-size 400000))
(def %obj-p (%alloc %OBJ-CAP))
(def %blob-p (%zeroed %BLOB-CAP))
(def %ty-name
  (fn (_ tw p)
    (if (eq? tw 0) "NIL"
      (if (eq? tw %reflect-satom-tw) "ATOM"
        (if (eq? tw %reflect-spair-tw) "SPAIR"
          (guard (_ "?") (%tname (%p->o (%i->p tw)))))))))
;  The object table and the blob are (image write!)'s: the walk, the index
; and every record in C; every NAME from here.  It asks once per distinct
; word it cannot place -- a reference to an object outside the image, or a
; foreign address -- and says which object it met it in.
(def %name
  (fn (_ w kind o)
    ((fn (_ p)
       (do (set! %CUR-TW (%rw p %type-off))
           (set! %CUR-KIND kind)
           (if (eq? kind 3) (%fn-word w p) (%extern-ref w))))
     (%o->p o))))
; The roots' values, in %ROOTS order; the write answers with their indices.
(def %ROOT-VALUES ((fn (self l) (if (null? l) () (pair (%root-value (first l)) (self (rest l))))) %ROOTS))
(def %RTCOUNT ((fn (self l n) (if (null? l) n (self (rest l) (%int+ n 1)))) %ROOTS 0))
(def %RESULT (%zeroed (* (%int+ 4 %RTCOUNT) %word-size)))
(%psw %RESULT 0 %OBJ-CAP-WORDS)
(%psw %RESULT %word-size %BLOB-CAP)
(def %N ((prim-ref (lit image) (lit write!)) %CURSOR %TRACE %obj-p %blob-p %name %ROOT-VALUES %RESULT))
(def %OBJW (%rw %RESULT (* 1 %word-size)))
(def %BLOBN (%rw %RESULT (* 2 %word-size)))
(def %root-index (fn (_ i) (%rw %RESULT (* (%int+ 4 i) %word-size))))
; A root's reference: its index, or -- a static, a spine node -- its external.
(def %root-ref
  (fn (_ i v)
    ((fn (_ k) (if (eq? k 0) (if (null? v) 0 (%int- 0 (%extern-ref (%addr v)))) k))
     (%root-index i))))
(%between)

; --- roots table (spec 3.5) ----------------------------------------------------------
(def %rt-p (%zeroed (* 8 4096)))
(def %RTWORDS
  ((fn (self l i cur)
     (if (null? l) cur
       (self (rest l) (%int+ i 1)
         (%put %rt-p (%put-name %rt-p cur (symbol->str (first (first l))))
               (%root-ref i (%root-value (first l)))))))
   %ROOTS 0 0))

; --- header, write (spec 3.1) -------------------------------------------------------
(def %RELEASE-OFF %BLOBN)
(set! %BLOBN ((fn (_ n) (do (%psw %blob-p %BLOBN n) (%pcopy! (%i->p (%int+ (Ptr ->int %blob-p) (%int+ %BLOBN %word-size))) (%i->p (%word-at (%o->p x-release) 0)) n) (%int+ %BLOBN (%int+ %word-size (%int+ n 1))))) (%blen x-release)))
(def %hdr-p (%zeroed 256))
(def %HDRN
  (do (%psw %hdr-p 0 1196247384)
      (%put %hdr-p 1 1)
      (%put %hdr-p 2 %word-size)
      (%put %hdr-p 3 1)
      (%put %hdr-p 4 %N)
      (%put %hdr-p 5 %OBJW)
      (%put %hdr-p 6 %BLOBN)
      (%put %hdr-p 7 %XCOUNT)
      (%put %hdr-p 8 %XCUR)
      (%put %hdr-p 9 %RTCOUNT)
      (%put %hdr-p 10 %RTWORDS)
      (%put %hdr-p 11 (first (%at %RAW (%row-steps %base-paths (lit obj-meta-extra)))))
      (%put %hdr-p 12 %RELEASE-OFF)
      (* 13 %word-size)))
((fn (_ fd)
   (do (%swrite fd %hdr-p %HDRN)
       (%swrite fd %x-p (%int* %XCUR %word-size))
       (%swrite fd %rt-p (%int* %RTWORDS %word-size))
       (%swrite fd %obj-p (%int* %OBJW %word-size))
       (%swrite fd %blob-p %BLOBN)
       (Sys close fd)))
 (Sys open-write %IMG-OUT))
(display "objects: ") (write %N)
(display "  externals: ") (write %XCOUNT) (display "  roots: ") (write %RTCOUNT)
(display "  unnameable: ") (write %SENT) (newline)
((fn (self l) (if (null? l) () (do (display "  ") (write (first l)) (newline) (self (rest l))))) %SENT-LOG)
(if (eq? %SENT 0) ()
  (do (display "  legend: satom-tw=") (write %reflect-satom-tw) (display " spair-tw=") (write %reflect-spair-tw)
      (display " true=") (write (%addr (first (%at %RAW (%row-steps %base-paths (lit true))))))
      (display " false=") (write (%addr (first (%at %RAW (%row-steps %base-paths (lit false))))))
      (display " units-pair=") (write (%addr (first (%type-units-cell (Type by-atom ((prim-ref (lit type) (lit make)) "%probe" ()))))))
      (display " token-eof=") (write (if (null? %TOKEN-EOF) 0 (%addr %TOKEN-EOF)))
      (newline)))
(display "image: ") (write (%int+ %HDRN (%int+ (%int* (%int+ %XCUR (%int+ %RTWORDS %OBJW)) %word-size) %BLOBN)))
(display " bytes -> ") (display %IMG-OUT) (newline)
(%clear! %TRACE)
