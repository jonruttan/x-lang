; parser.x -- Recursive descent parser for POSIX shell grammar
;
; Input:  flat token list from sh-tokenize
; Output: AST (nested tagged lists)
;
; Grammar (precedence low to high):
;   complete_command = list (newline list)* EOF
;   list             = and_or ((';'|'&') and_or)*
;   and_or           = pipeline (('&&'|'||') pipeline)*
;   pipeline         = command ('|' command)*
;   command          = compound_command | simple_command
;   compound_command = if_clause | while_clause | for_clause | '(' list ')'
;   simple_command   = (word|redirect)+
;   redirect         = [digit] ('<'|'>'|'>>'|'<&'|'>&'|'<>'|'>|') word
;
; AST nodes:
;   (sh-cmd  args redirs)
;   (sh-pipe cmds)
;   (sh-and  left right)
;   (sh-or   left right)
;   (sh-seq  left right)
;   (sh-bg   cmd)
;   (sh-subshell body)
;   (sh-if   cond then elifs else)
;   (sh-while cond body)
;   (sh-for  var words body)
;   (sh-redir op fd target)

; --- Cursor: mutable box holding remaining token list ---

(def %mk-cursor (fn (tokens)
  (pair tokens ())))

(def %cursor-peek (fn (cur)
  (if (null? (first cur)) () (first (first cur)))))

(def %cursor-advance! (fn (cur)
  (do (set-first! cur (rest (first cur)))
      ())))

(def %cursor-empty? (fn (cur)
  (null? (first cur))))

; --- Token predicates ---

(def %tok-type (fn (tok) (first tok)))
(def %tok-val (fn (tok) (first (rest tok))))

(def %tok-is-word? (fn (tok)
  (or (eq? (first tok) (lit tok-word))
      (eq? (first tok) (lit tok-sq))
      (eq? (first tok) (lit tok-dq)))))

(def %tok-is-op? (fn (tok op)
  (and (eq? (first tok) (lit tok-op))
       (string=? (first (rest tok)) op))))

(def %tok-is-newline? (fn (tok)
  (eq? (first tok) (lit tok-newline))))

; Get word value (works for tok-word, tok-sq, tok-dq)
(def %tok-word-val (fn (tok)
  (if (eq? (first tok) (lit tok-newline)) ()
    (first (rest tok)))))

; --- Match helpers ---

(def %match-op (fn (cur op)
  (if (%cursor-empty? cur) ()
    (let ((tok (%cursor-peek cur)))
      (if (and (eq? (first tok) (lit tok-op))
               (string=? (first (rest tok)) op))
        (do (%cursor-advance! cur) #t)
        ())))))

(def %skip-newlines (fn (cur)
  (if (and (not (%cursor-empty? cur))
           (%tok-is-newline? (%cursor-peek cur)))
    (do (%cursor-advance! cur) (%skip-newlines cur))
    ())))

; --- Reserved word check ---

(def %reserved-word? (fn (word)
  (or (string=? word "if") (string=? word "then")
      (string=? word "elif") (string=? word "else")
      (string=? word "fi") (string=? word "while")
      (string=? word "until") (string=? word "for")
      (string=? word "do") (string=? word "done")
      (string=? word "case") (string=? word "in")
      (string=? word "esac") (string=? word "!")
      (string=? word "{")(string=? word "}"))))

; --- Redirection check ---
; Returns redirect operator string if tok is a redirect op, else ()
(def %redir-op? (fn (tok)
  (if (not (eq? (first tok) (lit tok-op))) ()
    (let ((op (first (rest tok))))
      (if (or (string=? op "<") (string=? op ">")
              (string=? op ">>") (string=? op "<<")
              (string=? op "<&") (string=? op ">&")
              (string=? op "<>") (string=? op ">|")
              (string=? op "<<-"))
        op ())))))

; Check if a word string is all digits (for fd prefix like 2>)
(def %all-digits? (fn (s)
  (def %check (fn (i len)
    (if (= i len) #t
      (let ((c (convert (string-ref s i) %int)))
        (if (and (>= c 48) (<= c 57))
          (%check (+ i 1) len) ())))))
  (if (= (string-length s) 0) ()
    (%check 0 (string-length s)))))

; Default fd for a redirect operator
(def %default-fd (fn (op)
  (if (string=? op "<") 0
    (if (string=? op "<>") 0
      (if (string=? op "<&") 0
        1)))))

; --- Simple command parser ---
; Collects words and redirections

(def %parse-simple-cmd (fn (cur)
  (def %collect (fn (wds redirs)
    (if (%cursor-empty? cur)
      (list (lit sh-cmd) (reverse wds) (reverse redirs))
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-newline? tok)
          (list (lit sh-cmd) (reverse wds) (reverse redirs))
          ; Check for redirect operator
          (let ((rop (%redir-op? tok)))
            (if rop
              ; It's a redirect: consume op, get target word
              (do (%cursor-advance! cur)
                ; Check if previous arg was a digit (fd override)
                (let ((fd (if (and (not (null? wds))
                                   (%all-digits? (first wds)))
                            (let ((n (first wds)))
                              (set! wds (rest wds))
                              n)
                            (%default-fd rop))))
                  (if (%cursor-empty? cur)
                    (error "parse error: redirect without target")
                    (let ((target (%tok-word-val (%cursor-peek cur))))
                      (%cursor-advance! cur)
                      (%collect wds
                        (pair (list (lit sh-redir) rop fd target)
                              redirs))))))
              ; Check for word-like token
              (if (%tok-is-word? tok)
                (let ((val (%tok-word-val tok)))
                  ; Stop if reserved word and we have args already
                  (if (and (not (null? wds))
                           (eq? (first tok) (lit tok-word))
                           (%reserved-word? val))
                    (list (lit sh-cmd) (reverse wds) (reverse redirs))
                    (do (%cursor-advance! cur)
                        (%collect (pair val wds) redirs))))
                ; Not a word or redirect: stop
                (list (lit sh-cmd) (reverse wds)
                      (reverse redirs))))))))))
  (%collect () ())))

; --- Compound command parser ---

(def %is-compound-start? (fn (cur)
  (if (%cursor-empty? cur) ()
    (let ((tok (%cursor-peek cur)))
      (if (eq? (first tok) (lit tok-word))
        (let ((w (first (rest tok))))
          (or (string=? w "if") (string=? w "while")
              (string=? w "until") (string=? w "for")))
        (if (eq? (first tok) (lit tok-op))
          (string=? (first (rest tok)) "(")
          ()))))))

(def %expect-word (fn (cur word)
  (if (%cursor-empty? cur)
    (error (string-append "parse error: expected " word))
    (let ((tok (%cursor-peek cur)))
      (if (and (eq? (first tok) (lit tok-word))
               (string=? (first (rest tok)) word))
        (do (%cursor-advance! cur) #t)
        (error (string-append "parse error: expected " word)))))))

; Forward declaration via set
(def %parse-list ())

; if cond ; then body [elif cond ; then body]... [else body] fi
(def %parse-if (fn (cur)
  (%cursor-advance! cur) ; consume 'if'
  (%skip-newlines cur)
  (let ((cond (%parse-list cur)))
    (%skip-newlines cur)
    (%expect-word cur "then")
    (%skip-newlines cur)
    (let ((then-body (%parse-list cur)))
      ; Collect elifs
      (def %collect-elifs (fn (elifs)
        (%skip-newlines cur)
        (if (and (not (%cursor-empty? cur))
                 (eq? (first (%cursor-peek cur)) (lit tok-word))
                 (string=? (first (rest (%cursor-peek cur))) "elif"))
          (do (%cursor-advance! cur) ; consume 'elif'
              (%skip-newlines cur)
              (let ((elif-cond (%parse-list cur)))
                (%skip-newlines cur)
                (%expect-word cur "then")
                (%skip-newlines cur)
                (let ((elif-body (%parse-list cur)))
                  (%collect-elifs
                    (pair (list elif-cond elif-body) elifs)))))
          (reverse elifs))))
      (let ((elifs (%collect-elifs ())))
        (%skip-newlines cur)
        ; Check for else
        (let ((else-body
                (if (and (not (%cursor-empty? cur))
                         (eq? (first (%cursor-peek cur)) (lit tok-word))
                         (string=? (first (rest (%cursor-peek cur))) "else"))
                  (do (%cursor-advance! cur) ; consume 'else'
                      (%skip-newlines cur)
                      (%parse-list cur))
                  ())))
          (%skip-newlines cur)
          (%expect-word cur "fi")
          (list (lit sh-if) cond then-body elifs else-body)))))))

; while cond ; do body ; done
(def %parse-while (fn (cur)
  (%cursor-advance! cur) ; consume 'while'/'until'
  (%skip-newlines cur)
  (let ((cond (%parse-list cur)))
    (%skip-newlines cur)
    (%expect-word cur "do")
    (%skip-newlines cur)
    (let ((body (%parse-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "done")
      (list (lit sh-while) cond body)))))

; for var [in words...] ; do body ; done
(def %parse-for (fn (cur)
  (%cursor-advance! cur) ; consume 'for'
  (%skip-newlines cur)
  (if (%cursor-empty? cur) (error "parse error: for without variable")
    (let ((var (%tok-word-val (%cursor-peek cur))))
      (%cursor-advance! cur)
      ; Optionally consume 'in' + word list
      (%skip-newlines cur)
      ; Check for semicolon/newline before 'do' (no 'in' clause)
      (let ((words
              (if (and (not (%cursor-empty? cur))
                       (eq? (first (%cursor-peek cur)) (lit tok-word))
                       (string=? (first (rest (%cursor-peek cur))) "in"))
                (do (%cursor-advance! cur) ; consume 'in'
                    (def %collect-words (fn (ws)
                      (if (or (%cursor-empty? cur)
                              (%tok-is-newline? (%cursor-peek cur))
                              (and (eq? (first (%cursor-peek cur)) (lit tok-op))
                                   (string=? (first (rest (%cursor-peek cur))) ";")))
                        (reverse ws)
                        (let ((w (%tok-word-val (%cursor-peek cur))))
                          (%cursor-advance! cur)
                          (%collect-words (pair w ws))))))
                    (%collect-words ()))
                ())))
        ; Skip separator
        (%skip-newlines cur)
        (if (not (%cursor-empty? cur))
          (if (%match-op cur ";") (%skip-newlines cur) ())
          ())
        (%expect-word cur "do")
        (%skip-newlines cur)
        (let ((body (%parse-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (list (lit sh-for) var words body)))))))

; ( list )
(def %parse-subshell (fn (cur)
  (%cursor-advance! cur) ; consume '('
  (%skip-newlines cur)
  (let ((body (%parse-list cur)))
    (%skip-newlines cur)
    (if (%match-op cur ")")
      (list (lit sh-subshell) body)
      (error "parse error: expected )")))))

(def %parse-compound (fn (cur)
  (let ((tok (%cursor-peek cur)))
    (if (eq? (first tok) (lit tok-op))
      ; Subshell: ( ... )
      (%parse-subshell cur)
      ; Reserved word compound
      (let ((word (first (rest tok))))
        (if (string=? word "if") (%parse-if cur)
          (if (or (string=? word "while")
                  (string=? word "until"))
            (%parse-while cur)
            (if (string=? word "for") (%parse-for cur)
              (error (string-append "parse error: unexpected "
                                     word))))))))))

; --- Command parser ---

(def %parse-command (fn (cur)
  (if (%is-compound-start? cur)
    (%parse-compound cur)
    (%parse-simple-cmd cur))))

; --- Pipeline parser ---

(def %parse-pipeline (fn (cur)
  (%skip-newlines cur)
  (let ((first-cmd (%parse-command cur)))
    (def %collect-pipe (fn (cmds)
      (if (%match-op cur "|")
        (do (%skip-newlines cur)
            (%collect-pipe
              (pair (%parse-command cur) cmds)))
        (if (null? (rest cmds))
          (first cmds)
          (list (lit sh-pipe) (reverse cmds))))))
    (%collect-pipe (list first-cmd)))))

; --- And-or list parser ---

(def %parse-and-or (fn (cur)
  (let ((left (%parse-pipeline cur)))
    (if (%cursor-empty? cur) left
      (if (%match-op cur "&&")
        (do (%skip-newlines cur)
            (list (lit sh-and) left (%parse-and-or cur)))
        (if (%match-op cur "||")
          (do (%skip-newlines cur)
              (list (lit sh-or) left (%parse-and-or cur)))
          left))))))

; --- Stop-word helper ---
; Returns t if cursor is empty or at a list-terminating keyword/operator

(def %at-stop-word? (fn (cur)
  (if (%cursor-empty? cur) #t
    (let ((tok (%cursor-peek cur)))
      (if (eq? (first tok) (lit tok-word))
        (let ((w (first (rest tok))))
          (or (string=? w "then") (string=? w "elif")
              (string=? w "else") (string=? w "fi")
              (string=? w "do") (string=? w "done")
              (string=? w "esac") (string=? w "}")))
        (if (eq? (first tok) (lit tok-op))
          (string=? (first (rest tok)) ")")
          ()))))))

; --- List parser (sequences with ; and &) ---

(set! %parse-list (fn (cur)
  (%skip-newlines cur)
  (if (%at-stop-word? cur) ()
    (let ((left (%parse-and-or cur)))
      (if (%cursor-empty? cur) left
        (let ((tok (%cursor-peek cur)))
          (if (%tok-is-newline? tok)
            (do (%cursor-advance! cur)
                (%skip-newlines cur)
                (if (%at-stop-word? cur) left
                  (list (lit sh-seq) left (%parse-list cur))))
            (if (%match-op cur ";")
              (do (%skip-newlines cur)
                  (if (%at-stop-word? cur) left
                    (list (lit sh-seq) left (%parse-list cur))))
              (if (%match-op cur "&")
                (let ((bg (list (lit sh-bg) left)))
                  (%skip-newlines cur)
                  (if (%at-stop-word? cur) bg
                    (list (lit sh-seq) bg (%parse-list cur))))
                left)))))))))

; --- Public API ---

(def sh-parse (fn (input)
  (let ((tokens (sh-tokenize input)))
    (if (null? tokens) ()
      (let ((cur (%mk-cursor tokens)))
        (%parse-list cur))))))
