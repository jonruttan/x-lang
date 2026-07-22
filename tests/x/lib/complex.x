; Test harness: x-core.x + bignum + float + rational + complex
(include "lib/x-core.x")
(do
  (%set-first! %include-list-cell
    (pair "lib/x/num/bignum.x"
    (pair "lib/x/num/float.x"
    (pair "lib/x/num/rational.x"
    (pair "lib/x/num/complex.x"
      (first %include-list-cell))))))
  (include "lib/x/num/bignum.x")
  (include "lib/x/num/float.x")
  (include "lib/x/num/rational.x")
  (include "lib/x/num/complex.x")

  ())
