; whole-plain.x -- a file scoped/whole includes, with no header: its forms
; are evaluated where the include stands, in the module.
(def %plain-secret 5)
(def whole-plain (fn (_) (+ %count %plain-secret)))
