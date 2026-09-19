(module scoped/theta)
; theta.x -- exports a plain function under the name one of alpha's exports
; has.  A plain export stays its module's own, so the two do not meet.
(def alpha-twice (fn (_ n) (* n 100)))
(provide scoped/theta alpha-twice)
