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
; Block reader
; ============================================================
; Accumulates lines until blank line or dedent to col 0.
; Single unindented lines return immediately (no double-enter).
; TO definitions wait for an indented body.

(def %read-block
  (fn ()
    (def %rb
      (fn (self lines saw-indent)
        (def line (%read-line))
        (if (null? line)
          (if (null? lines) () (apply str (reverse lines)))
          (if (str=? line "")
            (if (null? lines)
              (self () #f)
              (apply str (reverse lines)))
            (let ((has-indent (if (char=? (line 0) #\space) #t
                               (if (char=? (line 0) #\tab) #t #f))))
              (if (if saw-indent #t #f)
                (if has-indent
                  (self (pair (str "\n" line) lines) #t)
                  (apply str (reverse (pair (str "\n" line) lines))))
                (if has-indent
                  (self (pair (str "\n" line) lines) #t)
                  (if (null? lines)
                    (if (if (>= (str-length line) 3)
                          (str=? (str-upcase (substring line 0 3)) "TO ") #f)
                      (self (pair (str "\n" line) ()) #t)
                      (str "\n" line))
                    (apply str (reverse (pair (str "\n" line) lines)))))))))))
    (%rb () #f)))

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
