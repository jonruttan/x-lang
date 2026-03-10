; ash.x -- ASH shell personality for x-lang
;
; Usage:
;   cat lang/ash/lib/ash.x - | ./x
;   (sh-tokenize "echo hello | grep h")
;   (sh-parse "echo hello | grep h")
;   (sh-eval "echo hello | grep h")

; Load x-lang standard library
(include "lib/x-core.x")

; Load shell token types
(include "lang/ash/lib/tokens.x")

; Load parser
(include "lang/ash/lib/parser.x")

; Load evaluator
(include "lang/ash/lib/eval.x")

; ASH REPL hooks — suppress prompt and result echo
(repl-prompt! (fn () (display "$ ")))
(repl-eval! (fn (result) ()))
