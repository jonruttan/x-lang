; sweet.x -- Sweet-expressions personality (SRFI-105/110)
;
; Follows the LIST type pattern (src/x-token/sexp/list.c):
;   LIST matches ( as a single char, reader recursively reads
;   elements via x_token_read until ) sentinel, builds list.
;   SWEET-CURLY does the same for { }, plus infix->prefix transform.
;
; Usage:
;   cat lang/sweet/lib/sweet.x - | ./x
;   {1 + 2}       -> 3
;   {2 * {3 + 4}} -> 14

(do
  (include "lang/r5rs/lib/r5rs.x")

  ; --- Buffer helpers (not in r5rs, needed for type handlers) ---

  (define (buffer-len buf)
    (- (first-int (cdr buf)) (first-int buf)))

  (define (buffer-unread buf)
    (set-first-int (cdr buf) (- (first-int (cdr buf)) 1)))

  (define (score-set score sign buf reader)
    (begin (set-first-int score (* sign (buffer-len buf)))
           (set-rest score reader)))

  ; --- Infix-to-prefix transformer (SRFI-105) ---

  (define (extract-ops tokens)
    (if (or (null? tokens) (null? (cdr tokens))) ()
      (cons (cadr tokens) (extract-ops (cddr tokens)))))

  (define (extract-operands tokens)
    (if (null? tokens) ()
      (cons (car tokens)
            (if (null? (cdr tokens)) ()
              (extract-operands (cddr tokens))))))

  (define (all-equal? lst)
    (if (or (null? lst) (null? (cdr lst))) #t
      (if (equal? (car lst) (cadr lst))
        (all-equal? (cdr lst))
        #f)))

  (define (infix->prefix tokens)
    (if (null? tokens) ()
      (if (null? (cdr tokens)) (car tokens)
        (if (null? (cddr tokens))
          tokens                          ; {e1 e2} -> (e1 e2)
          (let ((ops (extract-ops tokens))
                (operands (extract-operands tokens)))
            (if (all-equal? ops)
              (cons (car ops) operands)   ; {a + b + c} -> (+ a b c)
              (cons (lit $nfx$) tokens)))))))

  ; $nfx$ -- SRFI-105 mixed-operator sentinel (self-quoting)
  (def $nfx$ (op args e (pair (lit $nfx$) args)))

  ; --- SWEET-CURLY token type (follows LIST pattern) ---

  ; Sentinel: unique object returned by } reader, recognized by { reader
  (define %sweet-curly-close (list (lit %sweet-curly-close)))

  ; Shared reader for both { and } (like LIST handles ( . ) in one reader)
  (define %sweet-curly-reader (lambda args
    (let ((raw (buffer-token (car args))))
      (if (equal? raw "}")
        ; } -> return sentinel (like LIST returns list_read_prim for ))
        %sweet-curly-close
        ; { -> recursively read elements until } sentinel
        (let loop ((elems ()))
          (let ((e (read)))
            (if (eq? e %sweet-curly-close)
              (infix->prefix (reverse elems))
              (loop (cons e elems)))))))))

  ; Register SWEET-CURLY on the main base
  (make-type "SWEET-CURLY"
    (list
      (cons (lit analyse) (lambda (buffer score chr)
        ; Match { (123) or } (125) as single char, positive score
        (if (or (= chr (char->integer #\{)) (= chr (char->integer #\})))
          (score-set score 1 buffer %sweet-curly-reader)
          ())))
      (cons (lit delimit) (lambda (buffer score chr)
        ; Claim { and } so SYMBOL stops at them
        (if (or (= chr (char->integer #\{)) (= chr (char->integer #\})))
          (begin (buffer-unread buffer) buffer)
          ())))))

  (lit sweet))
