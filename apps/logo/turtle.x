; turtle.x -- Logo turtle graphics interpreter (aggregator)

(import logo/state)
(import logo/types)
(import logo/expr)
(import logo/dispatch)
(import logo/math)
(import logo/tstate)
(import logo/indent)
(import logo/repl)
(import logo/json)

(provide logo/turtle
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
