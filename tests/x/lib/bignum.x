; Test harness: x-core.x + bignum.x only (no float/rational/complex)
(include "lib/x-core.x")
(do
  (set-first! %include-list-cell
    (pair "lib/x/num/bignum.x" (first %include-list-cell)))
  (include "lib/x/num/bignum.x")

  ())
