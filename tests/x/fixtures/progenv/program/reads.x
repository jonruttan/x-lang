(module program/reads)
; reads.x -- a scoped fixture loaded after the program has started: it
; calls the library's `note` as it loads, as compile.x does.
(def %noted (note "a section"))
(def reads-noted (fn (_) (null? %noted)))
(provide program/reads reads-noted)
