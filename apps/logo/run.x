; logo.x -- Logo turtle graphics dialect
;
; Usage:  x.sh -l logo
; -l resolves lib/NAME.x first, then apps/NAME/run.x (x.sh #35), so the
; app name stays `logo` even though the code left the stdlib.
(include "lib/x-core.x")
; THE ONE PLACE THAT KNOWS WHERE THE APP LIVES.  The Logo app is outside
; the stdlib (#35), so its root is armed here -- and NAMED here, because
; the tree holds DATA as well as modules (serve.x's viewer.html) and a
; second file that re-derived the path was a second file to fix when the
; layout moved.  It was already wrong: serve.x read the viewer from a
; cwd-relative "apps/logo/viewer.html", which resolves only when cwd is
; the repo root -- so the viewer was broken in every INSTALLED tree, the
; one environment no test ran in.  An entry may carry layout literals
; (tools/check/path-literals.sh exempts apps/*/run.x); nothing else may.
; Installed trees define %install-root (see boot/module.x); the guard falls
; back to the repo-relative root when it is unbound.
(def %logo-app-root (guard (_ "apps") (%path-join %install-root "apps")))
(import-path! %logo-app-root)
(include "apps/logo/main.x")
; Batch (-f): stdin holds a Logo program, not a session -- and logo-repl's
; fd swap would discard it unread, the same bug the dialect entries had
; (see repl/banner.x).  %batch? comes from x-core via banner.x.
(if %batch? (logo-batch) (logo-repl))
