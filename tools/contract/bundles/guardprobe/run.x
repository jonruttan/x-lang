; run.x -- the fixture bundle's entry.  See lang.xon.
;
; With the interrupt flag set, the next evaluation step raises STOP if a guard
; is active.  With none, the definition is made and the flag is cleared, and
; the session that follows can read guardprobe-unguarded.
(%set-cell-int! %sigint-flag 1)
(def guardprobe-unguarded #t)
(%set-cell-int! %sigint-flag 0)
