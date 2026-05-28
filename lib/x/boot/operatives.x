; operatives.x -- Minimal boot operatives
;
; Only defines do/begin using C primitives.
; Everything else uses match directly until if is available.

(def %do-nest
  (fn (self %dn-f)
    (match
      ((eq? (rest %dn-f) ()) (first %dn-f))
      (#t
        (pair
          (lit %seq)
          (pair (first %dn-f) (pair (self (rest %dn-f)) ())))))))

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
      (#t (tail-eval (%do-nest %do-f) %do-e)))))

(def do %do-seq)

(def begin do)
