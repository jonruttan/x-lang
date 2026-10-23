; whole-step.x -- a file of scoped/whole: its definitions are the module's.
(module scoped/whole)
(def %step-by 1)
(def whole-step! (fn (_) (set! %count (+ %count %step-by)) %count))
