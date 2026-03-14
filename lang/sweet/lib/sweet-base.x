; sweet.x -- Sweet-expressions personality (SRFI-105/110)
;
; SRFI-105: Curly-infix notation {a + b} -> (+ a b)
; SRFI-110: Indentation-based grouping via SWEET-WS token type
;
; SWEET-WS beats the built-in WHITESPACE type for newline-containing
; whitespace by scoring bufferlen (vs WHITESPACE's bufferlen-1).
; The reader unreads the extra char and returns an indent marker.
; Space-only whitespace falls through to WHITESPACE (no competition).
;
; Usage:
;   cat lang/sweet/lib/sweet.x - | ./x
;   {1 + 2}       -> 3
;   {2 * {3 + 4}} -> 14

(include "lang/r5rs/lib/r5rs-base.x")
(begin
  ; --- Buffer helpers (not in r5rs, needed for type handlers) ---

  (define (buffer-len buf)
    (- (first-int (cdr buf)) (first-int buf)))

  (define (buffer-unread buf)
    (set-first-int (cdr buf) (- (first-int (cdr buf)) 1)))

  (define (score-set score sign buf)
    (set-first-int score (* sign (buffer-len buf))))

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

  ; --- Indent marker sentinel and helpers ---

  (define %sweet-indent-sentinel (list (lit %indent)))

  (define (indent-marker? x)
    (and (pair? x) (eq? (car x) %sweet-indent-sentinel)))

  (define (indent-level x) (cadr x))

  ; --- Strip indent markers from lists (leaked from inside parens) ---

  (define (strip-indent-markers lst)
    (cond
      ((null? lst) ())
      ((indent-marker? lst) ())
      ((not (pair? lst)) lst)
      ((indent-marker? (car lst))
       (strip-indent-markers (cdr lst)))
      (#t (cons (if (pair? (car lst))
                  (strip-indent-markers (car lst))
                  (car lst))
                (strip-indent-markers (cdr lst))))))

  ; --- SWEET-CURLY token type (follows LIST pattern) ---

  ; Sentinel: list whose car is a unique integer tag (GC-safe check)
  (define %sweet-curly-close (list 7777))
  (define (curly-close? x) (and (pair? x) (eq? (car x) (car %sweet-curly-close))))

  ; Shared reader for both { and }
  ; NOTE: uses if, not cond -- cond triggers GC inside tokenizer callbacks
  (define %sweet-curly-reader (lambda args
    (let ((raw (buffer-token (car args))))
      (if (equal? raw "}")
        %sweet-curly-close
        (let loop ((elems ()))
          (let ((e (read)))
            (if (null? e)
              (infix->prefix (reverse elems))
              (if (curly-close? e)
                (infix->prefix (reverse elems))
                (if (indent-marker? e)
                  (loop elems)
                  (loop (cons e elems)))))))))))

  ; Register SWEET-CURLY on the main base
  (make-type "SWEET-CURLY"
    (list
      (cons (lit analyse) (lambda (buffer score chr)
        (if (or (= chr (char->integer #\{)) (= chr (char->integer #\})))
          (score-set score 1 buffer)
          ())))
      (cons (lit read) %sweet-curly-reader)
      (cons (lit delimit) (lambda (buffer score chr)
        (if (or (= chr (char->integer #\{)) (= chr (char->integer #\})))
          (%seq (buffer-unread buffer) buffer)
          ())))))

  ; --- SWEET-WS token type (replaces built-in WHITESPACE) ---
  ;
  ; Scores bufferlen (not bufferlen-1) so it always beats the C
  ; WHITESPACE type by 1. The reader unreads the extra non-WS char.

  ; Mutable state for the analyse state machine
  (define %sweet-ws-saw-nl #f)
  (define %sweet-ws-level 0)

  ; Check if chr is whitespace (same chars as WHITESPACE_CHARS_STR)
  (define (%sweet-ws-char? chr)
    (or (= chr 32) (= chr 9) (= chr 10) (= chr 13) (= chr 11) (= chr 12)))

  ; Reader: unread the extra char, return indent marker
  (define %sweet-ws-reader (lambda args
    (buffer-unread (car args))
    (list %sweet-indent-sentinel %sweet-ws-level)))

  ; Analyse state 2: continue consuming, finalize on non-WS
  ; (defined before a1 because a1 references a2)
  ; NOTE: uses if, not cond -- cond triggers GC inside tokenizer callbacks
  (define %sweet-ws-a2 (lambda (buffer score chr)
    (if (= chr 32)                               ; space
      (%seq (if %sweet-ws-saw-nl
               (set! %sweet-ws-level (+ %sweet-ws-level 1)))
            %sweet-ws-a2)
      (if (= chr 9)                              ; tab
        (%seq (if %sweet-ws-saw-nl
                 (set! %sweet-ws-level (+ %sweet-ws-level 8)))
              %sweet-ws-a2)
        (if (= chr 10)                           ; newline
          (%seq (set! %sweet-ws-saw-nl #t)
                (%seq (set! %sweet-ws-level 0)
                      %sweet-ws-a2))
          (if (or (= chr 13) (= chr 11) (= chr 12))  ; CR, VT, FF
            %sweet-ws-a2
            (if %sweet-ws-saw-nl                 ; non-WS: finalize
              (score-set score 1 buffer)
              ())))))))

  ; Analyse state 1: first char must be whitespace
  (define %sweet-ws-a1 (lambda (buffer score chr)
    (if (%sweet-ws-char? chr)
      (%seq (if (= chr 10)
              (%seq (set! %sweet-ws-saw-nl #t)
                    (set! %sweet-ws-level 0))
              (set! %sweet-ws-saw-nl #f))
            %sweet-ws-a2)
      ())))

  ; Register SWEET-WS
  (make-type "SWEET-WS"
    (list
      (cons (lit analyse) %sweet-ws-a1)
      (cons (lit read) %sweet-ws-reader)
      (cons (lit delimit) (lambda (buffer score chr)
        (if (%sweet-ws-char? chr)
          (%seq (buffer-unread buffer) buffer)
          ())))))

  ; --- sweet-read: indentation-based grouping (SRFI-110) ---
  ;
  ; Tokens come from (read). SWEET-WS produces indent markers for
  ; newline-containing whitespace. Lists from (...) are stripped of
  ; any leaked indent markers.

  (define %sweet-none (list (lit %none)))
  (define %sweet-pending %sweet-none)

  ; Read next token, stripping indent markers from lists
  (define (sweet-token-read)
    (let ((t (read)))
      (cond
        ((null? t) t)
        ((indent-marker? t) t)
        ((pair? t) (strip-indent-markers t))
        (#t t))))

  (define (sweet-next)
    (if (not (eq? %sweet-pending %sweet-none))
      (let ((t %sweet-pending))
        (set! %sweet-pending %sweet-none)
        t)
      (sweet-token-read)))

  (define (sweet-push t)
    (set! %sweet-pending t))

  ; Finish expression: unwrap single items
  (define (sweet-finish tokens)
    (cond
      ((null? tokens) ())
      ((null? (cdr tokens)) (car tokens))
      (#t tokens)))

  ; Forward declaration for mutual recursion
  (define sweet-expr ())

  ; Read children at a given indentation level
  (define (sweet-children child-indent)
    (let loop ((results ()))
      (let ((child (sweet-expr child-indent)))
        (if (null? child) results
          (let ((results (append results (list child))))
            (let ((t (sweet-next)))
              (cond
                ((null? t) results)
                ((and (indent-marker? t) (= (indent-level t) child-indent))
                 (loop results))
                (#t (sweet-push t)
                    results))))))))

  ; Read one sweet expression at a given base indentation
  (set! sweet-expr (lambda (base-indent)
    (let read-head ((tokens ()))
      (let ((t (sweet-next)))
        (cond
          ((null? t)
           (sweet-finish (reverse tokens)))
          ((indent-marker? t)
           (let ((level (indent-level t)))
             (cond
               ((> level base-indent)
                (sweet-finish
                  (append (reverse tokens)
                          (sweet-children level))))
               ((and (null? tokens) (= level base-indent))
                (read-head tokens))  ; skip indent at base level
               (#t (sweet-push t)
                   (sweet-finish (reverse tokens))))))
          (#t
           (read-head (cons t tokens))))))))

  ; Main entry: skip leading blank lines, read one expression
  (define (sweet-read)
    (let skip ()
      (let ((t (sweet-next)))
        (cond
          ((null? t) ())
          ((and (indent-marker? t) (= (indent-level t) 0))
           (skip))
          (#t (sweet-push t)
              (sweet-expr 0))))))

  ; --- Sweet REPL ---
  (def sweet-repl (op ()
    (display %repl-prompt)
    (def %r (sweet-read))
    (if (null? %r) ()
      (%seq (guard (err
              (display "Error: ")
              (display err)
              (newline))
              (%repl-print (eval! %r)))
            (sweet-repl)))))

  ; %test-read: read wrapper that skips SWEET-WS indent markers
  ; Used by the test harness so %T doesn't try to evaluate markers
  (def %test-read (fn ()
    (def %tr (read))
    (if (and (pair? %tr) (pair? (first %tr))
             (eq? (first (first %tr)) (lit %indent)))
      (%test-read)
      %tr)))

  (sweet-repl)
)
