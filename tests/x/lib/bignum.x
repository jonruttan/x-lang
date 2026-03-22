; Test harness: x-core.x + bignum.x only (no float/rational/complex)
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/bignum.x" (first %include-list-cell)))
(include "lib/x/bignum.x")
