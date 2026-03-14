; fmt.x -- x-lang comment-preserving formatter
;
; Pushes a keeping reader onto the built-in COMMENT type's read stack
; so ;-comments are captured as (%comment "text") tokens instead of
; being discarded (null read = discard).
;
; Input: the shell wrapper pipes the file content as a quoted string
; literal after the library+formatter on stdin.

(do
  ; --- Create formatter base, patch COMMENT to keep tokens ---

  (def %fmt-base (make-base))

  ; Reader that keeps the comment text as a token
  (def %fmt-comment-reader (fn args
    (list (lit %comment) (buffer-token (first args)))))

  ; Navigate type struct: entry = (handle . type-struct)
  ; type-struct has 7 elements, io is the 7th
  ; io = (analyse-stack delimit-stack read-stack write-stack display-stack error-stack)
  (def %entry-io (fn (entry)
    (first (rest (rest (rest (rest (rest (rest entry)))))))))

  ; Find COMMENT entry: first with (analyse + delimit + no read + no write)
  (def %find-comment (fn (alist)
    (if (null? alist) ()
      (do (def io (%entry-io (first alist)))
          (if (and (not (null? (first (first io))))
                   (not (null? (first (first (rest io)))))
                   (null? (first (first (rest (rest io))))))
            (first alist)
            (%find-comment (rest alist)))))))

  ; Push keeping reader onto COMMENT's read stack
  (def %comment-entry (%find-comment (first (first (first %fmt-base)))))
  (def %comment-io (%entry-io %comment-entry))
  (def %comment-read-stack (first (rest (rest %comment-io))))
  (set-first %comment-read-stack %fmt-comment-reader)

  ; --- Read input string (next form on stdin) and tokenize ---
  ; The shell wrapper pipes the file content as a quoted string literal.

  (def %input (read))
  (def %tokens (token-read-string %fmt-base %input))

  ; --- Predicates ---

  (def %comment? (fn (tok)
    (if (pair? tok) (eq? (first tok) (lit %comment)) ())))

  ; --- Width estimation ---

  (def %atom-width (fn (form)
    (if (null? form) 2
      (if (string? form) (+ 2 (string-length form))
        (if (symbol? form) (string-length (symbol->string form))
          (if (number? form) (string-length (number->string form))
            (if (char? form) 3
              4)))))))

  (def %list-width ())
  (def %form-width ())

  (set %list-width (fn (form)
    (if (null? form) 2
      (if (not (pair? form))
        (+ 4 (%atom-width form))
        (fold (fn (acc x) (+ acc 1 (%form-width x))) 1 form)))))

  (set %form-width (fn (form)
    (if (%comment? form) 80
      (if (pair? form) (%list-width form)
        (%atom-width form)))))

  ; --- Indentation ---

  (def %indent (fn (col)
    (if (<= col 0) ()
      (do (display " ") (%indent (- col 1))))))

  ; --- Pretty printer ---

  (def %fmt-atom (fn (form)
    (if (null? form) (display "()")
      (if (string? form) (write form)
        (display form)))))

  ; Forward declarations
  (def %fmt-expr ())
  (def %fmt-list ())
  (def %fmt-body ())

  ; Format a sequence of body forms, each on its own line
  (set %fmt-body (fn (forms col)
    (if (null? forms) ()
      (do (display "\n") (%indent col)
          (%fmt-expr (first forms) col)
          (%fmt-body (rest forms) col)))))

  ; Format a list form with indentation awareness
  (set %fmt-list (fn (form col)
    (def head (first form))
    (def rest-forms (rest form))

    ; Single-line if narrow enough
    (if (< (%form-width form) 60)
      (do (display "(")
          (%fmt-expr head (+ col 1))
          (for-each (fn (x) (display " ") (%fmt-expr x (+ col 2))) rest-forms)
          (display ")"))

      ; Multi-line: special form aware
      (if (eq? head (lit def))
        (if (null? rest-forms) (do (display "(def)"))
          (do (display "(def ")
              (%fmt-expr (first rest-forms) (+ col 5))
              (%fmt-body (rest rest-forms) (+ col 2))
              (display ")")))

      (if (eq? head (lit set))
        (if (null? rest-forms) (do (display "(set)"))
          (do (display "(set ")
              (%fmt-expr (first rest-forms) (+ col 5))
              (%fmt-body (rest rest-forms) (+ col 2))
              (display ")")))

      (if (or (eq? head (lit fn)) (eq? head (lit op)))
        (do (display "(") (display head) (display " ")
            (def head-width (+ 2 (string-length (symbol->string head))))
            (%fmt-expr (first rest-forms) (+ col head-width))
            (%fmt-body (rest rest-forms) (+ col 2))
            (display ")"))

      (if (eq? head (lit if))
        (if (null? rest-forms) (do (display "(if)"))
          (do (display "(if ")
              (%fmt-expr (first rest-forms) (+ col 4))
              (%fmt-body (rest rest-forms) (+ col 2))
              (display ")")))

      (if (or (eq? head (lit do)) (eq? head (lit begin)))
        (do (display "(") (display head)
            (%fmt-body rest-forms (+ col 2))
            (display ")"))

      (if (eq? head (lit let))
        (if (null? rest-forms) (do (display "(let)"))
          (do (display "(let ")
              (%fmt-expr (first rest-forms) (+ col 5))
              (%fmt-body (rest rest-forms) (+ col 2))
              (display ")")))

      (if (or (eq? head (lit match)) (eq? head (lit cond)))
        (do (display "(") (display head)
            (%fmt-body rest-forms (+ col 2))
            (display ")"))

      (if (eq? head (lit guard))
        (if (null? rest-forms) (do (display "(guard)"))
          (do (display "(guard ")
              (%fmt-expr (first rest-forms) (+ col 7))
              (%fmt-body (rest rest-forms) (+ col 2))
              (display ")")))

        ; Default: head on first line, rest indented +2
        (do (display "(")
            (%fmt-expr head (+ col 1))
            (%fmt-body rest-forms (+ col 2))
            (display ")")))))))))))))

  ; Format any expression
  (set %fmt-expr (fn (form col)
    (if (%comment? form)
      (display (first (rest form)))
      (if (pair? form) (%fmt-list form col)
        (%fmt-atom form)))))

  ; --- Main: output formatted tokens ---

  (def %fmt-tokens (fn (tokens first-token)
    (if (null? tokens) ()
      (do (def tok (first tokens))
          ; Add blank line between top-level forms (not before first)
          (if first-token ()
            (if (%comment? tok) ()
              (display "\n")))
          (%fmt-expr tok 0)
          (if (%comment? tok) ()
            (display "\n"))
          (%fmt-tokens (rest tokens) ())))))

  (%fmt-tokens %tokens t))
