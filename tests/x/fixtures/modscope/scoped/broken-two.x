; broken-two.x -- a scoped fixture in two files; its other file fails as it loads.
(module scoped/broken-two)
(include-once "./broken-two-step.x")
(provide scoped/broken-two)
