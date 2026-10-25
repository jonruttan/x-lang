; wrapped.x -- a scoped fixture in two files, which the module-scope spec
; loads only through a wrapper set on include.
(module scoped/wrapped)
(def %wrapped-secret 4)
(include-once "./wrapped-part.x")
(provide scoped/wrapped wrapped-four)
