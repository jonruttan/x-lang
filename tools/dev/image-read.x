; image-read.x -- load a state image into THIS base.  docs/state-image-format.md
; is the contract; section numbers below are its.
;
;   { echo '(def %IMG-PATH "/tmp/x-core.ximg")'; cat tools/dev/image-read.x;
;     echo '(write (list 1 2 3))'; } | sh x.sh -q -l img
;
; Runs on the img dialect (lib/img.x): functions and operatives, no classes.
; %IMG-PATH names the file; without it the writer's default is read.  Bound
; by a runner, the loader prints nothing -- its stdout is the batch's; with
; %IMG-VERBOSE bound it prints one line of counts and names every external
; that did not resolve.
;
; What it does, in the contract's order (spec 5): read the file and refuse a
; word size, byte order or engine release that is not this process's;
; resolve every external to an object or an address; rebuild the object
; table in one primitive; then write the roots into this base's language
; cells as ONE form of nested primitive calls, env group last, tree last of
; all.  After that form nothing here resolves and the next form on stdin
; evaluates inside the image.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(def IMG (guard (_ "/tmp/x.ximg") (eval (lit %IMG-PATH))))
(def QUIET (guard (_ #f) (do (eval (lit %IMG-PATH)) #t)))
(def VERBOSE (guard (_ #f) (do (eval (lit %IMG-VERBOSE)) #t)))

(def %sread  (prim! (lit sys) (lit read)))
(def %sopen  (prim! (lit sys) (lit open)))
(def %sclose (prim! (lit sys) (lit close)))
(def %alloc  (prim! (lit ptr) (lit alloc)))
(def %rw     (prim! (lit ptr) (lit ref-word)))
(def %psw    (prim! (lit ptr) (lit set-word!)))
(def %p2i    (prim! (lit ptr) (lit ->int)))
(def %i2p    (prim! (lit int) (lit ->ptr)))
(def %p2o    (prim! (lit ptr) (lit ->obj)))
(def %p->s   (prim! (lit ptr) (lit ->str)))
(def %strcmp (prim! (lit ptr) (lit strcmp)))
(def %dlopen (prim! (lit ffi) (lit dlopen)))
(def %dlsym  (prim! (lit ffi) (lit dlsym)))
(def %->sym  (prim! (lit str) (lit ->sym)))
(def %i+ (prim! (lit int) (lit +)))  (def %i- (prim! (lit int) (lit -)))
(def %i* (prim! (lit int) (lit *)))  (def %lt (prim! (lit int) (lit <)))
(def %shr (prim! (lit int) (lit >>))) (def %i& (prim! (lit int) (lit &)))
(def %mk (prim! (lit obj) (lit make)))
(def W %word-size)
;  Say what, then raise: the bare engine renders a raised pair as "error".
(def %symbytes (fn (_ o) (%i2p (%ptr-ref-word (%obj->ptr o) (%data-word-off 0)))))
(def %fail
  (fn (_ what)
    (display "image: ")
    (if (null? what) () (display (%p->s (%symbytes (if (eq? (%reflect-type-word what) (%reflect-type-word (pair 1 2))) (first what) what)))))
    (newline)
    (error "image load failed")))

; --- the file (spec 3.1) ------------------------------------------------------
(def CAP (* 8 8000000))
(def buf (%alloc CAP))
(def fd (%sopen IMG 0))
(if (%lt fd 0) (%fail (pair (lit open-failed) IMG)) ())
(def got (%sread fd buf CAP))
(%sclose fd)
(if (%lt got CAP) () (%fail (lit larger-than-the-buffer)))
(def w (fn (_ i) (%rw buf (%i* i W))))
(def at (fn (_ i) (%i+ (%p2i buf) (%i* i W))))
(if (eq? (w 0) 1196247384) () (%fail (lit not-an-image)))
(if (eq? (w 1) 1) () (%fail (pair (lit version) (w 1))))
(if (eq? (w 2) W) () (%fail (pair (lit word-size) (w 2))))
(if (eq? (w 3) 1) () (%fail (lit byte-order)))
(def N (w 4)) (def OBJW (w 5)) (def BLOBN (w 6))
(def XCOUNT (w 7)) (def XWORDS (w 8))
(def RTCOUNT (w 9)) (def RTWORDS (w 10))
(def RELEASE (w 12))
(def XSTART 13)
(def RTSTART (%i+ XSTART XWORDS))
(def OSTART (%i+ RTSTART RTWORDS))
(def BSTART (%i+ OSTART OBJW))
(def BLOB (at BSTART))
; The engine release: [len][bytes] at RELEASE in the blob, against this
; process's x-release.  An image is a heap laid out by one build.
(def %strp (fn (_ s) (%i2p (%ptr-ref-word (%obj->ptr s) (%data-word-off 0)))))
(if (eq? 0 (%strcmp (%i2p (%i+ BLOB (%i+ RELEASE W))) (%strp x-release))) ()
  (%fail (pair (lit engine-release) (%p->s (%i2p (%i+ BLOB (%i+ RELEASE W)))))))

; --- names in the tables (spec 3.2) -----------------------------------------
(def %words-for (fn (_ n) (%i+ 1 (%shr (%i+ n 1) 3))))
(def %name-at (fn (_ pos) (%p->s (%i2p (at (%i+ pos 1))))))   ; pos: the len word
(def %after-name (fn (_ pos) (%i+ pos (%i+ 1 (%words-for (w pos))))))
(def %str-byte-ref (prim! (lit str) (lit byte-ref)))
(def %split
  (fn (self s i n sep)
    (if (eq? i n) ()
      (if (eq? (%str-byte-ref s i) sep) i (self s (%i+ i 1) n sep)))))
(def SLASH (%str-byte-ref "/" 0))
(def SPACE (%str-byte-ref " " 0))
(def %head (fn (_ s i) (%str-byte-sub s 0 i)))
(def %tail (fn (_ s i) (%str-byte-sub s (%i+ i 1) (%i- (%str-byte-len s) (%i+ i 1)))))

; --- externals (spec 3.4) -------------------------------------------------------
; Entry k of XV is an object (kinds 6-8) or an integer address (kinds 1-5).
; Every engine type this base registers lazily is registered first, so a
; type-static row of a type the image used has a struct to be walked here.
((prim! (lit ptr) (lit alloc)) 8)
(guard (_ ()) ((prim! (lit buf) (lit make)) ""))
(guard (_ ()) ((prim! (lit iter) (lit make)) (pair 1 2) ()))
(def PT ((prim! (lit type) (lit of)) (pair 1 2)))
(def mkn (fn (_ n) (%mk PT (if (%lt n 1) 1 n))))
(def XV (mkn (%i+ XCOUNT 1)))
(def %lib0 (%dlopen () 1))
(def fnptr-of (fn (_ v) (%ptr-ref-word (%obj->ptr v) (%data-word-off 0))))
(def %struct-named
  (fn (self al nm)
    (if (null? al) ()
      (if (str=? (%type-name (rest (first al))) nm) (rest (first al)) (self (rest al) nm)))))
(def %probe-units
  ((fn (_ h) (first (%type-units-cell (rest (first (first %reflect-type-alist-cell))))))
   ((prim! (lit type) (lit make)) "%img-probe" ())))
(def %unresolved 0)
(def %UNRESOLVED ())
(def %miss (fn (_ kind nm) (do (set! %unresolved (%i+ %unresolved 1)) (set! %UNRESOLVED (pair (pair kind nm) %UNRESOLVED)) ())))
(def %resolve-external
  (fn (_ kind nm)
    (guard (_ (%miss kind nm))
      (if (eq? kind 1)
          ((fn (_ i) (fnptr-of (prim-ref (%->sym (%head nm i)) (%->sym (%tail nm i)))))
           (%split nm 0 (%str-byte-len nm) SLASH))
        (if (eq? kind 2) (fnptr-of (eval (%->sym nm)))
          (if (eq? kind 3) (%p2i (%dlsym %lib0 nm))
            (if (eq? kind 4) (if (str=? nm "PROCEDURE") (fnptr-of (fn (_ x) x)) (fnptr-of (op (x) x)))
              (if (eq? kind 5) (%p2i %lib0)
                (if (eq? kind 6)
                    (if (str=? nm "true") (first (%img-cell (lit true)))
                      (if (str=? nm "false") (first (%img-cell (lit false)))
                        (if (str=? nm "sigint") (first (%img-cell (lit sigint)))
                          (if (str=? nm "token-eof") (eval (lit %token-eof))
                            (if (str=? nm "units-pair") %probe-units
                              (%miss kind nm))))))
                  (if (eq? kind 7)
                      ((fn (_ i)
                         ((fn (_ st) (if (null? st) (%miss kind nm) (%img-of st (%->sym (%tail nm i)))))
                          (%struct-named (first %reflect-type-alist-cell) (%head nm i))))
                       (%split nm 0 (%str-byte-len nm) SPACE))
                    (if (eq? kind 8)
                        (if (str=? nm "base") (%base) (%img-walk (%base) (%img-row %base-paths (%->sym nm))))
                        (%miss kind nm))))))))))))
(def rdexternals
  (fn (self k pos)
    (if (%lt XCOUNT k) ()
      (do (%obj-set! XV k (%resolve-external (w pos) (%name-at (%i+ pos 1))))
          (self (%i+ k 1) (%after-name (%i+ pos 1)))))))
(rdexternals 1 XSTART)

; --- rebuild (spec 5.3) ------------------------------------------------------------
(def IX (%alloc (%i* (%i+ N 1) W)))
;  REBUILT OBJECTS CARRY NO METADATA (spec 8).  This base allocates with
; its metadata width, and would give every rebuilt object the META flag
; over fresh, zeroed slots -- a claim of "line 0" that eval then copies
; into the line counter whenever an imaged form runs.  The width is 0 for
; the rebuild and put back after.  Changing it while objects live is
; undefined only for an object later freed at the wrong width; a rebuilt
; object is SHARED and never freed.
(def %META-ATOM (%obj->ptr (first (%img-cell (lit obj-meta-extra)))))
(def %META-WAS (%rw %META-ATOM (%data-word-off 0)))
(%psw %META-ATOM (%data-word-off 0) 0)
((prim! (lit image) (lit rebuild!)) buf OSTART N XV (%i+ XCOUNT 1) (%i2p BLOB) IX)
(%psw %META-ATOM (%data-word-off 0) %META-WAS)
(def ixref (fn (_ i) (%p2o (%i2p (%rw IX (%i* i W))))))
(def %ref-obj
  (fn (_ r) (if (eq? r 0) () (if (%lt 0 r) (ixref r) (%obj-ref XV (%i- 0 r))))))

; --- roots (spec 3.5): name -> ref ---------------------------------------------------
(def ROOTS ())
(def rdroots
  (fn (self i pos)
    (if (%lt RTCOUNT i) ()
      ((fn (_ np)
         (do (set! ROOTS (pair (pair (%name-at pos) (w np)) ROOTS))
             (self (%i+ i 1) (%i+ np 1))))
       (%after-name pos)))))
(rdroots 1 RTSTART)
;  A root's name in the file is a string; the contract's is a symbol.  Both
; carry their bytes in word 0, so one strcmp compares them.
(def %name=? (fn (_ sym str) (eq? 0 (%strcmp (%strp sym) (%strp str)))))
(def %root-ref
  (fn (self l nm)
    (if (null? l) (%fail (pair (lit root-not-in-image) nm))
      (if (%name=? nm (first (first l))) (rest (first l)) (self (rest l) nm)))))

; The contract's language cells, read as data the same way the writer reads
; them, so the two agree on what is a cell and what a slot.
(def %LANG ())
(def %IN-BUILD #f)
(def %eval-all (fn (self l e) (if (null? l) () (do (eval (first l) e) (self (rest l) e)))))
(def cell (op (nm) e (do (if %IN-BUILD (set! %LANG (pair (pair nm (lit cell)) %LANG)) ()) ())))
(def slot (op (nm) e (do (if %IN-BUILD (set! %LANG (pair (pair nm (lit slot)) %LANG)) ()) ())))
(def todo (op (nm) e ()))
(def nil (op () e ()))
(def node (op (nm . kids) e (do (%eval-all kids e) ())))
(def build (op (x) e (do (set! %IN-BUILD #t) (eval x e) (set! %IN-BUILD #f) ())))
(include "engine/tools/contract/base-layout.x")
(def %kind-of (fn (self l nm) (if (null? l) (%fail (pair (lit not-a-cell) nm)) (if (eq? (first (first l)) nm) (rest (first l)) (self (rest l) nm)))))
(def %but-last (fn (self l) (if (null? (rest l)) () (pair (first l) (self (rest l))))))
(def %last-of (fn (self l) (if (null? (rest l)) (first l) (self (rest l)))))

; One write: the target word's pointer and offset, and the value's address.
; A cell takes the object in its first slot; a slot is the half of its
; parent the last step names.
(def %write-of
  (fn (_ nm)
    ((fn (_ steps v)
       (if (eq? (%kind-of %LANG nm) (lit cell))
           (list (%obj->ptr (%img-walk (%base) steps)) (%data-word-off 0) v)
           (list (%obj->ptr (%img-walk (%base) (%but-last steps)))
                 (%data-word-off (if (eq? (%last-of steps) (lit f)) 0 1))
                 v)))
     (%img-row %base-paths nm)
     ((fn (_ o) (if (null? o) 0 (%ptr->int (%obj->ptr o)))) (%ref-obj (%root-ref ROOTS nm))))))

; The order: every root but the env group, then the env group with the tree
; last.  Each root the image carries is written; a language cell the image
; does not carry (the contract grew) is an error, never a silent skip.
(def %rev-l (fn (_ l) ((fn (loop l acc) (if (null? l) acc (loop (rest l) (pair (first l) acc)))) l ())))
(def %append-l (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))
(def %ENV-ORDER (lit (shadow-list env-local-boundary env-alist env-global-tree)))
(def %env-cell? (fn (self l nm) (if (null? l) #f (if (eq? (first l) nm) #t (self (rest l) nm)))))
;  The same cells the writer roots: not the profile counters, not sigint
; (spec 1) -- those stay this base's own.
(def %prefix? (fn (_ sym pre) (if (%lt (%str-byte-len (%p->s (%symbytes sym))) (%str-byte-len pre)) #f (str=? (%str-byte-sub (%p->s (%symbytes sym)) 0 (%str-byte-len pre)) pre))))
(def %root-cell? (fn (_ nm) (if (eq? nm (lit sigint)) #f (if (eq? nm (lit line)) #f (not (%prefix? nm "profile-"))))))
(def %OTHERS ((fn (self l acc) (if (null? l) acc (self (rest l) (if (%root-cell? (first (first l))) (if (%env-cell? %ENV-ORDER (first (first l))) acc (pair (first (first l)) acc)) acc)))) %LANG ()))
; execution order: the others, then the env group, the tree last
(def %ORDER (%append-l %OTHERS %ENV-ORDER))
(def %WRITES ((fn (self l acc) (if (null? l) (%rev-l acc) (self (rest l) (pair (%write-of (first l)) acc)))) %ORDER ()))

(if VERBOSE
    (do (display "image: objects=") (say-num N)
        (display " externals=") (say-num XCOUNT) (display " roots=") (say-num RTCOUNT)
        (display " unresolved=") (say-num %unresolved) (newline)
        ((fn (self l) (if (null? l) () (do (display "  unresolved kind ") (say-num (first (first l))) (display " ") (display (rest (first l))) (newline) (self (rest l))))) %UNRESOLVED))
    ())

;  THIS BASE'S OWN TYPE STRUCTS STAY ALIVE.  Its process state -- the read
; buffer, the allocation-error string -- is typed by structs of ITS registry,
; and the install replaces that registry with the image's.  Unreached from
; any cell, those structs would be freed at the next collect under objects
; that still carry them, and the marker would walk a freed type.  The old
; registry is made a mark root: never swept, never consulted.
((prim! (lit heap) (lit mark-root!)) (first (%img-cell (lit type-alist))))

; --- install (spec 5.4) ---------------------------------------------------------------
; ONE FORM, NOTHING IN IT BUT PRIMITIVE CALLS.  Built as data, evaluated
; last: (& (->int (set-word! P O V)) rest), nested so the first write is the
; innermost-leftmost and the tree's is the outermost.  The operators are the
; primitive OBJECTS, not their names, so no symbol is looked up while the
; base's cells are half this loader's and half the image's; `lit` is bound
; by the engine in every base.  A procedure or an operative anywhere in this
; form would push a TCO compound that a later restore would use to put this
; base's old env back.
;  The fold puts its first element INNERMOST, and the outermost argument is
; evaluated first, so the list is fed in reverse: the tree's write is the
; first element in and the last write out.
(def %INSTALL
  ((fn (self l acc)
     (if (null? l) acc
       (self (rest l) (list %i& (list %p2i (list %psw (list (lit lit) (first (first l))) (first (rest (first l))) (first (rest (rest (first l)))))) acc))))
   (%rev-l %WRITES) 0))
(eval %INSTALL)

;  The library recomputes what it cached by address (spec 5.5).  Resolved
; in the image, as every form from here on is.
(%image-recache!)
