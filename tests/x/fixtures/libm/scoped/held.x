; A scoped module that binds a libm function of its own through libm-fn, the
; way a lang bundle does, under a private name of its module.  The float
; harness imports it, so the harness's state image holds this module: the
; writer's transient thunk and the recache hook meet a held row whose name
; lives in a frame float's module cannot reach.

(module scoped/held)
(import x/num/float libm-fn)

(def %held-erf (libm-fn (lit %held-erf) "d->d" "erf"))

; erf of X, a FLOAT, through the held closure.
(def held-erf (fn (_ x) (%held-erf x)))

(provide scoped/held held-erf)
