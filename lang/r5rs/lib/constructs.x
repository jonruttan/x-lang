; constructs.x -- R5RS construct declarations (XEON)
;
; Extends x-lang constructs with Scheme-specific forms.

(
  (define  (fmt . head-1)  (scope . bind)    (branch . none))
  (lambda  (fmt . head-kw) (scope . params)  (branch . none))
  (let*    (fmt . head-1)  (scope . let)     (branch . none))
  (letrec  (fmt . head-1)  (scope . let)     (branch . none))
  (case    (fmt . head-1)  (scope . none)    (branch . clauses))
  (delay   (fmt . call)    (scope . none)    (branch . none))
  (quote   (fmt . call)    (scope . skip)    (branch . none))
)
