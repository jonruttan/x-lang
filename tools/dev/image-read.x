; image-read.x -- read a state image back and rebuild its object graph.
;
;   sh x.sh -q -f tools/dev/image-write.x     # write /tmp/x-core.ximg
;   X_BIN=<engine-with-image-rebuild> sh x.sh -q -f tools/dev/image-read.x
;
; NEEDS AN ENGINE CARRYING (image rebuild!), which the pinned one does not yet.
;
; THE SPLIT THIS DEMONSTRATES.  X resolves the tables -- verifying the header,
; matching each file type NAME to a live type, reacquiring foreign addresses by
; name, walking base paths for the statics -- which is per-entry work over a few
; hundred items.  One primitive does the only per-object work there is: two
; passes over ~86k records, allocate then patch.
;
; That division is not stylistic.  The same two passes written in x take ~30s
; and allocate garbage nothing collects, because collection is manual and a
; per-object interpreted loop has nowhere safe to collect; it exhausted a
; machine's memory.  Through the primitive the whole rebuild is ~0.5s on top of
; helium's boot.
;
; NOTHING ABOUT SHAPE COMES OUT OF THE FILE.  Unit counts and kinds are the
; LIVE type's, through (Type set-shape!), which is why there is no extent table
; and no mask column.  The reader proves it: it walks the object table with no
; length field anywhere and lands exactly on the declared word count.
;
; The three NON-HEAP tags are the exception, and the only shape the reader
; states itself: a structural PAIR is two references, a static ATOM one word,
; nil-typed one word.  image-walk.x's %over-tw says the same when writing.
; They have no live type to ask, so their counts go to the primitive in a
; table -- fifteen words, not per-object.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(include "tools/dev/image-walk.x")
(def %lib0 (Ffi dlopen () 1))
; The engine's own read and allocator, not libc's.  dlopen stays only for
; reacquiring foreign ADDRESSES by name, which is the dynamic linker's job and
; nothing else's.
(def %sread (prim-ref (lit sys) (lit read)))
(def %alloc (prim-ref (lit ptr) (lit alloc)))
(def %i2p (prim-ref (lit int) (lit ->ptr)))
(def %mk (prim-ref (lit obj) (lit make)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %psw (prim-ref (lit ptr) (lit set-word!)))
(def %i+ (prim-ref (lit int) (lit +)))  (def %i* (prim-ref (lit int) (lit *)))
(def %i- (prim-ref (lit int) (lit -)))  (def %lt (prim-ref (lit int) (lit <)))
(def W %word-size)
(def buf (%alloc (* 8 1000000)))
(def fd (Sys open-read "/tmp/x-core.ximg"))
(def got (%sread fd buf (* 8 1000000)))
(Sys close fd)
(def w (fn (_ i) (%rw buf (%i* i W))))
(def at (fn (_ i) (%i+ (Ptr ->int buf) (%i* i W))))
(def N (w 4)) (def OBJW (w 5)) (def ROOTENV (w 7)) (def ROOTG (w 12))
(def FCOUNT (w 8)) (def FWORDS (w 9)) (def TCOUNT (w 10)) (def TWORDS (w 11))
(def SCOUNT (w 13)) (def SWORDS (w 14))
(def TSTART 15)
(def SSTART (%i+ TSTART TWORDS))
(def FSTART (%i+ SSTART SWORDS))
(def OSTART (%i+ FSTART FWORDS))
(def BSTART (%i+ OSTART OBJW))
(def PT ((prim-ref (lit type) (lit of)) (pair 1 2)))
(def mkn (fn (_ n) (%mk PT (if (%lt n 1) 1 n))))

; The base the image is installed INTO.  It has to exist before the statics are
; resolved: a static reference is a walk from a base, and the walk has to start
; at the base the rebuilt graph will live in, not at the one doing the reading.
; Resolving them against the reader's own base would wire the loaded env to
; this process's spine.
(def B (Base make))
(def RAWB (Base raw-of B))

; --- live shapes by name ---------------------------------------------------
(def SHAPES ())   ; (name . (units-cell . struct))
(def add-shape
  (fn (self l)
    (if (null? l) ()
      (do (set! SHAPES (pair (pair ((Type wrap (rest (first l))) name)
                                   (pair (first (%type-units-cell (rest (first l))))
                                         (rest (first l)))) SHAPES))
          (self (rest l))))))
(add-shape (first %reflect-type-alist-cell))
(def lookup (fn (self l nm) (if (null? l) () (if (str=? (first (first l)) nm) (rest (first l)) (self (rest l) nm)))))
(def tagged (fn (_ nm) (if (str=? nm "PAIR") (pair 2 0) (if (str=? nm "ATOM") (pair 1 1) (if (str=? nm "NIL") (pair 1 1) ())))))
(def TN (mkn (%i+ TCOUNT 1)))  (def TS (mkn (%i+ TCOUNT 1)))  (def TT (mkn (%i+ TCOUNT 1)))
(def TCNT (mkn (%i+ TCOUNT 1)))
(def rdtypes
  (fn (self i pos)
    (if (%lt TCOUNT i) ()
      ((fn (_ nm) (do (%oset! TN i nm)
                      (%oset! TS i ((fn (_ e) (if (null? e) () (first e))) (lookup SHAPES nm)))
                      (%oset! TT i ((fn (_ e) (if (null? e) () (rest e))) (lookup SHAPES nm)))
                      (%oset! TCNT i ((fn (_ t) (if (null? t) -1 (first t))) (tagged nm)))
                      (self (%i+ i 1) (%i+ pos (%i+ 2 (%shr (w pos) 3))))))
       (Ptr ->str (%i2p (at (%i+ pos 1))))))))
(rdtypes 1 TSTART)
; Which index the file calls SYMBOL: the primitive interns those by name
; instead of rebuilding them, because the evaluator matches symbols by identity.
(def SYMTI
  ((fn (self i) (if (%lt TCOUNT i) -1
                  (if (str=? (%oref TN i) "SYMBOL") i (self (%i+ i 1))))) 1))
(def units-of
  (fn (_ ti pos)
    ((fn (_ t) (if (null? t) (%uheap ti pos) (first t))) (tagged (%oref TN ti)))))
(def %uheap
  (fn (_ ti pos)
    ((fn (_ u) (if (null? u) 0 ((fn (_ c) (if (%lt c 0) (%i+ (w (%i+ pos 2)) (%i- 0 c)) c)) (%sh-count u))))
     (%oref TS ti))))
(def kind-of
  (fn (_ ti j)
    ((fn (_ t) (if (null? t) (%kheap ti j) (rest t))) (tagged (%oref TN ti)))))
(def %kheap
  (fn (_ ti j)
    ((fn (_ u) (if (null? u) 1 (%kind (%sh-mask u) j (%sh-desc (%sh-count u))))) (%oref TS ti))))

; --- statics: walk the declared steps from THIS base ------------------------
(def ST (mkn (%i+ SCOUNT 1)))
(def stepwalk
  (fn (self v n pos)
    (if (eq? n 0) v (self (if (eq? (w pos) 0) (first v) (rest v)) (%i- n 1) (%i+ pos 1)))))
; Two forms.  A base path is steps from the base.  A TYPE path is a type NAME
; plus steps from that type's struct -- portable where a positional path is
; not, because a loader's type registry differs from the writer's.
; env-alist is a CELL: its value lives in the cell's first slot, so installing
; is a write into the cell.  env-global-tree is a SLOT: the value IS what the
; path reaches, so installing means writing into its PARENT, at whichever half
; the last step names.  base-layout.x is what says which is which.
(include "engine/tools/contract/base-paths.x")
(def %row-steps
  (fn (self rows nm)
    (if (null? rows) ()
      (if (eq? (first (first rows)) nm) (rest (rest (first rows)))
        (self (rest rows) nm)))))
(def %but-last
  (fn (self l) (if (null? (rest l)) () (pair (first l) (self (rest l))))))
(def %last (fn (self l) (if (null? (rest l)) (first l) (self (rest l)))))
(def %walk-steps
  (fn (self v steps)
    (if (null? steps) v (self (if (eq? (first steps) (lit f)) (first v) (rest v)) (rest steps)))))
(def %install-slot!
  (fn (_ nm v)
    ((fn (_ steps)
       (%oset! (%walk-steps RAWB (%but-last steps))
               (if (eq? (%last steps) (lit f)) 0 1) v))
     (%row-steps %base-paths nm))))

(def tstruct
  (fn (_ nm) ((fn (_ e) (if (null? e) () (rest e))) (lookup SHAPES nm))))
(def rdstatics
  (fn (self i pos)
    (if (%lt SCOUNT i) ()
      (if (eq? (w pos) 1) (%st-type self i pos) (%st-path self i pos)))))
(def %st-path
  (fn (_ k i pos)
    (do (%oset! ST i (stepwalk RAWB (w (%i+ pos 1)) (%i+ pos 2)))
        (k (%i+ i 1) (%i+ pos (%i+ 2 (w (%i+ pos 1))))))))
(def %st-type
  (fn (_ k i pos)
    ((fn (_ nl)
       ((fn (_ nm np)
          (do (%oset! ST i ((fn (_ st) (if (null? st) () (stepwalk st (w np) (%i+ np 1))))
                            (tstruct nm)))
              (k (%i+ i 1) (%i+ np (%i+ 1 (w np))))))
        (Ptr ->str (%i2p (at (%i+ pos 2))))
        (%i+ pos (%i+ 3 (%shr nl 3)))))
     (w (%i+ pos 1)))))
(rdstatics 1 SSTART)

; --- foreign: reacquire by name --------------------------------------------
(def FV (mkn (%i+ FCOUNT 1)))
(def fnptr-of (fn (_ v) (%word-at (%o->p v) 0)))
; (Str8 sub st len v): START, LENGTH, and the SUBJECT LAST -- methods dispatch
; subject-last.  These calls had the string first and an END offset instead of
; a length, so every catalog name raised into the guard and came back 0.  105 of
; 145 foreign entries never resolved, and nothing noticed because until the
; globals were installed nothing USED them.
(def slash
  (fn (self s i n)
    (if (eq? i n) -1 (if (str=? (Str8 sub i 1 s) "/") i (self s (%i+ i 1) n)))))
(def resolve
  (fn (_ kind nm)
    (guard (_ 0)
      (if (eq? kind 1) (%res-cat nm)
        (if (eq? kind 2) (fnptr-of (eval ((prim-ref (lit str) (lit ->sym)) nm)))
          (if (eq? kind 3) (Ptr ->int (Ffi dlsym %lib0 nm))
            (if (eq? kind 4) (%res-typecall nm)
              (if (eq? kind 5) (Ptr ->int %lib0) 0))))))))
; prim-ref is a BARE GLOBAL and it evaluates its arguments; (prim ref) is not a
; coordinate and never was.  Every catalog entry raised into the guard and came
; back 0 -- 105 of 145 foreign entries unresolved, `int/+` among them -- and a
; 0 in a callable's slot 0 is a call through a null pointer, which is what the
; installed image was doing.
(def %->sym (prim-ref (lit str) (lit ->sym)))
(def %res-cat
  (fn (_ nm)
    ((fn (_ i n)
       (fnptr-of (prim-ref (%->sym (Str8 sub 0 i nm))
                           (%->sym (Str8 sub (%i+ i 1) (%i- n (%i+ i 1)) nm)))))
     (slash nm 0 (Str8 length nm)) (Str8 length nm))))
(def %res-typecall
  (fn (_ nm) (if (str=? nm "PROCEDURE") (fnptr-of (fn (_ x) x)) (fnptr-of (op (x) x)))))
(def rdforeign
  (fn (self i pos)
    (if (%lt FCOUNT i) ()
      (do (%oset! FV i (resolve (w pos) (Ptr ->str (%i2p (at (%i+ pos 2))))))
          (self (%i+ i 1) (%i+ pos (%i+ 3 (%shr (w (%i+ pos 1)) 3))))))))
(rdforeign 1 FSTART)

; --- allocate, then patch every unit ---------------------------------------
(def mkt
  (fn (_ ti n)
    ((fn (_ st) (if (null? st) (mkn n) (%mk st (if (%lt n 1) 1 n)))) (%oref TT ti))))
(def mkt-unused ())
(def IX (mkn (%i+ N 1)))
(def alloc
  (fn (self i pos)
    (if (%lt N i) pos
      ((fn (_ n) (do (%oset! IX i (mkt (w pos) n)) (self (%i+ i 1) (%i+ pos (%i+ 2 n)))))
       (units-of (w pos) pos)))))

; --- the whole rebuild, in one primitive ------------------------------------
; X resolved the tables; C does the only per-object work there is.
((fn (_ ix)
   (do (display "rebuilt ") (write N) (display " objects") (newline)
       ; INSTALL: point the fresh base's env cells at the rebuilt roots.
       (%oset! (B cell (lit env-alist)) 0 (%oref ix ROOTENV))
       ; GLOBALS ARE NOT INSTALLED.  The rebuilt tree is structurally perfect
       ; -- 1,102 nodes, no nil entry, no nil children, every entry's first a
       ; SYMBOL, which is everything x_alist_bst_lookup dereferences -- and
       ; installing it still segfaults on the first evaluation.  Replaying
       ; X_OBJ_FLAG_SHARED (which bst_pair sets on every node) does not change
       ; it.  Unexplained.  Writing the rebuilt tree into the slot
       ; (which %install-slot! now does correctly -- it is a slot, not a cell)
       ; segfaults on the first evaluation, so the rebuilt tree is not yet a
       ; structure the evaluator can search.  The env alist is installed and
       ; works; globals stay the host's until that is understood.
       (display "installed.  evaluating in the loaded image:") (newline)
       (display "  (+ 1 2)        => ") (write (guard (_ (lit RAISED)) (B eval (lit (+ 1 2))))) (newline)
       (display "  x-release      => ") (write (guard (_ (lit RAISED)) (B eval (lit x-release)))) (newline)
       (display "  (list 1 2 3)   => ") (write (guard (_ (lit RAISED)) (B eval (lit (list 1 2 3))))) (newline)
       (display "  %word-size     => ") (write (guard (_ (lit RAISED)) (B eval (lit %word-size)))) (newline)
       ; Which is it: a truncated env chain, or symbols that lost identity?
       ((fn (_ chain)
          (do (display "  rebuilt env chain length: ") (write chain) (newline)))
        ((fn (self o n) (if (null? o) n (if (eq? n 100000) n (self (%oref o 1) (%i+ n 1)))))
         (%oref ix ROOTENV) 0))
       ((fn (_ g)
          (do (display "  rebuilt globals tree: type=") (write (Type name g))
              (display "  slot0=") (write (guard (_ (lit RAISED)) (Type name (%oref g 0))))
              (display "  slot1=") (write (guard (_ (lit RAISED)) (Type name (%oref g 1)))) (newline)))
        (%oref ix ROOTG))
       ; Is the rebuilt tree COMPLETE?  The engine's lookup derefs entry,
       ; entry's symbol, and the children pair with no nil checks.
       ((fn (_ r)
          (do (display "  tree nodes=") (write (first r))
              (display "  nil entries=") (write (first (rest r)))
              (display "  nil children=") (write (rest (rest r))) (newline)))
        ((fn (self t acc d)
           (if (null? t) acc
             (if (%lt 40 d) acc
               ((fn (_ e c)
                  (if (null? e) (pair (first acc) (pair (%i+ (first (rest acc)) 1) (rest (rest acc))))
                    (if (null? c) (pair (%i+ (first acc) 1) (pair (first (rest acc)) (%i+ (rest (rest acc)) 1)))
                      (self (%oref c 1)
                        (self (%oref c 0)
                          (pair (%i+ (first acc) 1) (rest acc)) (%i+ d 1)) (%i+ d 1)))))
                (%oref t 0) (%oref t 1)))))
         (%oref ix ROOTG) (pair 0 (pair 0 0)) 0))
       ; The engine derefs first(entry) as a SYMBOL with no check.
       ((fn (_ r)
          (do (display "  entries whose first is a SYMBOL: ") (write (first r))
              (display "   NOT a symbol: ") (write (rest r)) (newline)))
        ((fn (self t acc d)
           (if (null? t) acc
             (if (%lt 40 d) acc
               ((fn (_ e c)
                  (self (%oref c 1)
                    (self (%oref c 0)
                      (if (str=? (guard (_ "?") (Type name (%oref e 0))) "SYMBOL")
                        (pair (%i+ (first acc) 1) (rest acc))
                        (pair (first acc) (%i+ (rest acc) 1)))
                      (%i+ d 1)) (%i+ d 1)))
                (%oref t 0) (%oref t 1)))))
         (%oref ix ROOTG) (pair 0 0) 0))
       ((fn (_ sym)
          (do (display "  a rebuilt symbol vs the interned one: ")
              (write (guard (_ (lit RAISED))
                       (same? sym ((prim-ref (lit str) (lit ->sym)) (symbol->str sym)))))
              (display "   name=") (write (guard (_ (lit RAISED)) (symbol->str sym))) (newline)))
        ((fn (self i) (if (%lt N i) ()
            (if (str=? (Type name (%oref ix i)) "SYMBOL") (%oref ix i) (self (%i+ i 1)))))
         1))))
 ((prim-ref (lit image) (lit rebuild!))
  buf OSTART N TT FV ST (%i+ (Ptr ->int buf) (%i* BSTART W)) IX TCNT SYMTI))
