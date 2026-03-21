; or.x -- x/or Interactive
;
; x/or: Maximal Lisp dialect built on x-lang.
; Experimental / Hacker Lisp.
(include "lang/x-or/lib/or-base.x")
(set! %lang-name "x/or")
(set! %lang-version x-lib-version)
(%banner)
(repl)
