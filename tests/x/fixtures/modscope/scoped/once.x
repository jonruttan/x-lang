; once.x -- a scoped fixture loaded by include-once rather than import.
(module scoped/once)
(def %once-secret 7)
(def once-seven (fn (_) %once-secret))
(provide scoped/once once-seven)
