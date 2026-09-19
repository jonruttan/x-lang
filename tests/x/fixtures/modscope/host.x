; host.x -- an unscoped fixture, imported, that loads a scoped file by path.
; The shape of x/boot/tower-compiled, which includes x/type/hash.  A plain
; export stays in its module, so this reads it through the module's
; environment.
(include "./scoped/hosted.x")
(def host-thirteen
  (fn (_) (+ ((eval (lit hosted-twelve) (module scoped/hosted))) 1)))
