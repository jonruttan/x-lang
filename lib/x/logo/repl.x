; repl.x -- Logo REPL with multiline block reading
(import x/logo/types)
(import x/logo/dispatch)
(import x/logo/indent)

; ============================================================
; Line reader
; ============================================================

(def %read-line
  (fn ()
    (def %rl
      (fn (self acc)
        (def ch (read-char))
        (if (null? ch)
          (if (null? acc) () (list->str (reverse acc)))
          (if (= ch 10)
            (list->str (reverse acc))
            (self (pair (integer->char ch) acc))))))
    (%rl ())))

; ============================================================
; Bracket counting
; ============================================================

(def %count-brackets
  (fn (_ line)
    (def %cb
      (fn (self i depth)
        (if (>= i (str-length line)) depth
          (self (+ i 1)
            (if (char=? (line i) #\[) (+ depth 1)
              (if (char=? (line i) #\]) (- depth 1)
                depth))))))
    (%cb 0 0)))

(def %is-indented?
  (fn (_ line)
    (if (str=? line "") #f
      (if (char=? (line 0) #\space) #t
        (if (char=? (line 0) #\tab) #t #f)))))

; ============================================================
; Block reader
; ============================================================
; Rule: keep reading while there's an unmatched [ or the line is indented.
; After a col-0 balanced first line, peek ahead — if next line is indented,
; continue reading (it's the start of a multi-line block).

(def %repl-lookahead ())

(def %read-block
  (fn ()
    (def %rb
      (fn (self lines depth)
        ; Use lookahead if available
        (def line
          (if (null? %repl-lookahead) (%read-line)
            (let ((l %repl-lookahead))
              (set! %repl-lookahead ())
              l)))
        (if (null? line)
          ; EOF
          (if (null? lines) () (apply str (reverse lines)))
          (if (str=? line "")
            ; Blank line
            (if (> depth 0)
              (self lines depth)          ; open bracket — keep reading
              (if (null? lines)
                (self () 0)               ; skip leading blanks
                (apply str (reverse lines))))
            ; Non-empty line
            (let ((new-depth (+ depth (%count-brackets line))))
              (def new-lines (pair (str "\n" line) lines))
              (if (> new-depth 0)
                ; Open bracket — keep reading
                (self new-lines new-depth)
                (if (%is-indented? line)
                  ; Indented — keep reading
                  (self new-lines new-depth)
                  ; Col 0, balanced
                  (if (null? lines)
                    ; First line — peek ahead for indented continuation
                    (let ((next (%read-line)))
                      (if (null? next)
                        (apply str (reverse new-lines))
                        (if (str=? next "")
                          (apply str (reverse new-lines))
                          (if (%is-indented? next)
                            ; Next is indented — multi-line block, continue
                            (self (pair (str "\n" next) new-lines)
                                  (+ new-depth (%count-brackets next)))
                            ; Next is col 0 — save for next call, return first
                            (do (set! %repl-lookahead next)
                                (apply str (reverse new-lines)))))))
                    ; Continuation at col 0 — done
                    (apply str (reverse new-lines))))))))))
    (%rb () 0)))

; ============================================================
; REPL
; ============================================================

(def %logo-prompt "? ")
(def %logo-on-exit ())
(def %logo-on-command ())

(def logo-repl
  (op ()
    ()
    (display %logo-prompt)
    (def block (%read-block))
    (if (null? block)
      (if (null? %logo-on-exit) () (%logo-on-exit))
      (do
        (guard (err
            (%stderr "Error: ")
            (%stderr (if (str? err) err
                      (if (number? err) (number->str err)
                        (symbol->str err))))
            (%stderr "\n"))
          (def tokens (token-read-string %logo-base (str block " ")))
          (def processed (%logo-indent-to-blocks tokens))
          (logo-process-tokens processed)
          (if (null? %logo-on-command) () (%logo-on-command)))
        (logo-repl)))))

(provide x/logo/repl
  logo-repl %logo-on-exit %logo-on-command)
