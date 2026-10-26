; repl/paint.x -- Paint: colouring a line that is still being typed.
;
; The colours are x/tool/syntax's: a line is coloured by the spans of x-lang's
; grammar, (Syntax x), whose atoms are classed by what the reader reads them
; as, so a colour cannot disagree with the evaluator.  What this file adds is
; what a line editor needs over that: the text before the window painted as
; its start, each paren coloured by its nesting depth with the pair beside the
; cursor inverse, and the last line's paint kept, since moving the cursor or
; holding an arrow key asks for the same bytes again.
;
; The palette is repl/ansi.x's, so NO_COLOR, TERM=dumb and --no-color reach
; this for free, and a colourless terminal short-circuits the whole walk.

(module x/repl/paint)
(import x/type/class)
(import x/type/str)
(import x/type/list)
(import x/repl/ansi)
(import x/tool/syntax)

; --- cached prims (the walks run per span; none of these may be a door) ---
(def %pt-bref   (prim-ref (lit str)  (lit byte-ref)))
(def %pt-blen   (prim-ref (lit str)  (lit byte-len)))
(def %pt-append (prim-ref (lit str)  (lit append)))
(def %pt-cint   (prim-ref (lit char) (lit ->int)))
(def %pt+       (prim-ref (lit int)  (lit +)))
(def %pt-       (prim-ref (lit int)  (lit -)))
(def %pt-mod    (prim-ref (lit int)  (lit %)))
(def %pt-same?  (prim-ref (lit obj)  (lit same?)))

; --- state, all of it rebuilt by %paint-install! -------------------------
(def %paint-c-depth ())   ; the codes parens cycle through by nesting depth
(def %paint-c-depth-n 0)  ; and how many there are, so the cycle costs a mod and no door
(def %paint-c-lone "")    ; the code for a close paren with nothing to close
(def %paint-c-focus "")   ; the code added to the pair the cursor is beside
; The last line painted, and what it painted to.  A redraw repaints only
; because the TEXT changed: moving the cursor, walking history onto a line
; already seen, and a resize all ask for the same bytes again.  Identity, not
; equality -- the buffer builds a new string whenever it edits and keeps the
; old one whenever it does not, which is exactly the question being asked.
(def %paint-last-in ())
(def %paint-last-out ())
(def %paint-last-marks ())
(def %paint-last-before ())

; Two mark lists, the same or not: (offset depth focused) each, compared in
; place rather than through a generic equality a bundle might have rebound.
(def %paint-same-marks?
  (fn (self a b)
    (if (null? a) (null? b)
      (if (null? b) #f
        (let ((x (first a)) (y (first b)))
          (if (if (= (first x) (first y))
                (if (= (first (rest x)) (first (rest y)))
                  (eq? (first (rest (rest x))) (first (rest (rest y)))) #f) #f)
            (self (rest a) (rest b))
            #f))))))

; The code for a paren: its depth's colour, cycling through the palette, with
; the focus code added on the pair the cursor is beside; -1 is a close with
; nothing to close.
(def %paint-depth-code
  (fn (_ depth focused)
    (let ((base (if (< depth 0) %paint-c-lone
                  (let ((go (fn (self k codes)
                              (if (null? codes) ""
                                (if (= k 0) (first codes) (self (%pt- k 1) (rest codes)))))))
                    (go (%pt-mod depth %paint-c-depth-n) %paint-c-depth)))))
      (if focused (%pt-append base %paint-c-focus) base))))

; --- bracket depths -----------------------------------------------------------
;
; A mark for every paren in the line: (offset depth focused).  Depth is the
; nesting level, 0 at the top, and open and close share it, so a pair colours
; alike; a close paren with nothing to close is -1.  `focused` is true on the
; two halves of the pair the cursor is beside: a close just before the cursor
; is preferred, then an open under it, then the other two.  The parens are the
; grammar's punct spans, so one inside a string, a comment or a character
; literal is none; `open` is the stack of (offset . depth) for parens not yet
; closed.  Marks come back in source order.
(def %paint-depths
  (fn (_ s at)
    (let ((n (%pt-blen s)))
      (let ((before (if (> at 0) (%pt-cint (%pt-bref s (%pt- at 1))) 0))
            ; A cursor outside the line -- the editor passes -1 for a frame
            ; that is to keep no focus -- is beside nothing.
            (here (if (if (>= at 0) (< at n) #f) (%pt-cint (%pt-bref s at)) 0)))
        (let ((target (match
                        ((= before 41) (%pt- at 1))
                        ((= here 40) at)
                        ((= here 41) at)
                        ((= before 40) (%pt- at 1))
                        (#t -1))))
          ; The walk builds the marks reversed, then flips them once; a
          ; matched pair whose half is the target is flagged on both halves.
          (let ((flag (fn (self ms off)
                        (if (null? ms) ()
                          (if (= (first (first ms)) off)
                            (pair (list off (first (rest (first ms))) #t) (rest ms))
                            (pair (first ms) (self (rest ms) off)))))))
            (let ((go (fn (self sps open depth acc)
                        (if (null? sps) (%reverse acc)
                          (let ((i (first (first sps))))
                            (let ((b (if (eq? (first (rest (rest (first sps)))) (lit punct))
                                       (%pt-cint (%pt-bref s i)) 0)))
                              (match
                                ((= b 40)
                                  (self (rest sps) (pair (pair i depth) open) (%pt+ depth 1)
                                        (pair (list i depth #f) acc)))
                                ((= b 41)
                                  (if (null? open)
                                    (self (rest sps) () 0 (pair (list i -1 (= i target)) acc))
                                    (let ((o (first (first open))) (d (rest (first open))))
                                      (let ((hit (if (= i target) #t (= o target))))
                                        (self (rest sps) (rest open) d
                                              (pair (list i d hit)
                                                    (if hit (flag acc o) acc)))))))
                                (#t (self (rest sps) open depth acc)))))))))
              (go ((Syntax x) spans s) () 0 ()))))))))

; The depth code of the paren at offset off, or nil when no mark is there.
; Spans arrive in source order, so the cell holding the marks not yet passed
; drops the ones behind each ask and the head is the only candidate.
(def %paint-mark-code
  (fn (_ cell off)
    (let ((ms ((fn (self ms) (if (null? ms) () (if (< (first (first ms)) off) (self (rest ms)) ms)))
               (first cell))))
      (%set-first! cell ms)
      (if (if (null? ms) #t (not (= (first (first ms)) off))) ()
        (%paint-depth-code (first (rest (first ms))) (first (rest (rest (first ms)))))))))

; --- installation ----------------------------------------------------------
;
; Whether there is a terminal is a fact of the process, and so is what the
; colours are: repl/ansi.x recomputes its statics when a state image is
; loaded into a process that has a tty, and the paren palette baked here has
; to be rebuilt on the same beat, with the last paint.
(def %paint-install!
  (fn (_)
    ; Parens cycle through three colours by nesting depth, so open and close
    ; share a colour and the eye can pair them at a glance; a close with
    ; nothing to close is bold red, the palette's colour for a wrong answer;
    ; the pair beside the cursor is drawn inverse on top of its colour.
    (set! %paint-c-depth (list (Ansi yellow) (Ansi magenta) (Ansi cyan)))
    (set! %paint-c-depth-n 3)
    (set! %paint-c-lone (Ansi bold-red))
    (set! %paint-c-focus (Ansi inverse))
    (set! %paint-last-in ())
    (set! %paint-last-out ())
    (set! %paint-last-marks ())
    (set! %paint-last-before ())
    ()))

; --- the class: the cold-call API -----------------------------------------

(def-class Paint ()
  (doc "Syntax colouring for a line of x-lang that may still be half-typed, by the spans of (Syntax x): an atom's class comes from the READER, so numbers, characters, strings and any literal a lang added colour correctly without this class knowing their syntax."
    (note "Lexical at the span level: an unterminated string or an unclosed form colours optimistically rather than failing, which is the normal state of a line being typed.")
    (note "Returns a string rather than writing one, so the caller composes prompt and line and issues a single write; a redraw never tears.")
    (example "(Paint classify \"1/2\")" "'number")
    (see line) (see classify) (see forget!))

  (static
    (method line (self (param s STRING "The text to paint")
                       . (param more LIST "Optional: the marks, as `marks` answers them, then the text that comes before s in the same entry"))
      (doc "The text with ANSI colour codes inserted, and otherwise byte for byte -- the author's own spacing is preserved, because the cursor column is measured against it. With marks from `marks`, each paren is coloured by its nesting depth, a close with nothing to close is bold red, and the pair beside the cursor is inverse as well. With the text that comes before s -- the earlier lines of a multi-line entry, or the part of a line scrolled out of view -- s is painted as its continuation, so a string or a comment left open there colours the start of s. Returns s unchanged when colour is off."
        (returns STRING "A string safe to write to the terminal")
        (sample "(Paint line \"(def x 42)\")" "the same text, with `def` and `42` wrapped in SGR codes")
        (sample "(Paint line \"(f (g))\" (Paint marks \"(f (g))\" 0))" "the outer parens yellow, the inner magenta")
        (sample "(Paint line s () before)" "s painted as the continuation of before: when before leaves a string open, s is green up to the quote that closes it"))
      (if (not (Ansi enabled?)) s
        (let ((ms (if (null? more) () (first more)))
              (before (if (if (null? more) #t (null? (rest more))) () (first (rest more)))))
          (if (if (%pt-same? s %paint-last-in)
                (if (%paint-same-marks? ms %paint-last-marks) (%pt-same? before %paint-last-before) #f)
                #f)
            %paint-last-out
            (let ((from (if (null? before) 0 (%pt-blen before)))
                  (full (if (null? before) s (%pt-append before s)))
                  (n (%pt-blen s))
                  (cell (pair ms ())))
              (let ((out (Syntax ansi full ((Syntax x) spans full from n) from n
                           (fn (_ sp) (%paint-mark-code cell (%pt- (first sp) from))))))
                (set! %paint-last-in s)
                (set! %paint-last-marks ms)
                (set! %paint-last-before before)
                (set! %paint-last-out out)
                out))))))

    (method lexer (self (param l ANY "A Lexer whose rules read every byte: blanks a run rather than a skip, comments tagged rather than dropped")
                        (param colours LIST "Each (TAG . STYLE): STYLE an Ansi style name such as 'green, an escape string used as it is, or a function of the token's text answering either or nil"))
      (doc "A painter for %repl-paint that colours a line by its Lexer tokens. Each token's text is the bytes it read, so the line is drawn byte for byte, each token in the style its tag names; a tag with no entry, or a function answering nil, leaves the token plain. Bytes after the point where the lexer stops are drawn plain. The text before the window is read with it, so a string or comment opened there colours the window's start. Answers the window unchanged when colour is off."
        (returns CALLABLE "A painter: (fn (_ window marks before))")
        (note "A lexer with a skip rule, or an until rule with no tag, drops bytes, and the tokens no longer cover the line: give blanks a run and comments a tag.")
        (note "The painter reads through (Syntax over l colours): the colours table is a grammar's, its classes styles.")
        (sample "(set! %repl-paint (Paint lexer l (list (pair 'comment 'dim) (pair 'str 'green))))" "comments dim and strings green, everything else plain"))
      (Paint %lexer-painter l colours))

    ; The painter's state lives in its closure: the last window it painted and
    ; the codes its style names resolved to, which an image load forgets since
    ; the codes depend on the terminal.
    (method %lexer-painter (self l colours)
      (let ((codes (pair () ())) (last (pair () ())) (g (Syntax over l colours)))
        (set! %image-recache-hooks
          (pair (fn (_) (%set-first! codes ()) (%set-first! last ())) %image-recache-hooks))
        (def code
          (fn (_ style)
            (if (null? style) ""
              (if (str? style) style
              (let ((hit ((fn (self cs) (if (null? cs) () (if (eq? (first (first cs)) style) (first cs) (self (rest cs)))))
                          (first codes))))
                (if (null? hit)
                  (let ((c (guard (_ "") (eval (list (lit Ansi) style)))))
                    (%set-first! codes (pair (pair style c) (first codes)))
                    c)
                  (rest hit)))))))
        (fn (_ window marks before)
          (if (not (Ansi enabled?)) window
            (let ((b (if (null? before) "" before)))
              (if (if (null? (first last)) #f
                    (if (%pt-same? window (first (first last))) (%pt-same? b (rest (first last))) #f))
                (rest last)
                (let ((from (%pt-blen b)) (s (if (null? before) window (%pt-append b window)))
                      (n (%pt-blen window)))
                  (let ((out (Syntax ansi s (g spans s from n) from n
                               (fn (_ sp) (code (first (rest (rest sp))))))))
                    (%set-first! last (pair window b))
                    (%set-rest! last out)
                    out))))))))

    (method marks (self (param s STRING "The text: a line, or a whole multi-line entry") (param at INTEGER "The cursor, as a byte offset"))
      (doc "A mark for every paren in the line, as (offset depth focused): depth is the nesting level from 0, shared by both halves of a pair so they colour alike, and -1 for a close paren with nothing to close; focused is true on the two halves of the pair the cursor is beside, a close just before the cursor first, then an open under it. A cursor outside the line, -1 say, is beside nothing, which is how a settled line keeps its colours and loses its focus. Strings, comments and character literals are stepped over, so #\\( is not an open paren and a paren inside a string is not counted."
        (returns LIST "((offset depth focused) ...) in source order")
        (example "(Paint marks \"(f (g))\" 0)" "((0 0 #t) (3 1 #f) (5 1 #f) (6 0 #t))")
        (example "(Paint marks \"f x)\" 4)" "((3 -1 #t))")
        (example "(null? (Paint marks \"f x\" 3))" "#t"))
      (%paint-depths s at))

    (method classify (self (param text STRING "One atom's bytes"))
      (doc "What an atom is, as one of (Syntax classes): 'keyword for a construct of lib/x/constructs.x, else what READING the bytes on the base answers -- 'number 'string 'char 'constant -- or for a name 'private, 'class or 'name, so the reader and the colour cannot disagree."
        (returns SYMBOL "The atom's class")
        (example "(list (Paint classify \"def\") (Paint classify \"3.14\") (Paint classify \"-\"))" "('keyword 'number 'name)")
        (note "Memoised per distinct atom; forget! drops the memo."))
      (Syntax classify text))

    (method colour (self (param cls SYMBOL "A class from classify"))
      (doc "The SGR code a class is painted with, (Syntax code cls)."
        (returns STRING "An SGR code, empty when colour is off")
        (example "(Str8 =? (Paint colour 'number) (Ansi yellow))" "#t"))
      (Syntax code cls))

    (method labels (self)
      (doc "Every class `classify` and the spans can answer, (Syntax classes)."
        (returns LIST "Class symbols"))
      (Syntax classes))

    (method keywords (self)
      (doc "The construct set, as a Dict used as a set."
        (returns Dict "Construct name -> #t"))
      (Syntax keywords))

    (method enabled? (self)
      (doc "Whether painting will do anything -- false when colour is off, in which case `line` returns its argument unchanged."
        (returns BOOL "True when ANSI colour is on"))
      (Ansi enabled?))

    (method forget! (self)
      (doc "Rebuild the construct set, the memo and the palette. A lang that registers new literal syntax changes what the reader answers, and a state image loaded into a different process changes what the colours are; this is how a session says so."
        (returns NIL "Nothing; the caches are rebuilt"))
      (Syntax forget!)
      (%paint-install!))))

; --- the painter this file installs ------------------------------------------
;
; %repl-paint is the seam a lang sets to colour its own syntax, and this file
; loads with the line editor, after a lang's entry has run.  Installing
; unconditionally would take a lang's painter away and colour its lines as
; x-lang.  repl/ansi.x guards the printer the same way and repl/line.x the
; loop: install over nil, or over the painter this file last installed, and
; over nothing else.
(def %paint-own ())
(def %paint-own-marks ())

; Whatever the seams hold, the two are registered as x's painter and marks
; (x/repl/lang), so a session that switched to another lang and back gets
; them; the identity the install rule tests is the registered closure.
(def %paint-install-hook!
  (fn (_)
    (let ((painter (fn (_ s . more)
                     (Paint line s (if (null? more) () (first more))
                                   (if (if (null? more) #t (null? (rest more))) () (first (rest more))))))
          (marker (fn (_ s at) (%paint-depths s at))))
      (when (or (null? %repl-paint) (%pt-same? %repl-paint %paint-own))
        (set! %repl-paint painter))
      (set! %paint-own painter)
      (when (or (null? %repl-marks) (%pt-same? %repl-marks %paint-own-marks))
        (set! %repl-marks marker))
      (set! %paint-own-marks marker)
      (Lang register! "x" (list (pair (lit %repl-paint) painter)
                                (pair (lit %repl-marks) marker))))))

(%paint-install!)
(%paint-install-hook!)
(set! %image-recache-hooks
  (pair (fn (_) (do (%paint-install!) (%paint-install-hook!))) %image-recache-hooks))

(doc (provide x/repl/paint Paint)
  (note "The spans are (Syntax x)'s: x/tool/syntax reads the line and classes each token, and this file draws them, adding the paren depths and the pair beside the cursor.")
  (note "A lang whose syntax a Lexer reads colours its line with (Paint lexer l colours), each token by its tag, through the same span walk.")
  (note "marks gives every paren its nesting depth; line colours them by depth when handed the result. The editor threads the two together on every redraw.")
  "Paint: ANSI syntax colouring for a REPL line that is still being typed.")
(provide x/repl/paint Paint)
