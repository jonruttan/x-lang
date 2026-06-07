; # Computational Expressions in C
;
; ## lib/x/type/catalog.x -- bridge the primitives catalog onto the object system
;
; @description Each primitives-catalog namespace (int, char, ...) becomes a
;   CamelCase class (Int, Char, ...) whose static methods delegate to the
;   cataloged prims, so they are reached through the object system --
;   (Int + 2 3) -> 5.  This is the transitional home for the prims as the newer
;   object system supersedes the flat catalog + bare-name env registration.
;   Per namespace, by its target class name (default CamelCase, or an override):
;     - unbound        -> a fresh class is defined
;     - existing class -> the prims fold onto it as static methods, skipping any
;                         name the class already resolves (own or inherited), so
;                         canonical methods are never shadowed
;     - other binding  -> skipped, so live values (list, iter, ...) are kept
;   Overrides place a namespace's prims on a different class than its CamelCase
;   name: the byte-level str prims belong on Str8 (byte strings), not on the
;   UTF-8 Str (which already supersedes them via Str8's string protocol).
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

; Namespace symbol -> CamelCase class-name symbol (int -> Int, io -> Io).
(def %capitalize
  (fn (_ s)
    (let ((cs (symbol->str s)))
      (str->symbol
        (str-append
          (list->str (list (char-upcase (str-ref cs 0))))
          (substring cs 1 (str-length cs)))))))

; Target-class overrides: a namespace whose prims attach to a class other than
; its CamelCase name.  str (byte-level) -> Str8 (byte strings).
(def %catalog-targets (list (pair (lit str) (lit Str8))))
(def %catalog-target
  (fn (_ ns) (let ((o (assoc-get ns %catalog-targets)))
    (if (null? o) (%capitalize ns) o))))

; A namespace's static methods: one wrapper per cataloged prim.  The wrapper
; takes TWO ignored leading params -- a plain fn's first param auto-binds to
; the fn itself, and %class-dispatch (object.x) passes the class as the next
; arg -- so (_ _ . args) absorbs both and forwards the rest to the prim.
(def %catalog-statics
  (fn (_ ns)
    (map (fn (_ entry)
           (let ((p (rest entry)))
             (pair (first entry) (fn (_ _ . args) (apply p args)))))
         (prim-domain ns))))

; A fresh class holding a namespace's prims as static methods.
(def %catalog-class
  (fn (_ name ns) (%make-class name () () () (%catalog-statics ns) ())))

; Fold a namespace's prims onto an existing class as static methods, skipping
; any name the class already resolves (own or inherited, via %lookup) so
; canonical methods are never shadowed.  Mutate the s-methods entry's tail
; (set-rest! on a plain alist pair) -- NOT the class object's slot 0:
; set-first! on a typed class object is unchecked and corrupts the heap.
(def %catalog-fold!
  (fn (_ class ns)
    (let ((entry (List assoc (lit s-methods) (%class-data class))))
      (let ((adds (filter (fn (_ e) (null? (%lookup class (lit s-methods) (first e))))
                          (%catalog-statics ns))))
        (set-rest! entry (append adds (rest entry)))))))

; Install one class per catalog namespace.  Built as a single top-level (do ...)
; and eval!'d so the (def ...)s land in the global env.  `existing` is read
; during the map -- before the do runs -- so a class created this pass is never
; re-folded; only classes that pre-date the catalog (e.g. Str8) are folded onto.
(eval! (pair (lit do)
  (map (fn (_ ns)
         (let ((nm (%catalog-target ns)))
           (let ((existing (guard (e ()) (eval! nm))))
             (if (null? existing)
               (list (lit def) nm (%catalog-class nm ns))
               (if (class? existing)
                 (list (lit %catalog-fold!) existing (list (lit lit) ns))
                 (lit ()))))))
       (map first (prims)))))
