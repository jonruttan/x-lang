; regex.x -- Regular expression examples
;
; Usage:
;   sh x.sh -l x-and -f examples/and/regex.x

; Literal regex syntax
(def email-pattern #/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/)

(display "pattern: ")
(write email-pattern)
(newline)

; Match test
(display "match 'user@example.com': ")
(display (regex-match email-pattern "user@example.com"))
(newline)

(display "match 'not-an-email': ")
(display (regex-match email-pattern "not-an-email"))
(newline)
