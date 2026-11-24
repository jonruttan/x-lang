; run.x -- the fixture bundle's entry.  See bundle.xon.
;
; Writes the program's arguments, which is all the gate reads, and exits as
; an application does: a main that returns hands over to a session.
(module argprobe/run)
(import x/sys/posix)
(def main (fn (_) (do (write (rest (Sys args (lit program)))) (Sys exit 0))))
(provide argprobe/run main)
