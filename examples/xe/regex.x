; regex.x -- Regular expression examples
;
; Usage:
;   sh x.sh -l xe -f examples/xe/regex.x

; Literal regex syntax
(def email-pattern #/[a-z]+@[a-z]+\.[a-z]+/)

(display "pattern: ")
(write email-pattern)
(display "\n" "match 'user@example.com': "
         (Regex match "user@example.com" email-pattern) "\n"
         "match 'not-an-email': " (Regex match "not-an-email" email-pattern)
         "\n" "value-call: " (email-pattern match "user@example.com") "\n")
