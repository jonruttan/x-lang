; # Computational Expressions in C
;
; ## lib/x/type/catalog.x -- bridge the primitives catalog onto the object system
;
; @description Each primitives-catalog namespace (str, int, char, ...) is
;   installed as a CamelCase class (Str, Int, Char, ...) whose static methods
;   delegate to the cataloged prims, so (Int append ...) etc. reach them via
;   the object system.  This is the transitional home for the prims as the
;   newer object system supersedes the flat catalog + bare-name env
;   registration.  A namespace whose CamelCase name is already bound -- e.g.
;   the existing Str (StrUTF8) protocol class -- is skipped, to be converged
;   with the object system as a deliberate later step rather than clobbered.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

; Namespace symbol -> CamelCase class-name symbol (str -> Str, io -> Io).
(def %capitalize
  (fn (_ s)
    (let ((cs (symbol->str s)))
      (str->symbol
        (str-append
          (list->str (list (char-upcase (str-ref cs 0))))
          (substring cs 1 (str-length cs)))))))

; Build a class from a catalog namespace: one static method per cataloged prim.
; The wrapper takes TWO ignored leading params -- a plain fn's first param
; auto-binds to the fn itself, and %class-dispatch (object.x) passes the class
; as the next arg -- so (_ _ . args) absorbs both and forwards the rest.
(def %catalog-class
  (fn (_ name ns)
    (%make-class name () () ()
      (map (fn (_ entry)
             (let ((p (rest entry)))
               (pair (first entry) (fn (_ _ . args) (apply p args)))))
           (prim-domain ns))
      ())))

; A class name is installable iff it is not already bound, so the existing Str
; protocol class (and any other live binding) is never clobbered.
(def %catalog-free? (fn (_ nm) (guard (e #t) (do (eval! nm) #f))))

; Auto-discover and install: bind (def <Class> <class>) for every catalog
; namespace whose CamelCase name is free.  Built as one top-level (do ...) and
; eval!'d so the defs land in the global env.
(eval! (pair (lit do)
  (map (fn (_ ns) (let ((nm (%capitalize ns))) (list (lit def) nm (%catalog-class nm ns))))
       (filter (fn (_ ns) (%catalog-free? (%capitalize ns))) (map first (prims))))))
