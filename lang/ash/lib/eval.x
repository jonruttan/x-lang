; eval.x -- Combined token-list evaluator for ASH shell
;
; Replaces parser.x + old eval.x. Works directly on the flat
; token list from sh-tokenize using recursive descent that
; evaluates as it goes.
;
; Grammar (precedence low to high):
;   list      = and_or ((';'|'&'|newline) and_or)*
;   and_or    = pipeline (('&&'|'||') pipeline)*
;   pipeline  = command ('|' command)*
;   command   = compound | simple
;   compound  = if | while | for | '(' list ')'
;   simple    = (word|redirect)+
; --- Shell state ---

(def %sh-status 0)

(def %sh-pid (sh-getpid))
; --- Cursor: mutable box holding remaining token list ---

(def %mk-cursor (fn (tokens) (pair tokens ())))

(def %cursor-peek
  (fn (cur) (if (null? (first cur)) () (first (first cur)))))

(def %cursor-advance!
  (fn (cur) (set-first cur (rest (first cur))) ()))

(def %cursor-empty? (fn (cur) (null? (first cur))))
; --- Token predicates ---

(def %tok-is-word?
  (fn (tok)
    (or
      (eq? (first tok) (lit tok-word))
      (eq? (first tok) (lit tok-sq))
      (eq? (first tok) (lit tok-dq)))))

(def %tok-is-op?
  (fn (tok op)
    (and
      (eq? (first tok) (lit tok-op))
      (string=? (first (rest tok)) op))))

(def %tok-is-newline?
  (fn (tok) (eq? (first tok) (lit tok-newline))))

(def %tok-word-val
  (fn (tok)
    (if (eq? (first tok) (lit tok-newline))
      ()
      (first (rest tok)))))
; --- Match helpers ---

(def %match-op
  (fn (cur op)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-op))
              (string=? (first (rest tok)) op))
          (do (%cursor-advance! cur) t)
          ())))))

(def %skip-newlines
  (fn (cur)
    (if (and
          (not (%cursor-empty? cur))
          (%tok-is-newline? (%cursor-peek cur)))
      (do (%cursor-advance! cur) (%skip-newlines cur))
      ())))
; --- Reserved word check ---

(def %reserved-word?
  (fn (word)
    (or
      (string=? word "if")
      (string=? word "then")
      (string=? word "elif")
      (string=? word "else")
      (string=? word "fi")
      (string=? word "while")
      (string=? word "until")
      (string=? word "for")
      (string=? word "do")
      (string=? word "done")
      (string=? word "case")
      (string=? word "in")
      (string=? word "esac")
      (string=? word "!")
      (string=? word "{")
      (string=? word "}"))))
; --- Stop-word helper ---

(def %at-stop-word?
  (fn (cur)
    (if (%cursor-empty? cur)
      t
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (first (rest tok))))
            (or
              (string=? w "then")
              (string=? w "elif")
              (string=? w "else")
              (string=? w "fi")
              (string=? w "do")
              (string=? w "done")
              (string=? w "esac")
              (string=? w "}")))
          (if (eq? (first tok) (lit tok-op))
            (or
              (string=? (first (rest tok)) ")")
              (string=? (first (rest tok)) ";;"))
            ()))))))

(def %expect-word
  (fn (cur word)
    (if (%cursor-empty? cur)
      (error (string-append "parse error: expected " word))
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-word))
              (string=? (first (rest tok)) word))
          (do (%cursor-advance! cur) t)
          (error (string-append "parse error: expected " word)))))))
; --- Variable expansion ---

(def %sh-expand-word
  (fn (word)
    (if (not (string? word))
      word
      (if (= (string-length word) 0)
        word
        (if (not
              (= (char->integer (string-ref word 0)) (char->integer #\$)))
          word
          (let ((name (substring word 1 (string-length word))))
            (if (string=? name "?")
              (number->string %sh-status)
              (if (string=? name "$")
                (number->string %sh-pid)
                (let ((val (sh-getenv name))) (if (null? val) "" val))))))))))

(def %sh-expand-words
  (fn (wds)
    (if (null? wds)
      ()
      (pair
        (%sh-expand-word (first wds))
        (%sh-expand-words (rest wds))))))
; --- Redirection ---

(def %redir-op?
  (fn (tok)
    (if (not (eq? (first tok) (lit tok-op)))
      ()
      (let ((op (first (rest tok))))
        (if (or
              (string=? op "<")
              (string=? op ">")
              (string=? op ">>")
              (string=? op "<<")
              (string=? op "<&")
              (string=? op ">&")
              (string=? op "<>")
              (string=? op ">|")
              (string=? op "<<-"))
          op
          ())))))

(def %all-digits?
  (fn (s)
    (def %check ())
    (set %check
      (fn (i len)
        (if (= i len)
          t
          (let ((c (char->integer (string-ref s i))))
            (if (and (>= c (char->integer #\0)) (<= c (char->integer #\9)))
              (%check (+ i 1) len)
              ())))))
    (if (= (string-length s) 0)
      ()
      (%check 0 (string-length s)))))

(def %default-fd
  (fn (op)
    (if (string=? op "<")
      0
      (if (string=? op "<>") 0 (if (string=? op "<&") 0 1)))))

(def %sh-setup-redir
  (fn (redir)
    (let ((op (first (rest redir)))
           (fd-val (first (rest (rest redir))))
           (target
             (%sh-expand-word (first (rest (rest (rest redir)))))))
      (let ((fd (if (string? fd-val) (string->number fd-val) fd-val)))
        (if (string=? op "<")
          (let ((fh (sh-open-read target)))
            (sh-dup2 fh fd)
            (sh-close fh))
          (if (string=? op ">")
            (let ((fh (sh-open-write target)))
              (sh-dup2 fh fd)
              (sh-close fh))
            (if (string=? op ">>")
              (let ((fh (sh-open-append target)))
                (sh-dup2 fh fd)
                (sh-close fh))
              (if (string=? op "<>")
                (let ((fh (sh-open-read target)))
                  (sh-dup2 fh fd)
                  (sh-close fh))
                (if (string=? op ">&")
                  (sh-dup2 (string->number target) fd)
                  (if (string=? op "<&")
                    (sh-dup2 (string->number target) fd)
                    ()))))))))))

(def %sh-setup-redirs
  (fn (redirs)
    (if (null? redirs)
      ()
      (do
        (%sh-setup-redir (first redirs))
        (%sh-setup-redirs (rest redirs))))))
; --- Built-in commands ---

(def %sh-builtin?
  (fn (name)
    (or
      (string=? name "echo")
      (string=? name "cd")
      (string=? name "export")
      (string=? name "exit")
      (string=? name "true")
      (string=? name "false")
      (string=? name ":")
      (string=? name "test")
      (string=? name "["))))

(def %sh-echo
  (fn (wds)
    (def %print-words ())
    (set %print-words
      (fn (ws first-word)
        (if (null? ws)
          ()
          (do
            (if first-word () (display " "))
            (display (first ws))
            (%print-words (rest ws) ())))))
    (%print-words wds t)
    (newline)
    0))

(def %sh-cd
  (fn (wds)
    (let ((dir
            (if (null? wds)
              (let ((home (sh-getenv "HOME")))
                (if (null? home) "/" home))
              (first wds))))
      (let ((result (sh-chdir dir)))
        (if (= result -1)
          (do
            (display "ash: cd: ")
            (display dir)
            (display ": No such file or directory")
            (newline)
            1)
          0)))))

(def %sh-export
  (fn (wds)
    (if (null? wds)
      0
      (let ((word (first wds)))
        (def %find-eq ())
        (set %find-eq
          (fn (i)
            (if (= i (string-length word))
              -1
              (if (= (char->integer (string-ref word i)) (char->integer #\=))
                i
                (%find-eq (+ i 1))))))
        (let ((eq-pos (%find-eq 0)))
          (if (= eq-pos -1)
            0
            (do
              (sh-setenv
                (substring word 0 eq-pos)
                (substring word (+ eq-pos 1) (string-length word)))
              0)))))))

(def %sh-test
  (fn (wds)
    (if (null? wds)
      1
      (if (= (length wds) 1)
        (if (= (string-length (first wds)) 0) 1 0)
        (if (= (length wds) 2)
          (let ((op (first wds)) (val (first (rest wds))))
            (if (string=? op "-n")
              (if (= (string-length val) 0) 1 0)
              (if (string=? op "-z")
                (if (= (string-length val) 0) 0 1)
                (if (string=? op "!")
                  (if (= (%sh-test (rest wds)) 0) 1 0)
                  1))))
          (if (= (length wds) 3)
            (let ((left (first wds))
                   (op (first (rest wds)))
                   (right (first (rest (rest wds)))))
              (if (string=? op "=")
                (if (string=? left right) 0 1)
                (if (string=? op "!=") (if (string=? left right) 1 0) 1)))
            1))))))

(def %sh-run-builtin
  (fn (name wds)
    (if (string=? name "echo")
      (%sh-echo wds)
      (if (string=? name "cd")
        (%sh-cd wds)
        (if (string=? name "export")
          (%sh-export wds)
          (if (string=? name "exit")
            (sh-exit
              (if (null? wds) %sh-status (string->number (first wds))))
            (if (string=? name "true")
              0
              (if (string=? name "false")
                1
                (if (string=? name ":")
                  0
                  (if (string=? name "test")
                    (%sh-test wds)
                    (if (string=? name "[")
                      (let ((test-wds
                              (if (string=? (last wds) "]")
                                (take (- (length wds) 1) wds)
                                wds)))
                        (%sh-test test-wds))
                      1)))))))))))
; --- External command execution ---

(def %sh-run-external
  (fn (name wds redirs)
    (let ((pid (sh-fork)))
      (if (= pid 0)
        (do
          (%sh-setup-redirs redirs)
          (sh-exec name wds)
          (display "ash: ")
          (display name)
          (display ": command not found")
          (newline)
          (sh-exit 127))
        (sh-wait pid)))))
; --- Assignment handling ---

(def %is-assignment?
  (fn (word)
    (def %has-eq ())
    (set %has-eq
      (fn (i)
        (if (= i (string-length word))
          ()
          (if (= (char->integer (string-ref word i)) (char->integer #\=))
            (if (= i 0) () t)
            (%has-eq (+ i 1))))))
    (if (= (string-length word) 0) () (%has-eq 0))))

(def %process-assignments
  (fn (wds)
    (if (null? wds)
      ()
      (if (%is-assignment? (first wds))
        (do
          (%sh-export (list (first wds)))
          (%process-assignments (rest wds)))
        wds))))
; --- Execute collected command ---

(def %sh-run-cmd
  (fn (wds redirs)
    (let ((expanded (%sh-expand-words wds)))
      (let ((remaining (%process-assignments expanded)))
        (if (null? remaining)
          (do (set %sh-status 0) 0)
          (let ((name (first remaining)) (cmd-wds (rest remaining)))
            (if (%sh-builtin? name)
              (let ((status (%sh-run-builtin name cmd-wds)))
                (set %sh-status status)
                status)
              (let ((status (%sh-run-external name cmd-wds redirs)))
                (set %sh-status status)
                status))))))))
; Save C pipe primitive before we shadow it

(def %sh-pipe-create sh-pipe)
; --- Forward declarations ---

(def %eval-list ())

(def %eval-command ())

(def %sh-pipe-chain ())

(def %skip-to-fi ())

(def %skip-body-to-elif-else-fi ())

(def %eval-elif-chain ())

(def %skip-to-done ())

(def %eval-while-body ())

(def %eval-until-body ())

(def %eval-for-body ())

(def %eval-case-clauses ())
; --- Compound command detection ---

(def %is-compound-start?
  (fn (cur)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (first (rest tok))))
            (or
              (string=? w "if")
              (string=? w "while")
              (string=? w "until")
              (string=? w "for")
              (string=? w "case")))
          (if (eq? (first tok) (lit tok-op))
            (string=? (first (rest tok)) "(")
            ()))))))
; --- Simple command: collect words/redirects and execute ---

(def %collect-cmd-tokens ())

(set %collect-cmd-tokens
  (fn (cur wds redirs)
    (if (%cursor-empty? cur)
      (%sh-run-cmd (reverse wds) (reverse redirs))
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-newline? tok)
          (%sh-run-cmd (reverse wds) (reverse redirs))
          (let ((rop (%redir-op? tok)))
            (if rop
              (do
                (%cursor-advance! cur)
                (let ((fd
                        (if (and (not (null? wds)) (%all-digits? (first wds)))
                          (let ((n (first wds))) (set wds (rest wds)) n)
                          (%default-fd rop))))
                  (if (%cursor-empty? cur)
                    (error "parse error: redirect without target")
                    (let ((target (%tok-word-val (%cursor-peek cur))))
                      (%cursor-advance! cur)
                      (%collect-cmd-tokens
                        cur
                        wds
                        (pair (list (lit sh-redir) rop fd target) redirs))))))
              (if (%tok-is-word? tok)
                (let ((val (%tok-word-val tok)))
                  (if (and
                        (not (null? wds))
                        (eq? (first tok) (lit tok-word))
                        (%reserved-word? val))
                    (%sh-run-cmd (reverse wds) (reverse redirs))
                    (do
                      (%cursor-advance! cur)
                      (%collect-cmd-tokens cur (pair val wds) redirs))))
                (%sh-run-cmd (reverse wds) (reverse redirs))))))))))

(def %eval-simple-cmd
  (fn (cur) (%collect-cmd-tokens cur () ())))
; --- Compound commands: parse structure, evaluate directly ---
; if cond; then body [elif cond; then body]... [else body] fi

(def %eval-if
  (fn (cur)
    (%cursor-advance! cur)
    ; consume 'if'

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "then")
      (%skip-newlines cur)
      (if (= cond-result 0)
        ; True: eval body, skip remaining

        (let ((result (%eval-list cur)))
          (%skip-to-fi cur 0)
          (set %sh-status result)
          result)
        ; False: skip body, try elif/else

        (do
          (%skip-body-to-elif-else-fi cur 0)
          (%eval-elif-chain cur))))))
; Skip balanced tokens to elif/else/fi at depth 0

(set %skip-body-to-elif-else-fi
  (fn (cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in if")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-word? tok)
          (let ((w (%tok-word-val tok)))
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "case"))
              (do
                (%cursor-advance! cur)
                (%skip-body-to-elif-else-fi cur (+ depth 1)))
              (if (or
                    (string=? w "fi")
                    (string=? w "done")
                    (string=? w "esac"))
                (if (= depth 0)
                  ; fi at our level: consume and stop

                  (do (%cursor-advance! cur) ())
                  (do
                    (%cursor-advance! cur)
                    (%skip-body-to-elif-else-fi cur (- depth 1))))
                (if (and
                      (= depth 0)
                      (or (string=? w "elif") (string=? w "else")))
                  ; Stop here (don't consume) for elif/else handling

                  ()
                  (do
                    (%cursor-advance! cur)
                    (%skip-body-to-elif-else-fi cur depth))))))
          (do
            (%cursor-advance! cur)
            (%skip-body-to-elif-else-fi cur depth)))))))
; Skip to matching fi (after we evaluated the true branch)

(set %skip-to-fi
  (fn (cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in if")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-word? tok)
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "for"))
              (%skip-to-fi cur (+ depth 1))
              (if (string=? w "fi")
                (if (= depth 0) () (%skip-to-fi cur (- depth 1)))
                (if (string=? w "done")
                  (%skip-to-fi cur (- depth 1))
                  (%skip-to-fi cur depth)))))
          (do (%cursor-advance! cur) (%skip-to-fi cur depth)))))))
; Handle elif/else chain after condition was false

(set %eval-elif-chain
  (fn (cur)
    (if (%cursor-empty? cur)
      (error "parse error: expected fi")
      (let ((tok (%cursor-peek cur)))
        (if (and
              (%tok-is-word? tok)
              (string=? (%tok-word-val tok) "elif"))
          ; elif: evaluate its condition

          (do
            (%cursor-advance! cur)
            (%skip-newlines cur)
            (let ((cond-result (%eval-list cur)))
              (%skip-newlines cur)
              (%expect-word cur "then")
              (%skip-newlines cur)
              (if (= cond-result 0)
                (let ((result (%eval-list cur)))
                  (%skip-to-fi cur 0)
                  (set %sh-status result)
                  result)
                (do
                  (%skip-body-to-elif-else-fi cur 0)
                  (%eval-elif-chain cur)))))
          (if (and
                (%tok-is-word? tok)
                (string=? (%tok-word-val tok) "else"))
            ; else: evaluate body, expect fi

            (do
              (%cursor-advance! cur)
              (%skip-newlines cur)
              (let ((result (%eval-list cur)))
                (%skip-newlines cur)
                (%expect-word cur "fi")
                (set %sh-status result)
                result))
            (if (and
                  (%tok-is-word? tok)
                  (string=? (%tok-word-val tok) "fi"))
              ; fi: no else, return 0

              (do (%cursor-advance! cur) (set %sh-status 0) 0)
              (error "parse error: expected elif, else, or fi"))))))))
; while cond; do body; done

(def %eval-while
  (fn (cur)
    (%cursor-advance! cur)
    ; consume 'while'

    ; Save position to loop back

    (let ((saved (first cur))) (%eval-while-body cur saved))))

(set %eval-while-body
  (fn (cur saved)
    (set-first cur saved)
    ; reset cursor to condition

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (= cond-result 0)
        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (let ((new-saved saved)) (%eval-while-body cur new-saved)))
        ; Condition false: skip body, done

        (do (%skip-to-done cur 0) (set %sh-status 0) 0)))))
; until cond; do body; done (loops while condition fails)

(def %eval-until
  (fn (cur)
    (%cursor-advance! cur)
    ; consume 'until'

    (let ((saved (first cur))) (%eval-until-body cur saved))))

(set %eval-until-body
  (fn (cur saved)
    (set-first cur saved)
    ; reset cursor to condition

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (not (= cond-result 0))
        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (let ((new-saved saved)) (%eval-until-body cur new-saved)))
        ; Condition succeeded: skip body, done

        (do (%skip-to-done cur 0) (set %sh-status 0) 0)))))
; Skip to matching done

(set %skip-to-done
  (fn (cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in while")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-word? tok)
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "if")
                  (string=? w "case"))
              (%skip-to-done cur (+ depth 1))
              (if (or
                    (string=? w "done")
                    (string=? w "fi")
                    (string=? w "esac"))
                (if (= depth 0) () (%skip-to-done cur (- depth 1)))
                (%skip-to-done cur depth))))
          (do (%cursor-advance! cur) (%skip-to-done cur depth)))))))
; Collect for-in word list from cursor

(def %collect-for-words ())

(set %collect-for-words
  (fn (cur ws)
    (if (or
          (%cursor-empty? cur)
          (%tok-is-newline? (%cursor-peek cur))
          (and
            (eq? (first (%cursor-peek cur)) (lit tok-op))
            (string=? (first (rest (%cursor-peek cur))) ";")))
      (reverse ws)
      (let ((w (%tok-word-val (%cursor-peek cur))))
        (%cursor-advance! cur)
        (%collect-for-words cur (pair w ws))))))
; for var [in words...]; do body; done

(def %eval-for
  (fn (cur)
    (%cursor-advance! cur)
    ; consume 'for'

    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (error "parse error: for without variable")
      (let ((var (%tok-word-val (%cursor-peek cur))))
        (%cursor-advance! cur)
        (%skip-newlines cur)
        ; Collect in-list if present

        (let ((words
                (if (and
                      (not (%cursor-empty? cur))
                      (eq? (first (%cursor-peek cur)) (lit tok-word))
                      (string=? (first (rest (%cursor-peek cur))) "in"))
                  (do
                    (%cursor-advance! cur)
                    ; consume 'in'

                    (%collect-for-words cur ()))
                  ())))
          ; Skip separator

          (%skip-newlines cur)
          (if (not (%cursor-empty? cur))
            (if (%match-op cur ";") (%skip-newlines cur) ())
            ())
          (%expect-word cur "do")
          (%skip-newlines cur)
          ; Save position for looping

          (let ((body-start (first cur))
                 (expanded (%sh-expand-words words)))
            (%eval-for-body cur var expanded body-start)))))))

(set %eval-for-body
  (fn (cur var words body-start)
    (if (null? words)
      (do (set %sh-status 0) 0)
      (do
        (sh-setenv var (first words))
        (set-first cur body-start)
        ; reset to body

        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (if (null? (rest words))
            (do (set %sh-status 0) 0)
            (%eval-for-body cur var (rest words) body-start)))))))
; case WORD in PATTERN[|PATTERN]...) BODY;; ... esac

(def %sh-pattern-match?
  (fn (pat word)
    (if (string=? pat "*") t (string=? pat word))))

(def %collect-case-patterns ())

(set %collect-case-patterns
  (fn (cur pats)
    (if (%cursor-empty? cur)
      (error "parse error: expected ) in case")
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-op))
              (string=? (first (rest tok)) ")"))
          (do (%cursor-advance! cur) (reverse pats))
          (if (and
                (eq? (first tok) (lit tok-op))
                (string=? (first (rest tok)) "|"))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns cur pats))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns
                cur
                (pair (%tok-word-val tok) pats)))))))))

(def %case-match?
  (fn (pats word)
    (if (null? pats)
      ()
      (if (%sh-pattern-match? (first pats) word)
        t
        (%case-match? (rest pats) word)))))

(def %skip-case-body ())

(set %skip-case-body
  (fn (cur depth)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (and (= depth 0) (string=? w "esac"))
              ()
              (if (or
                    (string=? w "if")
                    (string=? w "while")
                    (string=? w "until")
                    (string=? w "for")
                    (string=? w "case"))
                (%skip-case-body cur (+ depth 1))
                (if (or
                      (string=? w "fi")
                      (string=? w "done")
                      (string=? w "esac"))
                  (%skip-case-body cur (- depth 1))
                  (%skip-case-body cur depth)))))
          (if (eq? (first tok) (lit tok-op))
            (do
              (%cursor-advance! cur)
              (if (and (= depth 0) (string=? (first (rest tok)) ";;"))
                ()
                (%skip-case-body cur depth)))
            (do (%cursor-advance! cur) (%skip-case-body cur depth))))))))

(def %skip-to-esac ())

(set %skip-to-esac
  (fn (cur depth)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "case"))
              (%skip-to-esac cur (+ depth 1))
              (if (or
                    (string=? w "fi")
                    (string=? w "done")
                    (string=? w "esac"))
                (if (= depth 0) () (%skip-to-esac cur (- depth 1)))
                (%skip-to-esac cur depth))))
          (do (%cursor-advance! cur) (%skip-to-esac cur depth)))))))

(set %eval-case-clauses
  (fn (cur word)
    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (do (set %sh-status 0) 0)
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-word))
              (string=? (first (rest tok)) "esac"))
          (do (%cursor-advance! cur) (set %sh-status 0) 0)
          (let ((pats (%collect-case-patterns cur ())))
            (%skip-newlines cur)
            (if (%case-match? pats word)
              ; Match: evaluate body, skip remaining

              (let ((result (%eval-list cur)))
                ; Consume ;; if present

                (if (and
                      (not (%cursor-empty? cur))
                      (not (eq? (first (%cursor-peek cur)) (lit tok-word))))
                  (if (and
                        (eq? (first (%cursor-peek cur)) (lit tok-op))
                        (string=? (first (rest (%cursor-peek cur))) ";;"))
                    (%cursor-advance! cur)
                    ())
                  ())
                (%skip-to-esac cur 0)
                (set %sh-status result)
                result)
              ; No match: skip body, try next clause

              (do (%skip-case-body cur 0) (%eval-case-clauses cur word)))))))))

(def %eval-case
  (fn (cur)
    (%cursor-advance! cur)
    ; consume 'case'

    (let ((word-tok (%cursor-peek cur)))
      (%cursor-advance! cur)
      ; consume WORD

      (let ((word (%sh-expand-word (%tok-word-val word-tok))))
        (%skip-newlines cur)
        (%expect-word cur "in")
        (%skip-newlines cur)
        (%eval-case-clauses cur word)))))
; ( list ) — subshell

(def %eval-subshell
  (fn (cur)
    (%cursor-advance! cur)
    ; consume '('

    (%skip-newlines cur)
    (let ((pid (sh-fork)))
      (if (= pid 0)
        (do (%eval-list cur) (sh-exit %sh-status))
        ; Parent: skip to matching )

        (do
          (%skip-to-close-paren cur 0)
          (let ((status (sh-wait pid)))
            (set %sh-status status)
            status))))))

(def %skip-to-close-paren
  (fn (cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: expected )")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (eq? (first tok) (lit tok-op))
          (let ((op (first (rest tok))))
            (if (string=? op "(")
              (%skip-to-close-paren cur (+ depth 1))
              (if (string=? op ")")
                (if (= depth 0) () (%skip-to-close-paren cur (- depth 1)))
                (%skip-to-close-paren cur depth))))
          (%skip-to-close-paren cur depth))))))
; --- Compound command dispatch ---

(def %eval-compound
  (fn (cur)
    (let ((tok (%cursor-peek cur)))
      (if (eq? (first tok) (lit tok-op))
        (%eval-subshell cur)
        (let ((word (first (rest tok))))
          (if (string=? word "if")
            (%eval-if cur)
            (if (string=? word "while")
              (%eval-while cur)
              (if (string=? word "until")
                (%eval-until cur)
                (if (string=? word "for")
                  (%eval-for cur)
                  (if (string=? word "case")
                    (%eval-case cur)
                    (error (string-append "parse error: unexpected " word))))))))))))
; --- Pipeline execution ---

(set %sh-pipe-chain
  (fn (cmds)
    (if (null? (rest cmds))
      ; Last command: evaluate directly

      (let ((cur (%mk-cursor (first cmds)))) (%eval-command cur))
      ; Pipe: fork left, chain right

      (let ((p (%sh-pipe-create))
             (left-tokens (first cmds))
             (rest-cmds (rest cmds)))
        (let ((read-fd (first p)) (write-fd (rest p)) (pid (sh-fork)))
          (if (= pid 0)
            ; Child: stdout → pipe, eval left

            (do
              (sh-close read-fd)
              (sh-dup2 write-fd 1)
              (sh-close write-fd)
              (let ((cur (%mk-cursor left-tokens))) (%eval-command cur))
              (sh-exit %sh-status))
            ; Parent: stdin ← pipe, continue chain

            (do
              (sh-close write-fd)
              (sh-dup2 read-fd 0)
              (sh-close read-fd)
              (let ((result (%sh-pipe-chain rest-cmds)))
                (sh-wait pid)
                result))))))))
; --- Recursive descent evaluator ---
; command: compound or simple

(set %eval-command
  (fn (cur)
    (if (%is-compound-start? cur)
      (%eval-compound cur)
      (%eval-simple-cmd cur))))
; --- Pipeline stage collection ---
; Collect tokens for one stage (until | or end of command)

(def %collect-stage ())

(set %collect-stage
  (fn (cur toks)
    (if (%cursor-empty? cur)
      (reverse toks)
      (let ((tok (%cursor-peek cur)))
        (if (or
              (%tok-is-newline? tok)
              (%tok-is-op? tok "|")
              (%tok-is-op? tok ";")
              (%tok-is-op? tok "&")
              (%tok-is-op? tok "&&")
              (%tok-is-op? tok "||"))
          (reverse toks)
          (if (and (%tok-is-word? tok) (%at-stop-word? cur))
            (reverse toks)
            (do
              (%cursor-advance! cur)
              (%collect-stage cur (pair tok toks)))))))))
; Collect all pipeline stages

(def %collect-stages ())

(set %collect-stages
  (fn (cur stages)
    (let ((stage (%collect-stage cur ())))
      (if (%match-op cur "|")
        (do
          (%skip-newlines cur)
          (%collect-stages cur (pair stage stages)))
        (reverse (pair stage stages))))))
; pipeline: ['!'] command ('|' command)*

(def %eval-pipeline
  (fn (cur)
    (%skip-newlines cur)
    ; Check for ! negation

    (let ((negate
            (if (and
                  (not (%cursor-empty? cur))
                  (%tok-is-word? (%cursor-peek cur))
                  (string=? (%tok-word-val (%cursor-peek cur)) "!"))
              (do (%cursor-advance! cur) (%skip-newlines cur) t)
              ())))
      ; Compound commands (if/while/for) contain internal ';' delimiters

      ; that %collect-stage would incorrectly split on. Handle directly.

      (let ((result
              (if (%is-compound-start? cur)
                (%eval-compound cur)
                (let ((stages (%collect-stages cur ())))
                  (if (null? (rest stages))
                    (let ((cur (%mk-cursor (first stages))))
                      (%eval-command cur))
                    (%sh-pipe-chain stages))))))
        (if negate
          (let ((neg-result (if (= result 0) 1 0)))
            (set %sh-status neg-result)
            neg-result)
          result)))))
; and_or: pipeline (('&&'|'||') pipeline)*

(def %eval-and-or
  (fn (cur)
    (let ((result (%eval-pipeline cur)))
      (if (%cursor-empty? cur)
        result
        (if (%match-op cur "&&")
          (do
            (%skip-newlines cur)
            (if (= result 0)
              (%eval-and-or cur)
              ; Short-circuit: skip remaining, but need to not evaluate right side

              ; Actually, since we use recursive descent, the right side

              ; won't be evaluated if we just return

              result))
          (if (%match-op cur "||")
            (do
              (%skip-newlines cur)
              (if (= result 0) 0 (%eval-and-or cur)))
            result))))))
; list: and_or ((';'|'&'|newline) and_or)*

(set %eval-list
  (fn (cur)
    (%skip-newlines cur)
    (if (%at-stop-word? cur)
      (do (set %sh-status 0) 0)
      (let ((result (%eval-and-or cur)))
        (if (%cursor-empty? cur)
          result
          (let ((tok (%cursor-peek cur)))
            (if (%tok-is-newline? tok)
              (do
                (%cursor-advance! cur)
                (%skip-newlines cur)
                (if (%at-stop-word? cur) result (%eval-list cur)))
              (if (%match-op cur ";")
                (do
                  (%skip-newlines cur)
                  (if (%at-stop-word? cur) result (%eval-list cur)))
                (if (%match-op cur "&")
                  (let ((pid (sh-fork)))
                    (if (= pid 0)
                      (do result (sh-exit 0))
                      (do
                        (set %sh-status 0)
                        (%skip-newlines cur)
                        (if (%at-stop-word? cur) 0 (%eval-list cur)))))
                  result)))))))))
; --- Public API ---

(def sh-eval
  (fn (input)
    (let ((tokens (sh-tokenize input)))
      (if (null? tokens)
        0
        (let ((cur (%mk-cursor tokens))) (%eval-list cur))))))
