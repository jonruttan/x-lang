; Test harness: x-core.x + posix + hash + compile (no numeric types)
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/sys/posix.x"
  (pair "lib/x/sys/hash.x"
  (pair "lib/x/tool/compile.x"
    (first %include-list-cell)))))
(include "lib/x/sys/posix.x")
(include "lib/x/sys/hash.x")
(include "lib/x/tool/compile.x")
