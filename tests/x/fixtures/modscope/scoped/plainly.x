; plainly.x -- a scoped fixture loaded by a plain include.
(module scoped/plainly)
(def %plainly-secret 11)
(def plainly-eleven (fn (_) %plainly-secret))
(provide scoped/plainly plainly-eleven)
