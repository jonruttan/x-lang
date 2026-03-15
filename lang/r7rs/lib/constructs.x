; constructs.x -- R7RS construct declarations (XEON)
;
; Extends R5RS constructs with R7RS-specific forms.

(
  (case-lambda        (fmt . body)    (scope . none)  (branch . clauses))
  (define-record-type (fmt . head-1)  (scope . bind)  (branch . none))
  (let-values         (fmt . head-1)  (scope . let)   (branch . none))
  (parameterize       (fmt . head-1)  (scope . none)  (branch . none))
)
