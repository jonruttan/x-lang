(module scoped/marks)
; marks.x -- an export the provide marks (global NAME), which is bound in the
; root, beside a plain one, which is not.
(def marks-six (fn (_) 6))
(def marks-plain (fn (_) 60))
(provide scoped/marks (global marks-six) marks-plain)
