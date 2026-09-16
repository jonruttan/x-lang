; reads.x -- a scoped fixture whose second form reads the form after it
; from the file, which a loader that reads the file one form at a time allows.
(module scoped/reads)
(def reads-next ((prim-ref (lit io) (lit read))))
(1 2 3)
(provide scoped/reads reads-next)
