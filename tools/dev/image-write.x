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
(include "engine/tools/contract/obj-layout.x")
(def %o->p (prim-ref (lit obj) (lit ->ptr)))
(def %p->o (prim-ref (lit ptr) (lit ->obj)))
(def %i->p (prim-ref (lit int) (lit ->ptr)))
(def %rw   (prim-ref (lit ptr) (lit ref-word)))
(def %int+ (prim-ref (lit int) (lit +)))
(def %int& (prim-ref (lit int) (lit &)))
(def %collect (prim-ref (lit heap) (lit collect)))
(def %hc (prim-ref (lit heap) (lit count)))
(def %mark! (prim-ref (lit heap) (lit tree-mark!)))
(def %clear! (prim-ref (lit heap) (lit chain-clear!)))
(def %TRACE 1024)
(def %heap-off  (* %obj-slot-heap  %word-size))
(def %flags-off (* %obj-slot-flags %word-size))
(def %next (fn (_ p) (%rw p %heap-off)))
(def %traced? (fn (_ p) (if (eq? (%int& (%rw p %flags-off) %TRACE) 0) #f #t)))

(def %walk
  (fn (_ cur f acc) (%walk-on cur f acc 0 0)))
(def %walk-on
  (fn (_ cur f acc n seen)
    (%walk-after cur f
      (if (%traced? (%o->p cur)) (f (%o->p cur) acc) acc)
      n
      (if (%traced? (%o->p cur)) (%int+ seen 1) seen))))
(def %walk-after
  (fn (_ cur f acc n seen)
    (do (if (eq? (%int& n 1023) 0) (%collect) ())
        (if (eq? (%next (%o->p cur)) 0)
            (pair acc seen)
            (%walk-on (%p->o (%i->p (%next (%o->p cur)))) f acc
                      (%int+ n 1) seen)))))

; --- shapes ---------------------------------------------------------------
(def %int- (prim-ref (lit int) (lit -)))
(def %int* (prim-ref (lit int) (lit *)))
(def %shr  (prim-ref (lit int) (lit >>)))
(def %ilt  (prim-ref (lit int) (lit <)))
(def %psw  (prim-ref (lit ptr) (lit set-word!)))
(def %p->s (prim-ref (lit ptr) (lit ->str)))
(def %blen (prim-ref (lit str) (lit byte-len)))
(def %type-off (* %obj-slot-type %word-size))
(def %data-off (* %obj-meta-len  %word-size))
(def %meta1-off (- 0 (* 2 %word-size)))
(def %meta-bit %obj-flag-meta)
(def %flagged? (fn (_ p) (if (eq? (%int& (%rw p %flags-off) %meta-bit) 0) #f #t)))
(def %sh-count (fn (_ u) (if (eq? (%reflect-type-word u) %reflect-spair-tw) (%int+ 0 (first u)) (%int+ 0 u))))
(def %sh-mask  (fn (_ u) (if (eq? (%reflect-type-word u) %reflect-spair-tw) (%int+ 0 (rest u)) 0)))
(def %sh-desc  (fn (_ c) (if (%ilt c 0) (%int+ 1 (%int- 0 c)) c)))
(def %kind (fn (_ m i d) (%int& (%shr m (%int* 2 (if (%ilt i d) i (%int- d 1)))) 3)))
(def %cell-of (fn (_ tw) (first (%type-units-cell (%p->o (%i->p tw))))))
(def %count-of
  (fn (_ p u)
    (if (%ilt (%sh-count u) 0)
        (%int+ (%rw p %data-off) (%int- 0 (%sh-count u)))
        (%sh-count u))))
(def %word-at (fn (_ p i) (%rw p (%int+ %data-off (%int* i %word-size)))))

; over-units: fold g over each unit of P, g called (g kind word acc)
(def %over-units
  (fn (_ p g acc)
    (%over-tw p (%rw p %type-off) g acc)))
(def %over-tw
  (fn (_ p tw g acc)
    (if (eq? tw %reflect-satom-tw) (g 1 (%word-at p 0) acc)
      (if (eq? tw 0) (g 1 (%word-at p 0) acc)
        (if (eq? tw %reflect-spair-tw) (%units p g acc 0 2 0 2)
          (%over-cell p (%cell-of tw) g acc))))))
(def %over-cell
  (fn (_ p u g acc)
    (if (eq? u ())
        acc                                  ; type declares nothing
        (%units p g acc 0 (%count-of p u) (%sh-mask u) (%sh-desc (%sh-count u))))))
(def %units
  (fn (_ p g acc i n m d)
    (if (eq? i n)
        acc
        (%units p g (g (%kind m i d) (%word-at p i) acc) (%int+ i 1) n m d))))

; --- pass 1: stamp an index, and count types that cannot state an extent ---
(def %refuses? (fn (_ p) (if (eq? (%rw p %type-off) %reflect-satom-tw) #f
  (if (eq? (%rw p %type-off) 0) #f
    (if (eq? (%rw p %type-off) %reflect-spair-tw) #f
      (eq? (%cell-of (%rw p %type-off)) ()))))))
(def %stamp
  (fn (_ p acc)
    (do (if (%flagged? p) (%psw p %meta1-off (%int+ (first acc) 1)) ())
        (pair (%int+ (first acc) 1)
              (if (%refuses? p) (%int+ (rest acc) 1) (rest acc))))))

; --- libc doors: raw fd I/O, memcpy, malloc -------------------------------
; The asm-cache rule applies here too: NOTHING WALKS BYTES.  Strings reach the
; blob through memcpy, one call per string, never a character loop.
(def %lib ((prim-ref (lit ffi) (lit dlopen)) () 1))
(def %dlsym (prim-ref (lit ffi) (lit dlsym)))
(def %pcall (prim-ref (lit ptr) (lit call)))
(def %p->i (prim-ref (lit ptr) (lit ->int)))
(def %c-creat  (%dlsym %lib "creat"))
(def %c-write  (%dlsym %lib "write"))
(def %c-close  (%dlsym %lib "close"))
(def %c-malloc (%dlsym %lib "malloc"))
(def %c-calloc (%dlsym %lib "calloc"))
(def %c-memcpy (%dlsym %lib "memcpy"))

; Buffers are allocated BEFORE the mark, so they are themselves traced and
; land in the image.  That is the writer-in-its-own-base problem the document
; records; a prototype pays it and says so rather than hiding it.
(def %EXT-CAP  (* 8 1000000))
(def %OBJ-CAP  (* 8 6000000))
(def %BLOB-CAP (* 8  400000))
(def %ext-p  (%i->p (%pcall %c-malloc %EXT-CAP)))
(def %obj-p  (%i->p (%pcall %c-malloc %OBJ-CAP)))
; calloc, not malloc: every blob entry ends in a NUL, and zeroed memory
; already has one.  ptr set! reads a slot as an OBJECT and segfaults on raw
; memory, so there is no byte poke available to write one.
(def %blob-p (%i->p (%pcall %c-calloc 1 %BLOB-CAP)))

(def %put (fn (_ p i w) (do (%psw p (%int* i %word-size) w) (%int+ i 1))))

; A ref resolves to the target's stamped index; 0 for nil, and 0 for a static,
; which is what the foreign table will carry instead (not yet emitted).
(def %ref-index
  (fn (_ w)
    (if (eq? w 0) 0
      (if (%flagged? (%i->p w)) (%rw (%i->p w) %meta1-off) 0))))

; acc = (obj-cursor . blob-cursor), both in units of their own buffer
(def %emit-unit
  (fn (_ k w acc)
    (if (eq? k 2) (%emit-bytes w acc)
      (pair (%put %obj-p (first acc) (if (eq? k 0) (%ref-index w) w))
            (rest acc)))))
(def %emit-bytes
  (fn (_ w acc)
    (%emit-bytes-at w acc (%blen (%p->s (%i->p w))) (rest acc))))
(def %emit-bytes-at
  (fn (_ w acc n off)
    (do (%psw %blob-p off n)
        (%pcall %c-memcpy (%int+ (%p->i %blob-p) (%int+ off %word-size)) w n)
        (pair (%put %obj-p (first acc) off)
              (%int+ off (%int+ %word-size (%int+ n 1)))))))

; One object record: type word, flags, then its units.  The extent table gets
; this object's unit count, so pass one of the loader is a straight loop.
(def %emit-obj
  (fn (_ p acc)
    (%emit-units p
      (pair (%put %obj-p (%put %obj-p (first (rest acc)) (%rw p %type-off))
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
(def %wr (fn (_ fd p n) (%pcall %c-write fd p n)))
(def %hdr-p (%i->p (%pcall %c-malloc 512)))
(def %emit-header
  (fn (_ n objw blobn)
    (do (%psw %hdr-p 0 1196247384)          ; "XIMG" little-endian
        (%psw %hdr-p (* 1 %word-size) 1)    ; format version
        (%psw %hdr-p (* 2 %word-size) %word-size)
        (%psw %hdr-p (* 3 %word-size) 1)    ; byte-order probe
        (%psw %hdr-p (* 4 %word-size) n)    ; object count
        (%psw %hdr-p (* 5 %word-size) objw) ; object-table words
        (%psw %hdr-p (* 6 %word-size) blobn); blob bytes
        (%psw %hdr-p (* 7 %word-size) 0)    ; root index -- not yet named
        (* 8 %word-size))))

(def %wr (fn (_ fd p n) (%pcall %c-write fd p n)))
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
        (display "IMAGE TOTAL: ")
        (write (%int+ hdrn (%int+ (%int* extw %word-size)
                                  (%int+ (%int* objw %word-size) blobn))))
        (display " bytes -> ") (display %IMG) (newline))))
(def %write-to
  (fn (_ fd n extw objw blobn hdrn)
    (do (%wr fd %hdr-p hdrn)
        (%wr fd %ext-p (%int* extw %word-size))
        (%wr fd %obj-p (%int* objw %word-size))
        (%wr fd %blob-p blobn)
        (%pcall %c-close fd)
        (%report-image n extw objw blobn hdrn))))
(def %finish
  (fn (_ r1 r2)
    (%write-to (%pcall %c-creat %IMG 420)
               (first (first r1))
               (first (first r2))
               (first (rest (first r2)))
               (rest (rest (first r2)))
               (%emit-header (first (first r1))
                             (first (rest (first r2)))
                             (rest (rest (first r2)))))))

; A null buffer would segfault on the first put, and the fault would look like
; a walk bug rather than an out-of-memory.  Say so here instead.
(if (eq? (%p->i %ext-p) 0) (Err raise 'state "writer: ext buffer alloc failed" ()) ())
(if (eq? (%p->i %obj-p) 0) (Err raise 'state "writer: obj buffer alloc failed" ()) ())
(if (eq? (%p->i %blob-p) 0) (Err raise 'state "writer: blob buffer alloc failed" ()) ())

(%collect)
(display "live objects:  ") (write (%hc)) (newline)
(%mark! (%base) %TRACE)
; ONE expression, no `def` between the mark and the last walk: a def repoints
; an environment pair, which is itself traced, at a value pass 1 never stamped.
((fn (_ r1) (%finish r1 (%walk (pair 1 2) %emit (pair 0 (pair 0 0)))))
 (%walk (pair 1 2) %stamp (pair 0 0)))
(%clear! %TRACE)
