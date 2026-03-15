; constructs.x -- Kernel construct declarations (XEON)
;
; Kernel uses $ prefix for all operative forms.

(
  ($vau      (fmt . head-kw) (scope . params-env) (branch . none))
  ($define!  (fmt . head-1)  (scope . bind)       (branch . none))
  ($lambda   (fmt . head-kw) (scope . params)     (branch . none))
  ($if       (fmt . head-1)  (scope . none)       (branch . cond))
  ($let      (fmt . head-1)  (scope . let)        (branch . none))
  ($let*     (fmt . head-1)  (scope . let)        (branch . none))
  ($letrec   (fmt . head-1)  (scope . let)        (branch . none))
  ($sequence (fmt . body)    (scope . none)       (branch . none))
  ($when     (fmt . head-1)  (scope . none)       (branch . cond))
  ($unless   (fmt . head-1)  (scope . none)       (branch . cond))
)
