; turtle.x -- Logo turtle graphics interpreter (aggregator)
;
; Imports all Logo modules and re-exports their public symbols.
; Individual modules:
;   state.x    — turtle state and movement primitives
;   types.x    — Logo tokenizer base and type definitions
;   expr.x     — expression parser (recursive descent)
;   dispatch.x — command table and interpreter loop
;   indent.x   — indentation-to-blocks pre-processor
;   repl.x     — interactive REPL with multiline block reading
;   json.x     — segment JSON output

(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/logo/dispatch)
(import x/logo/indent)
(import x/logo/repl)
(import x/logo/json)

(provide x/logo/turtle
  ; state
  turtle-forward turtle-back turtle-right turtle-left
  turtle-penup turtle-pendown turtle-clearscreen
  %turtle-on-segment %turtle-on-clear
  ; types
  %logo-base %logo
  ; expr
  %logo-functions
  ; dispatch
  logo-process-tokens
  ; indent
  %logo-indent-to-blocks
  ; repl
  logo-repl %logo-on-exit %logo-on-command
  ; json
  turtle-json turtle-json-str)
