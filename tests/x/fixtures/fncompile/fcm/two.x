; two.x -- a scoped module that imports one-sum and defines one closure of its own.
(module fcm/two)
(import x/core/doors int+)
(import fcm/one one-sum)
(def two-f (fn (_ n) (int+ (one-sum n) 10)))
(provide fcm/two two-f)
