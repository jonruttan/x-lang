; sweet-base.x -- Sweet-expressions personality (SRFI-105/110)
;
; Types tokenize; sweet-read groups by indentation.
; SWEET-WS beats WHITESPACE by scoring bufferlen (vs bufferlen-1).
; Space-only whitespace falls through to WHITESPACE.

(include "lang/r7rs/lib/r7rs-base.x")

(begin
  ; --- Infix-to-prefix (SRFI-105) ---
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
        (all-equal? (cdr lst)) #f)))
  (define (infix->prefix tokens)
    (if (null? tokens) ()
      (if (null? (cdr tokens)) (car tokens)
        (if (null? (cddr tokens)) tokens
          (let ((ops (extract-ops tokens))
                (operands (extract-operands tokens)))
            (if (all-equal? ops)
              (cons (car ops) operands)
              (cons (lit $nfx$) tokens)))))))
  (def $nfx$ (op args e (pair (lit $nfx$) args)))

  ; --- Mutable state cells ---
  (define %nl  (list 0))   ; saw-newline flag
  (define %lv  (list 0))   ; indent level
  (define %wsf (list 0))   ; ws-fired flag (0=no, 1=yes)
  (define %a2  (list ()))  ; a2 self-ref
  (define %sre (list 0))   ; sweet-read-expr base level (GC-safe)
  (define %slv (list 0))   ; sweet-read-siblings lv (GC-safe)

  ; --- WS sentinel (stripped from LIST results inside parens) ---
  (define %ws-mark (list (lit %ws)))
  (define (ws-mark? x) (and (pair? x) (eq? (car x) %ws-mark)))
  (define (strip-ws lst)
    (if (null? lst) ()
      (if (not (pair? lst)) lst
        (if (ws-mark? lst) ()
          (if (ws-mark? (car lst)) (strip-ws (cdr lst))
            (cons
              (if (pair? (car lst)) (strip-ws (car lst)) (car lst))
              (strip-ws (cdr lst))))))))

  ; --- Curly-close sentinel ---
  (define %curly-close (list 7777))
  (define (curly-close? x) (and (pair? x) (eq? (car x) (car %curly-close))))

  ; NOTE: uses if, not cond -- cond triggers GC inside tokenizer callbacks
  (define %curly-reader
    (lambda args
      (let ((raw (buffer-token (car args))))
        (if (equal? raw "}")
          %curly-close
          (let loop ((elems ()))
            (set-first %wsf 0)
            (let ((e (%prim-read)))
              (if (null? e) (infix->prefix (reverse elems))
                (if (curly-close? e) (infix->prefix (reverse elems))
                  (if (not (= (first %wsf) 0)) (loop elems)
                    (loop (cons (if (pair? e) (strip-ws e) e) elems)))))))))))

  ; --- Compiled tokenizer callbacks ---
  (define %ws-fvars
    (list
      (cons (lit %nl) %nl)
      (cons (lit %lv) %lv)
      (cons (lit %a2) %a2)))
  (define %compiled
    (compile-batch
      ; 0: curly analyse — { = 123, } = 125
      (lit (fn (buffer score chr)
        (if (or (= chr 123) (= chr 125)) (score-set score 1 buffer) ())))
      ; 1: curly delimit
      (lit (fn (buffer score chr)
        (if (or (= chr 123) (= chr 125))
          (%seq (buffer-unread buffer) buffer) ())))
      ; 2: ws delimit
      (lit (fn (buffer score chr)
        (if (or (= chr 32) (= chr 9) (= chr 10) (= chr 13) (= chr 11) (= chr 12))
          (%seq (buffer-unread buffer) buffer) ())))))
  (define (%nth n lst) (if (= n 0) (car lst) (%nth (- n 1) (cdr lst))))

  ; WS analyse a2: loop over whitespace, score on non-WS char.
  ; %nl=0: no newline yet, %nl>=1: after newline.
  ; Blank line (\n when %nl>=1) scores immediately — prevents interactive blocking.
  (define %ws-a2
    (compile
      (lit (fn (buffer score chr)
        (if (= chr 10)
          (if (atom-val (first %nl))
            ; Blank line (second+ newline) — score immediately
            (%seq (atom-set! (first %lv) 0) (score-set score 1 buffer))
            ; First newline inside a2
            (%seq (atom-set! (first %nl) 1)
                  (%seq (atom-set! (first %lv) 0) (first %a2))))
          (if (= chr 32)
            (%seq (if (atom-val (first %nl)) (atom-add! (first %lv) 1)) (first %a2))
            (if (= chr 9)
              (%seq (if (atom-val (first %nl)) (atom-add! (first %lv) 8)) (first %a2))
              (if (or (= chr 13) (= chr 11) (= chr 12))
                (first %a2)
                (if (atom-val (first %nl)) (score-set score 1 buffer) ())))))))
      %ws-fvars))
  (set-first %a2 %ws-a2)

  ; WS analyse a1: first char must be whitespace
  (define %ws-a1
    (compile
      (lit (fn (buffer score chr)
        (if (or (= chr 32) (= chr 9) (= chr 10) (= chr 13) (= chr 11) (= chr 12))
          (%seq
            (if (= chr 10)
              (%seq (atom-set! (first %nl) 1) (atom-set! (first %lv) 0))
              (atom-set! (first %nl) 0))
            (first %a2))
          ())))
      %ws-fvars))

  ; WS reader: unread extra char, signal sweet-read, return sentinel
  (define %ws-reader
    (lambda args
      (buffer-unread (car args))
      (set-first %wsf 1)
      %ws-mark))

  ; --- Register types ---
  (make-type "SWEET-CURLY"
    (list
      (cons (lit first-chars) "{}")
      (cons (lit analyse) (%nth 0 %compiled))
      (cons (lit read) %curly-reader)
      (cons (lit delimit) (%nth 1 %compiled))))
  (make-type "SWEET-WS"
    (list
      (cons (lit first-chars) " \t\n\r")
      (cons (lit analyse) %ws-a1)
      (cons (lit read) %ws-reader)
      (cons (lit delimit) (%nth 2 %compiled))))

  ; --- Override WHITESPACE to ignore newlines ---
  ; WHITESPACE's analyse reads past \n, blocking interactive stdin.
  ; Replace with compiled callbacks that treat \n as non-whitespace.
  ; WHITESPACE's delimit (hardcoded C call) is unaffected — \n still delimits.
  (define %ws-ov-a2-ref (list ()))
  (define %ws-ov-fvars
    (list (cons (lit %ws-ov-a2-ref) %ws-ov-a2-ref)))
  (define %ws-ov-a2
    (compile
      (lit (fn (buffer score chr)
        (if (or (= chr 32) (= chr 9) (= chr 13) (= chr 11) (= chr 12))
          (first %ws-ov-a2-ref)
          (%seq (buffer-unread buffer) (score-set score 1 buffer)))))
      %ws-ov-fvars))
  (set-first %ws-ov-a2-ref %ws-ov-a2)
  (define %ws-ov-a1
    (compile
      (lit (fn (buffer score chr)
        (if (or (= chr 32) (= chr 9) (= chr 13) (= chr 11) (= chr 12))
          (first %ws-ov-a2-ref)
          ())))
      %ws-ov-fvars))
  ; Find WHITESPACE type struct and replace its analyse
  (define (%find-type name alist)
    (if (null? alist) ()
      (if (string=? (ptr->string (int->ptr (first-int (first (first alist))))) name)
        (rest (first alist))
        (%find-type name (rest alist)))))
  (define %ws-type
    (%find-type "WHITESPACE"
      (first (first (first (first (rest (first (%base)))))))))
  (define %ws-io
    (first (rest (rest (rest (rest (rest %ws-type)))))))
  (set-first (first %ws-io) %ws-ov-a1)

  ; --- GC roots ---
  (heap-mark-root! %nl)
  (heap-mark-root! %lv)
  (heap-mark-root! %wsf)
  (heap-mark-root! %a2)
  (heap-mark-root! %sre)
  (heap-mark-root! %slv)
  (heap-mark-root! %compiled)
  (heap-mark-root! %curly-reader)
  (heap-mark-root! %curly-close)
  (heap-mark-root! %ws-mark)
  (heap-mark-root! %ws-reader)
  (heap-mark-root! %ws-ov-a2-ref)
  (heap-mark-root! %ws-ov-a1)
  (heap-mark-root! %ws-ov-a2)

  ; --- Indentation grouping (SRFI-110) ---
  (define (sw1 x)
    (if (null? x) ()
      (if (null? (cdr x)) (car x) x)))

  (define sweet-read-expr ())

  (define (sweet-read-siblings lv)
    (set-first-int %slv lv)
    (let lp ((ch ()))
      (let ((child (sweet-read-expr (first-int %slv))))
        (if (null? child) (reverse ch)
          (let ((ch (cons child ch)))
            (if (and (not (= (first %wsf) 0))
                     (= (first %lv) (first-int %slv)))
              (lp ch)
              (reverse ch)))))))

  (set! sweet-read-expr
    (lambda (base)
      (set-first-int %sre base)
      (let lp ((acc ()))
        (set-first %wsf 0)
        (let ((t (%prim-read)))
          (if (null? t)
            (sw1 (reverse acc))
            (if (= (first %wsf) 0)
              (lp (cons (if (pair? t) (strip-ws t) t) acc))
              (if (null? acc)
                (lp acc)
                (let ((lv (first %lv)))
                  (if (> lv (first-int %sre))
                    (sw1 (append (reverse acc) (sweet-read-siblings lv)))
                    (sw1 (reverse acc)))))))))))

  (define (sweet-read) (sweet-read-expr 0))

  ; --- Sweet REPL ---
  (def sweet-repl
    (op ()
      (display %repl-prompt)
      (def %r (sweet-read))
      (if (null? %r) ()
        (%seq
          (guard (err (display "Error: ") (display err) (newline))
            (%repl-print (eval! %r)))
          (sweet-repl)))))

  ; %test-read: skip SWEET-WS tokens for test harness
  (def %test-read
    (fn ()
      (set-first %wsf 0)
      (def %tr (%prim-read))
      (if (not (= (first %wsf) 0)) (%test-read) %tr)))

  (sweet-repl))
