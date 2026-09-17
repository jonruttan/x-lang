; unit.x -- a scoped fixture with a literal () among its forms, before a
; private definition.
(module scoped/unit)
()
(def %unit-after 2)
(def unit-reads (fn (_) %unit-after))
(provide scoped/unit unit-reads)
