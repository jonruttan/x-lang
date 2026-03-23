; Test harness: x-core.x + hash.x only
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/sys/hash.x" (first %include-list-cell)))
(include "lib/x/sys/hash.x")
