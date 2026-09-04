; image-read.x -- read a state image back and rebuild its object graph.
;
;   sh x.sh -q -f tools/dev/image-write.x           # write /tmp/x-core.ximg
;   X_BIN=<engine-with-image-rebuild> sh x.sh -q -l img -f tools/dev/image-read.x
;
; NEEDS AN ENGINE CARRYING (image rebuild!), which the pinned one does not yet.
;
; RUNS ON THE img DIALECT (lib/img.x), NOT HELIUM.  The host is the floor under
; every load, and helium's 0.88s boot was 96% of a 2.3s load; on img the same
; load is 0.26s -- read 5ms, types 24ms, statics 107ms, foreign 39ms, rebuild
; 7ms, install 0.2ms -- against 0.90s to boot the x-core it replaces.  Nothing
; here touches a class: (obj ref)/(obj set!) are img's, type names and units
; cells come from the base-paths rows, strings are the byte prims.
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
(def %dlopen (prim! (lit ffi) (lit dlopen)))
(def %dlsym (prim! (lit ffi) (lit dlsym)))
(def %lib0 (%dlopen () 1))
; The engine's own read and allocator, not libc's.  dlopen stays only for
; reacquiring foreign ADDRESSES by name, which is the dynamic linker's job and
; nothing else's.
(def %sread (prim! (lit sys) (lit read)))
(def %alloc (prim! (lit ptr) (lit alloc)))
(def %i2p (prim! (lit int) (lit ->ptr)))
(def %p2i (prim! (lit ptr) (lit ->int)))
(def %sopen (prim! (lit sys) (lit open)))
(def %sclose (prim! (lit sys) (lit close)))
(def %beval (prim! (lit base) (lit eval)))
(def %mk (prim! (lit obj) (lit make)))
; Not (obj set!)/(obj ref): those are library definitions, absent from a bare
; base, and the img dialect supplies its own.
(def %oset! %obj-set!)
(def %oref %obj-ref)
(def %psw (prim! (lit ptr) (lit set-word!)))
(def %i+ (prim! (lit int) (lit +)))  (def %i* (prim! (lit int) (lit *)))
(def %i- (prim! (lit int) (lit -)))  (def %lt (prim! (lit int) (lit <)))
(def W %word-size)
(def buf (%alloc (* 8 1000000)))
(def fd (%sopen "/tmp/x-core.ximg" 0))          ; 0 is O_RDONLY
(def got (%sread fd buf (* 8 1000000)))
(%sclose fd)
(def w (fn (_ i) (%rw buf (%i* i W))))
(def at (fn (_ i) (%i+ (%p2i buf) (%i* i W))))
(def N (w 4)) (def OBJW (w 5)) (def ROOTENV (w 7)) (def ROOTG (w 12))
(def FCOUNT (w 8)) (def FWORDS (w 9)) (def TCOUNT (w 10)) (def TWORDS (w 11))
(def SCOUNT (w 13)) (def SWORDS (w 14))
(def TSTART 15)
(def SSTART (%i+ TSTART TWORDS))
(def FSTART (%i+ SSTART SWORDS))
(def OSTART (%i+ FSTART FWORDS))
(def BSTART (%i+ OSTART OBJW))
(def PT ((prim! (lit type) (lit of)) (pair 1 2)))
(def mkn (fn (_ n) (%mk PT (if (%lt n 1) 1 n))))

; The base the image is installed INTO.  It has to exist before the statics are
; resolved: a static reference is a walk from a base, and the walk has to start
; at the base the rebuilt graph will live in, not at the one doing the reading.
; Resolving them against the reader's own base would wire the loaded env to
; this process's spine.
(def RAWB ((prim! (lit base) (lit make))))

; --- live shapes by name ---------------------------------------------------
; A type's name as a RAW BYTE POINTER, not an x string.  Names in the file are
; already bytes in the image buffer; lifting each one into a string to compare
; it allocated 954 strings for the statics table alone and then compared them
; through class dispatch.  (ptr strcmp) compares them where they lie.
(def %strcmp (prim! (lit ptr) (lit strcmp)))
(def %namep (fn (_ s) (%i2p (%word-at (%o->p s) 0))))
(def SHAPES ())   ; (name . (units-cell . struct))
(def add-shape
  (fn (self l)
    (if (null? l) ()
      (do (set! SHAPES (pair (pair (%namep (%type-name (rest (first l))))
                                   (pair (first (%type-units-cell (rest (first l))))
                                         (rest (first l)))) SHAPES))
          (self (rest l))))))
; The reader's own type registry, not B's -- and that is a constraint worth
; naming: an image of helium CANNOT be loaded into a bare base.  It references
; fifteen types by name and a fresh (Base make) does not have VECTOR, PROMISE
; or ITER, so the shape lookup misses, units-of returns 0, and the record walk
; desyncs on the first such object.  A loader's base must already carry the
; type registry the image was written against.
(add-shape (first %reflect-type-alist-cell))
(def lookup
  (fn (self l nm)
    (if (null? l) ()
      (if (eq? (%strcmp (first (first l)) nm) 0) (rest (first l)) (self (rest l) nm)))))
(def tagged (fn (_ nm) (if (str=? nm "PAIR") (pair 2 0) (if (str=? nm "ATOM") (pair 1 1) (if (str=? nm "NIL") (pair 1 1) ())))))
; Types the file names and this base lacks -- CLASS and OBJECT are the
; library's, registered by lib/x/type/class.x, and a loader that has not run
; the library has neither.  Register them empty so the type-rooted statics have
; a struct to walk from and the rebuild has a type to make instances of.  Empty
; is the honest word: their handler stacks are the writer's base's state and
; the image does not carry them yet, so class dispatch is not restored here.
(def %type-make (prim! (lit type) (lit make)))
(def ensure-types
  (fn (self i pos)
    (if (%lt TCOUNT i) ()
      (do ((fn (_ nm)
             (if (null? (lookup SHAPES nm))
                 (if (null? (tagged nm)) (%type-make nm ()) ())
                 ()))
           (%p->s (%i2p (at (%i+ pos 1)))))
          (self (%i+ i 1) (%i+ pos (%i+ 2 (%shr (w pos) 3))))))))
(ensure-types 1 TSTART)
(set! SHAPES ())
(add-shape (first %reflect-type-alist-cell))
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
       (%p->s (%i2p (at (%i+ pos 1))))))))
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
        (%i2p (at (%i+ pos 2)))
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
    (if (eq? i n) -1 (if (str=? (%str-byte-sub s i 1) "/") i (self s (%i+ i 1) n)))))
(def resolve
  (fn (_ kind nm)
    (guard (_ 0)
      (if (eq? kind 1) (%res-cat nm)
        (if (eq? kind 2) (fnptr-of (eval ((prim! (lit str) (lit ->sym)) nm)))
          (if (eq? kind 3) (%p2i (%dlsym %lib0 nm))
            (if (eq? kind 4) (%res-typecall nm)
              (if (eq? kind 5) (%p2i %lib0) 0))))))))
; prim-ref is a BARE GLOBAL and it evaluates its arguments; (prim ref) is not a
; coordinate and never was.  Every catalog entry raised into the guard and came
; back 0 -- 105 of 145 foreign entries unresolved, `int/+` among them -- and a
; 0 in a callable's slot 0 is a call through a null pointer, which is what the
; installed image was doing.
(def %->sym (prim! (lit str) (lit ->sym)))
(def %res-cat
  (fn (_ nm)
    ((fn (_ i n)
       (fnptr-of (prim-ref (%->sym (%str-byte-sub nm 0 i))
                           (%->sym (%str-byte-sub nm (%i+ i 1) (%i- n (%i+ i 1)))))))
     (slash nm 0 (%str-byte-len nm)) (%str-byte-len nm))))
(def %res-typecall
  (fn (_ nm) (if (str=? nm "PROCEDURE") (fnptr-of (fn (_ x) x)) (fnptr-of (op (x) x)))))
(def rdforeign
  (fn (self i pos)
    (if (%lt FCOUNT i) ()
      (do (%oset! FV i (resolve (w pos) (%p->s (%i2p (at (%i+ pos 2))))))
          (self (%i+ i 1) (%i+ pos (%i+ 3 (%shr (w (%i+ pos 1)) 3))))))))
(rdforeign 1 FSTART)

; --- allocate, then patch every unit ---------------------------------------
(def mkt
  (fn (_ ti n)
    ((fn (_ st) (if (null? st) (mkn n) (%mk st (if (%lt n 1) 1 n)))) (%oref TT ti))))
(def mkt-unused ())
; RAW MEMORY, not an object: an obj make of ~95k units cost 612ms of a 1.5s
; load, more than every other phase together.  The collector need not see it --
; rebuilt objects are on the heap chain from birth, and nothing collects
; between the rebuild and the install.
(def IX (%alloc (%i* (%i+ N 1) W)))
; The index is raw memory now, so reading an entry is a word read and a cast,
; not (obj ref).
(def %p2o (prim! (lit ptr) (lit ->obj)))
(def ixref (fn (_ ix i) (%p2o (%i2p (%rw ix (%i* i W))))))
(def alloc
  (fn (self i pos)
    (if (%lt N i) pos
      ((fn (_ n) (do (%oset! IX i (mkt (w pos) n)) (self (%i+ i 1) (%i+ pos (%i+ 2 n)))))
       (units-of (w pos) pos)))))

; --- the whole rebuild, in one primitive ------------------------------------
; X resolved the tables; C does the only per-object work there is.
; --- rebuild and install --------------------------------------------------
; One primitive does the per-object work; everything above is per-entry.
((fn (_ ix)
   (do (%oset! (%img-of RAWB (lit env-alist)) 0 (ixref ix ROOTENV))
       (%install-slot! (lit env-global-tree) (ixref ix ROOTG))
       (display "loaded ") (say-num N) (display " objects; ")
       ; The image's `list` runs and the host reads the pairs it built.  Not
       ; the image's `write`: printing dispatches through the type stacks, which
       ; are the writer's base's state and are not restored yet.
       (display "(list 1 2 3) => (")
       ((fn (_ r)
          (say-num (first r)) (display " ")
          (say-num (first (rest r))) (display " ")
          (say-num (first (rest (rest r))))
          (display (if (null? (rest (rest (rest r)))) ")" " ...)")))
        (%beval RAWB (lit (list 1 2 3))))
       (newline)))
 ((prim! (lit image) (lit rebuild!))
  buf OSTART N TT FV ST (%i+ (%p2i buf) (%i* BSTART W)) IX TCNT SYMTI
  (%i+ FCOUNT 1) (%i+ SCOUNT 1)))
