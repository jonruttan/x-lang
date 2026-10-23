; whole-step.x -- a part of scoped/whole: its definitions are the module's.
(module-part scoped/whole)
(def %step-by 1)
(def whole-step! (fn (_) (set! %count (+ %count %step-by)) %count))
