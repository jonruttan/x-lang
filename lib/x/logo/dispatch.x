; dispatch.x -- Logo command dispatch and interpreter
(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/logo/indent)
(import x/sys/posix)

; ============================================================
; File reader (uses read-char with stdin redirection)
; ============================================================

(def %c-read (dlsym (dlopen () 1) "read"))
(def %c-malloc (dlsym (dlopen () 1) "malloc"))
(def %c-free (dlsym (dlopen () 1) "free"))

(def %logo-slurp-file
  (fn (_ path)
    (def fd (sh-open-read path))
    (if (< fd 0) (error (str "Cannot open: " path)))
    (def bufsize 65536)
    (def buf (int->ptr (ptr-call %c-malloc bufsize)))
    (def %read-all
      (fn (self acc)
        (def n (ptr-call %c-read fd buf (- bufsize 1)))
        (if (<= n 0) acc
          (do (ptr-set! buf n 0 1)
              (self (str acc (ptr->str buf)))))))
    (def content (%read-all ""))
    (ptr-call %c-free buf)
    (sh-close fd)
    content))

; ============================================================
; Command table
; ============================================================

(set! %logo-commands
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
    (list "HEADING" 0 (fn () %turtle-heading))
    (list "XCOR"    0 (fn () %turtle-x))
    (list "YCOR"    0 (fn () %turtle-y))
    (list "REPEAT"  -1 ())
    (list "TO"      -1 ())
    (list "IF"      -1 ())
    (list "STOP"    -1 ())
    (list "RETURN"  -1 ())
    (list "PRINT"   -1 ())
    (list "TYPE"    -1 ())
    (list "EXECUTE" -1 ())
    (list "LOAD"    -1 ())))

; ============================================================
; Variable management
; ============================================================

(def %logo-var-set!
  (fn (_ name value)
    (def uname (str-upcase name))
    (def %update
      (fn (self vars)
        (match
          ((null? vars) #f)
          ((str=? (first (first vars)) uname)
            (set-rest! (first vars) value) #t)
          (#t (self (rest vars))))))
    (if (%update %logo-vars) ()
      (set! %logo-vars (pair (pair uname value) %logo-vars)))))

; ============================================================
; STOP / RETURN sentinel tags
; ============================================================

(def %logo-stop-tag (pair (lit logo-stop) ()))
(def %logo-return-tag (pair (lit logo-return) ()))

(def %is-stop? (fn (_ v) (eq? v %logo-stop-tag)))
(def %is-return? (fn (_ v) (and (pair? v) (eq? (first v) %logo-return-tag))))

; ============================================================
; Argument consumption (delegates to expression parser)
; ============================================================

(def %logo-consume-arg
  (fn (_ tokens) (%logo-parse-one-expr tokens)))

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
; Token list utilities
; ============================================================

; Take tokens until pointer-equal to stop
(def %take-until
  (fn (_ toks stop)
    (def %go
      (fn (self toks acc)
        (if (eq? toks stop) (reverse acc)
          (self (rest toks) (pair (first toks) acc)))))
    (%go toks ())))

(def %skip-one-expr ())
(def %skip-parens ())

; Skip one expression worth of tokens (no evaluation)
; Returns remaining tokens after the expression
(set! %skip-one-expr
  (fn (_ tokens)
    (if (null? tokens) tokens
      (let ((tok (first tokens))
            (rest-t (rest tokens)))
        ; Skip primary
        (def after-primary
          (match
            ((number? tok) rest-t)
            ((float? tok)  rest-t)
            ((%is-string? tok) rest-t)
            ((%is-block? tok)  rest-t)
            ((%is-paren? tok "(") (%skip-parens rest-t 1))
            ((%is-op-str? tok "-") (%skip-one-expr rest-t))
            (#t
              ; Word — check for fn call: word(args)
              (if (and (not (null? rest-t)) (%is-paren? (first rest-t) "("))
                (%skip-parens (rest rest-t) 1)
                rest-t))))
        ; Skip trailing infix operators
        (if (and (not (null? after-primary))
                 (> (%op-precedence (first after-primary)) 0))
          (%skip-one-expr (rest after-primary))
          after-primary)))))

; Skip tokens until matching close paren (depth tracking)
(set! %skip-parens
  (fn (_ tokens depth)
    (if (null? tokens) tokens
      (if (= depth 0) tokens
        (match
          ((%is-paren? (first tokens) "(") (%skip-parens (rest tokens) (+ depth 1)))
          ((%is-paren? (first tokens) ")") (%skip-parens (rest tokens) (- depth 1)))
          (#t (%skip-parens (rest tokens) depth)))))))

; Consume word + one expression worth of tokens (no evaluation)
(def %consume-word-and-expr
  (fn (_ tok rest-tokens)
    (def after (%skip-one-expr rest-tokens))
    (pair (pair tok (%take-until rest-tokens after))
          after)))

; ============================================================
; PRINT helper
; ============================================================

(def %logo-print-value
  (fn (_ val)
    (match
      ((null? val)   (display "()"))
      ((eq? val #t)  (display "TRUE"))
      ((eq? val #f)  (display "FALSE"))
      (#t            (display val)))))

; ============================================================
; Forward declarations
; ============================================================

(def %logo-do-repeat ())
(def %logo-do-if ())
(def %logo-dispatch ())
(def %logo-dispatch-special ())

; ============================================================
; Main dispatcher
; ============================================================

(set! logo-process-tokens
  (fn (_ tokens)
    (if (null? tokens) ()
      (if (sigint-check) (error %logo-stop-tag)
      (let ((tok (first tokens))
            (remaining (rest tokens)))
        (def word (%logo-word tok))
        (match
          ((null? word)
            (logo-process-tokens remaining))
          ((and (not (null? remaining))
                (%is-op-str? (first remaining) "<-"))
            (let ((r (%logo-consume-arg (rest remaining))))
              (%logo-var-set! word (first r))
              (logo-process-tokens (rest r))))
          (#t
            (%logo-dispatch word remaining))))))))

(set! %logo-dispatch
  (fn (_ word remaining)
    (def entry (%logo-lookup word))
    (if (null? entry)
      (logo-process-tokens remaining)
      (let ((arity (%cmd-arity entry))
            (handler (%cmd-handler entry)))
        (match
          ((= arity 0)
            (handler)
            (logo-process-tokens remaining))
          ((>= arity 1)
            (let ((result (%logo-consume-n-args arity remaining)))
              (apply handler (first result))
              (logo-process-tokens (rest result))))
          (#t
            (%logo-dispatch-special (str-upcase word) remaining)))))))

(set! %logo-dispatch-special
  (fn (_ uword remaining)
    (match
      ((str=? uword "REPEAT") (%logo-do-repeat remaining))
      ((str=? uword "TO")     (logo-process-to remaining))
      ((str=? uword "IF")     (%logo-do-if remaining))
      ((str=? uword "STOP")   (error %logo-stop-tag))
      ((str=? uword "RETURN")
        (let ((r (%logo-consume-arg remaining)))
          (error (pair %logo-return-tag (first r)))))
      ((str=? uword "PRINT")
        (let ((r (%logo-consume-arg remaining)))
          (%logo-print-value (first r))
          (newline)
          (logo-process-tokens (rest r))))
      ((str=? uword "TYPE")
        (let ((r (%logo-consume-arg remaining)))
          (%logo-print-value (first r))
          (logo-process-tokens (rest r))))
      ((str=? uword "EXECUTE")
        (let ((r (%logo-consume-arg remaining)))
          (def code (first r))
          (logo-process-tokens
            (token-read-string %logo-base (str code " ")))
          (logo-process-tokens (rest r))))
      ((str=? uword "LOAD")
        (let ((r (%logo-consume-arg remaining)))
          (def filename (first r))
          (def content (%logo-slurp-file filename))
          (def tokens (token-read-string %logo-base (str content " ")))
          (logo-process-tokens (%logo-indent-to-blocks tokens))
          (logo-process-tokens (rest r))))
      (#t (error (str "Unknown special: " uword))))))

; ============================================================
; REPEAT
; ============================================================

(set! %logo-do-repeat
  (fn (_ tokens)
    (if (null? tokens) (error "REPEAT: expected arguments")
      (if (%logo-word=? (first tokens) "FOREVER")
        ; REPEAT FOREVER [block]
        (let ((r (%logo-consume-arg (rest tokens))))
          (def block (first r))
          (def %loop
            (fn (self)
              (guard (err
                  (if (%is-stop? err) () (error err)))
                (logo-process-tokens (%block-contents block))
                (self))))
          (%loop)
          (logo-process-tokens (rest r)))
        ; REPEAT count [block] or REPEAT [block] UNTIL cond
        (let ((r1 (%logo-consume-arg tokens)))
          (if (%is-block? (first r1))
            ; REPEAT [block] UNTIL cond
            (let ((block (first r1))
                  (after-block (rest r1)))
              (if (not (%logo-word=? (first after-block) "UNTIL"))
                (error "REPEAT: expected UNTIL after block")
                (let ((cond-tokens (rest after-block)))
                  (def %loop
                    (fn (self)
                      (guard (err
                          (if (%is-stop? err) () (error err)))
                        (logo-process-tokens (%block-contents block))
                        (let ((cr (%logo-parse-expr cond-tokens)))
                          (if (first cr)
                            (logo-process-tokens (rest cr))
                            (self))))))
                  (%loop))))
            ; REPEAT count [block]
            (let ((r2 (%logo-consume-arg (rest r1))))
              (def count (%as-int (first r1)))
              (def block (first r2))
              (def %rep
                (fn (self i)
                  (if (> i 0)
                    (do (logo-process-tokens (%block-contents block))
                        (self (- i 1)))
                    ())))
              (%rep count)
              (logo-process-tokens (rest r2)))))))))

; ============================================================
; Consume one command from token list, return (cmd-tokens . rest)
; ============================================================

(def %consume-one-command
  (fn (_ tokens)
    (if (null? tokens) (pair () ())
      (let ((tok (first tokens))
            (rest-t (rest tokens))
            (word (%logo-word (first tokens))))
        (match
          ((%is-block? tok) (pair (list tok) rest-t))
          ((null? word)     (pair (list tok) rest-t))
          (#t
            (let ((entry (%logo-lookup word)))
              (if (null? entry) (pair (list tok) rest-t)
                (let ((arity (%cmd-arity entry)))
                  (match
                    ((= arity 0)  (pair (list tok) rest-t))
                    ((>= arity 1) (%consume-word-and-expr tok rest-t))
                    (#t
                      (let ((uword (str-upcase word)))
                        (match
                          ((str=? uword "STOP")   (pair (list tok) rest-t))
                          ((str=? uword "RETURN") (%consume-word-and-expr tok rest-t))
                          ((str=? uword "PRINT")  (%consume-word-and-expr tok rest-t))
                          ((str=? uword "TYPE")   (%consume-word-and-expr tok rest-t))
                          (#t (pair tokens ())))))))))))))))

; ============================================================
; IF: decomposed into condition parser + clause consumer
; ============================================================

; Parse condition, handling NOT and EITHER prefixes.
; Returns (test-value . remaining-tokens-after-condition)
(def %parse-if-condition
  (fn (_ tokens)
    (def first-word (%logo-word (first tokens)))
    (def has-not (and (not (null? first-word))
                      (str=? (str-upcase first-word) "NOT")))
    (def has-either (and (not (null? first-word))
                         (str=? (str-upcase first-word) "EITHER")))
    (def cond-tokens
      (if (or has-not has-either) (rest tokens) tokens))
    (def cond-result (%logo-parse-expr cond-tokens))
    (def cond-val (first cond-result))
    (def after-cond (rest cond-result))
    ; EITHER: parse second condition after comma
    (def final-cond
      (if has-either
        (if (and (not (null? after-cond))
                 (%is-op-str? (first after-cond) ","))
          (let ((r2 (%logo-parse-expr (rest after-cond))))
            (set! after-cond (rest r2))
            (or cond-val (first r2)))
          cond-val)
        cond-val))
    (pair (if has-not (not final-cond) final-cond)
          after-cond)))

; Expect THEN keyword, consume one THEN command and optional ELSE command.
; Returns remaining tokens after both clauses.
(def %parse-then-else
  (fn (_ test-val after-cond)
    (if (null? after-cond) (error "IF: expected THEN"))
    (if (not (%logo-word=? (first after-cond) "THEN"))
      (error "IF: expected THEN"))
    (def after-then (rest after-cond))
    (def then-cmd (%consume-one-command after-then))
    (def then-tokens (first then-cmd))
    (def after-then-cmd (rest then-cmd))
    (def has-else
      (and (not (null? after-then-cmd))
           (%logo-word=? (first after-then-cmd) "ELSE")))
    (def else-cmd
      (if has-else
        (%consume-one-command (rest after-then-cmd))
        (pair () after-then-cmd)))
    (def else-tokens (first else-cmd))
    (def remaining (rest else-cmd))
    (if test-val
      (logo-process-tokens then-tokens)
      (if has-else (logo-process-tokens else-tokens) ()))
    remaining))

(set! %logo-do-if
  (fn (_ tokens)
    (if (null? tokens) (error "IF: expected condition")
      (let ((cond-result (%parse-if-condition tokens)))
        (def test-val (first cond-result))
        (def after-cond (rest cond-result))
        (def remaining (%parse-then-else test-val after-cond))
        (logo-process-tokens remaining)))))

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
                (match
                  ((%is-block? tok) (list params tok (rest toks)))
                  ((%is-paren? tok "(") (self params (rest toks)))
                  ((%is-paren? tok ")") (self params (rest toks)))
                  ((%is-op-str? tok ",") (self params (rest toks)))
                  (#t (self (pair (%logo-word tok) params) (rest toks))))))))
        (def result (%read-params () rest-toks))
        ; Upcase param names once at definition time
        (def param-names
          (map str-upcase (reverse (first result))))
        (def body (first (rest result)))
        (def remaining (first (rest (rest result))))
        (def n-params (length param-names))
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
            (def result
              (guard (err
                  (set! %logo-vars saved-vars)
                  (match
                    ((%is-stop? err) ())
                    ((%is-return? err) (rest err))
                    (#t (error err))))
                (logo-process-tokens (%block-contents body))
                ()))
            (set! %logo-vars saved-vars)
            result))
        (set! %logo-commands
          (pair (list name n-params proc) %logo-commands))
        (logo-process-tokens remaining)))))

(provide x/logo/dispatch
  %logo-commands %logo-lookup %logo-vars %logo-var-set!
  logo-process-tokens logo-process-to
  %logo-stop-tag %logo-return-tag)
