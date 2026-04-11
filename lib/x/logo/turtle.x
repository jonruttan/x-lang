; turtle.x -- Logo turtle graphics interpreter (aggregator)

(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/logo/dispatch)
(import x/logo/math)
(import x/logo/tstate)
(import x/logo/indent)
(import x/logo/repl)
(import x/logo/json)

(provide x/logo/turtle
  ; state
  turtle-forward turtle-back turtle-right turtle-left
  turtle-penup turtle-pendown turtle-clearscreen
  %turtle-on-bc %turtle-on-clear %turtle-bc
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
  turtle-json turtle-json-str turtle-bc-str)
