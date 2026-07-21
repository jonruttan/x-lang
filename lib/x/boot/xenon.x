; boot/xenon.x -- the xenon dialect body: everything but the launcher
;
; Included by the lib/xe.x entry (#95).  The (repl) launcher cannot ride
; a nested (include ...): the REPL reads the CURRENT input source, so
; inside an include frame it meets the file's EOF and exits instead of
; reading the session's stdin.  The entry therefore keeps the launcher at
; stream top level and includes this body.  (Same extraction idiom as
; boot/tower-compiled.x.)

; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")

; Load the x/xe module (parsed through all compiled analysers).  Pre-registered
; so a later (import x/xe) is a no-op.  This body registers itself too: the
; entry and shim load it via raw `include`, which does not register
; (pre-seed invariant, check-boot-order).
(set-first! %include-list-cell
  (pair "lib/x/boot/xenon.x"
  (pair "lib/x/xe.x" (first %include-list-cell))))
(include "lib/x/xe.x")

; ANSI colour already loaded by x-core.x -- a second include here re-captured
; the wrapped %repl-print as %saved-repl-print, making (Ansi disable-repl)
; "restore" the highlighted printer.

(set! %lang-name "xenon")
(set! %lang-version x-lib-version)
