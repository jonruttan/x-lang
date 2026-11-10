; lint-image.x -- the library a lint child boots: lib/x-core.x and the linter.
;
; tools/dev/lint.sh writes a state image of this file once
; (tools/dev/image-build.sh, keyed on the library, the linter and the engine)
; and boots every lint child from it, instead of evaluating the library and
; the linter from source in each one.  The child then loads the target's
; preload and runs the driver, tools/dev/lint-run.x.  Both includes are
; root-relative: the image writer runs from the checkout's root.
(include "lib/x-core.x")
(include "tools/dev/lint.x")
