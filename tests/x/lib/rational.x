; Test harness: x-core.x + bignum + float + rational
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/bignum.x"
  (pair "lib/x/float.x"
  (pair "lib/x/rational.x"
    (first %include-list-cell)))))
(include "lib/x/bignum.x")
(include "lib/x/float.x")
(include "lib/x/rational.x")
