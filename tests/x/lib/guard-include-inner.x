; guard-include-inner.x -- a guard INSIDE an included file catches its
; own raise; reading must continue in THIS file afterwards (the #242
; unwind restores to the guard's snapshot, which includes this file's
; frames -- it must not over-unwind them).
(def %gi-inner (guard (e 'inner-caught) (error "inner")))
(def %gi-inner-after 'after)
