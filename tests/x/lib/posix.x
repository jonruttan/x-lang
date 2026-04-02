; Test harness: x-core.x + posix only
(include "lib/x-core.x")
(do
  (set-first! %include-list-cell
    (pair "lib/x/sys/posix.x"
      (first %include-list-cell)))
  (include "lib/x/sys/posix.x")

  ())
