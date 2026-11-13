; one.x -- a scoped module of two closures and a number, for compile-module!.
(module fcm/one)
(import x/core/doors int+ int*)
(def %sq (fn (_ n) (int* n n)))
(def one-sum (fn (_ n) (int+ (%sq n) 1)))
(def one-k 7)
(provide fcm/one one-sum)
