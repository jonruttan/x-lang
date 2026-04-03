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
      (#t (eval (%do-nest %do-f))))))

(def do %do-seq)

(def begin do)
