; run.x -- the fixture bundle's entry.  See bundle.xon.
;
; With the interrupt flag set, the next evaluation step raises STOP if a guard
; is active.  With none, main gets past it, records that it did and clears the
; flag, and the session that follows reads guardprobe-unguarded from this
; module.
(module guardprobe/run)
(def guardprobe-unguarded #f)
(def main
  (fn (_)
    (%set-cell-int! %sigint-flag 1)
    (set! guardprobe-unguarded #t)
    (%set-cell-int! %sigint-flag 0)))
(provide guardprobe/run main guardprobe-unguarded)
