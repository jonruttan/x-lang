; Test harness: x-core.x + regex.x only
(include "lib/x-core.x")
(set-first! %include-list-cell
  (pair "lib/x/sys/regex.x" (first %include-list-cell)))
(include "lib/x/sys/regex.x")
