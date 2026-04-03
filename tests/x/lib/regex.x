; Test harness: x-core.x + regex.x only
(include "lib/x-core.x")
(do
  (set-first! %include-list-cell
    (pair "lib/x/type/regex.x" (first %include-list-cell)))
  (include "lib/x/type/regex.x")

  ())
