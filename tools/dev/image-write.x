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

(import x/tool/image/walk image-walk image-walk-collect! image-walk-collect? image-over-units image-word-at image-traced? image-trace-flag image-collect image-heap-count image-mark! image-clear! image-shape-static? image-type-kind image-type-heap)
(import x/tool/image/walk image-heap-off image-flags-off image-type-off image-obj->ptr image-ptr->obj image-int->ptr image-ref-word image-set-word! image-ptr->str image-byte-len image-int+ image-int- image-int* image-int& image-int>> image-int<)
(import x/tool/image/name image-name-map image-name-map-add image-name-map-get image-fnptr image-dl-name image-dl-handle image-foreign-bare image-foreign-dlsym image-foreign-typecall image-foreign-dlopen)
(include "engine/tools/contract/base-paths.x")

(def %IMG-LIB (guard (_ ()) (eval (lit %IMG-LIB))))
(def %OBJ-CAP-WORDS 6000000)
(def %IMG-OUT (guard (_ "/tmp/x.ximg") (eval (lit %IMG-OUT))))

(def %alloc  (prim-ref (lit ptr) (lit alloc)))
(def %swrite (prim-ref (lit sys) (lit write)))
(def %pcopy! (prim-ref (lit ptr) (lit copy!)))
(def %pfill! (prim-ref (lit ptr) (lit fill!)))
(def %zeroed (fn (_ n) ((fn (_ p) (do (%pfill! p 0 n) p)) (%alloc n))))
(def %put (fn (_ p i w) (do (image-set-word! p (image-int* i %word-size) w) (image-int+ i 1))))
(def %addr (fn (_ o) (Ptr ->int (image-obj->ptr o))))

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
                          (list (lit lit) (image-int->ptr (image-word-at (image-obj->ptr fnobj) 0)))))))
(def %child-str!
  (fn (_ nm s)
    (%child-def! nm (list (prim-ref (lit str) (lit append)) "" (list (lit lit) s)))))
(if (null? %IMG-LIB) ()
  (do (%child-prim! (lit include) %raw-include)
      (guard (_ ()) (%child-prim! (lit syscall) (eval (lit syscall))))
      ; x-cli files catalog entries into the root base's catalog too: since
      ; x-engine-c 0.2.14, (ffi dlopen) and (ffi dlsym) are x-cli's, and a
      ; child has neither.  Without them the child's prim-ref answers nil, and
      ; err.x's errno lookup, which calls dlsym on dlopen's answer, ends in a
      ; (ptr call) through whatever the call on nil returned.  Each entry is
      ; filed in the child's own catalog, from the function pointer the root's
      ; primitive holds, under names the child interns; the image's foreign
      ; table then names it ffi/NAME, and the loader takes the loading
      ; process's own.  Symbols are per base, so the child's catalog is
      ; searched by name.
      ((fn (_ named add!)
         (do (add! named "ffi" "dlopen" (prim-ref (lit ffi) (lit dlopen)))
             (add! named "ffi" "dlsym" (prim-ref (lit ffi) (lit dlsym)))))
       (fn (self l name)
         (if (null? l) ()
           (if (str=? (symbol->str (first (first l))) name) (first l) (self (rest l) name))))
       (fn (_ named ns m fnobj)
         ((fn (_ cell put! sym)
            ((fn (_ dom)
               (if (if (null? fnobj) #t (not (null? (named (if (null? dom) () (rest dom)) m)))) ()
                 ((fn (_ entry)
                    (if (null? dom)
                      (put! cell 0
                        (%B eval (list (lit pair)
                                       (list (lit pair) (sym ns) (list (lit pair) (list (lit lit) entry) (list (lit lit) ())))
                                       (list (lit lit) (first cell)))))
                      (put! dom 1
                        (%B eval (list (lit pair) (list (lit lit) entry) (list (lit lit) (rest dom)))))))
                  (%B eval (list (lit pair) (sym m)
                                 (list (prim-ref (lit obj) (lit make-callable))
                                       (list (lit lit) (image-int->ptr (image-word-at (image-obj->ptr fnobj) 0)))))))))
             (named (first cell) ns)))
          (%B cell (lit prims))
          (prim-ref (lit obj) (lit set!))
          (fn (_ name) (list (prim-ref (lit str) (lit ->sym)) name)))))
      (%child-str! (lit x-machine) x-machine)
      (%child-str! (lit x-version) x-version)
      (%child-str! (lit x-release) x-release)
      ; The child is a BATCH: a dialect entry ends in (unless %batch? (do
      ; (%banner) (repl))), and repl/banner.x derives %batch? from args
      ; holding "--batch".  Without it the child's REPL reads this writer's
      ; own stdin and the image is never written.  One string, the child's.
      (%child-def! (lit args)
        (list (lit pair) (list (prim-ref (lit str) (lit append)) "" "--batch") (list (lit lit) ())))
      ; The child is told it is being imaged.  An entry that reads stdin at
      ; load -- logo's and ash's dispatch on %batch? -- would otherwise read
      ; this script, since the engine's program and the child's stdin are one
      ; fd; a lang that binds nothing while %image-writing is bound loads and
      ; stops.  The marker before the include is how image-build.sh tells an
      ; entry that ended the writer from a writer that never ran.
      (%child-def! (lit %image-writing) (list (lit lit) #t))
      (display "image: writer begins") (newline)
      ; The path too: `include` records it in the child's file registry.
      (%B eval (list (lit include) (list (prim-ref (lit str) (lit append)) "" %IMG-LIB)))
      ;  And the mark is taken back.  It is a global in the child, so the
      ; walk below would carry it into the image, and every boot from that
      ; image would read "I am being imaged" and skip the dispatch the entry
      ; skipped here -- so a lang that images would never start.
      ; Cleared rather than unbound: the entry reads it through a guard
      ; (there is no bound? predicate), and a bound nil is what a normal
      ; boot's guard answers anyway.
      (%child-def! (lit %image-writing) (list (lit lit) ()))
      ; A transient is imaged as nil, or put down.  reflect.x's
      ; %image-transients holds the globals whose value belongs to this
      ; process alone -- float.x's libm handle -- and a recache hook of the
      ; same module re-derives each once the loader has installed the image;
      ; an entry that is a THUNK rather than a symbol is run instead --
      ; tower-compiled.x swaps its interpreted analysers back in for the
      ; compiled ones, and its recache hook compiles them anew.  Cleared and
      ; run here, inside the child, so the walk below never meets the word.
      ; One form, walked by
      ; the child over its own list: a version that fetched the list out
      ; and evaluated a set! per name put child objects in this base's
      ; hands between two collects, and the x-base writer died of it.
      ;  The walk runs here, over the child's list, and names nothing in the
      ; child.  A form evaluated in the child resolves its names in the child,
      ; and a lang is free to have rebound them: r5rs's `fn` is not x-core's,
      ; so a walk sent over as a form dies there on an unbound name.  Each
      ; entry is handled from this base instead -- a symbol is cleared with the
      ; set! primitive object (engine-bound, the same object in every base), a
      ; thunk is applied as an object -- so nothing the child could rename is
      ; in the form.  Child objects are in this base's hands for the length of
      ; the loop, which is safe exactly as long as nothing here collects: no
      ; %between until the loop is done.
      ;  A raise inside the child is a refusal, never swallowed.  Answering nil
      ; and carrying on to the collect below leaves the child's root chain
      ; holding the nodes the unwound C frames pushed, and the collect then
      ; walks freed stack.
      (guard (e (do (display "image: clearing a transient raised in the child: ")
                    (display (guard (_ e) (Err message e))) (newline) (Sys exit 3)))
        ((fn (self l)
           (if (null? l) ()
             (do ((fn (_ t)
                    (if (symbol? t)
                        (%B eval (list (eval (lit set!)) t ()))
                        (%B eval (list t))))
                  (first l))
                 (self (rest l)))))
         (%B eval (lit %image-transients))))
      ; The child has never collected.  Its own collect, evaluated inside it.
      (%B eval (list image-collect))
      ; What the writer can hold is stated rather than discovered at run time.
      ; Its object table is a fixed allocation (%OBJ-CAP-WORDS below), and a
      ; record is three words plus the units, so the live count the child's
      ; collect leaves bounds what fits.  Without the bound, a heap past it --
      ; python's runtime is tens of millions of allocations and a few million
      ; live -- walks until the process runs out of memory.
      ((fn (_ live)
         (if (image-int< live 1000000) ()
           (do (display "image: refused -- ") (write live)
               (display " live objects in the child; this writer holds a million")
               (display " (raise %OBJ-CAP-WORDS in tools/dev/image-write.x to widen it)") (newline)
               (Sys exit 3))))
       (%B eval (list image-heap-count)))
      ; And this base may not collect while a walk holds a cursor into the
      ; child (x/tool/image/walk).  Walks run with the periodic collect off.
      (image-walk-collect! #f)))
;  The child is evaluated in twice more, both HERE and never after: the
; token-eof static, looked up by name, and the walk cursor -- a pair that is
; the head of the child's chain.  Every snapshot below (spine set, mark,
; write) is of the child as it is now.  An evaluation in the child after
; this point can allocate, and a collect can then free a process leaf the
; spine set recorded and hand its address to a language object.
(def %TOKEN-EOF (guard (_ ()) (%B eval (lit %token-eof))))
(def %CURSOR (if (null? %IMG-LIB) (pair 1 2) (%B eval (lit (pair 1 2)))))
(def %cursor (fn (_) %CURSOR))
(def %between (fn (_) (if (image-walk-collect?) () (image-collect))))

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
(def %ht-mask (image-int- %HT-SIZE 1))
(def %ht-new (fn (_) (%zeroed (* 16 %HT-SIZE))))
(def %ht-idx (fn (_ a) (image-int& (image-int>> a 4) %ht-mask)))
(def %ht-put
  (fn (self t a v i)
    (if (eq? (image-ref-word t (image-int* (image-int* i 2) %word-size)) 0)
        (do (image-set-word! t (image-int* (image-int* i 2) %word-size) a)
            (image-set-word! t (image-int* (image-int+ (image-int* i 2) 1) %word-size) v))
      (if (eq? (image-ref-word t (image-int* (image-int* i 2) %word-size)) a)
          (image-set-word! t (image-int* (image-int+ (image-int* i 2) 1) %word-size) v)
          (self t a v (image-int& (image-int+ i 1) %ht-mask))))))
(def %ht-get
  (fn (self t a i)
    (if (eq? (image-ref-word t (image-int* (image-int* i 2) %word-size)) 0) 0
      (if (eq? (image-ref-word t (image-int* (image-int* i 2) %word-size)) a)
          (image-ref-word t (image-int* (image-int+ (image-int* i 2) 1) %word-size))
          (self t a (image-int& (image-int+ i 1) %ht-mask))))))
(def %ht-add! (fn (_ t a v) (%ht-put t a v (%ht-idx a))))
(def %ht-find (fn (_ t a) (%ht-get t a (%ht-idx a))))

(def %SPINE (%ht-new))          ; address -> 1
(def %SPINE-LIST ())            ; every address the walk put in, for the passes below
(def %ROOT-ADDRS ((fn (self l acc) (if (null? l) acc (self (rest l) ((fn (_ v) (if (null? v) acc (pair (%addr v) acc))) (%root-value (first l)))))) %ROOTS ()))
(def %root-addr? (fn (self l a) (if (null? l) #f (if (eq? (first l) a) #t (self (rest l) a)))))
(def %spair-p? (fn (_ p) (eq? (image-ref-word p image-type-off) %reflect-spair-tw)))
;  Only ON-CHAIN nodes go in the set: an off-chain leaf under the spine (the
; sigint flag, #t, #f) is an engine static, and statics are named by role or
; type row, never as spine.
(def %spine-walk
  (fn (self p)
    (if (eq? p 0) ()
      (if (%root-addr? %ROOT-ADDRS p) ()
        (if (eq? (image-ref-word p image-heap-off) 0) ()
          (do (%ht-add! %SPINE p 1)
              (set! %SPINE-LIST (pair p %SPINE-LIST))
              (if (%spair-p? p)
                  (do (self (image-word-at p 0)) (self (image-word-at p 1)))
                  ())))))))
(%spine-walk (image-word-at (image-obj->ptr %RAW) 0))
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
                  (if (image-shape-static? u) (%static! (%addr u) %X-STATIC "units-pair") (self (rest al)))))
      (Type cell (rest (first al)) (lit type-units)))))
 (first (%at %RAW (%row-steps %base-paths (lit type-alist)))))
; A fresh base's type structs hold the engine's static handlers, name atoms
; and default units at known rows; every off-chain node found there is named
; "TYPE row".
(def %type-rows ((fn (self rows acc) (if (null? rows) acc (self (rest rows) (if (eq? (first (rest (first rows))) (lit type)) (pair (first rows) acc) acc)))) %base-paths ()))
(def %off-chain? (fn (_ o) (eq? (image-ref-word (image-obj->ptr o) image-heap-off) 0)))
(def %tname (fn (_ st) (image-ptr->str (image-int->ptr (image-word-at (image-obj->ptr (%at st (%row-steps %base-paths (lit type-name)))) 0)))))
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

; --- function pointers (spec 3.4 kinds 1-5), the naming x/tool/image/name does ----
(def %MAP (image-name-map %B))

; --- mark (spec 4.1) ------------------------------------------------------------
(%between)
((fn (self l) (if (null? l) () (do ((fn (_ v) (if (null? v) () (image-mark! v image-trace-flag))) (%root-value (first l))) (self (rest l))))) %ROOTS)
;  A leaf under a cell that a root reaches is the library's, not the base's:
; module.x hangs its include-once list off the false cell.  The cells stay
; spine whatever reaches them; their traced non-cell leaves come out, as
; the hook and root list elements did above.
(def %unhash-traced-leaves!
  (fn (self l)
    (if (null? l) ()
      (do ((fn (_ a)
             (if (eq? (%ht-find %SPINE a) 1)
                 (if (%spair-p? a) () (if (image-traced? a) (%ht-add! %SPINE a 0) ()))
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
                 (if (image-traced? a)
                     (image-set-word! a image-flags-off (image-int& (image-ref-word a image-flags-off) (image-int- (image-int- 0 1) image-trace-flag)))
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
(def %words-for (fn (_ n) (image-int+ 1 (image-int>> (image-int+ n 1) 3))))
(def %put-name
  (fn (_ b cur nm)
    ((fn (_ n)
       (do (image-set-word! b (image-int* cur %word-size) n)
           (%pcopy! (image-int->ptr (image-int+ (Ptr ->int b) (image-int* (image-int+ cur 1) %word-size))) (image-int->ptr (image-word-at (image-obj->ptr nm) 0)) n)
           (image-int+ cur (image-int+ 1 (%words-for n)))))
     (image-byte-len nm))))
(def %x-new!
  (fn (_ a kind nm)
    (do (set! %XCOUNT (image-int+ %XCOUNT 1))
        (%ht-add! %XIDX a %XCOUNT)
        (set! %XCUR (%put-name %x-p (%put %x-p %XCUR kind) nm))
        %XCOUNT)))
(def %x-index
  (fn (_ a kind nm) ((fn (_ i) (if (eq? i 0) (%x-new! a kind nm) i)) (%ht-find %XIDX a))))
(def %SENT 0)                    ; unnameable references, counted and described
(def %SENT-LOG ())               ; ((holder address . description) ...)
(def %CUR ())                    ; (type word, unit kind, address) of the object whose word is being named
(def %describe
  (fn (_ w)
    ((fn (_ %CUR-TW %CUR-KIND)
    (if (eq? %CUR-KIND 3) (list (%ty-name %CUR-TW 0) (lit foreign-unnamed) w)
    ;  A reference word the writer could not place is not read.  Reading its
    ; heap link, flags and type word to classify the miss is a read at an
    ; integer whenever a lang's object holds one in a declared reference unit
    ; (logo, python), which crashes in place of a census.  A spine node is
    ; known and named by its row; anything else is reported by the holder's
    ; type and the word, which is what a refusal needs, and the holder chase
    ; (%IMG-WHO) walks only real objects.
    (list (%ty-name %CUR-TW 0)
          (if (eq? (%ht-find %SPINE w) 1) (lit spine-unnamed) (lit reference-unplaced))
          w
          (if (eq? (%ht-find %SPINE w) 1) ((fn (_ nm) (if (eq? nm 0) "no-row" (symbol->str (image-ptr->obj (image-int->ptr nm))))) (%ht-find %SPINE-NAMES w)) "-"))))
     (first %CUR) (first (rest %CUR)))))
(def %sentinel!
  (fn (_ w) (do (set! %SENT (image-int+ %SENT 1)) (set! %SENT-LOG (pair (pair (first (rest (rest %CUR))) (%describe w)) %SENT-LOG)) 0)))
; A reference: an imaged object's index; a spine node by row; a static by
; role or type row; else the sentinel (past the table, restores nil).
(def %extern-ref
  (fn (_ w)
    (if (eq? (%ht-find %SPINE w) 1)
        ((fn (_ nm) (if (eq? nm 0) (%sentinel! w) (%x-index w %X-BASE-ROW (symbol->str (image-ptr->obj (image-int->ptr nm))))))
         (%ht-find %SPINE-NAMES w))
      ((fn (_ e) (if (eq? e 0) (%sentinel! w) (%x-index w (first (image-ptr->obj (image-int->ptr e))) (rest (image-ptr->obj (image-int->ptr e))))))
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
      ((fn (_ h) (if (null? h) 0 (image-word-at (image-obj->ptr h) 0)))
       (%at (image-ptr->obj (image-int->ptr tw)) (%row-steps %base-paths (lit type-call)))))))
(def %cp-word
  (fn (_ w p)
    ((fn (_ tw)
       (if (if (eq? (image-type-kind tw) image-type-heap) (eq? w (%call-word-of tw)) #f)
           (%x-index w image-foreign-typecall (Type name (image-ptr->obj p)))
           ()))
     (image-ref-word p image-type-off))))
; A function pointer: type-call, catalog, bare global, dlopen handle, dlsym.
(def %fn-word
  (fn (_ w p)
    ((fn (_ k)
       (if (null? k)
           ((fn (_ e)
              (if (null? e)
                  ((fn (_ nm) (if (null? nm) (%sentinel! w) (%x-index w image-foreign-dlsym nm))) (image-dl-name w))
                (%x-index w (first e) (rest e))))
            (image-name-map-get %MAP w))
         k))
     (%cp-word w p))))
(set! %MAP (image-name-map-add %MAP (Ptr ->int image-dl-handle) image-foreign-dlopen ""))
; The bare primitives the library binds its own definitions over: module.x's
; include and x/core/fn's apply.  In the imaged base their bare names reach the
; library's definitions, so each is named by the function it holds.  include
; comes from module.x's %raw-include, since x-cli binds it in the root base
; only; apply is asked of a fresh base, where the engine bound it.  The loader
; finds each by its bare name in its own base.
(set! %MAP (image-name-map-add %MAP (image-fnptr %raw-include) image-foreign-bare "include"))
(set! %MAP (image-name-map-add %MAP (image-fnptr ((Base make) eval (lit apply))) image-foreign-bare "apply"))
(guard (_ ()) (set! %MAP (image-name-map-add %MAP (image-fnptr (eval (lit syscall))) image-foreign-bare "syscall")))
(%between)

; --- the object table and the blob (spec 3.6, 3.7) --------------------------------
(def %OBJ-CAP (* %word-size %OBJ-CAP-WORDS))
(def %BLOB-CAP (* %word-size 400000))
(def %obj-p (%alloc %OBJ-CAP))
(def %blob-p (%zeroed %BLOB-CAP))
(def %ty-name
  (fn (_ tw p)
    (if (eq? tw 0) "NIL"
      (if (eq? tw %reflect-satom-tw) "ATOM"
        (if (eq? tw %reflect-spair-tw) "SPAIR"
          (guard (_ "?") (%tname (image-ptr->obj (image-int->ptr tw)))))))))
;  The object table and the blob are (image write!)'s: the walk, the index
; and every record in C; every NAME from here.  It asks once per distinct
; word it cannot place -- a reference to an object outside the image, or a
; foreign address -- and says which object it met it in.
(def %name
  (fn (_ w kind o)
    ((fn (_ p)
       (do (set! %CUR (list (image-ref-word p image-type-off) kind (Ptr ->int p)))
           (if (eq? kind 3) (%fn-word w p) (%extern-ref w))))
     (image-obj->ptr o))))
; The roots' values, in %ROOTS order; the write answers with their indices.
(def %ROOT-VALUES ((fn (self l) (if (null? l) () (pair (%root-value (first l)) (self (rest l))))) %ROOTS))
(def %RTCOUNT ((fn (self l n) (if (null? l) n (self (rest l) (image-int+ n 1)))) %ROOTS 0))
(def %RESULT (%zeroed (* (image-int+ 4 %RTCOUNT) %word-size)))
(image-set-word! %RESULT 0 %OBJ-CAP-WORDS)
(image-set-word! %RESULT %word-size %BLOB-CAP)
(def %N ((prim-ref (lit image) (lit write!)) %CURSOR image-trace-flag %obj-p %blob-p %name %ROOT-VALUES %RESULT))
(def %OBJW (image-ref-word %RESULT (* 1 %word-size)))
(def %BLOBN (image-ref-word %RESULT (* 2 %word-size)))
(def %root-index (fn (_ i) (image-ref-word %RESULT (* (image-int+ 4 i) %word-size))))
; A root's reference: its index, or -- a static, a spine node -- its external.
(def %root-ref
  (fn (_ i v)
    ((fn (_ k) (if (eq? k 0) (if (null? v) 0 (image-int- 0 (%extern-ref (%addr v)))) k))
     (%root-index i))))
(%between)

; --- roots table (spec 3.5) ----------------------------------------------------------
(def %rt-p (%zeroed (* 8 4096)))
(def %RTWORDS
  ((fn (self l i cur)
     (if (null? l) cur
       (self (rest l) (image-int+ i 1)
         (%put %rt-p (%put-name %rt-p cur (symbol->str (first (first l))))
               (%root-ref i (%root-value (first l)))))))
   %ROOTS 0 0))

; --- header, write (spec 3.1) -------------------------------------------------------
(def %RELEASE-OFF %BLOBN)
(set! %BLOBN ((fn (_ n) (do (image-set-word! %blob-p %BLOBN n) (%pcopy! (image-int->ptr (image-int+ (Ptr ->int %blob-p) (image-int+ %BLOBN %word-size))) (image-int->ptr (image-word-at (image-obj->ptr x-release) 0)) n) (image-int+ %BLOBN (image-int+ %word-size (image-int+ n 1))))) (image-byte-len x-release)))
(def %hdr-p (%zeroed 256))
(def %HDRN
  (do (image-set-word! %hdr-p 0 1196247384)
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
       (%swrite fd %x-p (image-int* %XCUR %word-size))
       (%swrite fd %rt-p (image-int* %RTWORDS %word-size))
       (%swrite fd %obj-p (image-int* %OBJW %word-size))
       (%swrite fd %blob-p %BLOBN)
       (Sys close fd)))
 (Sys open-write %IMG-OUT))
(display "objects: ") (write %N)
(display "  externals: ") (write %XCOUNT) (display "  roots: ") (write %RTCOUNT)
(display "  unnameable: ") (write %SENT) (newline)
((fn (self l) (if (null? l) () (do (display "  ") (write (rest (first l))) (newline) (self (rest l))))) %SENT-LOG)
; --- who holds an unnameable.  For each object that carried a word the writer
; could not name, the objects that reference it, one path up to a named spine
; node, naming the global where a level lands on a (symbol . value) pair --
; one pass over the traced chain per level.  The census above says what could
; not be named; this says why it was reached.  Only when asked (%IMG-WHO):
; forty passes over a dialect-sized heap take minutes each.
(def %holders-of
  (fn (_ targets)
    ((fn (_ in? first-name spine-name)
       (first (image-walk %CURSOR
         (fn (_ p acc)
           (image-over-units p
             (fn (_ kind w acc2)
               (if (in? w targets)
                   (do (display "    ") (write (list (%ty-name (image-ref-word p image-type-off) p) (Ptr ->int p) (lit holds) w (first-name p) (spine-name p))) (newline)
                       (pair (Ptr ->int p) acc2))
                 acc2))
             acc))
         ())))
     (fn (self w l) (if (null? l) #f (if (eq? w (first l)) #t (self w (rest l)))))
     ;  A (symbol . value) pair names a global: the symbol's bytes are its word 0.
     (fn (_ p) (guard (_ "") ((fn (_ q) (if (eq? q 0) "" (if (str=? (%ty-name (image-ref-word (image-int->ptr q) image-type-off) (image-int->ptr q)) "SYMBOL") (image-ptr->str (image-int->ptr (image-word-at (image-int->ptr q) 0))) ""))) (image-word-at p 0))))
     (fn (_ p) ((fn (_ nm) (if (eq? nm 0) "" (symbol->str (image-ptr->obj (image-int->ptr nm))))) (%ht-find %SPINE-NAMES (Ptr ->int p)))))))
;  %IMG-WHO bound (to anything) asks for it: image-build.sh binds it under
; X_IMG_WHO=1.  Read here rather than def'd, on the file's %-global budget.
(if (if (eq? %SENT 0) #t (guard (_ #t) (do (eval (lit %IMG-WHO)) #f))) ()
  (do (display "  holders, nearest first (one path, up to a spine node):") (newline)
      ((fn (self ts depth)
         (if (eq? depth 0) ()
           (if (null? ts) ()
             (do (display "   level ") (write (image-int- 41 depth)) (newline)
                 ((fn (_ hs)
                    (do (image-collect)
                        (if (null? hs) ()
                          (if (eq? (%ht-find %SPINE (first hs)) 1) ()
                            (self (list (first hs)) (image-int- depth 1))))))
                  (%holders-of ts))))))
       (list (first (first %SENT-LOG))) 40)))
(if (eq? %SENT 0) ()
  (do (display "  legend: satom-tw=") (write %reflect-satom-tw) (display " spair-tw=") (write %reflect-spair-tw)
      (display " true=") (write (%addr (first (%at %RAW (%row-steps %base-paths (lit true))))))
      (display " false=") (write (%addr (first (%at %RAW (%row-steps %base-paths (lit false))))))
      (display " units-pair=") (write (%addr (Type cell (Type by-atom ((prim-ref (lit type) (lit make)) "%probe" ())) (lit type-units))))
      (display " token-eof=") (write (if (null? %TOKEN-EOF) 0 (%addr %TOKEN-EOF)))
      (newline)))
(display "image: ") (write (image-int+ %HDRN (image-int+ (image-int* (image-int+ %XCUR (image-int+ %RTWORDS %OBJW)) %word-size) %BLOBN)))
(display " bytes -> ") (display %IMG-OUT) (newline)
(image-clear! image-trace-flag)
