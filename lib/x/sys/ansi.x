; ansi.x -- ANSI terminal color support
;
; Detects terminal capabilities and provides color constants.
; When stdout is not a terminal, or NO_COLOR is set, or TERM is "dumb",
; all color constants are empty strings — zero-cost no-ops.
;
; Color scheme follows LSP semantic token types mapped to standard ANSI:
;   number=yellow, string=green, variable/symbol=blue, keyword=bold-red,
;   function=cyan, string.escape/char=magenta, regexp=red, nil=dim
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
(def ansi-bold-blue    (str-append (%sgr "1") (%sgr "34")))

; --- Helpers ---

(doc (def ansi-wrap
  (fn (_ (param style STRING "ANSI escape sequence") (param text STRING "Text to wrap"))
    (str-append style (str-append text ansi-reset))))
  (returns STRING "Text wrapped in ANSI codes, or plain text if colors disabled")
  "Wrap text in an ANSI style code with automatic reset.")

(doc (def ansi?
  (fn (_ ) %ansi?))
  (returns BOOLEAN "True if ANSI color output is enabled")
  "Check whether ANSI color support is active.")

; --- LSP semantic token colors ---
; number=yellow, string=green, symbol=blue, char=magenta,
; keyword/bool=bold-red, function=cyan, regexp=red, nil=dim

(def %c-number   ansi-yellow)
(def %c-string   ansi-green)
(def %c-symbol   ansi-blue)
(def %c-char     ansi-magenta)
(def %c-bool     ansi-bold-red)
(def %c-nil-val  ansi-dim)
(def %c-function ansi-cyan)
(def %c-regexp   ansi-red)
(def %c-punct    "")

; --- Syntax-highlighted recursive writer ---
;
; Walks the value structure, emitting ANSI codes per type.
; Uses (write obj) for atomic values (delegates to C handlers),
; and (display ...) for color codes (bypasses type dispatch).

; Forward declaration for mutual recursion
(def %ansi-write ())

(def %ansi-write-list
  (fn (self obj)
    (if (null? (first obj))
      (do (display %c-nil-val) (display "()") (display ansi-reset))
      (%ansi-write (first obj)))
    (if (null? (rest obj))
      ()
      (if (not (pair? (rest obj)))
        ; Dotted pair
        (do (display " . ") (%ansi-write (rest obj)))
        ; Continue list
        (do (display " ") (self (rest obj)))))))

(set! %ansi-write
  (fn (self obj)
    (if (null? obj)
      (do (display %c-nil-val) (display "()") (display ansi-reset))
    (if (eq? obj #t)
      (do (display %c-bool) (display "#t") (display ansi-reset))
    (if (eq? obj #f)
      (do (display %c-bool) (display "#f") (display ansi-reset))
    (if (pair? obj)
      (do (display "(") (%ansi-write-list obj) (display ")"))
    (if (number? obj)
      (do (display %c-number) (write obj) (display ansi-reset))
    (if (str? obj)
      (do (display %c-string) (write obj) (display ansi-reset))
    (if (symbol? obj)
      (do (display %c-symbol) (write obj) (display ansi-reset))
    (if (char? obj)
      (do (display %c-char) (write obj) (display ansi-reset))
    (if (procedure? obj)
      (do (display %c-function) (write obj) (display ansi-reset))
    ; Default (regex, custom types, etc.): write without color
    (write obj))))))))))))

; --- Source code syntax highlighting ---
;
; Tokenizes a code string on the current base, then walks the token
; tree with keyword-aware coloring. Keywords (special forms) get bold
; magenta; regular symbols get blue; numbers/strings/chars/bools get
; their LSP semantic token colors.

(def %c-keyword  (str-append (%sgr "1") (%sgr "35")))

; Keyword set — x-lang special forms and core operatives
(def %keywords
  (list (lit def) (lit fn) (lit op) (lit if) (lit let) (lit do)
        (lit match) (lit guard) (lit set!) (lit lit) (lit quasi)
        (lit import) (lit include) (lit provide)
        (lit and) (lit or) (lit not)
        (lit apply) (lit eval) (lit begin)
        (lit when) (lit unless) (lit let*) (lit letrec)
        (lit cond) (lit case) (lit doc) (lit note)))

(def %keyword?
  (fn (self sym)
    (def %go
      (fn (self lst)
        (if (null? lst) #f
          (if (eq? (first lst) sym) #t
            (self (rest lst))))))
    (%go %keywords)))

; Forward declaration for mutual recursion
(def %ansi-write-code ())

(def %ansi-write-code-list
  (fn (self obj)
    (if (null? (first obj))
      (do (display %c-nil-val) (display "()") (display ansi-reset))
      (%ansi-write-code (first obj)))
    (if (null? (rest obj))
      ()
      (if (not (pair? (rest obj)))
        (do (display " . ") (%ansi-write-code (rest obj)))
        (do (display " ") (self (rest obj)))))))

(set! %ansi-write-code
  (fn (self obj)
    (if (null? obj)
      (do (display %c-nil-val) (display "()") (display ansi-reset))
    (if (eq? obj #t)
      (do (display %c-bool) (display "#t") (display ansi-reset))
    (if (eq? obj #f)
      (do (display %c-bool) (display "#f") (display ansi-reset))
    (if (pair? obj)
      (do (display "(") (%ansi-write-code-list obj) (display ")"))
    (if (number? obj)
      (do (display %c-number) (write obj) (display ansi-reset))
    (if (str? obj)
      (do (display %c-string) (write obj) (display ansi-reset))
    (if (symbol? obj)
      (if (%keyword? obj)
        (do (display %c-keyword) (display obj) (display ansi-reset))
        (do (display %c-symbol) (display obj) (display ansi-reset)))
    (if (char? obj)
      (do (display %c-char) (write obj) (display ansi-reset))
    (write obj)))))))))))

(doc (def ansi-highlight
  (fn (_ (param code STRING "Source code string to highlight"))
    (if (not %ansi?)
      (display code)
      (do
        (def %toks (token-read-string (%base) code))
        (def %go
          (fn (self toks first?)
            (if (null? toks) ()
              (do
                (if first? () (display " "))
                (%ansi-write-code (first toks))
                (self (rest toks) ())))))
        (%go %toks #t)))))
  (returns ANY "Displays highlighted code to stdout")
  (example "(ansi-highlight \"(def x 42)\")" "(def x 42)")
  "Syntax-highlight a code string and display it. Keywords in bold magenta, symbols in blue, numbers in yellow, strings in green.")

; --- REPL integration ---

(def %saved-repl-print %repl-print)

(doc (def ansi-enable-repl
  (fn (_ )
    (if (not %ansi?) ()
      (set! %repl-print
        (fn (_ result)
          (if (null? result) () (%ansi-write result))
          (newline))))))
  "Enable syntax-highlighted REPL output using LSP semantic token colors.")

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
    (set! %c-module  ansi-bold)
    (set! %highlight-code ansi-highlight)))

; --- Activate REPL highlighting ---

(ansi-enable-repl)

(doc (provide x/sys/ansi
  ansi? ansi-wrap ansi-highlight ansi-enable-repl ansi-disable-repl
  ansi-reset ansi-bold ansi-dim
  ansi-red ansi-green ansi-yellow ansi-blue ansi-magenta ansi-cyan
  ansi-bold-cyan ansi-bold-green ansi-bold-yellow ansi-bold-red ansi-bold-blue)
  (note "Color scheme: LSP semantic tokens — number=yellow, string=green, symbol=blue, char=magenta, bool=bold-red, function=cyan.")
  (note "Respects NO_COLOR environment variable and TERM=dumb.")
  (note "Pass --no-color on command line to disable.")
  "ANSI terminal color support with syntax-highlighted REPL output.")
