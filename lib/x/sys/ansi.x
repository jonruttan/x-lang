; ansi.x -- ANSI terminal color support
;
; Detects terminal capabilities and provides color constants.
; When stdout is not a terminal, or NO_COLOR is set, or TERM is "dumb",
; all color constants are empty strings — zero-cost no-ops.
;
; Requires: posix.x (sh-isatty, sh-getenv), type.x (type-push-write)

(import x/sys/posix)
(import x/sys/type)

; --- Terminal detection ---

(def %no-color-env (sh-getenv "NO_COLOR"))
(def %term-env (sh-getenv "TERM"))
(def %no-color-arg
  (fold
    (fn (_ acc a) (or acc (str=? a "--no-color")))
    ()
    args))

(def %ansi?
  (and (sh-isatty 1)
       (null? %no-color-env)
       (not (and (not (null? %term-env)) (str=? %term-env "dumb")))
       (not %no-color-arg)))

; --- Escape sequence builder ---

(def %esc "\x1b")
(def %sgr (fn (_ code) (if %ansi? (str-append %esc (str-append "[" (str-append code "m"))) "")))

; --- Color constants ---

(def ansi-reset   (%sgr "0"))
(def ansi-bold    (%sgr "1"))
(def ansi-dim     (%sgr "2"))
(def ansi-red     (%sgr "31"))
(def ansi-green   (%sgr "32"))
(def ansi-yellow  (%sgr "33"))
(def ansi-blue    (%sgr "34"))
(def ansi-magenta (%sgr "35"))
(def ansi-cyan    (%sgr "36"))

; --- Compound styles ---

(def ansi-bold-cyan    (str-append (%sgr "1") (%sgr "36")))
(def ansi-bold-green   (str-append (%sgr "1") (%sgr "32")))
(def ansi-bold-yellow  (str-append (%sgr "1") (%sgr "33")))
(def ansi-bold-red     (str-append (%sgr "1") (%sgr "31")))

; --- Helpers ---

(doc (def ansi-wrap
  (fn (_ (param style STRING "ANSI escape sequence") (param text STRING "Text to wrap"))
    (str-append style (str-append text ansi-reset))))
  (returns STRING "Text wrapped in ANSI codes, or plain text if colors disabled")
  (example "(ansi-wrap ansi-red \"error\")" "\"\\x1b[31merror\\x1b[0m\"")
  "Wrap text in an ANSI style code with automatic reset.")

(doc (def ansi?
  (fn (_ ) %ansi?))
  (returns BOOLEAN "True if ANSI color output is enabled")
  "Check whether ANSI color support is active.")

; --- REPL syntax highlighting via type-push-write ---

; --- REPL colorized print ---
;
; Override %repl-print to wrap output in a dim color.
; This is simpler and safer than pushing type write handlers,
; which require calling C function pointers from x-lang closures.

(def %saved-repl-print %repl-print)

(doc (def ansi-enable-repl
  (fn (_ )
    (if (not %ansi?) ()
      (set! %repl-print
        (fn (_ result)
          (if (null? result) ()
            (do (display ansi-cyan) (write result) (display ansi-reset)))
          (newline))))))
  "Enable ANSI-colored REPL output (cyan for results).")

(doc (def ansi-disable-repl
  (fn (_ )
    (set! %repl-print %saved-repl-print)))
  "Restore plain REPL output.")

; --- Set doc.x color variables (doc.x defines stubs as "") ---

(if %ansi?
  (do
    (set! %c-reset   ansi-reset)
    (set! %c-bold    ansi-bold)
    (set! %c-dim     ansi-dim)
    (set! %c-name    ansi-bold-cyan)
    (set! %c-type    ansi-green)
    (set! %c-param   ansi-yellow)
    (set! %c-example ansi-cyan)
    (set! %c-error   ansi-bold-red)
    (set! %c-module  ansi-bold)))

; --- Activate REPL highlighting ---

(ansi-enable-repl)

(doc (provide x/sys/ansi
  ansi? ansi-wrap ansi-enable-repl ansi-disable-repl
  ansi-reset ansi-bold ansi-dim
  ansi-red ansi-green ansi-yellow ansi-blue ansi-magenta ansi-cyan
  ansi-bold-cyan ansi-bold-green ansi-bold-yellow ansi-bold-red)
  (note "Respects NO_COLOR environment variable and TERM=dumb.")
  (note "Pass --no-color on command line to disable.")
  "ANSI terminal color constants and REPL syntax highlighting.")
