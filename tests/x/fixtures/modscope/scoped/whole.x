; whole.x -- a scoped fixture written in two files: this one includes the
; other, which is headed with the same name.
(module scoped/whole)
(def %count 0)
(include-once "./whole-step.x")
(include-once "./whole-plain.x")
(def whole-read (fn (_) %count))
(provide scoped/whole whole-step! whole-read whole-plain)
