; bool.x -- BOOL: an x-defined type claiming the C-static singletons (#101)
;
; #t and #f were nil-typed C statics, which left two holes nothing else
; could close: (+ #t 1) fell through to machine arithmetic (op_try cannot
; consult a type that is not there -- the #52 residual), and (Type of #t)
; answered nil, a documented wart. The type is defined HERE, in x, and the
; singletons are claimed with the one C instruction this needed:
; (obj retag!), which writes an object's type header slot. C prims return
; the singletons by IDENTITY, so rebinding the name #t would touch nothing
; -- the objects themselves change type. Type policy in x, C supplies one
; instruction.
;
; Everything identity-based survives retagging untouched, verified by spec:
; truthiness (if/match test isnil-or-false-singleton, never the type),
; eq? (value word), the printer's #t/#f fast path, boolean?, and Dict's
; unhashable-key refusal.
;
; The refusal ops close the #52 residual: (+ #t 1) now raises
; "no + for BOOL" through the same registry as every other non-numeric
; type (op-guard.x, loaded just before this file -- %og-refuse and %og-all
; are its globals). SYMBOLS remain the one residual: tree-typed, and
; retagging the interning tree is not an option (every symbol shares it).
;
; Idempotent: a child base re-running boot must not re-claim the shared
; singletons with its own tree -- name-interned handles compare across
; bases, so the first claim serves every base.

(def %bool-make-type (prim-ref (lit type) (lit make)))
(def %bool ())
(set! %bool
  (%bool-make-type "BOOL"
    (list
      (pair (lit write)
        (fn (_ self)
          (display (match ((eq? self #t) "#t") (#t "#f")))))
      ; THE load-bearing pair: build_struct DEFAULTS x-made types to PAIR
      ; units (right for make-instance products), but the singletons are
      ; 1-slot C-static satoms -- the collector's generic walk would read
      ; slot 0 (the "#t" text POINTER) as a child object and slot 1 off the
      ; end of the static. units 0 declares: instances of this type trace
      ; NOTHING. (Found by ASan: global-buffer-overflow 13 bytes past the
      ; "#f" string global, inside x_heap_tree_mark. Do NOT add a (lit
      ; mark) handler instead: that field is called as a C FUNCTION
      ; POINTER by the hook -- an x closure there is an instant wild jump.)
      (pair (lit units) 0))))

; push-op wants the STRUCT, reached via by-atom of the make-type return --
; the return itself is the registry handle, not the struct (float.x's
; %float-ts idiom; pushing onto the handle segfaults, found by bisecting
; boot).
(def %bool-push (prim-ref (lit type) (lit push-op)))
(def %bool-ts ((prim-ref (lit type) (lit by-atom)) %bool))
(List for-each
  (fn (_ op) (%bool-push %bool-ts op (%og-refuse (symbol->str op) "BOOL")))
  %og-all)

(def %bool-retag (prim-ref (lit obj) (lit retag!)))
(match
  ((null? (%og-type-of #t))
    (do
      (%bool-retag #t %bool)
      (%bool-retag #f %bool)))
  (#t ()))

(doc (provide x/type/bool)
  "BOOL: the boolean singletons as a real x-defined type -- (Type of #t) answers, and arithmetic on booleans refuses through the op registry instead of falling through to machine math.")
