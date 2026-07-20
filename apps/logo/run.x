; logo.x -- Logo turtle graphics dialect
;
; Usage:  x.sh -l logo
; -l resolves lib/NAME.x first, then apps/NAME/run.x (x.sh #35), so the
; app name stays `logo` even though the code left the stdlib.
(include "lib/x-core.x")
; The Logo app lives outside the stdlib (#35): arm its root, then load.
(import-path! "apps")
(include "apps/logo/main.x")
(logo-repl)
