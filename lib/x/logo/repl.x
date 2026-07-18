; repl.x -- Logo REPL with multiline block reading
(import x/logo/types)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))

(import x/logo/dispatch)
(import x/logo/indent)
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read-char (prim-ref 'io 'read-char))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %integer->char (prim-ref 'int '->char))



; ============================================================
; Line reader
; ============================================================

(def %read-line
  (fn ()
    (def %rl
      (fn (self acc)
        (def ch (%read-char))
        ; bytes->str, not list->str: acc holds raw input BYTES; the utf8-aware
        ; list->str would re-encode bytes >= 128, corrupting UTF-8 input.
        (if (null? ch)
          (unless (null? acc) (bytes->str (reverse acc)))
          (if (= ch 10)
            (bytes->str (reverse acc))
            (self (pair (%integer->char ch) acc))))))
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
            (if (Char =? (str-ref line i) #\[) (+ depth 1)
              (if (Char =? (str-ref line i) #\]) (- depth 1)
                depth))))))
    (%cb 0 0)))

(def %is-indented?
  (fn (_ line)
    (if (str=? line "") #f
      (if (Char =? (str-ref line 0) #\space) #t
        (Char =? (str-ref line 0) #\tab)))))

; Probe: try processing accumulated input.
; If it succeeds, the input was complete.
; If it errors, the input is incomplete — keep reading.
(def %is-complete?
  (fn (_ text depth)
    (if (> depth 0) #f
      (guard (err
          ; Re-throw STOP (from ctrl-c) instead of swallowing it
          (if (if (atom? err) (str=? (symbol->str err) "STOP") #f)
            (error err)
            #f))
        (def tokens (%token-read-string %logo-base (Str append text " ")))
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
        ; Default SIGINT while reading so ctrl-c at prompt exits;
        ; reinstall handler after so ctrl-c during execution breaks loops
        (sigint-restore)
        (def line (%read-line))
        (sigint-install)
        (if (null? line)
          ; EOF — if caused by ctrl-c, retry
          (unless (null? lines) (Str join "" (reverse lines)))
          (if (str=? line "")
            ; Blank line
            (if (null? lines)
              (self () 0)
              (if (> depth 0)
                (self lines depth)
                ; Balanced — probe for completeness
                (if (%is-complete? (Str join "" (reverse lines)) depth)
                  (Str join "" (reverse lines))
                  (self lines depth))))
            ; Non-empty line
            (let ((new-depth (+ depth (%count-brackets line)))
                  (new-lines (pair (Str append "\n" line) lines)))
              (if (> new-depth 0)
                (self new-lines new-depth)
                (if (%is-indented? line)
                  (self new-lines new-depth)
                  ; Col 0, balanced — probe for completeness
                  (if (%is-complete? (Str join "" (reverse new-lines)) new-depth)
                    (Str join "" (reverse new-lines))
                    (self new-lines new-depth)))))))))
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
    ; On first call, reclaim terminal stdin from fd 3 (saved by x.sh
    ; before the pipe, so stdin survives ctrl-c)
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))
    (set-first-int! %sigint-flag 0)
    (display %logo-prompt)
    (def block (%read-block))
    (if (null? block)
      ; EOF or ctrl-c — kill the server child, then exit
      (do (unless (null? %logo-on-exit) (%logo-on-exit))
          (newline) (Sys exit 0))
      (do
        (guard (err
            (set-first-int! %sigint-flag 0)
            (if (if (atom? err) (str=? (symbol->str err) "STOP") #f)
              (display "\n")
              (%seq
                (%stderr "Error: ")
                (%stderr (if (str? err) err
                          (if (number? err) (number->str err)
                            (symbol->str err))))
                (%stderr "\n"))))
          ; Block already executed by %is-complete? probe —
          ; no need to process again
          (unless (null? %logo-on-command) (%logo-on-command)))
        (logo-repl)))))

(provide x/logo/repl
  logo-repl %logo-on-exit %logo-on-command)
