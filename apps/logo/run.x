; logo.x -- Logo turtle graphics dialect
;
; Usage:  x.sh -l logo
; -l resolves lib/NAME.x first, then apps/NAME/run.x (x.sh #35), so the
; app name stays `logo` even though the code left the stdlib.
(include "lib/x-core.x")
; The Logo app lives outside the stdlib (#35): arm its root, then load.
; Installed trees define %install-root (see boot/module.x); the guard falls
; back to the repo-relative root when it is unbound.
(import-path! (guard (_ "apps") (%path-join %install-root "apps")))
(include "apps/logo/main.x")
; Batch (-f): stdin holds a Logo program, not a session -- and logo-repl's
; fd swap would discard it unread, the same bug the dialect entries had
; (see repl/banner.x).  %batch? comes from x-core via banner.x.
(if %batch? (logo-batch) (logo-repl))
