; Test harness: x-core.x + posix + hash + compile (no numeric types)
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/posix.x"
  (pair "lib/x/hash.x"
  (pair "lib/x/compile.x"
    (first %include-list-cell)))))
(include "lib/x/posix.x")
(include "lib/x/hash.x")
(include "lib/x/compile.x")
