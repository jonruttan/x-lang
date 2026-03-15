; Coverage tests for lib/x-core.x
; Exercises branches in boot forms and core library

; --- let: %let-params + %let-vals ---
(let ((a 1) (b 2)) (+ a b))
(let () 42)

; --- and: expand + rewrite + cached paths ---
(and)                  ; null args → #t
(and #t)               ; single arg
(and #t #t)            ; multi-arg, first-use expand path
(and #t #t)            ; second call: cached (%expanded) path
(and #t ())            ; multi-arg, second evaluates to nil
(and () #t)            ; first is nil, short-circuit

; --- or: expand + rewrite + cached paths ---
(or)                   ; null args → ()
(or #t)                ; single arg
(or () #t)             ; multi-arg, first-use expand path
(or () #t)             ; second call: cached path
(or #t ())             ; first truthy, short-circuit
(or () ())             ; both nil

; --- Comparisons: >, <=, >= ---
(> 5 3)
(> 3 5)
(<= 3 5)
(<= 5 5)
(<= 5 3)
(>= 5 3)
(>= 5 5)
(>= 3 5)

; --- Variadic arithmetic ---
(+)            ; null → 0
(+ 5)          ; single arg
(+ 1 2 3)     ; fold
(-)            ; null → 0
(- 5)          ; single → negate
(- 10 3 2)    ; fold
(*)            ; null → 1
(* 2 3 4)     ; fold
(/)            ; null → 1
(/ 24 3 2)    ; fold

; --- peek-char exercised by just calling it ---
; (peek-char is hard to test without actual reader input)

; --- quasi: all compilation paths ---
(quasi ())                      ; null → (lit ())
(quasi 42)                      ; atom → (lit 42)
(quasi (a b c))                 ; pair → (pair (%qc first) (%qc rest))
(def x 99)
(quasi (unquote x))             ; unquote → value
(def lst (list 1 2))
(quasi (a (unquote-splicing lst) b))  ; splicing → append

; --- guard ---
(guard (err err) (error "test"))   ; error path: handler receives error
(guard (err ()) (+ 1 2))          ; normal path: no error

; --- string=? ---
(string=? "hello" "hello")  ; same length, same content
(string=? "hello" "world")  ; same length, different content
(string=? "hi" "hello")     ; different length

; --- %repl-print ---
(%repl-print 42)        ; non-nil: write + newline
(%repl-print ())        ; nil: just newline

; --- Banner: set %lang-name to exercise banner code ---
(set %lang-name "TestLang")
(set %lang-version "1.0")
(%banner)                ; exercises lang-name + lang-version branches
(set %lang-version ())
(%banner)                ; exercises null %lang-version branch
(set %lang-name ())
(%banner)                ; exercises null %lang-name branch
