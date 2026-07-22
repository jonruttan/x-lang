; predicates.x -- Type predicates
;
; Defines type-checking predicates using only C primitives.
; No library dependencies.

; same? (identity) and eq? (value equality) are C primitives. eq? compares
; immediate scalars (int, char) by value and falls back to identity, so it
; still covers nil, booleans, and interned symbols too.
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj-meta-ref (prim-ref (lit obj) (lit meta-ref)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %integer->char (prim-ref (lit int) (lit ->char)))



(def null? (fn (_ x) (eq? x ())))

(def %type-pair (%type-of (pair 1 2)))
(def %type-int (%type-of 0))
(def %type-str (%type-of ""))
(def %type-sym (%type-of (lit a)))
(def %type-char (%type-of (%integer->char 0)))
(def %type-proc (%type-of (fn (_ ) ())))
(def %type-prim (%type-of eq?))
(def %type-op (%type-of (op (_ ) ())))

(def pair? (fn (_ x) (%type? x %type-pair)))
(def not (fn (_ x) (match (x #f) (#t #t))))
(def atom? (fn (_ x) (not (pair? x))))
(def number? (fn (_ x) (%type? x %type-int)))
(def str? (fn (_ x) (%type? x %type-str)))
(def symbol? (fn (_ x) (%type? x %type-sym)))
(def char? (fn (_ x) (%type? x %type-char)))
(def procedure?
  (fn (_ x)
    (match
      ((%type? x %type-proc) #t)
      ((%type? x %type-prim) #t)
      (#t #f))))
; Operatives (op) are a distinct callable from applicatives: they receive
; their arguments unevaluated, so procedure? deliberately excludes them.
(def operative? (fn (_ x) (%type? x %type-op)))

; Source line of an object (0 if no metadata)
(def %line-of (fn (_ obj) (%obj-meta-ref obj 0)))

; NOTE: this module loads before the doc system (x/doc/doc.x), so it cannot
; wrap its provide in (doc ...). Its module description is registered
; retroactively in x/doc/doc-prims.x.
(provide x/core/predicates
  null? pair? not atom? number? str? symbol? char? procedure? operative?
  )
