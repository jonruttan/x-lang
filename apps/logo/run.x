; logo.x -- Logo turtle graphics dialect
;
; Usage:  x.sh -l apps/logo/run  (formerly `-l logo`)
(include "lib/x-core.x")
; The Logo app lives outside the stdlib (#35): arm its root, then load.
(import-path! "apps")
(include "apps/logo/main.x")
(logo-repl)
