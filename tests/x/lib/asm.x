; Test harness: x-core.x + asm.x
(include "lib/x-core.x")
(do
  (%set-first! %include-list-cell
    (pair "lib/x/tool/asm.x" (first %include-list-cell)))
  (include "lib/x/tool/asm.x")

  ())
