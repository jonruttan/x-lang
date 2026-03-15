; Coverage tests for lib/x/string.x
; Exercises all branches

; string-join -- all 3 match clauses
(string-join ", " ())                  ; empty list
(string-join ", " (list "a"))          ; single element
(string-join ", " (list "a" "b" "c"))  ; fold over rest

; string-repeat -- both branches
(string-repeat "x" 0)   ; <= 0 → ""
(string-repeat "ab" 3)  ; recurse

; string-contains? -- all clauses + empty check
(string-contains? "" "hello")     ; sub-len=0 → #t
(string-contains? "ll" "hello")   ; found → #t via go
(string-contains? "xyz" "hello")  ; not found → () via go overflow
(string-contains? "lo" "hello")   ; found at end

; string-starts? -- both branches
(string-starts? "he" "hello")    ; match
(string-starts? "lo" "hello")    ; no match
(string-starts? "toolong" "hi")  ; pfx longer than s

; string-ends? -- both branches
(string-ends? "lo" "hello")      ; match
(string-ends? "he" "hello")      ; no match
(string-ends? "toolong" "hi")    ; sfx longer than s

; string-reverse -- both branches
(string-reverse "hello")  ; normal recursion
(string-reverse "")       ; empty, i < 0 immediately
