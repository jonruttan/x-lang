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
; Balance checking
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
        (char=? (line 0) #\tab)))))

; Probe: try processing accumulated input.
; If it succeeds, the input was complete.
; If it errors, the input is incomplete — keep reading.
(def %is-complete?
  (fn (_ text depth)
    (if (> depth 0) #f
      (guard (err #f)
        (def tokens (token-read-string %logo-base (str text " ")))
        (def processed (%logo-indent-to-blocks tokens))
        (logo-process-tokens processed)
        #t))))

; ============================================================
; Block reader
; ============================================================

(def %read-block
  (fn ()
    (def %rb
      (fn (self lines depth)
        (def line (%read-line))
        (if (null? line)
          ; EOF
          (if (null? lines) () (apply str (reverse lines)))
          (if (str=? line "")
            ; Blank line
            (if (null? lines)
              (self () 0)
              (if (> depth 0)
                (self lines depth)
                ; Balanced — probe for completeness
                (if (%is-complete? (apply str (reverse lines)) depth)
                  (apply str (reverse lines))
                  (self lines depth))))
            ; Non-empty line
            (let ((new-depth (+ depth (%count-brackets line)))
                  (new-lines (pair (str "\n" line) lines)))
              (if (> new-depth 0)
                (self new-lines new-depth)
                (if (%is-indented? line)
                  (self new-lines new-depth)
                  ; Col 0, balanced — probe for completeness
                  (if (%is-complete? (apply str (reverse new-lines)) new-depth)
                    (apply str (reverse new-lines))
                    (self new-lines new-depth)))))))))
    (%rb () 0)))

; ============================================================
; REPL
; ============================================================

; Install ctrl-c handler so it breaks loops instead of killing the process
(sigint-install)

(def %logo-prompt "? ")
(def %logo-on-exit ())
(def %logo-on-command ())

(def logo-repl
  (op ()
    ()
    (display %logo-prompt)
    (def block (%read-block))
    (if (null? block)
      ; EOF — but if ctrl-c caused it, retry instead of exiting
      (if (sigint-check)
        (do (newline) (logo-repl))
        (if (null? %logo-on-exit) () (%logo-on-exit)))
      (do
        (guard (err
            (%stderr "Error: ")
            (%stderr (if (str? err) err
                      (if (number? err) (number->str err)
                        (symbol->str err))))
            (%stderr "\n"))
          ; Block already executed by %is-complete? probe —
          ; no need to process again
          (if (null? %logo-on-command) () (%logo-on-command)))
        (logo-repl)))))

(provide x/logo/repl
  logo-repl %logo-on-exit %logo-on-command)
