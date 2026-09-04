; image-walk.x -- one heap walk and one unit reader, shared by the image tools.
;
; Included by tools/dev/image-write.x and tools/dev/image-foreign.x.  It is a
; file rather than a copy in each because the three rules below were each
; learned by breaking them, and a second copy is a second place to relearn.
;
;   (%walk start f acc)  ->  (acc . visited)
;
; f is called (f p acc) for each TRACED object, p a pointer to it.  VISITED is
; returned so a vacuous walk is visible: a pass reporting a clean zero over
; zero objects is not a clean pass.
;
;   * NOTHING WALKS BYTES.  An interpreted per-byte loop costs hundreds of
;     evals a byte.  This is lib/x/tool/asm-cache.x's rule, for its reason.
;   * NO `def` BETWEEN THE MARK AND THE LAST WALK.  A def repoints an
;     environment pair -- itself a traced object in the image -- at a value
;     the stamping pass never saw, and each one surfaces as an unresolved
;     reference.  Measured: three extra defs, three extra unresolved.
;   * THE CURSOR IS AN OBJECT, NEVER A POINTER.  An object held in a parameter
;     is rooted, so a collect cannot free it under the walk; a PTR roots
;     nothing it addresses.  The first version collected on iteration zero,
;     freed its own cursor, visited nothing, and reported a clean zero of
;     everything -- which reads exactly like success.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

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

; %walk visits only TRACED objects and so needs a mark; %walk-all visits every
; object on the chain and needs none.  That distinction is forced, not stylish:
;
;   MARK ONCE PER PROCESS.  (heap chain-clear!) permanently disables any later
;   (heap tree-mark!) -- marking twice with no clear between is idempotent and
;   fine, but a mark AFTER a clear flags nothing at all, silently, and every
;   subsequent walk then reports a clean zero of everything.  So a pass that
;   needs no reachability must not spend the one mark: it uses %walk-all and
;   runs BEFORE the mark, which also lets it `def` its results freely.
(def %walk     (fn (_ cur f acc) (%walk-on cur f acc 0 0 #t)))
(def %walk-all (fn (_ cur f acc) (%walk-on cur f acc 0 0 #f)))
(def %take? (fn (_ p filt) (if filt (%traced? p) #t)))
(def %walk-on
  (fn (_ cur f acc n seen filt)
    (%walk-after cur f
      (if (%take? (%o->p cur) filt) (f (%o->p cur) acc) acc)
      n
      (if (%take? (%o->p cur) filt) (%int+ seen 1) seen) filt)))
(def %walk-after
  (fn (_ cur f acc n seen filt)
    (do (if (eq? (%int& n 1023) 0) (%collect) ())
        (if (eq? (%next (%o->p cur)) 0)
            (pair acc seen)
            (%walk-on (%p->o (%i->p (%next (%o->p cur)))) f acc
                      (%int+ n 1) seen filt)))))

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


; How a type word is tagged.  Three of the four are not heap types at all --
; nil-typed, the static ATOM sentinel, the structural PAIR sentinel -- and none
; of those carries a navigable type pointer, so every consumer branches here
; before dereferencing one.
(def %T-NIL 0)
(def %T-ATOM 1)
(def %T-PAIR 2)
(def %T-HEAP 3)
(def %ty-kind
  (fn (_ tw)
    (if (eq? tw 0) %T-NIL
      (if (eq? tw %reflect-satom-tw) %T-ATOM
        (if (eq? tw %reflect-spair-tw) %T-PAIR %T-HEAP)))))

