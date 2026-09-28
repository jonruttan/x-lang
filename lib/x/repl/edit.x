; repl/edit.x -- Edit: the line buffer a key press acts on, with no terminal
; in sight.
;
; The split this file exists to make: a line editor is two things wearing
; one coat: a state machine over a string and a cursor, and a pile of
; terminal escape sequences.  Only the second needs a tty, and only the
; second is hard to test -- so they are separate files, and this is the one
; with the logic in it.  Every operation here is a pure function of the
; buffer and its point; nothing reads a descriptor, nothing writes one, and
; the whole of it runs under the ordinary spec harness with no pty at all.
; repl/term.x owns the descriptor, repl/line.x joins the two.
;
; The point is a byte offset, and the buffer is bytes, because that is what
; the reader downstream consumes and what a redraw has to measure.  Motion,
; though, is by CHARACTER: ctrl-b over an accented letter moves one glyph,
; not one of its two bytes, or the next keystroke splits the sequence and
; the terminal renders a replacement glyph for the rest of the session.  So
; the two motion helpers below step whole UTF-8 sequences and everything
; else is offset arithmetic over bytes.
;
; Zero top-level %-globals (new-file budget 0): the cached byte prims that
; the hot paths want are bound inside the methods that use them.

(module x/repl/edit)
(import x/type/class)
(import x/type/str)
(import x/type/list)

(def-class Edit ()
  (doc "A line buffer and its cursor: the state a key press acts on. Pure -- no terminal, no descriptor, no escape sequences (repl/term.x owns those). Motion is by character, offsets are bytes."
    (note "The point is a BYTE offset into text; motion helpers step whole UTF-8 sequences so a multi-byte glyph is never split.")
    (note "History is held newest-first. While browsing, the half-typed line is stashed so that walking back down to the bottom restores it.")
    (example "(let ((e (Edit make))) (e insert! \"ab\") (e back!) (e insert! \"X\") (e text))" "\"aXb\"")
    (see insert!) (see earlier!) (see kill-eol!))

  text    ; the line, as bytes
  point   ; cursor, a byte offset in [0, (length text)]
  hist    ; entries, NEWEST first
  hpos    ; how far back we have walked, or nil when editing a fresh line
  stash   ; the fresh line, parked while hpos is non-nil
  kill    ; the kill ring, one entry deep -- what yank! puts back

  ; --- construction --------------------------------------------------------

  (static
    (method make (self . (param prior LIST "Prior entries, newest first; default empty"))
      (doc "An empty buffer, optionally carrying a history list (newest first)."
        (returns Edit "A new buffer with the point at 0")
        (example "((Edit make) text)" "\"\""))
      (new-from self (list 'text "" 'point 0
                           'hist (if (null? prior) () (first prior))
                           'hpos () 'stash "" 'kill "")))

    ; UTF-8 motion, as statics because they are facts about a string rather
    ; than about any one buffer -- repl/line.x measures a prompt with them too.
    (method next-start (self (param s STRING "Byte string")
                             (param i INTEGER "A sequence start, or the end"))
      (doc "The byte offset of the sequence after the one starting at i, clamped to the end of s."
        (returns INTEGER "Offset of the next character, or (Str8 length s) at the end")
        (example "(Edit next-start \"hé\" 1)" "3"))
      (let ((n (Str8 length s)))
        (if (>= i n) n
          (let ((e (+ i (StrUtf8 width s i))))
            (if (> e n) n e)))))

    (method prev-start (self (param s STRING "Byte string")
                             (param i INTEGER "A sequence start, or the end"))
      (doc "The byte offset of the sequence before the one starting at i, clamped to 0. Walks back over continuation bytes (0x80-0xBF), so it lands on a character boundary rather than inside one."
        (returns INTEGER "Offset of the previous character, or 0 at the start")
        (example "(Edit prev-start \"hé\" 3)" "1"))
      (let ((bref (prim-ref (lit str) (lit byte-ref)))
            (cint (prim-ref (lit char) (lit ->int))))
        (let ((go (fn (self j)
                    (if (<= j 0) 0
                      ; A continuation byte is 10xxxxxx: keep walking.
                      (if (= 128 (& (cint (bref s (- j 1))) 192))
                        (self (- j 1))
                        (- j 1))))))
          (go (if (> i (Str8 length s)) (Str8 length s) i)))))

    ; Word motion's one rule, in one place so that forward and back agree on
    ; what a word is: anything that is not a space and not a delimiter the
    ; reader would break on.  A REPL's words are mostly symbols, and a symbol
    ; may hold nearly any punctuation, so the class is defined by what it
    ; excludes rather than by an alphabet.
    (method word-byte? (self (param b INTEGER "A byte value"))
      (doc "Whether a byte counts as part of a word for ctrl-left / meta-b motion: not whitespace, and not one of ()\";'`|."
        (returns BOOL "True when the byte is word material")
        (example "(Edit word-byte? 40)" "#f"))
      (not (or (<= b 32)
               (or (= b 40) (or (= b 41) (or (= b 34) (or (= b 59)
               (or (= b 39) (or (= b 96) (or (= b 124) (= b 127))))))))))))

  ; --- reading the buffer ---------------------------------------------------

  (method text (self)
    (doc "The buffer's bytes." (returns STRING "The line as typed so far"))
    (field 'text))

  (method point (self)
    (doc "The cursor, as a byte offset into the text." (returns INTEGER "Byte offset"))
    (field 'point))

  (method empty? (self)
    (doc "Whether the buffer holds no bytes." (returns BOOL "True when the line is empty"))
    (= 0 (Str8 length (field 'text))))

  (method before (self)
    (doc "The text to the left of the point -- what a completion has to work from."
      (returns STRING "Bytes in [0, point)")
      (example "(let ((e (Edit make))) (e insert! \"ab\") (e back!) (e before))" "\"a\""))
    (Str8 sub 0 (field 'point) (field 'text)))

  (method after (self)
    (doc "The text to the right of the point." (returns STRING "Bytes in [point, end)"))
    (let ((t (field 'text)))
      (Str8 sub (field 'point) (- (Str8 length t) (field 'point)) t)))

  ; --- editing --------------------------------------------------------------

  (method set-text! (self (param s STRING "Replacement text")
                          . (param at INTEGER "Where to leave the point; default the end"))
    (doc "Replace the whole buffer, leaving the point at `at` (the end by default). The point is clamped into the new text."
      (returns Edit "self"))
    (set-field! 'text s)
    (let ((n (Str8 length s)))
      (let ((p (if (null? at) n (first at))))
        (set-field! 'point (if (< p 0) 0 (if (> p n) n p)))))
    self)

  (method insert! (self (param s STRING "Text to insert at the point"))
    (doc "Insert s at the point and leave the point after it."
      (returns Edit "self")
      (example "(let ((e (Edit make))) (e insert! \"hi\") (e text))" "\"hi\""))
    (let ((t (field 'text)) (p (field 'point)))
      (set-field! 'text (Str8 append (Str8 sub 0 p t)
                                      (Str8 append s (Str8 sub p (- (Str8 length t) p) t))))
      (set-field! 'point (+ p (Str8 length s))))
    self)

  (method del-back! (self)
    (doc "Delete the character before the point (backspace). A no-op at the start of the line."
      (returns Edit "self")
      (example "(let ((e (Edit make))) (e insert! \"ab\") (e del-back!) (e text))" "\"a\""))
    (let ((p (field 'point)))
      (unless (<= p 0)
        (let ((t (field 'text)))
          (let ((b (Edit prev-start t p)))
            (set-field! 'text (Str8 append (Str8 sub 0 b t)
                                            (Str8 sub p (- (Str8 length t) p) t)))
            (set-field! 'point b)))))
    self)

  (method del! (self)
    (doc "Delete the character at the point (the Delete key). A no-op at the end of the line."
      (returns Edit "self"))
    (let ((t (field 'text)) (p (field 'point)))
      (unless (>= p (Str8 length t))
        (let ((e (Edit next-start t p)))
          (set-field! 'text (Str8 append (Str8 sub 0 p t)
                                          (Str8 sub e (- (Str8 length t) e) t))))))
    self)

  ; --- motion ---------------------------------------------------------------

  (method back! (self)
    (doc "Move the point one character left." (returns Edit "self"))
    (set-field! 'point (Edit prev-start (field 'text) (field 'point)))
    self)

  (method forward! (self)
    (doc "Move the point one character right." (returns Edit "self"))
    (set-field! 'point (Edit next-start (field 'text) (field 'point)))
    self)

  (method bol! (self)
    (doc "Move the point to the start of the line (ctrl-a / Home)." (returns Edit "self"))
    (set-field! 'point 0)
    self)

  (method eol! (self)
    (doc "Move the point to the end of the line (ctrl-e / End)." (returns Edit "self"))
    (set-field! 'point (Str8 length (field 'text)))
    self)

  ; Word motion skips the run of non-word bytes first, then the word itself --
  ; the readline rule, and the reason `(foo bar|)` with ctrl-left lands before
  ; `bar` rather than between the paren and it.
  (method back-word! (self)
    (doc "Move the point left over one word, skipping any separators first (meta-b / ctrl-left)."
      (returns Edit "self")
      (example "(let ((e (Edit make))) (e insert! \"ab cd\") (e back-word!) (e point))" "3"))
    (let ((bref (prim-ref (lit str) (lit byte-ref)))
          (cint (prim-ref (lit char) (lit ->int)))
          (t (field 'text)))
      (let ((skip (fn (self j want)
                    (if (<= j 0) 0
                      (let ((b (Edit prev-start t j)))
                        (if (eq? want (Edit word-byte? (cint (bref t b))))
                          (self b want) j))))))
        (set-field! 'point (skip (skip (field 'point) #f) #t))))
    self)

  (method forward-word! (self)
    (doc "Move the point right over one word, skipping any separators first (meta-f / ctrl-right)."
      (returns Edit "self"))
    (let ((bref (prim-ref (lit str) (lit byte-ref)))
          (cint (prim-ref (lit char) (lit ->int)))
          (t (field 'text)))
      (let ((skip (fn (self j want)
                    (if (>= j (Str8 length t)) (Str8 length t)
                      (if (eq? want (Edit word-byte? (cint (bref t j))))
                        (self (Edit next-start t j) want) j)))))
        (set-field! 'point (skip (skip (field 'point) #f) #t))))
    self)

  ; --- killing and yanking ---------------------------------------------------

  (method kill-eol! (self)
    (doc "Delete from the point to the end of the line, saving it for yank! (ctrl-k)."
      (returns Edit "self"))
    (let ((t (field 'text)) (p (field 'point)))
      (set-field! 'kill (Str8 sub p (- (Str8 length t) p) t))
      (set-field! 'text (Str8 sub 0 p t)))
    self)

  (method kill-bol! (self)
    (doc "Delete from the start of the line to the point, saving it for yank! (ctrl-u)."
      (returns Edit "self"))
    (let ((t (field 'text)) (p (field 'point)))
      (set-field! 'kill (Str8 sub 0 p t))
      (set-field! 'text (Str8 sub p (- (Str8 length t) p) t))
      (set-field! 'point 0))
    self)

  (method kill-word-back! (self)
    (doc "Delete the word before the point, saving it for yank! (ctrl-w)."
      (returns Edit "self")
      (example "(let ((e (Edit make))) (e insert! \"ab cd\") (e kill-word-back!) (e text))" "\"ab \""))
    (let ((p (field 'point)))
      (self back-word!)
      (let ((b (field 'point)) (t (field 'text)))
        (set-field! 'kill (Str8 sub b (- p b) t))
        (set-field! 'text (Str8 append (Str8 sub 0 b t)
                                        (Str8 sub p (- (Str8 length t) p) t)))))
    self)

  (method yank! (self)
    (doc "Insert the last killed text at the point (ctrl-y)." (returns Edit "self"))
    (self insert! (field 'kill))
    self)

  (method kill (self)
    (doc "The last killed text." (returns STRING "The kill ring's one entry"))
    (field 'kill))

  (method clear! (self)
    (doc "Empty the buffer, put the point at 0, and end any history walk -- the three things that together mean `a fresh line starts here`."
      (returns Edit "self")
      (note "Ending the walk is the part that is easy to leave out: without it, a line abandoned halfway through browsing leaves hpos where it was, and the next Up carries on from the middle of the history instead of from the newest entry.")
      (example "(let ((e (Edit make))) (e remember! \"a\") (e earlier!) (e clear!) (list (e text) (e browsing?)))" "(\"\" #f)"))
    (self set-text! "" 0)
    (set-field! 'hpos ())
    (set-field! 'stash "")
    self)

  ; --- history ---------------------------------------------------------------
  ;
  ; Browsing is a walk down a list, and the subtlety is the BOTTOM of it: a
  ; half-typed line that the user leaves by pressing Up has to come back when
  ; they press Down again, so it is stashed on the way out and restored on the
  ; way in.  hpos nil means "editing the fresh line"; 0 means "showing the
  ; newest entry", and it counts upward into the past.

  (method hist (self)
    (doc "The history list, newest first." (returns LIST "Entries"))
    (field 'hist))

  (method remember! (self (param s STRING "The line to record"))
    (doc "Push a line onto the front of the history and leave browsing. A blank line, or a repeat of the newest entry, is not recorded -- the two cases that otherwise fill a history with noise."
      (returns Edit "self")
      (example "(let ((e (Edit make))) (e remember! \"a\") (e remember! \"a\") (List length (e hist)))" "1"))
    (let ((h (field 'hist)))
      (unless (or (= 0 (Str8 length (Str8 trim s)))
                  (and (not (null? h)) (Str8 =? s (first h))))
        (set-field! 'hist (pair s h))))
    (set-field! 'hpos ())
    (set-field! 'stash "")
    self)

  (method earlier! (self)
    (doc "Show the next entry further back in history (Up / ctrl-p), stashing the fresh line on the way out. A no-op at the oldest entry."
      (returns BOOL "True when the buffer changed"))
    (let ((h (field 'hist)) (hp (field 'hpos)))
      (let ((next (if (null? hp) 0 (+ hp 1))))
        (if (>= next (List length h)) #f
          (do
            (when (null? hp) (set-field! 'stash (field 'text)))
            (set-field! 'hpos next)
            (self set-text! (List ref next h))
            #t)))))

  (method later! (self)
    (doc "Show the next entry toward the present (Down / ctrl-n), restoring the stashed fresh line at the bottom. A no-op when already editing a fresh line."
      (returns BOOL "True when the buffer changed"))
    (let ((hp (field 'hpos)))
      (if (null? hp) #f
        (if (= hp 0)
          (do (set-field! 'hpos ())
              (self set-text! (field 'stash))
              #t)
          (do (set-field! 'hpos (- hp 1))
              (self set-text! (List ref (- hp 1) (field 'hist)))
              #t)))))

  (method browsing? (self)
    (doc "Whether the buffer is showing a history entry rather than a fresh line."
      (returns BOOL "True while browsing"))
    (not (null? (field 'hpos))))

  (method position (self)
    (doc "The index of the history entry being shown, 0 being the newest, or nil while a fresh line is being edited."
      (returns ANY "An index, or nil"))
    (field 'hpos))

  ; --- searching the history -------------------------------------------------
  ;
  ; A search reports where a match is rather than moving there, so a caller
  ; can show a match without disturbing the line being edited.  jump! moves
  ; there once the match is accepted, the same way earlier! would have, so
  ; later! walks back down to the line that was being typed.

  (method search (self (param query STRING "Text to look for")
                       (param from INTEGER "Index of the first entry to try; 0 is the newest")
                       (param dir SYMBOL "'back to walk toward older entries, 'forward toward newer ones")
                       . (param unlike STRING "An entry equal to this is passed over; optional"))
    (doc "Find the first history entry at or beyond `from`, walking in direction `dir`, that contains query. Answers (index . offset): the entry's index, and where query occurs in it -- its last occurrence walking back, its first walking forward -- or nil when no entry matches. An entry equal to `unlike` is passed over, so a repeated search moves on to a different line."
      (returns ANY "(index . offset), or nil")
      (example "(let ((e (Edit make (list \"cd\" \"ls a\" \"ls b\")))) (e search \"ls\" 0 'back))" "(1 . 0)"))
    (let ((h (field 'hist))
          (skip (if (null? unlike) () (first unlike)))
          (back? (eq? dir 'back)))
      (let ((at (fn (_ entry)
                  (if (if (null? skip) #f (Str8 =? entry skip)) ()
                    (if back? (Str8 last-index-of query entry) (Str8 index-of query entry)))))
            (n (List length h)))
        (let ((go (fn (self entries k step)
                    (if (null? entries) ()
                      (let ((o (at (first entries))))
                        (if (null? o) (self (rest entries) (+ k step) step) (pair k o)))))))
          (if back?
            (if (>= from n) ()
              (let ((f (if (< from 0) 0 from))) (go (List drop f h) f 1)))
            ; Walking toward the present is a walk down the first from+1
            ; entries reversed, so the list is taken once rather than
            ; indexed once per step.
            (let ((top (if (>= from n) (- n 1) from)))
              (if (< top 0) ()
                (go (List reverse (List take (+ top 1) h)) top -1))))))))

  (method jump! (self (param k INTEGER "Index of the entry to show; 0 is the newest")
                      . (param at INTEGER "Where to leave the point; default the end"))
    (doc "Show history entry k as if walked to with earlier!, stashing the fresh line first when not already browsing, so later! walks back down to it. The point is left at `at`, the end of the entry by default. An index outside the history leaves the buffer as it was."
      (returns BOOL "True when the buffer changed")
      (example "(let ((e (Edit make (list \"b\" \"a\")))) (e insert! \"draft\") (e jump! 1) (e later!) (e later!) (e text))" "\"draft\""))
    (let ((h (field 'hist)))
      (if (if (< k 0) #t (>= k (List length h))) #f
        (do
          (when (null? (field 'hpos)) (set-field! 'stash (field 'text)))
          (set-field! 'hpos k)
          (if (null? at) (self set-text! (List ref k h))
            (self set-text! (List ref k h) (first at)))
          #t)))))

(doc (provide x/repl/edit Edit)
  (note "Pure: no terminal, no descriptor. repl/term.x owns the tty and repl/line.x drives both.")
  (note "Offsets are bytes; motion is by character, so multi-byte glyphs are never split.")
  "Edit: the line buffer and cursor a REPL key press acts on.")
