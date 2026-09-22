; repl/line.x -- Line: reading one edited, coloured line from a terminal.
;
; This is the file that replaces `rlwrap sh x.sh`.  The three pieces under it
; each answer one question and none of them answer two: repl/edit.x is the
; buffer and the cursor with no terminal in it, repl/term.x is the terminal
; with no buffer in it, repl/paint.x turns bytes into coloured bytes.  What
; is left here is the loop that reads a key, applies it, and redraws -- plus
; the two things a session needs around that loop, a history file and
; completion.
;
; The terminal is borrowed per line.  raw! and restore! bracket the read and
; nothing else, so the form that was typed is evaluated in the cooked
; terminal every other part of the system expects: output still gets its
; newlines translated, a child process inherits a sane tty, and ctrl-c
; during a long evaluation is a signal for the boot's SIGINT handler rather
; than a byte nobody is reading.  The cost is two tcsetattr calls per line,
; which is nothing next to being the reason someone's shell came back broken.
;
; Redrawing is a window, not a wrap.  A line longer than the terminal scrolls
; sideways inside its row rather than wrapping onto more rows.  That is the
; smaller and far more robust of the two designs -- no cursor arithmetic
; across rows, nothing to get wrong when the terminal is resized mid-line --
; and it has a second benefit that matters more than it looks: only the
; visible bytes are painted, so the cost of a redraw is bounded by the width
; of the terminal instead of the length of the line.
;
; Percent-globals: the redraw and key dispatch run per keystroke, so they are
; %-private functions over cached prims rather than class methods (the rule
; reader/analyser.x states); Line is the cold-call API over them.

(module x/repl/line)
(import x/type/class)
(import x/type/str)
(import x/type/list)
(import x/sys/posix)
(import x/sys/file)
(import x/type/path)
(import x/repl/edit)
(import x/repl/term)
(import x/repl/paint)
(import x/reader/indent)

(def %ln-blen (prim-ref (lit str) (lit byte-len)))
(def %ln-bsub (prim-ref (lit str) (lit byte-sub)))
(def %ln-append (prim-ref (lit str) (lit append)))
(def %ln-bref (prim-ref (lit str) (lit byte-ref)))
(def %ln-write-to-str (prim-ref (lit io) (lit write-to-str)))
(def %ln-collect (prim-ref (lit heap) (lit collect)))
(def %ln-cint (prim-ref (lit char) (lit ->int)))
(def %ln-byte (fn (_ s i) (%ln-cint (%ln-bref s i))))

; The session's buffer: one Edit, so history survives from line to line.
(def %ln-buffer ())
; The descriptor the session reads from.  Zero -- but x.sh parks the user's
; terminal on fd 3 while the boot stream occupies fd 0, so it is only zero
; after the swap %ln-repl does on its first turn.  That is why %ln-install!
; below asks about fd 3 as well: at LOAD time the terminal is still there.
(def %ln-fd 0)

; The earlier lines of the entry being read, each followed by a newline, or ""
; on an entry's first line.  Line read sets it from its optional argument for
; the length of one read, and the redraw hands it on: to the marker, so depths
; and partners carry from one line of a multi-line entry to the next, and to
; the painter, so a line that begins inside a string is coloured as one.
(def %ln-context "")
(def %ln-history-loaded ())

; --- escape sequences, named once ------------------------------------------
(def %ln-kill-right "\x1b[K")     ; erase from the cursor to end of line
(def %ln-clear-screen "\x1b[2J\x1b[H")

; --- measuring --------------------------------------------------------------
;
; Columns, not bytes.  Every position the terminal is told about is a column
; count, and a multi-byte character occupies one of them, so the conversion
; happens here and nowhere else.  (A double-width glyph occupies two and this
; counts it as one; that is a known and bounded wrongness -- the cursor sits
; one column left of where it looks like it should on a CJK line -- and
; fixing it needs a width table this tree does not have.)
;
; A tab occupies the columns up to the next multiple of eight, the stops a
; terminal has unless something has moved them, so its width depends on the
; column it starts at.  Each measure here therefore begins from a column, and
; the step is x/reader/indent's, which is the tab stop x-python's and x-sweet's
; readers measure a line with.
(def %ln-tab-stop 8)
(def %ln-indent-advance (prim-ref (lit indent) (lit advance)))

; The column after the character at byte i of s, drawn from column col.
(def %ln-advance
  (fn (_ s i col)
    (if (= 9 (%ln-byte s i)) (%ln-indent-advance col 9 %ln-tab-stop) (+ col 1))))

; The column reached by drawing s[from, to) from column col.
(def %ln-columns
  (fn (_ s from to col)
    (let ((go (fn (self i c)
                (if (>= i to) c (self (Edit next-start s i) (%ln-advance s i c))))))
      (go from col))))

; The byte offset to start drawing from so that s[start, i) fits in k columns.
; Walking back, a tab is counted at its full width: what it really occupies
; depends on where the drawing starts, which is what is being decided.  The
; window may come out narrower than it needed to be when a tab has scrolled
; into it, and the cursor is always in view.
(def %ln-back-columns
  (fn (_ s i k)
    (let ((go (fn (self j c)
                (if (<= j 0) 0
                  (let ((p (Edit prev-start s j)))
                    (let ((w (if (= 9 (%ln-byte s p)) %ln-tab-stop 1)))
                      (if (> w c) j (self p (- c w)))))))))
      (go i k))))

; The byte offset at most k columns forward from i, drawing from column col.
(def %ln-forward-columns
  (fn (_ s i k col)
    (let ((n (%ln-blen s)) (limit (+ col k)))
      (let ((go (fn (self j c)
                  (if (>= j n) n
                    (let ((c2 (%ln-advance s j c)))
                      (if (> c2 limit) j (self (Edit next-start s j) c2)))))))
        (go i col)))))

; Guarded: a painter that raises must not lose the keystroke.  The line is
; drawn unpainted for that redraw instead.  `before` is the entry's text ahead
; of the window, for a painter that needs to know whether the window begins
; inside a string or a comment.
(def %ln-paint
  (fn (_ window marks before)
    (if (null? %repl-paint) window
      (guard (_ window) (%repl-paint window marks before)))))

; The marks for this redraw, asked of the whole entry so far -- the earlier
; lines of a multi-line entry and all of this line -- so that a partner on an
; earlier line, or scrolled out of view, is still found.  They are then
; translated into the window: offsets become window-relative and any that fall
; outside it are dropped.  A point below 0 asks for no focus, and stays below
; 0.  Guarded like the painter, and for the same reason.
(def %ln-marks
  (fn (_ text point start end)
    (if (null? %repl-marks) ()
      (let ((base (%ln-blen %ln-context)))
        (let ((lo (+ base start)) (hi (+ base end)))
          (let ((go (fn (self ms acc)
                      (if (null? ms) acc
                        (let ((o (first (first ms))))
                          (self (rest ms)
                            (if (if (>= o lo) (< o hi) #f)
                              (pair (pair (- o lo) (rest (first ms))) acc)
                              acc)))))))
            ; Reversed back into source order: the scan consumes marks in the
            ; order it meets them.
            (%reverse
              (go (guard (_ ())
                    (%repl-marks (if (= base 0) text (%ln-append %ln-context text))
                                 (if (< point 0) -1 (+ base point))))
                  ()))))))))

; --- the redraw -------------------------------------------------------------
;
; One write.  The whole frame -- return, erase, prompt, painted window,
; return, cursor right -- is built as a single string and handed to the
; descriptor once.  Writing it in pieces lets the terminal render a
; half-drawn line, which is visible as a flicker on every keystroke.
; With `settled`, the frame is the one that stays in the transcript: the
; cursor is treated as nowhere, so the pair beside it loses its inverse and
; only the depth colours remain.
(def %ln-redraw
  (fn (_ fd prompt ed cols . settled)
    (let ((text (ed text))
          (point (ed point))
          (pwidth (%ln-columns prompt 0 (%ln-blen prompt) 0)))
      (let ((avail (let ((a (- cols pwidth 1))) (if (< a 8) 8 a))))
        ; Scroll sideways only as far as it takes to keep the cursor in view.
        (let ((start (let ((cc (%ln-columns text 0 point pwidth)))
                       (if (<= (- cc pwidth) avail) 0 (%ln-back-columns text point avail)))))
          (let ((end (%ln-forward-columns text start avail pwidth)))
            (let ((window (%ln-bsub text start (- end start)))
                  (marks (%ln-marks text (if (null? settled) point -1) start end))
                  (col (%ln-columns text start point pwidth)))
              (Term emit fd
                (%ln-append "\r"
                  (%ln-append %ln-kill-right
                    (%ln-append prompt
                      ; The painter belongs to the session, not to this file.
                      ; A lang that reads its own syntax sets %repl-paint to a
                      ; painter that knows it; nil means no colouring.
                      ; On a line that is not scrolled the text before the
                      ; window is the context itself, the same string on every
                      ; keystroke, which the painter's cache compares by
                      ; identity.
                      (%ln-append (%ln-paint window marks
                                    (if (= start 0) %ln-context
                                      (%ln-append %ln-context (%ln-bsub text 0 start))))
                        (%ln-append "\r"
                          (if (= col 0) ""
                            (%ln-append "\x1b[" (%ln-append (Str8 str col) "C"))))))))))))))))

; --- history on disk --------------------------------------------------------
;
; A REPL history outlives the process, or it is not a history.  The path
; follows the XDG state convention -- state, not cache: a cache is something
; a tool may delete, and this is the user's own typing.  X_HISTORY overrides
; it outright, and an empty X_HISTORY turns persistence off, which is what a
; session handling secrets wants.
(def %ln-history-path
  (fn (_)
    (let ((override (Sys getenv "X_HISTORY")))
      (if (not (null? override)) override
        (let ((state (Sys getenv "XDG_STATE_HOME"))
              (home (Sys getenv "HOME")))
          (if (not (null? state)) (%ln-append state "/x/history")
            (if (null? home) () (%ln-append home "/.local/state/x/history"))))))))

(def %ln-load-history!
  (fn (_ ed)
    (let ((path (%ln-history-path)))
      (unless (or (null? path) (= 0 (%ln-blen path)))
        ; Newest first is the order Edit browses in; the file is oldest first,
        ; the order a person reads it in.
        (guard (_ ())
          (List for-each (fn (_ l) (unless (= 0 (%ln-blen l)) (ed remember! l)))
                (File read-lines path)))))))

(def %ln-append-history!
  (fn (_ s)
    (let ((path (%ln-history-path)))
      (unless (or (null? path) (= 0 (%ln-blen path)))
        ; Appended per line rather than written out at exit: a session that
        ; ends in a crash, a kill, or a power cut still keeps what it typed,
        ; and two sessions running at once interleave instead of one of them
        ; overwriting the other's file wholesale.
        ; The mkdir gets its OWN guard, and that is the whole of this
        ; comment's reason for existing: creating a directory that is
        ; already there raises, and under one shared guard that raise
        ; skipped the append -- so history was written only on the very
        ; first run of a session whose directory did not yet exist, and
        ; silently never again.
        (guard (_ ()) (File mkdir (Path dirname path) 493))
        (guard (_ ())
          (let ((fd (Sys open-append path)))
            (unless (< fd 0)
              (Sys fd-write fd (%ln-append s "\n"))
              (Sys close fd))))))))

; --- completion --------------------------------------------------------------
;
; The library documents itself, so completion is a prefix search of the doc
; registry -- the same entries (apropos) reports.  No separate list of names
; to keep in step, and a module that documents a new export completes the
; moment it loads.
(def %ln-completions
  (fn (_ prefix)
    ; The registry is filled lazily -- docs accumulate as modules load and
    ; are committed on demand -- so completion commits first, exactly as
    ; apropos and modules do.  Without this the first Tab of a session
    ; completes against an empty registry and silently offers nothing.
    (%doc-commit!)
    (if (= 0 (%ln-blen prefix)) ()
      (let ((go (fn (self entries acc)
                  (if (null? entries) acc
                    (let ((name (symbol->str (first (first entries)))))
                      (self (rest entries)
                        (if (Str8 starts? prefix name) (pair name acc) acc)))))))
        (List sort (fn (_ a b) (Str8 <? a b))
              (List distinct (go (first %doc-registry-cell) ())))))))

; The word before the point: what a completion is a completion OF.
(def %ln-word-before
  (fn (_ ed)
    (let ((text (ed text)) (point (ed point)))
      (let ((b (let ((probe (Edit make))) (probe set-text! text point) (probe back-word!) (probe point))))
        (%ln-bsub text b (- point b))))))

; The head of the innermost form still open at the point -- the `Str8` in
; `(Str8 sta`.  A forward walk with a depth count, because going backwards
; cannot tell an open paren from one inside a string without rescanning
; anyway; strings, character literals and comments are stepped over so a
; paren inside them opens nothing.
(def %ln-form-head
  (fn (_ text point)
    (let ((go (fn (self i opens)
                (if (>= i point) opens
                  (let ((b (%ln-byte text i)))
                    (match
                      ((= b 59) (self (%ln-eol text i point) opens))
                      ((= b 34) (self (%ln-string-end text (+ i 1) point) opens))
                      ((and (= b 35) (and (< (+ i 1) point) (= 92 (%ln-byte text (+ i 1)))))
                        (self (+ i 3) opens))
                      ((= b 40) (self (+ i 1) (pair (+ i 1) opens)))
                      ((= b 41) (self (+ i 1) (if (null? opens) () (rest opens))))
                      (#t (self (+ i 1) opens))))))))
      (let ((opens (go 0 ())))
        (if (null? opens) ""
          ; The first atom after that paren, if the paren is not immediately
          ; followed by another one -- `((f x) y` has no head to speak of.
          (let ((st (first opens)))
            (let ((e (%ln-atom-end text st point)))
              (if (<= e st) "" (%ln-bsub text st (- e st))))))))))

(def %ln-eol
  (fn (self s i n) (if (>= i n) i (if (= 10 (%ln-byte s i)) i (self s (+ i 1) n)))))
(def %ln-string-end
  (fn (self s i n)
    (if (>= i n) n
      (let ((b (%ln-byte s i)))
        (if (= 92 b) (self s (+ i 2) n) (if (= 34 b) (+ i 1) (self s (+ i 1) n)))))))
(def %ln-atom-end
  (fn (self s i n)
    (if (>= i n) i
      (let ((b (%ln-byte s i)))
        (match
          ((<= b 32) i)
          ((= b 40) i)
          ((= b 41) i)
          ((= b 59) i)
          (#t (self s (+ i 1) n)))))))

; What is already typed, and what the registry calls the thing being typed,
; are not the same string in this language, and that is the whole reason this
; function exists.  Methods dispatch subject-last -- `(Str8 split "," s)` --
; so at `(Str8 sta` the three letters under the cursor are the tail of
; `Str8/starts?`, which is the name the documentation registry holds.  So the
; class at the head of the open form is put back on the front before the
; search, and the answer is the pair (typed-prefix . full-names) so the
; caller knows how much of each name is already on screen.
(def %ln-candidates
  (fn (_ ed)
    (let ((word (%ln-word-before ed))
          (head (%ln-form-head (ed text) (ed point))))
      (let ((qualified?
              (and (> (%ln-blen head) 0)
                (and (null? (Str8 index-of "/" word))
                  (let ((b0 (%ln-byte head 0))) (and (>= b0 65) (<= b0 90)))))))
        (let ((qual (if qualified? (%ln-append head (%ln-append "/" word)) ())))
          (let ((qnames (if (null? qual) () (%ln-completions qual))))
            (if (not (null? qnames)) (pair qual qnames)
              (pair word (%ln-completions word)))))))))

; The candidate source, as a value, the way %repl-paint holds the painter.
; %ln-candidates prefix-searches the doc registry, which holds what x-lang
; modules document; a lang that parses its own syntax has none of its names
; in there, so Tab at its prompt offers x-lang's.  The seam is repl/loop.x's
; %repl-complete: a lang sets it to its own (ed -> (typed . names)), or to
; nil for a Tab that does nothing, and %ln-install! below puts this one there
; when nobody else has.  What is left below -- fill the unique answer, extend
; to the common prefix, list on the second Tab -- is the same job whatever
; the syntax is.

; The longest prefix every candidate shares -- what Tab fills in when the
; answer is not yet unique, the way a shell does it.
(def %ln-common-prefix
  (fn (_ names)
    (if (null? names) ""
      (let ((go (fn (self acc rest-names)
                  (if (null? rest-names) acc
                    (let ((b (first rest-names)))
                      (let ((trim (fn (self k)
                                    (if (= k 0) ""
                                      (if (Str8 starts? (%ln-bsub acc 0 k) b)
                                        (%ln-bsub acc 0 k) (self (- k 1)))))))
                        (self (trim (%ln-blen acc)) (rest rest-names))))))))
        (go (first names) (rest names))))))

; Everything of `name` that is not yet on screen.
(def %ln-tail
  (fn (_ name typed)
    (%ln-bsub name (%ln-blen typed) (- (%ln-blen name) (%ln-blen typed)))))

; Whether only spaces and tabs come before the point.
(def %ln-blank-before?
  (fn (_ ed)
    (let ((text (ed text)) (point (ed point)))
      (let ((go (fn (self i)
                  (if (>= i point) #t
                    (let ((b (%ln-byte text i)))
                      (if (if (= b 32) #t (= b 9)) (self (+ i 1)) #f))))))
        (go 0)))))

; Tab.  With candidates the unique one is filled in, or the prefix all of them
; share, or on the second Tab the list.  With nothing to complete -- no
; completer, or one with no answer -- a Tab after only whitespace inserts a
; tab, so an indented line in a lang that reads indentation is typed as it is
; in a file; after text it changes nothing, and ctrl-v Tab inserts one there.
(def %ln-complete!
  (fn (_ fd ed)
    ; With no completer installed there is nothing to destructure, and
    ; first/rest are unchecked prims, so the test comes before the walk.
    (let ((c (if (null? %repl-complete) () (%repl-complete ed))))
      (let ((typed (if (null? c) "" (first c)))
            (names (if (null? c) () (rest c))))
        (match
          ((null? names) (when (%ln-blank-before? ed) (ed insert! "\t")))
          ; One answer: finish the word.
          ((null? (rest names)) (ed insert! (%ln-tail (first names) typed)))
          (#t
            ; Several: extend as far as they agree, and if that added
            ; nothing, show them -- the shell's bargain, and the reason a
            ; second Tab is what lists rather than the first.
            (let ((common (%ln-common-prefix names)))
              (if (> (%ln-blen common) (%ln-blen typed))
                (ed insert! (%ln-tail common typed))
                (do
                  (Term emit fd "\r\n")
                  (List for-each
                        (fn (_ n) (Term emit fd (%ln-append "  " (%ln-append n "\r\n"))))
                        (List take 40 names))
                  (when (> (List length names) 40)
                    (Term emit fd (%ln-append "  ... "
                      (%ln-append (Str8 str (- (List length names) 40)) " more\r\n")))))))))))))

; ctrl-v, readline's quoted-insert: the key after it goes into the buffer as
; text, whatever it would have done on its own.  A Tab is the case that
; matters, since a bare Tab completes; a printable key inserts as it would
; anyway, and a control byte the buffer cannot hold is dropped as it is
; elsewhere.
(def %ln-quoted!
  (fn (_ ed read-byte)
    (let ((k (Term key read-byte)))
      (match
        ((eq? k (lit complete)) (ed insert! "\t"))
        ((str? k) (ed insert! k))
        (#t ())))))

; --- the key loop -------------------------------------------------------------
;
; Returns the line, or a symbol: 'eof for ctrl-d on an empty buffer, 'cancel
; for ctrl-c.  Both are the caller's business, not this loop's -- the REPL
; ends on one and reprompts on the other, and a different caller might do
; something else entirely.
(def %ln-loop
  (fn (self fd prompt ed read-byte)
    ; The width is asked for on every keystroke, deliberately: it is one
    ; ioctl against a redraw that costs milliseconds, and asking each time is
    ; what makes a terminal resized mid-line simply start drawing to the new
    ; width on the next key, with no SIGWINCH handler to install.
    (let ((cols (first (Term window fd))))
      (%ln-redraw fd prompt ed cols)
      (let ((k (Term key read-byte)))
        (match
          ; The descriptor ended under us: the same answer as ctrl-d.
          ((null? k) (lit eof))
          ((str? k) (do (ed insert! k) (self fd prompt ed read-byte)))
          ; The line is kept: draw it once more with no cursor focus, since
          ; this frame is what the transcript keeps.
          ((eq? k (lit enter)) (do (%ln-redraw fd prompt ed cols #t) (ed text)))
          ((eq? k (lit interrupt)) (lit cancel))
          ((eq? k (lit eof))
            ; ctrl-d ends the session only on an EMPTY line; on a line with
            ; text it is readline's delete-forward, which is what a hand
            ; reaching for it in the middle of a word means by it.
            (if (ed empty?) (lit eof)
              (do (ed del!) (self fd prompt ed read-byte))))
          (#t
            (do
              (match
                ((eq? k (lit left))       (ed back!))
                ((eq? k (lit right))      (ed forward!))
                ((eq? k (lit up))         (ed earlier!))
                ((eq? k (lit down))       (ed later!))
                ((eq? k (lit home))       (ed bol!))
                ((eq? k (lit end))        (ed eol!))
                ((eq? k (lit backspace))  (ed del-back!))
                ((eq? k (lit delete))     (ed del!))
                ((eq? k (lit word-left))  (ed back-word!))
                ((eq? k (lit word-right)) (ed forward-word!))
                ((eq? k (lit kill-eol))   (ed kill-eol!))
                ((eq? k (lit kill-bol))   (ed kill-bol!))
                ((eq? k (lit kill-word))  (ed kill-word-back!))
                ((eq? k (lit yank))       (ed yank!))
                ((eq? k (lit complete))   (%ln-complete! fd ed))
                ((eq? k (lit quoted-insert)) (%ln-quoted! ed read-byte))
                ((eq? k (lit clear))      (Term emit fd %ln-clear-screen))
                ; 'escape and 'unbound: a chord with no binding changes
                ; nothing, and silently doing nothing is the right answer --
                ; inserting the byte would put something unprintable in a
                ; buffer the redraw has to measure.
                (#t ()))
              (self fd prompt ed read-byte))))))))

; --- the class ----------------------------------------------------------------

(def-class Line ()
  (doc "Read one line from the terminal with editing, history and as-you-type colour -- the built-in answer to wrapping a session in rlwrap."
    (note "Raw mode brackets the read only: the line is handed back with the terminal already restored, so whatever evaluates it runs in a cooked tty.")
    (note "Long lines scroll sideways within the row rather than wrapping, which also bounds a redraw's cost by the terminal's width rather than the line's length.")
    (see read) (see available?) (see history-path))

  (static
    (method available? (self)
      (doc "Whether a line can be edited here: a terminal on the read descriptor, and a build whose termios calls resolved. False means the caller should fall back to plain line-at-a-time reading."
        (returns BOOL "True when the editor can run"))
      (Term tty? %ln-fd))

    (method fd (self . (param fd INT "The descriptor to read from; omit to read the current one"))
      (doc "The descriptor the editor reads from, and sets it when given one. repl/loop.x reclaims the terminal onto fd 0 before the first read, so 0 is right for a session; a caller driving a different tty says so here."
        (returns INT "The descriptor in force"))
      (unless (null? fd) (set! %ln-fd (first fd)))
      %ln-fd)

    (method completer (self . (param f CALLABLE "The completer to install; () turns Tab off. Omit to read the one in force"))
      (doc "The function Tab asks for candidates, and installs one when given it. It is handed the Edit buffer and answers (typed . names) -- the text being completed, and every name it could become. The seam itself is %repl-complete; this reads and sets it."
        (returns ANY "The completer in force, or nil when Tab does nothing")
        (note "The default prefix-searches the doc registry, which holds what x-lang modules document. A lang that parses its own syntax has none of its names there, so it installs its own here, the way it sets %repl-paint for the colour. Filling a unique answer, extending to the common prefix and listing on the second Tab stay whichever completer is installed."))
      (unless (null? f) (set! %repl-complete (first f)))
      %repl-complete)

    (method buffer (self)
      (doc "The session's Edit buffer -- one for the process, so history carries from line to line. Made on first use, with the history file loaded into it."
        (returns Edit "The session buffer"))
      (when (null? %ln-buffer)
        (set! %ln-buffer (Edit make))
        (unless %ln-history-loaded
          (set! %ln-history-loaded #t)
          (%ln-load-history! %ln-buffer)))
      %ln-buffer)

    (method history-path (self)
      (doc "Where the history is kept: $X_HISTORY if set, else $XDG_STATE_HOME/x/history, else ~/.local/state/x/history. An empty X_HISTORY turns persistence off."
        (returns ANY "The path, or nil when there is nowhere to keep one")
        (sample "(Line history-path)" "\"/home/you/.local/state/x/history\""))
      (%ln-history-path))

    (method read (self (param prompt STRING "The prompt to show")
                       . (param context STRING "Optional: the lines already entered for this entry, joined by newlines"))
      (doc "Read one edited line. Returns the line as a string, 'eof for ctrl-d on an empty line, or 'cancel for ctrl-c. The terminal is restored before this returns, whichever way it ends."
        (returns ANY "A STRING, 'eof, or 'cancel")
        (note "A line that is kept is pushed onto the history and appended to the history file; 'eof and 'cancel are not recorded.")
        (note "With context, a continuation line is marked and painted as the rest of the entry: paren depths carry on from the earlier lines, a close paren that closes one of them takes its colour, and a string left open there is coloured as a string."))
      (let ((fd %ln-fd))
        (let ((saved (Term raw! fd)))
          (if (null? saved) (lit eof)
            (let ((ed (Line buffer))
                  (read-byte (fn (_) (let ((b (Sys fd-read fd 1)))
                                       (if (null? b) () (first b))))))
              (ed clear!)
              (set! %ln-context
                (if (null? context) ""
                  (if (= 0 (%ln-blen (first context))) ""
                    (%ln-append (first context) "\n"))))
              ; The terminal goes back even if the loop raises: a session that
              ; dies with ECHO off leaves the user's shell broken, and that is
              ; not a thing to leave to the happy path.
              (let ((r (guard (err
                          (do (set! %ln-context "")
                              (Term restore! fd saved)
                              (Term emit fd "\r\n")
                              (Err raise (lit io) "Line read: interrupted" err)))
                        (%ln-loop fd prompt ed read-byte))))
                (set! %ln-context "")
                (Term restore! fd saved)
                (Term emit fd "\r\n")
                (when (str? r)
                  (ed remember! r)
                  (%ln-append-history! r))
                r))))))))

; --- REPL integration --------------------------------------------------------
;
; repl/loop.x runs one TURN per iteration and reads it with the C reader,
; which reads a form straight off the descriptor and therefore cannot be
; edited.  Rather than reach into that loop, this file installs a whole turn
; -- the same shape repl/ansi.x uses when it installs a printer -- and
; loop.x keeps its own path untouched for every case where there is no
; terminal to edit on.
;
; A turn is a form, but a read is a line, and those are not the same thing.
; The C reader knows when a form is finished because it is the thing doing
; the reading; here the line arrives whole and has to be offered to the
; reader to find out.  "Unterminated input" is the reader saying `keep
; going`, so the turn asks for another line and tries again -- which is what
; makes a multi-line definition editable one line at a time.
;
; What the turn does with the line is the %repl-eval-line seam, and what is
; below is the platform's answer to it: read as x-lang, ask for more while
; the reader says the form is unfinished, evaluate and print each form.  A
; lang installs its own -- Python's reads a block to the blank line and
; parses Python -- and the turn, the keys, the history and the colour hooks
; around it stay.  %ln-install! puts this one on the seam over nil or over
; itself, the rule %repl-paint states, so a lang's survives whether it was
; set before this file loaded or after.

; Everything the reader said it could not finish, and nothing else: any other
; raise is a real syntax error and belongs on stderr.
;
; Two shapes, because the reader's raise has two.  With x/type/err loaded it
; arrives as an engine ERR whose code carries the text; without it, as the
; bare string it has always been.  Reading the CODE rather than rendering the
; error and matching that is what keeps this working when an Err grows a
; prefix or a location.
;
; It is still a match on a message, which is the weakest join in this file:
; the engine has no distinct condition for `input ended inside a form`, only
; this text.  repl/loop.x is in the same position and tells ctrl-c from
; ctrl-d by the interrupt flag rather than by the message; there is no such
; second channel here, because a line editor has already consumed the key.
(def %ln-unterminated?
  (fn (_ err)
    (if (str? err) (Str8 =? err "Unterminated input")
      (guard (_ #f) (Str8 =? (Err code-of err) "Unterminated input")))))

; The newline is the terminator.  The editor hands the line back without
; one, and the reader drops a final atom that nothing ends (#161): `name`
; read as no forms at all, and printed nothing, while `(def name 1)` was
; fine because the paren closes it.  repl/paint.x appends a space for the
; same reason; here it is a newline so a trailing comment ends too.
(def %ln-eval-line
  (fn (self text)
    (let ((forms (guard (err (if (%ln-unterminated?  err) (lit %more) (Err raise (lit syntax) err ())))
                   ((prim-ref (lit tok) (lit read-str)) (%base) (%ln-append text "\n")))))
      (if (eq? forms (lit %more))
        ; Unfinished: ask for the rest.  ctrl-c abandons the whole entry,
        ; ctrl-d on an empty continuation line is the end of the session --
        ; the same two answers they give on the first line.
        (let ((more (Line read %repl-prompt-more text)))
          (match
            ((eq? more (lit eof)) (Sys exit 0))
            ((eq? more (lit cancel)) ())
            (#t (self (%ln-append text (%ln-append "\n" more))))))
        ; A line may hold several forms, and each one is its own result:
        ; `(write 1) (write 2)` prints both, the way handing the same text
        ; to the C reader would.
        (List for-each (fn (_ f) (%repl-print (eval! f))) forms)))))

(def %ln-turn
  (fn (_)
    (let ((line (Line read %repl-prompt)))
      (match
        ((eq? line (lit eof)) (Sys exit 0))
        ((eq? line (lit cancel)) ())
        (#t
          (guard (err
              (%set-cell-int! %sigint-flag 0)
              (if (Err stop? err) (display "\n")
                (%seq
                  (%stderr (%str-append (%error-loc-prefix)
                             (if (str? err) err (%ln-write-to-str err))))
                  (%stderr "\n"))))
            (%repl-eval-line line)))))))

; The whole loop, replacing repl/loop.x's.  Replacing `repl` is the seam
; this tree already uses: x-python and x-ash both install a reader of their
; own that way, for the same reason this needs to -- the platform loop
; customises the PROMPT and the PRINTER, and reading a form with a line
; editor is neither of those.  What is kept from the original is everything
; around the read: the fd-3 reclaim, the per-turn sweep, and clearing the
; interrupt flag before the prompt.
(def %ln-repl
  (op ()
    ()
    ; x.sh parks the user's terminal on fd 3 while the boot stream occupies
    ; fd 0.  loop.x's repl does this on ITS first call; this one replaces
    ; that repl, so it has to do it too -- and before Line reads anything,
    ; because the descriptor it reads is the one this installs.
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))
    ; Stepping aside rather than exiting.  Installation decided there was a
    ; terminal, but that was before the swap above and it can still turn out
    ; to be wrong -- fd 3 was a tty and fd 0 is not, the tty went away, a
    ; build's termios calls resolved but tcgetattr refuses this descriptor.
    ; A read that cannot enter raw mode has no line to give back, and the
    ; honest answer is to hand the session to the loop that does not need
    ; raw mode, not to report end-of-input and exit 0 -- which is what this
    ; did, and which looks from the outside like the REPL quitting for no
    ; reason.
    (if (not (Term tty? %ln-fd))
      (do (set! repl %repl-platform-repl) (repl))
      (do
        ; The turn sweep, at the top of the iteration where the seat is quiet.
        (%ln-collect)
        (%set-cell-int! %sigint-flag 0)
        (%ln-turn)
        (%ln-repl)))))

; Installed only when there is a terminal to edit on.  Without one -- a pipe,
; a spec harness, a `-f` run, a build whose termios calls did not resolve --
; `repl` is left alone and the session reads exactly as it did before this
; file existed.
;
; The tty test looks at fd 3 as well as fd 0, because at the moment this
; loads the terminal is still parked on fd 3 and fd 0 is the boot pipe -- the
; swap %ln-repl does has not happened yet.
;
; `repl` is only ours to move when nobody else has moved it.  A lang
; replaces repl to read its own syntax -- x-python and x-ash both do -- and a
; bundle's entry runs BEFORE the launcher that imports this file, so the
; obvious unconditional set! would take the lang's reader away and read Lisp
; at its prompt.  So this installs over the PLATFORM's repl, or over the one
; it last installed itself (the state-image rerun), and over nothing else.
; repl/ansi.x guards the REPL printer by exactly this rule, for exactly this
; reason.
;
; The two seams this file answers -- what a finished line means, and where
; Tab's candidates come from -- install under the same rule, but with no
; terminal test: they are values a lang may read or replace whether or not
; a session is running, and a spec exercises them without a tty.  Both are
; named globals here, so "the one this file last installed" is an identity
; test against the name and needs no anchor of its own.  What they are is
; also registered as x's, so a session that switched to another lang and
; back gets them again.
(def %ln-own ())
(def %ln-install!
  (fn (_)
    (when (or (null? %repl-eval-line) (same? %repl-eval-line %ln-eval-line))
      (set! %repl-eval-line %ln-eval-line))
    (when (or (null? %repl-complete) (same? %repl-complete %ln-candidates))
      (set! %repl-complete %ln-candidates))
    (Lang register! "x" (list (pair (lit %repl-eval-line) %ln-eval-line)
                              (pair (lit %repl-complete) %ln-candidates)))
    (when (and (or (same? repl %repl-platform-repl) (same? repl %ln-own))
               (or (Term tty? %ln-fd) (Sys isatty 3)))
      (set! repl %ln-repl)
      (set! %ln-own %ln-repl))))

(%ln-install!)
(set! %image-recache-hooks (pair (fn (_) (%ln-install!)) %image-recache-hooks))

(doc (provide x/repl/line Line)
  (note "Built on repl/edit.x (the buffer), repl/term.x (the tty) and repl/paint.x (the colour); each is usable on its own.")
  (note "History is appended per line to $XDG_STATE_HOME/x/history, so a session that crashes still keeps what it typed. X_HISTORY overrides the path; an empty X_HISTORY disables it.")
  (note "Tab completes against the documentation registry -- the same names apropos searches -- so a module that documents an export completes as soon as it loads.")
  (note "A Tab with nothing to complete and only whitespace before the cursor inserts a tab, and ctrl-v followed by Tab inserts one after text; a tab is drawn to the next multiple of eight columns.")
  (note "A lang that reads its own syntax has no names in that registry: it sets (Line completer) to its own, or () to turn Tab off, as it sets %repl-paint for the colour, and %repl-eval-line to read its syntax from the line the editor hands back. x/repl/lang bundles those as a named lang a session switches to with (lang NAME).")
  "Line: one edited, coloured line read from the terminal; the built-in replacement for rlwrap.")
(provide x/repl/line Line)
