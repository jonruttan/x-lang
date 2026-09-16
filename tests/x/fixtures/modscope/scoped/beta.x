(module scoped/beta)
; beta.x -- a second scoped fixture with the SAME private name as alpha's,
; and its own export.
(def %helper (fn (_ n) (* n 10)))
(def beta-tenfold (fn (_ n) (%helper n)))
(provide scoped/beta beta-tenfold)
