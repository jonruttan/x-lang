; image-write.x -- write the live heap out as a state image.
;
;   sh x.sh -q -f tools/dev/image-write.x
;
; The writer half of docs/state-images.md.  It walks the heap chain once per
; pass, asks the collector which objects are reachable, reads each object's
; units through its type's declared shape, and emits the graph as a binary
; image, to the path named by %IMG below (/tmp/x-core.ximg).
;
; Run it under the dialect you want imaged -- the writer images the base it is
; running in, so `-l xe` writes a xenon image and no flag writes a helium one.
;
; WHAT IT DOES NOT YET DO.  There is no type table, no foreign table and no
; root index, so this file is not yet loadable; it is the graph, verified
; self-consistent, and the tables are the next step.  Nothing can read it
; either way until the engine grows the allocate-and-patch loop.
;
; THREE RULES GOVERN EVERY LINE HERE, each learned by breaking it:
;
;   * NOTHING WALKS BYTES.  An interpreted per-byte loop costs hundreds of
;     evals a byte; the blob moves through memcpy, one call per string.  This
;     is lib/x/tool/asm-cache.x's rule and it applies for the same reason.
;   * NO `def` BETWEEN THE MARK AND THE LAST WALK.  A def repoints an
;     environment pair, which is itself a traced object in the image, at a
;     value pass one never stamped -- and each one surfaces as an unresolved
;     reference.  Measured: three extra defs, three extra unresolved.  The
;     driver at the bottom is therefore one expression.
;   * THE WALK CURSOR IS AN OBJECT, NEVER A POINTER.  An object held in a
;     parameter is rooted, so a collect cannot free it under the walk; a PTR
;     roots nothing it addresses.  The first version collected on iteration
;     zero, freed its own cursor, visited nothing, and reported a clean zero
;     of everything -- which read exactly like success.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

;
; Written once because doing it per pass produced the same three faults
; repeatedly: a PTR cursor that a collect frees under the walk, a collect on
; the first iteration while the start object is still an unrooted temporary,
; and a pass that visits nothing and reports zero of everything.
;
;   (%walk start f acc)  ->  (acc . visited)
;
; f is called (f p acc) for each TRACED object, p a pointer to it, and returns
; the new accumulator.  VISITED is returned so a vacuous walk is visible: a
; pass reporting a clean zero over zero objects is not a clean pass.
;
; The cursor is an OBJECT, never a pointer.  An object held in a parameter is
; rooted, so a collect cannot free it; a PTR roots nothing it addresses.
(include "tools/dev/image-name.x")

; --- pass 1: stamp an index, and count types that cannot state an extent ---
(def %refuses? (fn (_ p) (if (eq? (%rw p %type-off) %reflect-satom-tw) #f
  (if (eq? (%rw p %type-off) 0) #f
    (if (eq? (%rw p %type-off) %reflect-spair-tw) #f
      (eq? (%cell-of (%rw p %type-off)) ()))))))
; THE ROOT IS THE ENVIRONMENT, NOT THE BASE.
;
; The base object is traced but is NOT on the allocation chain, so no walk
; reaches it and it is not in the image at all.  That is right rather than a
; gap: the base is the static spine, which docs/state-images.md says may only
; be read through base-layout.x and base-paths.x, and which a loader rebuilds
; for itself.  What a loader must REATTACH is what hangs off it -- and the
; env-alist and the global tree are both flagged, traced and on the chain, so
; both are imaged and both carry a stamped index.
;
; Which means no threading: after the stamping pass their indices can simply be
; read back out of their metadata slots.
(def %stamp
  (fn (_ p acc)
    (do (if (%flagged? p) (%psw p %meta1-off (%int+ (first acc) 1)) ())
        (pair (%int+ (first acc) 1)
              (if (%refuses? p) (%int+ (rest acc) 1) (rest acc))))))
(def %ENV-P  (%o->p (first (%reflect-base-cell (lit env-alist)))))
(def %GLOB-P (%o->p (first (%reflect-base-cell (lit env-global-tree)))))

; --- libc doors: raw fd I/O, memcpy, malloc -------------------------------
; The asm-cache rule applies here too: NOTHING WALKS BYTES.  Strings reach the
; blob through memcpy, one call per string, never a character loop.
; Sys owns the file: (Sys open-write) and (Sys close) are the stdlib doors and
; there is no reason to reach past them.  What Sys cannot do is write a REGION
; OF MEMORY -- (Sys fd-write) takes a string, and an image is binary, NULs and
; all -- so the buffers and the write itself go through Ptr and Ffi, which are
; stdlib too (x/type/ptr exports both).  Nothing here hand-fetches a prim;
; image-walk.x does, and says why: the library's own note is that hot callers
; cache prims rather than class-dispatch per unit.
(def %c-write  (Ffi dlsym %lib "write"))
(def %c-malloc (Ffi dlsym %lib "malloc"))
(def %c-calloc (Ffi dlsym %lib "calloc"))
(def %c-memcpy (Ffi dlsym %lib "memcpy"))

; Buffers are allocated BEFORE the mark, so they are themselves traced and
; land in the image.  That is the writer-in-its-own-base problem the document
; records; a prototype pays it and says so rather than hiding it.
(def %EXT-CAP  (* 8 1000000))
(def %OBJ-CAP  (* 8 6000000))
(def %BLOB-CAP (* 8  400000))
(def %ext-p  (%i->p (Ptr call %c-malloc %EXT-CAP)))
(def %obj-p  (%i->p (Ptr call %c-malloc %OBJ-CAP)))
; calloc, not malloc: every blob entry ends in a NUL, and zeroed memory
; already has one, so no byte poke is needed to place it.  (An earlier comment
; here claimed (Ptr set!) could not do that job.  It can -- it writes a
; WIDTH-byte little-endian value at P+OFF; the probe that "proved" otherwise
; had called (Ptr ref) with the width argument missing and crashed before it
; ever reached set!.)
(def %blob-p (%i->p (Ptr call %c-calloc 1 %BLOB-CAP)))

(def %put (fn (_ p i w) (do (%psw p (%int* i %word-size) w) (%int+ i 1))))

; --- the foreign table -----------------------------------------------------
; One entry per named address: kind word, name-length word, then the name
; bytes NUL-padded to a word boundary.  Self-contained -- it references no
; other section -- so it can be built before the object walk and written
; wherever it is wanted in the file.
(def %F-CAP (* 8 40000))
(def %f-p (%i->p (Ptr call %c-calloc 1 %F-CAP)))
(def %t-p (%i->p (Ptr call %c-calloc 1 %F-CAP)))
(def %s-p (%i->p (Ptr call %c-calloc 1 %F-CAP)))
(def %words-for (fn (_ n) (%int+ 1 (%shr n 3))))
(def %emit-ftable
  (fn (self t cur)
    (if (null? t) cur (self (rest t) (%emit-fentry (rest (first t)) cur)))))
(def %emit-fentry
  (fn (_ kp cur) (%emit-fbytes (first kp) (rest kp) cur (%blen (rest kp)))))
(def %emit-fbytes
  (fn (_ kind nm cur n)
    (do (%psw %f-p (%int* cur %word-size) kind)
        (%psw %f-p (%int* (%int+ cur 1) %word-size) n)
        (Ptr call %c-memcpy (%int+ (Ptr ->int %f-p) (%int* (%int+ cur 2) %word-size))
                (%word-at (%o->p nm) 0) n)
        (%int+ cur (%int+ 2 (%words-for n))))))
; Shared by both tables: an entry's index is its position, 1-based, 0 meaning
; "not in the table".
(def %f-index
  (fn (self t a n)
    (if (null? t) 0 (if (eq? (first (first t)) a) n (self (rest t) a (%int+ n 1))))))

; --- the statics table ----------------------------------------------------
; A reference into the base's spine cannot be an object index: the spine is
; static, off the allocation chain, and never stamped -- which is why 266
; references were resolving to 0.  It is recorded as the WALK instead: the
; first/rest steps that reach it from the base.
;
; Only DECLARED steps are followed.  That is the whole safety argument: the
; spine may hold a raw C function pointer in a structural pair (the collector's
; own hooks), so following it as ordinary structure is a wild read, and
; base-paths.x is the committed list of steps that are real.  Every node along
; a declared path measures as Type name () -- a structural pair -- and that is
; the check before an address is taken.
;
; Steps rather than a field NAME, because not every node in that tree is named:
; a reference may land on an interior pair that no row ends at, so every prefix
; of every row is recorded, not just its leaf.
(include "engine/tools/contract/base-paths.x")
(def %step (fn (_ v s) (if (eq? s (lit f)) (first v) (rest v))))
(def %st-record
  (fn (_ v acc rpfx)
    (if (null? (Type name v))
      ((fn (_ a) (if (null? (%map-get acc a)) (%map-add acc a 0 rpfx) acc))
       (Ptr ->int (%o->p v)))
      acc)))
(def %st-walk
  (fn (self v steps acc rpfx)
    (if (null? steps) acc
      ((fn (_ nv nr) (self nv (rest steps) (%st-record nv acc nr) nr))
       (%step v (first steps)) (pair (first steps) rpfx)))))
(def %st-row
  (fn (_ row acc)
    (if (eq? (first (rest row)) (lit base))
      (%st-walk (%base) (rest (rest row)) acc ())
      acc)))
(def %st-rows
  (fn (self rows acc)
    (if (null? rows) acc (self (rest rows) (%st-row (first rows) acc)))))
(def %rev (fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc)))))
(def %slen (fn (self l n) (if (null? l) n (self (rest l) (%int+ n 1)))))
(def %emit-stable
  (fn (self t cur)
    (if (null? t) cur (self (rest t) (%emit-sentry (rest (rest (first t))) cur)))))
(def %emit-sentry
  (fn (_ rpfx cur)
    (%emit-steps (%rev rpfx ()) (%put %s-p cur (%slen rpfx 0)))))
(def %emit-steps
  (fn (self steps cur)
    (if (null? steps) cur
      (self (rest steps) (%put %s-p cur (if (eq? (first steps) (lit f)) 0 1))))))

; --- the type table --------------------------------------------------------
; One entry per DISTINCT type word the heap actually uses, discovered from the
; heap rather than read off the type alist -- the alist would not tell us which
; types have instances, and the three non-heap tags (nil-typed, static ATOM,
; structural PAIR) are not in it at all.  Entry: kind, unit count, unit mask,
; then the name.  A count may be NEGATIVE: that is the slot-0-counted form, and
; the loader needs the sign as much as the magnitude.
(def %T-NIL 0)
(def %T-ATOM 1)
(def %T-PAIR 2)
(def %T-HEAP 3)
(def %ty-kind
  (fn (_ tw)
    (if (eq? tw 0) %T-NIL
      (if (eq? tw %reflect-satom-tw) %T-ATOM
        (if (eq? tw %reflect-spair-tw) %T-PAIR %T-HEAP)))))
(def %ty-shape
  (fn (_ tw)
    (if (eq? (%ty-kind tw) %T-HEAP) (%ty-cell-shape (%cell-of tw)) (%ty-flat tw))))
(def %ty-flat
  (fn (_ tw)
    (if (eq? tw %reflect-spair-tw) (pair 2 0) (pair 1 1))))   ; PAIR: 2 refs; else 1 word
(def %ty-cell-shape
  (fn (_ u) (if (eq? u ()) (pair 0 0) (pair (%sh-count u) (%sh-mask u)))))
(def %ty-name
  (fn (_ tw p)
    (if (eq? tw 0) "NIL"
      (if (eq? tw %reflect-satom-tw) "ATOM"
        (if (eq? tw %reflect-spair-tw) "PAIR" (%ty-heap-name p))))))
(def %ty-heap-name
  (fn (_ p) (guard (_ "?") ((fn (_ nm) (if (null? nm) "?" nm)) (Type name (%p->o p))))))
(def %ty-discover (fn (_ p acc) (%ty-see p (%rw p %type-off) acc)))
(def %ty-see
  (fn (_ p tw acc)
    (if (null? (%map-get acc tw)) (%ty-add p tw acc) acc)))
(def %ty-add
  (fn (_ p tw acc)
    ((fn (_ sh)
       (%map-add acc tw (%ty-kind tw)
         (pair (first sh) (pair (rest sh) (%ty-name tw p)))))
     (%ty-shape tw))))
; --- the call pointer a whole TYPE shares -----------------------------------
; A PROCEDURE's unit 0 is the engine's procedure-call function, and EVERY
; procedure holds the same one; operatives likewise hold theirs.  Such an
; address has no useful symbol -- it is internal, so dladdr names it and dlsym
; will not give it back -- and it needs none: a loader creating an object of
; that type already knows which call function to install.  So it is named by
; the TYPE, not by a symbol.
;
; Which types qualify is MEASURED, not assumed: PRIMITIVE and POINTER also
; carry a foreign unit 0 and theirs differ per instance, so a type qualifies
; only if every instance seen agrees.  acc = (first-seen . disagreed).
(def %F-TYPECALL 4)
(def %cp-kind0
  (fn (_ tw)
    (if (eq? (%ty-kind tw) %T-HEAP) (%cp-cell-kind (%cell-of tw)) 9)))
(def %cp-cell-kind
  (fn (_ u)
    (if (eq? u ()) 9 (%kind (%sh-mask u) 0 (%sh-desc (%sh-count u))))))
(def %cp-scan
  (fn (_ p acc)
    (if (eq? (%cp-kind0 (%rw p %type-off)) 3)
        (%cp-note (%rw p %type-off) (%word-at p 0) acc)
        acc)))
(def %cp-note
  (fn (_ tw v acc)
    ((fn (_ e)
       (if (null? e) (pair (%map-add (first acc) tw 0 v) (rest acc))
         (if (eq? (rest e) v) acc (pair (first acc) (%cp-disagree (rest acc) tw)))))
     (%map-get (first acc) tw))))
(def %cp-disagree
  (fn (_ d tw) (if (null? (%map-get d tw)) (%map-add d tw 0 0) d)))
(def %cp-entries
  (fn (self m d acc)
    (if (null? m) acc
      (self (rest m) d
        (if (null? (%map-get d (first (first m))))
            (%map-add acc (rest (rest (first m))) %F-TYPECALL
                      (%tw-name (first (first m))))
            acc)))))
(def %tw-name
  (fn (_ tw)
    ((fn (_ e) (if (null? e) "?" (rest (rest (rest e))))) (%map-get %TTABLE tw))))

(def %emit-ttable
  (fn (self t cur)
    (if (null? t) cur (self (rest t) (%emit-tentry (rest (first t)) cur)))))
(def %emit-tentry
  (fn (_ kv cur)
    (%emit-tbytes (first kv) (first (rest kv)) (first (rest (rest kv)))
                  (rest (rest (rest kv))) cur)))
(def %emit-tbytes
  (fn (_ kind count mask nm cur)
    (%emit-tbytes2 kind count mask nm cur (%blen nm))))
(def %emit-tbytes2
  (fn (_ kind count mask nm cur n)
    (do (%psw %t-p (%int* cur %word-size) kind)
        (%psw %t-p (%int* (%int+ cur 1) %word-size) count)
        (%psw %t-p (%int* (%int+ cur 2) %word-size) mask)
        (%psw %t-p (%int* (%int+ cur 3) %word-size) n)
        (Ptr call %c-memcpy (%int+ (Ptr ->int %t-p) (%int* (%int+ cur 4) %word-size))
             (%word-at (%o->p nm) 0) n)
        (%int+ cur (%int+ 4 (%words-for n))))))
(def %flen (fn (self t n) (if (null? t) n (self (rest t) (%int+ n 1)))))

; Discovery: a foreign address the declared sources do not name may still be
; nameable by the linker.  This runs as its own walk so the table is complete
; BEFORE the stamping pass -- the emit pass may not allocate a table entry.
(def %discover (fn (_ p acc) (%over-units p %disc-unit acc)))
(def %disc-unit
  (fn (_ k w acc)
    (if (eq? k 3)
      (if (null? (%map-get %MAP w))
        (if (null? (%map-get acc w)) (%disc-add w acc) acc)
        acc)
      acc)))
(def %disc-add
  (fn (_ w acc)
    ((fn (_ nm) (if (null? nm) acc (%map-add acc w %F-DLSYM nm))) (%dl-name w))))
(def %append (fn (self a b) (if (null? a) b (self (rest a) (pair (first a) b)))))

; A ref resolves to the target's stamped index; 0 for nil, and 0 for a static,
; which is what the foreign table will carry instead (not yet emitted).
; A static reference is emitted NEGATIVE -- object indices are non-negative, so
; the ranges cannot collide and the loader needs no count to tell them apart.
;
; A reference that can be named NEITHER way gets -(SCOUNT+1), one past the
; table, rather than 0.  0 is NIL in this format, so writing an unnameable
; reference as 0 would restore it as an empty list -- a silent wrong answer,
; and the failure shape this work keeps producing.  One past the table is a
; value the loader can refuse.
(def %ref-index
  (fn (_ w)
    (if (eq? w 0) 0
      (if (%flagged? (%i->p w)) (%rw (%i->p w) %meta1-off) (%static-ref w)))))
(def %static-ref
  (fn (_ w)
    ((fn (_ i) (%int- 0 (if (eq? i 0) (%int+ %SCOUNT 1) i)))
     (%f-index %STATICS w 1))))

; acc = (obj-cursor . blob-cursor), both in units of their own buffer
(def %emit-unit
  (fn (_ k w acc)
    (if (eq? k 2) (%emit-bytes w acc)
      (pair (%put %obj-p (first acc)
              (if (eq? k 0) (%ref-index w)
                (if (eq? k 3) (%f-index %FTABLE w 1) w)))
            (rest acc)))))
(def %emit-bytes
  (fn (_ w acc)
    (%emit-bytes-at w acc (%blen (%p->s (%i->p w))) (rest acc))))
(def %emit-bytes-at
  (fn (_ w acc n off)
    (do (%psw %blob-p off n)
        (Ptr call %c-memcpy (%int+ (Ptr ->int %blob-p) (%int+ off %word-size)) w n)
        (pair (%put %obj-p (first acc) off)
              (%int+ off (%int+ %word-size (%int+ n 1)))))))

; One object record: type word, flags, then its units.  The extent table gets
; this object's unit count, so pass one of the loader is a straight loop.
(def %emit-obj
  (fn (_ p acc)
    (%emit-units p
      (pair (%put %obj-p (%put %obj-p (first (rest acc))
                    (%f-index %TTABLE (%rw p %type-off) 1))
                  (%int& (%rw p %flags-off) 65535))
            (rest (rest acc)))
      (first acc))))
(def %emit-units
  (fn (_ p acc ecur)
    (%emit-after p (%over-units p %emit-unit acc) ecur (first acc))))
(def %emit-after
  (fn (_ p acc ecur before)
    (pair (%put %ext-p ecur (%int- (first acc) before))
          acc)))

(def %emit (fn (_ p acc) (%emit-obj p acc)))

; --- write the sections out, in format order ------------------------------
(def %wr (fn (_ fd p n) (Ptr call %c-write fd p n)))
(def %hdr-p (%i->p (Ptr call %c-malloc 512)))
(def %emit-header
  (fn (_ n objw blobn)
    (do (%psw %hdr-p 0 1196247384)          ; "XIMG" little-endian
        (%psw %hdr-p (* 1 %word-size) 1)    ; format version
        (%psw %hdr-p (* 2 %word-size) %word-size)
        (%psw %hdr-p (* 3 %word-size) 1)    ; byte-order probe
        (%psw %hdr-p (* 4 %word-size) n)    ; object count
        (%psw %hdr-p (* 5 %word-size) objw) ; object-table words
        (%psw %hdr-p (* 6 %word-size) blobn); blob bytes
        (%psw %hdr-p (* 7 %word-size) (%rw %ENV-P %meta1-off))   ; root: the env
        (%psw %hdr-p (* 8 %word-size) %FCOUNT)
        (%psw %hdr-p (* 9 %word-size) %FWORDS)
        (%psw %hdr-p (* 10 %word-size) %TCOUNT)
        (%psw %hdr-p (* 11 %word-size) %TWORDS)
        (%psw %hdr-p (* 12 %word-size) (%rw %GLOB-P %meta1-off))  ; the globals
        (%psw %hdr-p (* 13 %word-size) %SCOUNT)
        (%psw %hdr-p (* 14 %word-size) %SWORDS)
        (* 15 %word-size))))

; Where the image lands.  A def rather than an argument: `Contract argv` is
; injected by x.sh's pin machinery, not the library, so a tool run with -f
; cannot see it.  Change it here, or copy the file afterwards.
(def %IMG "/tmp/x-core.ximg")
(def %report-image
  (fn (_ n extw objw blobn hdrn)
    (do (display "objects:     ") (write n) (newline)
        (display "extent:      ") (write (%int* extw %word-size)) (display " bytes") (newline)
        (display "objects tbl: ") (write (%int* objw %word-size)) (display " bytes") (newline)
        (display "byte blob:   ") (write blobn) (display " bytes") (newline)
        (display "type tbl:    ") (write (%int* %TWORDS %word-size))
        (display " bytes, ") (write %TCOUNT) (display " types") (newline)
        (display "statics tbl: ") (write (%int* %SWORDS %word-size))
        (display " bytes, ") (write %SCOUNT) (display " nodes") (newline)
        (display "unresolvable refs (written as nil, indistinguishable): ")
        (write %UNRES) (newline)
        (display "foreign tbl: ") (write (%int* %FWORDS %word-size))
        (display " bytes, ") (write %FCOUNT) (display " entries, ")
        (write (%flen %CALLS 0)) (display " of them type-call") (newline)
        (display "IMAGE TOTAL: ")
        (write (%int+ hdrn (%int+ (%int* %TWORDS %word-size)
                            (%int+ (%int* %SWORDS %word-size)
                             (%int+ (%int* %FWORDS %word-size)
                              (%int+ (%int* extw %word-size)
                                     (%int+ (%int* objw %word-size) blobn)))))))
        (display " bytes -> ") (display %IMG) (newline))))
(def %write-to
  (fn (_ fd n extw objw blobn hdrn)
    (do (%wr fd %hdr-p hdrn)
        (%wr fd %t-p (%int* %TWORDS %word-size))
        (%wr fd %s-p (%int* %SWORDS %word-size))
        (%wr fd %f-p (%int* %FWORDS %word-size))
        (%wr fd %ext-p (%int* extw %word-size))
        (%wr fd %obj-p (%int* objw %word-size))
        (%wr fd %blob-p blobn)
        (Sys close fd)
        (%report-image n extw objw blobn hdrn))))
(def %finish
  (fn (_ r1 r2)
    (%write-to (Sys open-write %IMG)
               (first (first r1))
               (first (first r2))
               (first (rest (first r2)))
               (rest (rest (first r2)))
               (%emit-header (first (first r1))
                             (first (rest (first r2)))
                             (rest (rest (first r2)))))))

; A null buffer would segfault on the first put, and the fault would look like
; a walk bug rather than an out-of-memory.  Say so here instead.
(if (eq? (Ptr ->int %ext-p) 0) (Err raise 'state "writer: ext buffer alloc failed" ()) ())
(if (eq? (Ptr ->int %obj-p) 0) (Err raise 'state "writer: obj buffer alloc failed" ()) ())
(if (eq? (Ptr ->int %blob-p) 0) (Err raise 'state "writer: blob buffer alloc failed" ()) ())

(%collect)
(display "live objects:  ") (write (%hc)) (newline)

; PASS 0 -- both tables, BEFORE the mark and unfiltered.
;
; Neither discovery needs to know what is REACHABLE, only what exists, so
; neither may spend the one mark this process has (see image-walk.x).  Running
; here also lets them `def` freely: the def discipline binds only between the
; mark and the last stamping walk.  Both tables must be COMPLETE before then,
; because the emit pass looks entries up and may not add them.
; The type table comes first: naming a shared call pointer needs its type's
; name, so %TTABLE has to exist before the foreign table is assembled.
(def %TTABLE (first (%walk-all (pair 1 2) %ty-discover ())))
(def %TCOUNT (%flen %TTABLE 0))
(def %TWORDS (%emit-ttable %TTABLE 0))
(def %CPSCAN (first (%walk-all (pair 1 2) %cp-scan (pair () ()))))
(def %CALLS (%cp-entries (first %CPSCAN) (rest %CPSCAN) ()))
(def %EXTRAS (first (%walk-all (pair 1 2) %discover ())))
(def %FTABLE (%append %CALLS (%append %EXTRAS %MAP)))
(def %FCOUNT (%flen %FTABLE 0))
(def %FWORDS (%emit-ftable %FTABLE 0))
; No walk at all: the statics come from the declared paths, not the heap.
(def %STATICS (%st-rows %base-paths ()))
(def %SCOUNT (%flen %STATICS 0))
(def %SWORDS (%emit-stable %STATICS 0))

; A reference emitted as 0 means NIL, so an unresolvable one is invisible in
; the file -- it looks exactly like an empty list.  Count them here, where the
; two cases are still distinguishable: a target that is neither stampable
; (flagged) nor a declared static cannot be written down at all.
(def %unres
  (fn (_ p acc) (%over-units p %unres-unit acc)))
(def %unres-unit
  (fn (_ k w acc)
    (if (eq? k 0)
      (if (eq? w 0) acc
        (if (%flagged? (%i->p w)) acc
          (if (eq? (%f-index %STATICS w 1) 0) (%int+ acc 1) acc)))
      acc)))
(def %UNRES (first (%walk-all (pair 1 2) %unres 0)))

(%mark! (%base) %TRACE)
; ONE expression, no `def` between the mark and the last walk: a def repoints
; an environment pair, which is itself traced, at a value pass 1 never stamped.
((fn (_ r1) (%finish r1 (%walk (pair 1 2) %emit (pair 0 (pair 0 0)))))
 (%walk (pair 1 2) %stamp (pair 0 0)))
(%clear! %TRACE)
