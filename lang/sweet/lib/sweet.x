; sweet.x -- Sweet-expressions personality (interactive)
;
; SRFI-105: Curly-infix notation {a + b} -> (+ a b)
; SRFI-110: Indentation-based grouping via SWEET-WS token type
;
; Usage:
;   cat lang/sweet/lib/sweet.x - | ./x
;   {1 + 2}       -> 3
;   {2 * {3 + 4}} -> 14

(include "lang/sweet/lib/sweet-base.x")
(set %lang-name "Sweet Expressions")
(set %lang-version x-lib-version)
(%banner)
(sweet-repl)
