; host.x -- an unscoped fixture, imported, that loads a scoped file by path.
; The shape of x/boot/tower-compiled, which includes x/type/hash.
(include "./scoped/hosted.x")
(def host-thirteen (fn (_) (+ (hosted-twelve) 1)))
