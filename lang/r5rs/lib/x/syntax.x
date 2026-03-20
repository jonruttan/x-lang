; --- Tokenizer types for Scheme syntax ---
; Native-compiled analyse/delimit callbacks for tokenizer speed.

; Batch-compile all analyse/delimit callbacks in one cc invocation
(def %syntax-compiled
  (compile-batch
    ; 0: analyse single char (= chr 39) — quote '
    (lit (fn (buffer score chr)
      (if (= chr 39) (score-set score 1 buffer) ())))
    ; 1: delimit single char (= chr 39) — quote '
    (lit (fn (buffer score chr)
      (if (= chr 39) (%seq (buffer-unread buffer) buffer) ())))
    ; 2: analyse single char (= chr 96) — quasiquote `
    (lit (fn (buffer score chr)
      (if (= chr 96) (score-set score 1 buffer) ())))
    ; 3: delimit single char (= chr 96) — quasiquote `
    (lit (fn (buffer score chr)
      (if (= chr 96) (%seq (buffer-unread buffer) buffer) ())))
    ; 4: analyse single char (= chr 44) — comma ,
    (lit (fn (buffer score chr)
      (if (= chr 44) (score-set score 1 buffer) ())))
    ; 5: delimit single char (= chr 44) — comma ,
    (lit (fn (buffer score chr)
      (if (= chr 44) (%seq (buffer-unread buffer) buffer) ())))
  ))

; Extract compiled functions by index
(def %syntax-nth
  (fn (n lst)
    (if (= n 0) (first lst)
      (%syntax-nth (- n 1) (rest lst)))))

; --- Quote shorthand: 'expr -> (lit expr) ---

(def %quote-reader
  (fn args (pair (lit lit) (pair (%prim-read) ()))))
(make-type
  "QUOTE"
  (list
    (pair (lit first-chars) "'")
    (pair (lit analyse) (%syntax-nth 0 %syntax-compiled))
    (pair (lit read) %quote-reader)
    (pair (lit delimit) (%syntax-nth 1 %syntax-compiled))))

; --- Quasiquote shorthand: `expr -> (quasiquote expr) ---

(def %quasiquote-reader
  (fn args (pair (lit quasiquote) (pair (%prim-read) ()))))
(make-type
  "QUASIQUOTE"
  (list
    (pair (lit first-chars) "`")
    (pair (lit analyse) (%syntax-nth 2 %syntax-compiled))
    (pair (lit read) %quasiquote-reader)
    (pair (lit delimit) (%syntax-nth 3 %syntax-compiled))))

; --- Unquote shorthand: ,expr -> (unquote expr)
;                         ,@expr -> (unquote-splicing expr) ---

(def %unquote-reader
  (fn args (pair (lit unquote) (pair (%prim-read) ()))))
(def %unquote-splicing-reader
  (fn args (pair (lit unquote-splicing) (pair (%prim-read) ()))))
(make-type
  "UNQUOTE"
  (list
    (pair (lit first-chars) ",")
    (pair (lit analyse) (%syntax-nth 4 %syntax-compiled))
    (pair (lit read) %unquote-reader)
    (pair (lit delimit) (%syntax-nth 5 %syntax-compiled))))
(make-type
  "UNQUOTE-SPLICING"
  (list
    (pair (lit first-chars) ",")
    (pair (lit analyse)
      (compile (lit (fn (buffer score chr)
        (if (= chr 44)
          (fn (buffer score chr)
            (if (= chr 64)
              (score-set score 1 buffer) ()))
          ())))))
    (pair (lit read) %unquote-splicing-reader)
    (pair (lit delimit) (%syntax-nth 5 %syntax-compiled))))

; --- Ellipsis tokenizer type ---
; Register '...' as a token so it parses as a symbol, not as dot-pair
; %ellipsis-sym is defined in macro.scm
; 4-state machine: dot1 → dot2 → dot3 → lookahead check
; All states compiled to native code with nested fn support.

(make-type
  "ELLIPSIS"
  (list
    (pair (lit first-chars) ".")
    (pair (lit analyse)
      (compile (lit (fn (buffer score chr)
        (if (= chr 46)
          (fn (buffer score chr)
            (if (= chr 46)
              (fn (buffer score chr)
                (if (= chr 46)
                  (%seq (score-set score 1 buffer)
                    (fn (buffer score chr)
                      (if (= chr 46) ()
                        (%seq (buffer-unread buffer)
                              (score-set score 1 buffer)))))
                  ()))
              ()))
          ())))))
    (pair (lit read) (fn args %ellipsis-sym))))
