; Test harness: x-core.x + hash.x only
(include "lib/x-core.x")
(do
  (set-first! %include-list-cell
    (pair "lib/x/sys/hash.x" (first %include-list-cell)))
  (include "lib/x/sys/hash.x")

  ())
