; Test harness: x-core.x + float + the Logo app's turtle kernel.
;
; Repo-root cwd, like every harness in this directory: the includes below
; are root-relative, and spec-runner.awk cats this file onto the engine's
; STDIN rather than including it, so there is no file directory to resolve
; against.  `make test-x` runs from the root.
;
; THE APP ROOT IS THE SEAM.  apps/ is where the Logo tree sits today, and
; this is the harness half of a pair whose other half is run.x's
; %logo-app-root -- when Logo moves to its own bundle those are the two
; lines that follow it (docs/personality-contract.md).  Named rather than
; inlined so the pair greps as a pair, and spelled the same on both sides.
;
; CHECKED, because the unchecked failure is illegible.  import-path! arms
; whatever it is handed, so a root that is not there does not fail here:
; it fails later, inside (import logo/turtle), as `include: cannot open`
; with NO FILENAME -- which the runner reports as "interpreter died
; mid-batch (crash, OOM, or the 60s timeout)" on all 83 tests, naming none
; of the three.  That is three inference steps from "the app is not where
; I looked", the same distance the -I check in
; tools/check/path-literals.sh exists to close.
;
; THE MESSAGE GOES TO STDOUT, and that is not a slip: spec-runner.awk runs
; the engine with 2>/dev/null, so a raise alone is swallowed and changes
; nothing a reader sees.  On stdout it lands in the first test's `got:`,
; which is the one place the diagnosis is actually read.  The raise still
; follows, to stop the batch rather than let 82 more tests time out.
(include "lib/x-core.x")
(def %bigint ())
(include "lib/x/num/float.x")
(def %logo-app-root "apps")
(unless (%file-exists? (%path-join %logo-app-root "logo/turtle.x"))
  (do
    (display "logo harness: no Logo tree under '" %logo-app-root
             "' -- run the spec suite from the repo root\n")
    (Err raise 'io "logo harness: app root not found" ())))
(import-path! %logo-app-root)
; import, not include: include would sidestep the pre-seed and double-load
; turtle.x's own deps.
(import logo/turtle)
