; ash.x -- ASH shell personality for x-lang
;
; Phase 1: parser only (tokenizer + recursive descent -> AST)
;
; Usage:
;   cat lang/ash/lib/ash.x - | ./x
;   (sh-tokenize "echo hello | grep h")
;   (sh-parse "echo hello | grep h")

; Load x-lang standard library
(include "lib/x-core.x")

; Load shell token types
(include "lang/ash/lib/tokens.x")
