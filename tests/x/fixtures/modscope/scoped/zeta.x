(module scoped/zeta)
; zeta.x -- a scoped module that provides a name it never defines.
(def zeta-one 1)
(provide scoped/zeta zeta-one zeta-two)
