; # Computational Expressions in C
;
; ## img.x -- the loader dialect: functions only, no object system
;
; @description The smallest library a state-image loader needs.  helium costs
;   0.88s to boot and brings a class system, a numeric surface and a reader the
;   loader never touches; this boots in 0.05s and carries only what
;   tools/dev/image-read.x reaches for: `if`/`do`, prim-ref (a base-path walk
;   and two assoc lookups), byte strings and an integer printer, the object
;   and type reflection of boot/data.x and boot/reflect.x re-derived on this
;   base, and the unit shapes of lib/x/type/shape-rows.x declared on it.
;   Every definition here is a function or an operative -- no classes, no
;   modules -- and every fact it uses comes from a contract or a shared file,
;   never a copy.  Load with `sh x.sh -l img`.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(def null? (fn (_ x) (eq? x ())))
(def not (fn (_ x) (match (x #f) (#t #t))))
(def if
  (op (test then . else)
    e
    (match
      ((eval test e) (tail-eval then e))
      ((null? else) ())
      (#t (tail-eval (first else) e)))))

; --- reaching the primitives -----------------------------------------------
; prim-ref lives in x/boot/registry.x, which needs reflect, which needs the
; path contract.  All of it is a base-path walk and two assoc lookups, so it is
; cheaper to do here than to pull the boot chain in.  The steps come from the
; contract, never from a literal: (prims base f r r r ...) is not a fact to
; copy.
(include "engine/tools/contract/base-paths.x")
(def %img-step (fn (_ v s) (if (eq? s (lit f)) (first v) (rest v))))
(def %img-walk
  (fn (self v steps)
    (if (null? steps) v (self (%img-step v (first steps)) (rest steps)))))
(def %img-row
  (fn (self rows nm)
    (if (null? rows) ()
      (if (eq? (first (first rows)) nm) (rest (rest (first rows)))
        (self (rest rows) nm)))))
(def %img-cell (fn (_ nm) (%img-walk (%base) (%img-row %base-paths nm))))
(def %img-assoc
  (fn (self k l)
    (if (null? l) ()
      (if (eq? (first (first l)) k) (rest (first l)) (self k (rest l))))))
(def prims (fn (_) (first (%img-cell (lit prims)))))
(def prim-domain (fn (_ ns) (%img-assoc ns (prims))))
(def prim-ref (fn (_ ns m) (%img-assoc m (prim-domain ns))))

; --- sequencing ------------------------------------------------------------
; do, without operatives.x.  Two OPERATIVES that hand the rest of the body to
; each other through tail-eval, the way boot/operatives.x's %do-seq nests: the
; trampoline honours a tail-eval from an operative, so (do ... (self ...))
; iterates in constant stack.  Neither `match` clause bodies nor a helper
; procedure will do: a match clause evaluates ONE form, and a tail-eval inside
; a procedure body is an ordinary call -- a 300,000-step loop segfaulted where
; the same loop on bare `match` ran.  An op body IS a sequence.
(def %img-do-rest
  (op body e
    (eval (first body) e)
    (tail-eval (pair do (rest body)) e)))
(def do
  (op body e
    (match
      ((null? body) ())
      ((null? (rest body)) (tail-eval (first body) e))
      (#t (tail-eval (pair %img-do-rest body) e)))))
(def list (fn (_ . args) args))

; --- strings ---------------------------------------------------------------
; The prims take the SUBJECT FIRST; the Str8 class is what puts it last.
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def %str-append   (prim-ref (lit str) (lit append)))
(def %str->ptr     (prim-ref (lit str) (lit ->ptr)))
(def %mem-cmp      (prim-ref (lit mem) (lit cmp)))
(def str=?
  (fn (_ a b)
    (if (eq? (%str-byte-len a) (%str-byte-len b))
        (eq? 0 (%mem-cmp (%str->ptr a) (%str->ptr b) (%str-byte-len a)))
        #f)))

; --- output ----------------------------------------------------------------
; The object printer is lib/x/boot/printer.x, which needs the class system.
; A loader reports counts and names, so bytes and integers are the whole
; vocabulary: anything that wants a real (write obj) can ask the loaded image
; to do it, which is a better proof of life than the host's printer anyway.
(def display (prim-ref (lit io) (lit write-str)))
(def newline (fn (_) (display "\n")))
(def %img-digits "0123456789")
(def num->str
  (fn (self n)
    (if (< n 10)
        (%str-byte-sub %img-digits n 1)
        (%str-append (self (/ n 10))
                     (%str-byte-sub %img-digits (% n 10) 1)))))
(def say-num (fn (_ n) (display (num->str n))))

; --- object and type reflection --------------------------------------------
; The same derivations as lib/x/boot/data.x and lib/x/boot/reflect.x, which a
; loader cannot load: reflect.x is four files deep into the boot chain.  These
; are re-derived from the machine and from the path contract, never copied
; constants -- the one number below, 4294967296, is 2^32, which is what makes
; the probe a width test.
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
(def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
(def %word-size (if (< 0 (%ptr->int (%int->ptr 4294967296))) 8 4))

(include "engine/tools/contract/obj-layout.x")
(def %reflect-type-off (* %obj-slot-type %word-size))
(def %reflect-type-word
  (fn (_ o) (%ptr-ref-word (%obj->ptr o) %reflect-type-off)))
(def %reflect-type-alist-cell (%img-cell (lit type-alist)))
(def %reflect-satom-tw
  (%reflect-type-word ((prim-ref (lit type) (lit of)) 0)))
(def %reflect-spair-tw
  (%reflect-type-word (rest (first (first %reflect-type-alist-cell)))))
; The loader calls this after its install (docs/state-image-format.md 5.5);
; img caches nothing an image moves, so there is nothing to recompute.
(def %image-recache! (fn (_) ()))

; Type slots are base-paths rows too, rooted at the type object rather than at
; (%base) -- so the same walker reaches them, given the type.
(def %img-of (fn (_ o nm) (%img-walk o (%img-row %base-paths nm))))
(def %type-units-cell (fn (_ t) (%img-of t (lit type-units-stack))))
(def %type-name       (fn (_ t) (%img-of t (lit type-name))))

; --- data-slot access ------------------------------------------------------
; (obj ref) and (obj set!) are not engine primitives: boot/data.x and
; boot/reflect.x define them and file them into the catalog under those
; names, so in a bare base the coordinate is simply absent.  One addressing
; formula for both halves, as data.x insists, so a read and a write can never
; name different words.
(def %ptr->obj      (prim-ref (lit ptr) (lit ->obj)))
(def %ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))
(def %data-offset   (* %word-size %obj-meta-len))
(def %data-word-off (fn (_ i) (+ %data-offset (* i %word-size))))
(def %obj-ref
  (fn (_ o i)
    (%ptr->obj (%int->ptr (%ptr-ref-word (%obj->ptr o) (%data-word-off i))))))
(def %obj-set!
  (fn (_ o i v)
    (%ptr-set-word! (%obj->ptr o) (%data-word-off i) (%ptr->int (%obj->ptr v)))
    v))

; A prim-ref that answers () for a coordinate that is not there is the
; registry's contract, and it is the wrong one for a loader: calling () in a
; bare base does not fail, it returns whatever the nil call handler returns.
(def prim!
  (fn (_ ns m)
    ((fn (_ p) (if (null? p) (error "no such primitive") p)) (prim-ref ns m))))

; --- unit shapes -----------------------------------------------------------
; The same declarations helium makes at boot (lib/x/type/type.x), on this base.
; Without them a fresh base says every unit is a reference, and an image
; rebuild reading a type's units then walks a STRING's byte pointer as an
; object.  Guarded the same way type.x guards it: an engine without the
; coordinate simply leaves the types undeclared.
(include "lib/x/type/shape-rows.x")
(def %img-kind-code
  (fn (self k rows)
    (if (null? rows) (error (pair (lit type-shape-unknown-kind) k))
      (if (eq? (first (first rows)) k) (rest (first rows)) (self k (rest rows))))))
(def %img-kind-mask
  (fn (self ks acc scale)
    (if (null? ks) acc
      (self (rest ks) (+ acc (* scale (%img-kind-code (first ks) %type-kind-codes)))
            (* scale 4)))))
(def %img-shape-row
  (fn (self rows nm)
    (if (null? rows) ()
      (if (str=? (first (first rows)) nm) (first rows) (self (rest rows) nm)))))
(def %img-declare-shape!
  (fn (_ ts)
    ((fn (_ row)
       (if (null? row) ()
         ((prim-ref (lit type) (lit set-shape!))
          ts (first (rest row)) (%img-kind-mask (first (rest (rest row))) 0 1))))
     (%img-shape-row %type-shape-rows (%type-name ts)))))
(def %img-declare-shapes!
  (fn (self alist)
    (if (null? alist) ()
      (do (%img-declare-shape! (rest (first alist))) (self (rest alist))))))
(if (null? (prim-ref (lit type) (lit set-shape!)))
  ()
  (%img-declare-shapes! (first %reflect-type-alist-cell)))
