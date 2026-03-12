; ash.x -- ASH shell personality for x-lang (interactive)
;
; Usage:
;   cat lang/ash/lib/ash.x - | ./x
;   (sh-tokenize "echo hello | grep h")
;   (sh-eval "echo hello | grep h")

(include "lang/ash/lib/ash-base.x")
(set %repl-prompt "$ ")
(set %lang-name "ASH Shell")
(set %lang-version x-lib-version)
(%banner)
(repl)
