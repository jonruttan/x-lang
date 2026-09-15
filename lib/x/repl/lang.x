; repl/lang.x -- Lang: the languages a session can switch between.
;
; A session's prompt is a bundle of seams: the prompt string, the
; continuation prompt, the printer, the painter, the bracket marks, Tab's
; candidate source and what a finished line means.  repl/loop.x defines each
; as a global a lang sets, and that is enough for a lang that owns the
; session from boot to exit.  Switching languages mid-session needs the
; bundle as a value: what x-lang's prompt is, what Python's is, and one call
; that installs either.  A registered lang is that bundle, keyed by name.
;
; The platform's own is registered here as "x", from what boot knows -- the
; two prompts and the plain printer -- and each file that owns another part
; registers it as it loads: repl/ansi.x the coloured printer, repl/paint.x
; the painter and the marks, repl/line.x the completer and the line
; evaluator.  Registration merges, so "x" is complete once the editor has
; loaded and each part stays with the file that defines it.  The same calls
; run again from the image recache hooks, so a state image loaded into a
; different process registers that process's closures.
;
; A lang that does not say what a seam is inherits x's answer for it.  Nil
; is an answer -- no painter, Tab off -- so a lang that wants neither says
; so rather than leaving the key out.

(def-class Lang ()
  (doc "The languages a session can switch between, each a bundle of the REPL's seams keyed by name: the prompt, the continuation prompt, the printer, the painter, the bracket marks, Tab's candidate source and what a finished line means. x-lang's own is \"x\"; a lang registers its own as it loads, and `(lang NAME)` installs one."
    (note "A bundle is an alist from seam name to value, over the closed vocabulary `keys` answers: %repl-prompt, %repl-prompt-more, %repl-print, %repl-paint, %repl-marks, %repl-complete, %repl-eval-line, %lang-name and %lang-version. An unknown key is an error at registration.")
    (note "Installing a lang sets every seam it names, and every seam it does not name to x's value for it. Nil is a value -- no painter, Tab off -- so a lang that wants neither says so.")
    (note "Registering a name again merges: keys given replace, keys omitted stay. This is how \"x\" is assembled by the files that own its parts, and re-assembled after a state image loads.")
    (example "(Lang current)" "\"x\"")
    (see register!) (see use!) (see get) (see names) (see current) (see keys))

  (static
    ; ((name . alist) ...), in registration order; "x" first.
    (%lang-table-cell (pair () ()))
    (%lang-current-cell (pair "x" ()))
    (%lang-vocabulary
      (list (lit %repl-prompt) (lit %repl-prompt-more) (lit %repl-print)
            (lit %repl-paint) (lit %repl-marks) (lit %repl-complete)
            (lit %repl-eval-line) (lit %lang-name) (lit %lang-version)))

    ; A name as a string, whichever spelling arrived: `(lang python)` hands
    ; the op a symbol, `(Lang use! "python")` a string.
    (method %lang-str (self v)
      (if (symbol? v) (Str8 str v) v))

    ; The table entry for a name, or nil.  Strings, not symbols, so the
    ; lookup is by content.
    (method %lang-entry (self name)
      (let ((go (fn (self rows)
                  (if (null? rows) ()
                    (if (str=? (first (first rows)) name) (first rows)
                      (self (rest rows)))))))
        (go (first (Lang %lang-table-cell)))))

    ; Every key of an alist is a symbol in the vocabulary, or this raises.
    (method %lang-check (self alist)
      (List for-each
        (fn (_ entry)
          (unless (pair? entry)
            (Err raise (lit lang) "Lang register!: a bundle is an alist of (seam . value)" entry))
          (unless (%memq? (first entry) (Lang %lang-vocabulary))
            (Err raise (lit lang) "Lang register!: not a REPL seam" (first entry))))
        alist))

    ; One seam, set by name.  The seams are globals of repl/loop.x, and a
    ; set! through eval! reaches them from here as it would from the prompt.
    (method %lang-set (self key val)
      (eval! (list (lit set!) key (list (lit lit) val))))

    (method register! (self (param name ANY "The lang's name, a string or a symbol")
                            (param alist LIST "((seam . value) ...) over `keys`"))
      (doc "Register a lang, or merge into one already registered under the name: keys given replace, keys omitted stay. Raises on a key outside the vocabulary."
        (returns LIST "The lang's alist after the merge")
        (sample "(Lang register! \"logo\" (list (pair '%repl-prompt \"? \") (pair '%repl-paint ())))" "the alist, and (lang logo) now installs it"))
      (Lang %lang-check alist)
      (let ((name (Lang %lang-str name)))
        (let ((entry (Lang %lang-entry name)))
          (let ((merged (if (null? entry) alist
                          (List fold (fn (_ acc e) (Assoc put (first e) (rest e) acc))
                                     (rest entry) alist))))
            (if (null? entry)
              (%set-first! (Lang %lang-table-cell)
                (%append (first (Lang %lang-table-cell)) (list (pair name merged))))
              (%set-rest! entry merged))
            merged))))

    (method use! (self (param name ANY "A registered name, a string or a symbol"))
      (doc "Install a registered lang: every seam it names is set to its value, and every seam it does not name to x's. Raises when no lang has the name."
        (returns NIL "Nothing; the next line the editor reads is in the lang installed")
        (sample "(Lang use! \"python\")" "the prompt, painter and line evaluator are Python's"))
      (let ((name (Lang %lang-str name)))
        (let ((entry (Lang %lang-entry name)))
          (when (null? entry)
            (Err raise (lit lang) (%str-append "no such lang: " name) ()))
          (let ((mode (rest entry)) (base (Lang get "x")))
            (List for-each
              (fn (_ key)
                (if (Assoc has? key mode)
                  (Lang %lang-set key (Assoc get key mode))
                  (when (Assoc has? key base)
                    (Lang %lang-set key (Assoc get key base)))))
              (Lang %lang-vocabulary))
            (%set-first! (Lang %lang-current-cell) name)
            ()))))

    (method get (self (param name ANY "A name, a string or a symbol"))
      (doc "A registered lang's alist, or nil when none has the name."
        (returns LIST "((seam . value) ...)"))
      (let ((entry (Lang %lang-entry (Lang %lang-str name))))
        (if (null? entry) () (rest entry))))

    (method names (self)
      (doc "Every registered name, in registration order; \"x\" is first."
        (returns LIST "Strings")
        (example "(first (Lang names))" "\"x\""))
      (List map (fn (_ row) (first row)) (first (Lang %lang-table-cell))))

    (method current (self)
      (doc "The name of the lang last installed; \"x\" until one is."
        (returns STRING "A registered name")
        (example "(Lang current)" "\"x\""))
      (first (Lang %lang-current-cell)))

    (method keys (self)
      (doc "The seams a lang may set: the closed vocabulary `register!` checks against."
        (returns LIST "Symbols")
        (example "(first (Lang keys))" "'%repl-prompt"))
      (Lang %lang-vocabulary))))

; What boot knows of x-lang's own prompt.  The rest of "x" arrives as the
; files that own it load; see the module note.
(Lang register! "x"
  (list (pair (lit %repl-prompt) %repl-prompt)
        (pair (lit %repl-prompt-more) %repl-prompt-more)
        (pair (lit %repl-print) %repl-print)))

(doc (def lang
  (op names _
    (if (null? names)
      (do (display "current: " (Lang current) "  registered:")
          (List for-each (fn (_ n) (display " " n)) (Lang names))
          (newline))
      (Lang use! (first names)))))
  (param name SYMBOL "Optional: the lang to switch to, bare or as a string; omit to list")
  (sample "(lang python)" "the next line is read as Python")
  (sample "(lang \"x\")" "and this one, from Python's own spelling, comes back")
  (sample "(lang)" "current: x  registered: x python")
  (note "The switch takes effect on the next line the editor reads; the line it was typed on finishes in the lang it was typed in.")
  "Switch the session to a registered lang, or list them.")

(doc (provide x/repl/lang Lang lang)
  (note "x-lang's own prompt is registered as \"x\" by the files that own its parts, merging as each loads: this file the prompts and the plain printer, repl/ansi.x the coloured printer, repl/paint.x the painter and marks, repl/line.x the completer and the line evaluator.")
  (note "A lang registers itself from its entry, then installs itself with use! if it owns the session, or leaves the platform's prompt in place if it was loaded beside another lang.")
  "Lang: the languages a session can switch between, and `lang`, the switch.")
