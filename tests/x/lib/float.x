; Test harness: x-core.x + bigint.x + float.x (numeric tower up to float)
(include "lib/x-core.x")
(import x/num/bigint)
(import x/num/bigint/literal)
(import x/num/float)
(import x/num/float/literal)
; A scoped module holding a libm closure of its own, so the state image of
; this harness carries a held row whose name is a module's.
(import-path! "tests/x/fixtures/libm")
(import scoped/held)
