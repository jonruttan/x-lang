; Test harness: x-core.x + bignum.x + float.x (numeric tower up to float)
(include "lib/x-core.x")
(do
  (%set-first! %include-list-cell
    (pair "lib/x/num/bignum.x"
    (pair "lib/x/num/float.x"
      (first %include-list-cell))))
  (include "lib/x/num/bignum.x")
  (include "lib/x/num/float.x")

  ())
