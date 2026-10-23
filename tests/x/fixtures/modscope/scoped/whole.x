; whole.x -- a scoped fixture in two files: its part sets the count it keeps.
(module scoped/whole)
(def %count 0)
(include-once "./whole-step.x")
(def whole-read (fn (_) %count))
(provide scoped/whole whole-step! whole-read)
