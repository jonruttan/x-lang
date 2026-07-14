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

(def %boot-cell?
  (fn (_ %bc-x)
    (match
      ((%boot-type? %bc-x %list-type) #t)
      (#t (%boot-type? %bc-x %pair-type)))))

(def %do-nest
  (fn (self %dn-f)
    (match
      ((eq? (rest %dn-f) ()) (first %dn-f))
      ((%boot-cell? (rest %dn-f))
        (pair
          (lit %seq)
          (pair (first %dn-f) (pair (self (rest %dn-f)) ()))))
      (#t (error "do: improper body (dotted tail)")))))

(def %do-seq
  (op %do-f
    %do-e
    (match
      ((eq? %do-f ()) ())
      ; Tail-eval (NOT eval) so the expansion runs in %do-e (the caller's
      ; env): ops are lexically scoped, so any (def ...) in the body must
      ; resolve to the caller's frame, not do's own frame.  eval-with-env
      ; save/restores env around a synchronous eval and so does NOT
      ; propagate env to the TCO continuation that %seq produces.
      ((%boot-cell? %do-f) (tail-eval (%do-nest %do-f) %do-e))
      (#t (error "do: improper body (dotted tail)")))))

(def do %do-seq)

(def begin do)
