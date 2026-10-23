; whole-more.x -- headed with a loaded module's name and included from
; elsewhere: it joins the module.
(module scoped/whole)
(def whole-more (fn (_) (* %count 10)))
