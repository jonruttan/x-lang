; ash.x -- ASH shell personality for x-lang
;
; Usage:
;   cat lang/ash/lib/ash.x - | ./x
;   (sh-tokenize "echo hello | grep h")
;   (sh-eval "echo hello | grep h")

; Load x-lang standard library
(include "lib/x-core.x")

; Load POSIX wrappers via FFI
(include "lib/x/posix.x")

; Load shell token types
(include "lang/ash/lib/tokens.x")

; Load evaluator (combined parser-evaluator)
(include "lang/ash/lib/eval.x")

