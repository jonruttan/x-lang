; lib.x -- a scoped module that asks to be compiled wherever an image is
; built with (image compiled), for compile-root!.
(module fcmk/lib)
(import x/core/doors int+)
(def image-compiled #t)
(def lib-inc (fn (_ n) (int+ n 1)))
(provide fcmk/lib lib-inc)
