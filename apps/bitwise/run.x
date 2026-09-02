; # x-lang -- Bitwise
;
; ## apps/bitwise/run.x -- THE entry:  x -l bitwise -- ...
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; An in-tree app is self-booting (apps/README.md): it opens with the core
; and arms its own roots.  Installed trees define %install-root
; (boot/module.x); the guard falls back to the repo-relative layout.
(include "lib/x-core.x")
(def %bitwise-root (guard (_ "apps/bitwise") (%path-join %install-root "apps/bitwise")))
(import-path! (guard (_ "apps") (%path-join %install-root "apps")))
(import bitwise/cli)
(bitwise-main args)
