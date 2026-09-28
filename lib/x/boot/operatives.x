; operatives.x -- Minimal boot operatives
;
; Only defines do/begin using C primitives.
; Everything else uses match directly until if is available.

; Walk-cell type handles, from probe cells: boot runs before the predicate
; layer (no pair? yet), so the walkers below test their walk cells with the
; type prims directly (catalog-fetched -- the type ns is de-registered).
; A dotted body -- (do 7 . 5), e.g. from a malformed numeric literal read
; as 7 . 5 -- would otherwise reach the unchecked rest prim and evaluate a
; value word as an expression: the C core does not bounds-check (it is the
; processor); the walker that ACCEPTS the program does the checking, here.
; TWO handles: reader-built cells and pair-prim cells carry different types
; (and differ per dialect -- x-base vs x-core), so probe each honestly.
(def %boot-type? (prim-ref (lit type) (lit ?)))
(def %list-type ((prim-ref (lit type) (lit of)) (lit (0))))
(def %pair-type ((prim-ref (lit type) (lit of)) (pair () ())))

; The form that runs a body of three or more forms, (%seq a (%seq b ... (%seq y
; z))).  Each rest is checked before any form runs, so a dotted body raises with
; nothing evaluated.  The innermost %seq takes the body's own last cell, (y z),
; as its operand list.
(def %do-nest
  (fn (self %dn-f)
    (match
      ((match ((%boot-type? (rest %dn-f) %list-type) #f)
              ((%boot-type? (rest %dn-f) %pair-type) #f)
              (#t #t))
        (error "do: improper body (dotted tail)"))
      ((eq? (rest (rest %dn-f)) ()) (pair (lit %seq) %dn-f))
      (#t (pair (lit %seq) (pair (first %dn-f) (pair (self (rest %dn-f)) ())))))))

; A cell is tested by a match over the type prims, which allocates nothing,
; where a helper would cost a call per test.  One form is tail-evaluated as it
; is, two are handed to %seq in the body's own cells, and only a longer body
; builds a nest.
(def %do-seq
  (op %do-f
    %do-e
    (match
      ((eq? %do-f ()) ())
      ((match ((%boot-type? %do-f %list-type) #f)
              ((%boot-type? %do-f %pair-type) #f)
              (#t #t))
        (error "do: improper body (dotted tail)"))
      ; Tail-eval (NOT eval) so the body runs in %do-e (the caller's env):
      ; ops are lexically scoped, so any (def ...) in the body must resolve
      ; to the caller's frame, not do's own frame.  eval-with-env
      ; save/restores env around a synchronous eval and so does NOT
      ; propagate env to the TCO continuation that %seq produces.
      ((eq? (rest %do-f) ()) (tail-eval (first %do-f) %do-e))
      ((match ((%boot-type? (rest %do-f) %list-type) #f)
              ((%boot-type? (rest %do-f) %pair-type) #f)
              (#t #t))
        (error "do: improper body (dotted tail)"))
      ((eq? (rest (rest %do-f)) ()) (tail-eval (pair (lit %seq) %do-f) %do-e))
      (#t (tail-eval (%do-nest %do-f) %do-e)))))

(def do %do-seq)

(def begin do)
