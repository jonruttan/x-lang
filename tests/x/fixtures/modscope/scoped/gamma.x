(module scoped/gamma)
; gamma.x -- provides a name alpha already owns.
(def alpha-twice (fn (_ n) n))
(provide scoped/gamma alpha-twice)
