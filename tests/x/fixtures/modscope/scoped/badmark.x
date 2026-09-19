(module scoped/badmark)
; badmark.x -- an export that is neither a name nor (global name).
(def badmark-one 1)
(provide scoped/badmark (other badmark-one))
