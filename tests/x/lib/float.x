; Test harness: x-core.x + bignum.x + float.x (numeric tower up to float)
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/bignum.x"
  (pair "lib/x/float.x"
    (first %include-list-cell))))
(include "lib/x/bignum.x")
(include "lib/x/float.x")
