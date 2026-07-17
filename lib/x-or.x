; # Computational Expressions in C
;
; ## x-or.x -- x/or Standard Library
;
; @description x/or: Experimental/Hacking dialect.  x-core plus the shared
;   compiled numeric tower (lib/x/boot/tower-compiled.x), the x/or
;   extensions, and the interactive banner/REPL.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")

; Load x-or extensions (parsed through all compiled analysers).  Pre-registered
; so a later (import x/or) is a no-op.
(set-first! %include-list-cell
  (pair "lib/x/or.x" (first %include-list-cell)))
(include "lib/x/or.x")

; ANSI colour already loaded by x-core.x -- a second include here re-captured
; the wrapped %repl-print as %saved-repl-print, making (Ansi disable-repl)
; "restore" the highlighted printer.

(set! %lang-name "x-or")
(set! %lang-version x-lib-version)
(%banner)
(repl)
