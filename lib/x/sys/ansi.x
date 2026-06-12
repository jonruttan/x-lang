; ansi.x -- Ansi: terminal color support, homed on the Ansi class.
;
; Detects terminal capabilities; the color codes live as Ansi static MEMBERS
; (computed once at class definition -- empty strings when color is off, so
; every use is a zero-cost no-op). When stdout is not a terminal, or NO_COLOR
; is set, or TERM is "dumb", or --no-color was passed, color is off.
;
; Color scheme follows LSP semantic token types mapped to standard ANSI:
;   number=yellow, string=green, variable/symbol=blue, keyword=bold-red,
;   function=cyan, string.escape/char=magenta, regexp=red, nil=dim
;
; Load-time wiring (by design, the module's integration job): fills doc.x's
; %c-* color stubs and installs the syntax-highlighted REPL printer.
;
; Requires: posix.x (Sys isatty/getenv), type.x (%type-push-write)

(import x/sys/posix)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-push-write (prim-ref (lit type) (lit push-write)))

(import x/sys/type)
(import x/type/object)

; --- Terminal detection ---

(def %no-color-env (Sys getenv "NO_COLOR"))
(def %term-env (Sys getenv "TERM"))
(def %no-color-arg
  (fold
    (fn (_ acc a) (or acc (str=? a "--no-color")))
    ()
    args))

(def %ansi?
  (and (Sys isatty 1)
       (null? %no-color-env)
       (not (and (not (null? %term-env)) (str=? %term-env "dumb")))
       (not %no-color-arg)))

; --- Escape sequence builder ---

(def %esc "\x1b")
(def %sgr (fn (_ code) (if %ansi? (%str-append %esc (%str-append "[" (%str-append code "m"))) "")))

; --- The Ansi class: color members + operations ---
; Members evaluate once, here, at class definition. Methods referencing the
; %-helpers below resolve them at call time (deferred, the List precedent).

(def-class Ansi ()
  (static
    (reset   (%sgr "0")  "Reset all attributes")
    (bold    (%sgr "1")  "Bold")
    (dim     (%sgr "2")  "Dim")
    (red     (%sgr "31") "Red foreground")
    (green   (%sgr "32") "Green foreground")
    (yellow  (%sgr "33") "Yellow foreground")
    (blue    (%sgr "34") "Blue foreground")
    (magenta (%sgr "35") "Magenta foreground")
    (cyan    (%sgr "36") "Cyan foreground")
    (bold-cyan   (%str-append (%sgr "1") (%sgr "36")) "Bold cyan foreground")
    (bold-green  (%str-append (%sgr "1") (%sgr "32")) "Bold green foreground")
    (bold-yellow (%str-append (%sgr "1") (%sgr "33")) "Bold yellow foreground")
    (bold-red    (%str-append (%sgr "1") (%sgr "31")) "Bold red foreground")
    (bold-blue   (%str-append (%sgr "1") (%sgr "34")) "Bold blue foreground")
    (method enabled? (self)
      (doc "Check whether ANSI color support is active."
        (returns BOOLEAN "True if ANSI color output is enabled"))
      %ansi?)
    (method wrap (self (param style STRING "ANSI escape sequence") (param text STRING "Text to wrap"))
      (doc "Wrap text in an ANSI style code with automatic reset."
        (returns STRING "Text wrapped in ANSI codes, or plain text if colors disabled"))
      (%str-append style (%str-append text (Ansi reset))))
    (method highlight (self (param code STRING "Source code string to highlight"))
      (doc "Syntax-highlight a code string and display it. Keywords in bold magenta, symbols in blue, numbers in yellow, strings in green."
        (returns ANY "Displays highlighted code to stdout")
        (example "(Ansi highlight \"(def x 42)\")" "(def x 42)"))
      (if (not %ansi?)
        (display code)
        (let ((%toks (token-read-string (%base) code))
              (%go
                (fn (self toks first?)
                  (if (null? toks) ()
                    (do
                      (if first? () (display " "))
                      (%ansi-write-code (first toks))
                      (self (rest toks) ()))))))
          (%go %toks #t))))
    (method enable-repl (self)
      (doc "Enable syntax-highlighted REPL output using LSP semantic token colors.")
      (if (not %ansi?) ()
        (set! %repl-print
          (fn (_ result)
            (if (null? result) () (%ansi-write result))
            (newline)))))
    (method disable-repl (self)
      (doc "Restore plain REPL output.")
      (set! %repl-print %saved-repl-print))))

; --- LSP semantic token colors ---
; number=yellow, string=green, symbol=blue, char=magenta,
; keyword/bool=bold-red, function=cyan, regexp=red, nil=dim

(def %c-number   (Ansi yellow))
(def %c-string   (Ansi green))
(def %c-symbol   (Ansi blue))
(def %c-char     (Ansi magenta))
(def %c-bool     (Ansi bold-red))
(def %c-nil-val  (Ansi dim))
(def %c-function (Ansi cyan))
(def %c-regexp   (Ansi red))
(def %c-punct    "")
(def %c-rst      (Ansi reset))

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
      (do (display %c-nil-val) (display "()") (display %c-rst))
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
      (do (display %c-nil-val) (display "()") (display %c-rst))
    (if (eq? obj #t)
      (do (display %c-bool) (display "#t") (display %c-rst))
    (if (eq? obj #f)
      (do (display %c-bool) (display "#f") (display %c-rst))
    (if (pair? obj)
      (do (display "(") (%ansi-write-list obj) (display ")"))
    (if (number? obj)
      (do (display %c-number) (write obj) (display %c-rst))
    (if (str? obj)
      (do (display %c-string) (write obj) (display %c-rst))
    (if (symbol? obj)
      (do (display %c-symbol) (write obj) (display %c-rst))
    (if (char? obj)
      (do (display %c-char) (write obj) (display %c-rst))
    (if (procedure? obj)
      (do (display %c-function) (write obj) (display %c-rst))
    ; Default (regex, custom types, etc.): write without color
    (write obj))))))))))))

; --- Source code syntax highlighting ---
;
; Tokenizes a code string on the current base, then walks the token
; tree with keyword-aware coloring. Keywords (special forms) get bold
; magenta; regular symbols get blue; numbers/strings/chars/bools get
; their LSP semantic token colors.

(def %c-keyword  (%str-append (%sgr "1") (%sgr "35")))

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
      (do (display %c-nil-val) (display "()") (display %c-rst))
      (%ansi-write-code (first obj)))
    (if (null? (rest obj))
      ()
      (if (not (pair? (rest obj)))
        (do (display " . ") (%ansi-write-code (rest obj)))
        (do (display " ") (self (rest obj)))))))

(set! %ansi-write-code
  (fn (self obj)
    (if (null? obj)
      (do (display %c-nil-val) (display "()") (display %c-rst))
    (if (eq? obj #t)
      (do (display %c-bool) (display "#t") (display %c-rst))
    (if (eq? obj #f)
      (do (display %c-bool) (display "#f") (display %c-rst))
    (if (pair? obj)
      (do (display "(") (%ansi-write-code-list obj) (display ")"))
    (if (number? obj)
      (do (display %c-number) (write obj) (display %c-rst))
    (if (str? obj)
      (do (display %c-string) (write obj) (display %c-rst))
    (if (symbol? obj)
      (if (%keyword? obj)
        (do (display %c-keyword) (display obj) (display %c-rst))
        (do (display %c-symbol) (display obj) (display %c-rst)))
    (if (char? obj)
      (do (display %c-char) (write obj) (display %c-rst))
    (write obj)))))))))))

; --- REPL integration ---

(def %saved-repl-print %repl-print)

; --- Set doc.x color variables (doc.x defines stubs as "") ---

(if %ansi?
  (do
    (set! %c-reset   (Ansi reset))
    (set! %c-bold    (Ansi bold))
    (set! %c-dim     (Ansi dim))
    (set! %c-name    (Ansi bold-cyan))
    (set! %c-type    (Ansi green))
    (set! %c-param   (Ansi yellow))
    (set! %c-example (Ansi cyan))
    (set! %c-error   (Ansi bold-red))
    (set! %c-module  (Ansi bold))
    (set! %highlight-code (method-ref Ansi highlight))))

; --- Activate REPL highlighting ---

(Ansi enable-repl)

(doc (provide x/sys/ansi Ansi)
  (note "Color scheme: LSP semantic tokens — number=yellow, string=green, symbol=blue, char=magenta, bool=bold-red, function=cyan.")
  (note "Colors are Ansi static members ((Ansi red), (Ansi bold-cyan), ...); empty strings when color is off.")
  (note "Respects NO_COLOR and TERM=dumb; pass --no-color to disable.")
  "ANSI terminal color support, homed on the Ansi class.")
