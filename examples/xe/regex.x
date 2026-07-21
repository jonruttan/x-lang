; regex.x -- Regular expression examples
;
; Usage:
;   sh x.sh -l xe -f examples/xe/regex.x

; Literal regex syntax
(def email-pattern #/[a-z]+@[a-z]+\.[a-z]+/)

(display "pattern: ")
(write email-pattern)
(newline)

; Match test -- subject-last, like every class method
(display "match 'user@example.com': ")
(display (Regex match "user@example.com" email-pattern))
(newline)

(display "match 'not-an-email': ")
(display (Regex match "not-an-email" email-pattern))
(newline)

; A regex is callable as a value: the pattern dispatches to its class
(display "value-call: ")
(display (email-pattern match "user@example.com"))
(newline)
