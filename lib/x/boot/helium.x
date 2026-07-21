; boot/helium.x -- the helium dialect body: everything but the launcher
;
; Shared by the lib/he.x entry and the lib/x.x default shim (#95).  The
; (repl) launcher cannot ride a nested (include ...): the REPL reads the
; CURRENT input source, so inside an include frame it meets the file's
; EOF and exits instead of reading the session's stdin.  Entries and
; shims therefore keep the launcher at stream top level and include this
; body.  (Same extraction idiom as boot/tower-compiled.x.)
(include "lib/x-core.x")
; Pre-seed invariant (check-boot-order): loaded via raw `include` from the
; entry/shim, which does not register -- self-register or a later import
; of this path reloads it mid-session.
(set-first! %include-list-cell
  (pair "lib/x/boot/helium.x" (first %include-list-cell)))
(set! %lang-name "helium")
(set! %lang-version x-lib-version)
