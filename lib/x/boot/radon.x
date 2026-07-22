; boot/radon.x -- the radon dialect body: everything but the launcher
;
; Included by the lib/rn.x entry (#95).  The (repl) launcher cannot ride
; a nested (include ...): the REPL reads the CURRENT input source, so
; inside an include frame it meets the file's EOF and exits instead of
; reading the session's stdin.  The entry therefore keeps the launcher at
; stream top level and includes this body.  (Same extraction idiom as
; boot/tower-compiled.x.)

; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")

; Load the x/rn extensions (parsed through all compiled analysers).  Pre-registered
; so a later (import x/rn) is a no-op.  This body registers itself too: the
; entry and shim load it via raw `include`, which does not register
; (pre-seed invariant, check-boot-order).
(%set-first! %include-list-cell
  (pair "lib/x/boot/radon.x"
  (pair "lib/x/rn.x" (first %include-list-cell))))
(include "lib/x/rn.x")

; ANSI colour already loaded by x-core.x -- a second include here re-captured
; the wrapped %repl-print as %saved-repl-print, making (Ansi disable-repl)
; "restore" the highlighted printer.

(set! %lang-name "radon")
(set! %lang-version x-lib-version)
