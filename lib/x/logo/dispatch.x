; dispatch.x -- Logo command dispatch and interpreter
(import x/logo/state)
(import x/logo/types)

; ============================================================
; Command table
; ============================================================

(def %logo-commands
  (list
    (list "FORWARD" 1 (fn (_ n) (turtle-forward n)))
    (list "FD"      1 (fn (_ n) (turtle-forward n)))
    (list "BACK"    1 (fn (_ n) (turtle-back n)))
    (list "BK"      1 (fn (_ n) (turtle-back n)))
    (list "RIGHT"   1 (fn (_ n) (turtle-right n)))
    (list "RT"      1 (fn (_ n) (turtle-right n)))
    (list "LEFT"    1 (fn (_ n) (turtle-left n)))
    (list "LT"      1 (fn (_ n) (turtle-left n)))
    (list "PENUP"   0 (fn () (turtle-penup)))
    (list "PU"      0 (fn () (turtle-penup)))
    (list "PENDOWN" 0 (fn () (turtle-pendown)))
    (list "PD"      0 (fn () (turtle-pendown)))
    (list "CLEARSCREEN" 0 (fn () (turtle-clearscreen)))
    (list "CS"      0 (fn () (turtle-clearscreen)))
    (list "SETHEADING" 1 (fn (_ n) (set! %turtle-heading (%as-float n))))
    (list "SETH"    1 (fn (_ n) (set! %turtle-heading (%as-float n))))
    (list "HEADING" 0 (fn () %turtle-heading))
    (list "XCOR"    0 (fn () %turtle-x))
    (list "YCOR"    0 (fn () %turtle-y))
    (list "REPEAT"  -1 ())
    (list "TO"      -1 ())))

(def %logo-lookup
  (fn (_ word)
    (def uword (str-upcase word))
    (def %find
      (fn (self cmds)
        (if (null? cmds) ()
          (if (str=? uword (first (first cmds)))
            (first cmds)
            (self (rest cmds))))))
    (%find %logo-commands)))

; ============================================================
; Variable stack (dynamic scoping for procedure parameters)
; ============================================================

(def %logo-vars ())

; ============================================================
; Token evaluation
; ============================================================

(def %logo-eval-tok
  (fn (_ tok)
    (def word (%logo-word tok))
    (if (null? word)
      (if (%is-block? tok)
        tok
        (eval! tok))
      (let ((var (assoc word %logo-vars str=?)))
        (if (null? var)
          (eval (str->symbol word))
          (rest var))))))

(def %logo-consume-arg
  (fn (_ tokens)
    (if (null? tokens) (error "Expected argument")
      (pair (%logo-eval-tok (first tokens)) (rest tokens)))))

(def %logo-consume-n-args
  (fn (_ n tokens)
    (def %consume
      (fn (self i toks acc)
        (if (= i 0)
          (pair (reverse acc) toks)
          (let ((r (%logo-consume-arg toks)))
            (self (- i 1) (rest r) (pair (first r) acc))))))
    (%consume n tokens ())))

; ============================================================
; Main dispatcher
; ============================================================

(set! logo-process-tokens
  (fn (_ tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens))
            (remaining (rest tokens)))
        (def word (%logo-word tok))
        (if (null? word)
          (logo-process-tokens remaining)
          (let ((entry (%logo-lookup word)))
            (if (null? entry)
              (logo-process-tokens remaining)
              (let ((arity (first (rest entry)))
                    (handler (first (rest (rest entry)))))
                (if (= arity 0)
                  (do (handler) (logo-process-tokens remaining))
                  (if (>= arity 1)
                    (let ((result (%logo-consume-n-args arity remaining)))
                      (apply handler (first result))
                      (logo-process-tokens (rest result)))
                    (if (str=? (str-upcase word) "REPEAT")
                      (let ((r1 (%logo-consume-arg remaining)))
                        (let ((r2 (%logo-consume-arg (rest r1))))
                          (def count (%as-int (first r1)))
                          (def block (first r2))
                          (def %rep
                            (fn (self i)
                              (if (> i 0)
                                (do
                                  (logo-process-tokens (%block-contents block))
                                  (self (- i 1)))
                                ())))
                          (%rep count)
                          (logo-process-tokens (rest r2))))
                      (if (str=? (str-upcase word) "TO")
                        (logo-process-to remaining)
                        (do
                          (error (str "Unknown special: " word))
                          (logo-process-tokens remaining)))))))))))))))

; ============================================================
; TO procedure definition
; ============================================================

(set! logo-process-to
  (fn (_ tokens)
    (if (null? tokens) (error "TO: expected name")
      (let ((name-tok (first tokens))
            (rest-toks (rest tokens)))
        (def name (str-upcase (%logo-word name-tok)))
        (def %read-params
          (fn (self params toks)
            (if (null? toks) (error "TO: expected [ body ]")
              (let ((tok (first toks)))
                (if (%is-block? tok)
                  (list params tok (rest toks))
                  (self (pair (%logo-word tok) params) (rest toks)))))))
        (def result (%read-params () rest-toks))
        (def param-names (reverse (first result)))
        (def body (first (rest result)))
        (def remaining (first (rest (rest result))))
        (def proc
          (fn (_ . logo-args)
            (def saved-vars %logo-vars)
            (def %push
              (fn (self names vals)
                (if (null? names) ()
                  (do
                    (set! %logo-vars
                      (pair (pair (first names) (first vals)) %logo-vars))
                    (self (rest names) (rest vals))))))
            (%push param-names logo-args)
            (logo-process-tokens (%block-contents body))
            (set! %logo-vars saved-vars)))
        (set! %logo-commands
          (pair (list name (length param-names) proc) %logo-commands))
        (logo-process-tokens remaining)))))

(provide x/logo/dispatch
  %logo-commands %logo-lookup %logo-vars
  %logo-eval-tok logo-process-tokens logo-process-to)
