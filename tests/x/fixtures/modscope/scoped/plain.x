; plain.x -- no header: loads through include, in the root, as before.
(def %plain-helper 7)
(def plain-seven (fn (_) %plain-helper))
(provide scoped/plain plain-seven)
