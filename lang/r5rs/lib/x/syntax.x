; --- Tokenizer types for Scheme syntax ---

; --- Quote shorthand: 'expr -> (lit expr) ---

(def %quote-reader
  (fn args (pair (lit lit) (pair (%prim-read) ()))))
(make-type
  "QUOTE"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (score-set score 1 buffer)
          ())))
    (pair (lit read) %quote-reader)
    (pair
      (lit delimit)
      (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (%seq (buffer-unread buffer) buffer)
          ())))))

; --- Quasiquote shorthand: `expr -> (quasiquote expr) ---

(def %quasiquote-reader
  (fn args (pair (lit quasiquote) (pair (%prim-read) ()))))
(make-type
  "QUASIQUOTE"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (score-set score 1 buffer)
          ())))
    (pair (lit read) %quasiquote-reader)
    (pair
      (lit delimit)
      (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (%seq (buffer-unread buffer) buffer)
          ())))))

; --- Unquote shorthand: ,expr -> (unquote expr)
;                         ,@expr -> (unquote-splicing expr) ---

(def %unquote-reader
  (fn args (pair (lit unquote) (pair (%prim-read) ()))))
(def %unquote-splicing-reader
  (fn args (pair (lit unquote-splicing) (pair (%prim-read) ()))))
(make-type
  "UNQUOTE"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (score-set score 1 buffer)
          ())))
    (pair (lit read) %unquote-reader)
    (pair
      (lit delimit)
      (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (%seq (buffer-unread buffer) buffer)
          ())))))
(make-type
  "UNQUOTE-SPLICING"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (fn (buffer score chr)
            (if (= chr (char->integer #\@))
              (score-set score 1 buffer)
              ()))
          ())))
    (pair (lit read) %unquote-splicing-reader)
    (pair
      (lit delimit)
      (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (%seq (buffer-unread buffer) buffer)
          ())))))

; --- Ellipsis tokenizer type ---

; Register '...' as a token so it parses as a symbol, not as dot-pair
; %ellipsis-sym is defined in macro.scm

; State machine: dot1 → dot2 → dot3 → lookahead check

(define
  %ellipsis-check
  (lambda
    (buffer score chr)
    (if (= chr 46)
      ()
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))
(define
  %ellipsis-dot3
  (lambda
    (buffer score chr)
    (if (= chr 46)
      (%seq (score-set score 1 buffer) %ellipsis-check)
      ())))
(define
  %ellipsis-dot2
  (lambda
    (buffer score chr)
    (if (= chr 46) %ellipsis-dot3 ())))
(make-type
  "ELLIPSIS"
  (list
    (pair
      (lit analyse)
      (lambda
        (buffer score chr)
        (if (= chr 46) %ellipsis-dot2 ())))
    (pair (lit read) (lambda args %ellipsis-sym))))
