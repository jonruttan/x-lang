; broken.x -- a scoped fixture whose third form fails while it loads.
(module scoped/broken)
(def broken-ok 1)
(undefined-at-load 1)
(provide scoped/broken broken-ok)
