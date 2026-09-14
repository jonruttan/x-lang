; repl/paint.x -- Paint: colouring a line that is still being typed.
;
; What decides a colour here is the reader, not this file.  An atom's class is
; settled by handing its bytes to the base and taking the type of the value
; that comes back, which is the verdict the evaluator reaches on the same
; bytes.  There is no second set of rules here for what counts as a number, so
; 3.14, 1/2, 0xff and a literal syntax a lang adds all classify without this
; file knowing about them.  The cost is one call per distinct atom; answers are
; memoised, and a line being typed asks about few new atoms.
;
; What is still scanned here is where tokens begin and end.  The base's reader
; is recursive: (tok read) on `(def x 42)` consumes the whole form and answers
; with a list, leaving (buf tok) empty, so it yields values and never spans.
; The per-type analyser scoring that does know spans lives inside x_token_read
; and has no primitive over it.  A painter must keep the author's own bytes,
; spacing included, or the cursor column stops matching the buffer, so it needs
; spans and splits the line itself into whitespace, parens, comments, strings
; and atoms.  That is a smaller surface than classification, and it is the
; piece an engine primitive could take over later (see the provide note).
;
; The hot path does not dispatch, the rule reader/analyser.x and type/buf.x
; state: class doors allocate, and a redraw runs on every keystroke.  A class
; door costs 0.3-1.0ms here, which dwarfs the byte scanning between them.  So
; the scan is %-private functions over cached prims, the palette is built once
; rather than per render, and the memo is reached through instance-bound
; method-refs.  A 70-byte line renders in 19ms, and a redraw whose text has not
; changed in 0.24ms.  The Paint class is the cold-call API over them, as
; Analyser is over its builders.
;
; The palette is repl/ansi.x's, so NO_COLOR, TERM=dumb and --no-color reach
; this for free, and a colourless terminal short-circuits the whole walk.

(import x/type/class)
(import x/type/str)
(import x/type/dict)
(import x/type/list)
(import x/repl/ansi)
(import x/sys/file)

; --- cached prims (the scan runs per byte; none of these may be a door) ---
(def %pt-bref   (prim-ref (lit str)  (lit byte-ref)))
(def %pt-blen   (prim-ref (lit str)  (lit byte-len)))
(def %pt-bsub   (prim-ref (lit str)  (lit byte-sub)))
(def %pt-append (prim-ref (lit str)  (lit append)))
(def %pt-cint   (prim-ref (lit char) (lit ->int)))
(def %pt+       (prim-ref (lit int)  (lit +)))
(def %pt-       (prim-ref (lit int)  (lit -)))
(def %pt-mod    (prim-ref (lit int)  (lit %)))
(def %pt-read-str (prim-ref (lit tok) (lit read-str)))
(def %pt-same?  (prim-ref (lit obj)  (lit same?)))

; --- state, all of it rebuilt by %paint-install! -------------------------
(def %paint-kw ())        ; Dict: construct name -> #t
(def %paint-memo ())      ; Dict: atom text -> class symbol
(def %paint-memo-get ())  ; instance-bound (method-ref memo get-or)
(def %paint-memo-set ())  ; instance-bound (method-ref memo set!)
(def %paint-pal ())       ; the nine codes, in %paint-classes order
(def %paint-rst "")       ; the reset code
(def %paint-c-comment "") ; hoisted: the two codes the scan needs without a classify
(def %paint-c-string "")
(def %paint-c-depth ())   ; hoisted: the codes parens cycle through by nesting depth
(def %paint-c-depth-n 0)  ; and how many there are, so the cycle costs a mod and no door
(def %paint-c-lone "")    ; and the code for a close paren with nothing to close
(def %paint-c-focus "")   ; and the code added to the pair the cursor is beside
; The last line painted, and what it painted to.  A redraw repaints only
; because the TEXT changed: moving the cursor, walking history onto a line
; already seen, and a resize all ask for the same bytes again, and holding an
; arrow key down asks thirty times a second.  Identity, not equality -- the
; buffer builds a new string whenever it edits and keeps the old one
; whenever it does not, which is exactly the question being asked.
(def %paint-last-in ())
(def %paint-last-out ())
(def %paint-last-marks ())

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

(def %paint-classes
  (list (lit symbol) (lit construct) (lit number) (lit string) (lit char)
        (lit bool) (lit private) (lit class) (lit comment)))

; --- the construct vocabulary --------------------------------------------
; The same list the formatter, the linter, the coverage tool and the
; documentation renderer read, so a construct added there colours here
; without this file being touched.
;
; An unreadable file yields an empty set: losing a colour is not worth
; refusing to start a session over, and this runs from %paint-install!, which
; the image-recache hook calls.  The cause is reported rather than dropped,
; because an empty vocabulary looks the same as a session in which nothing
; happens to be a construct -- a line with no colour on it, either way.  One
; line to stderr, naming what could not be read.
(def %paint-load-keywords
  (fn (_)
    (guard (e (do (%stderr "x/repl/paint: construct vocabulary unreadable ("
                           e ") -- constructs will not colour\n")
                  (Dict make)))
      (let ((path (%module-resolve-file "x/constructs.x"))
            (d (Dict make)))
        (List for-each
          (fn (_ entry) (d set! (Str8 str (first entry)) #t))
          (first (%pt-read-str (%base) (File read-all path))))
        d))))

; --- classification, on the base ------------------------------------------

; Which kind of NAME an atom is, by the conventions the library itself
; follows: a leading % marks a private, a leading capital marks a class.
(def %paint-name-class
  (fn (_ text)
    (let ((b0 (if (= 0 (%pt-blen text)) 0 (%pt-cint (%pt-bref text 0)))))
      (match
        ((= b0 37) (lit private))
        ((and (>= b0 65) (<= b0 90)) (lit class))
        (#t (lit symbol))))))

; Ask the reader what an atom is.  The trailing space is the terminator:
; without it a final token is dropped as unfinished (#161), and every atom
; reaching here is by definition the tail of something still being typed.
; Guarded, because half a literal is not a reader error here -- it is
; Tuesday, and it colours as a plain name until it finishes.
(def %paint-ask
  (fn (_ text)
    (if ((first %paint-kw) get-or #f text) (lit construct)
      (let ((v (guard (_ (lit %unreadable))
                 (first (%pt-read-str (%base) (%pt-append text " "))))))
        (match
          ((eq? v (lit %unreadable)) (lit symbol))
          ((number? v) (lit number))
          ((str? v)    (lit string))
          ((char? v)   (lit char))
          ((eq? v #t)  (lit bool))
          ((eq? v #f)  (lit bool))
          ((null? v)   (lit bool))
          (#t (%paint-name-class text)))))))

; The memo holds both answers.  An entry is (class . code): the class is what
; `classify` is asked for and what a spec can check without a terminal, the
; code is what the scan actually writes.  Keeping only the class meant the
; scan walked the palette list per atom to turn one into the other -- nine
; eq? tests a token, and closure calls are the unit of cost here, so that
; walk alone was a fifth of a render.
(def %paint-entry
  (fn (_ text)
    (let ((hit (%paint-memo-get () text)))
      (if (null? hit)
        (let ((e (let ((cls (%paint-ask text))) (pair cls (%paint-code cls)))))
          (%paint-memo-set text e)
          e)
        hit))))

(def %paint-classify (fn (_ text) (first (%paint-entry text))))

; The code for a class: a walk down two lists in step.  Nine eq? tests at
; worst, no allocation, no dispatch.
(def %paint-code
  (fn (_ cls)
    (let ((go (fn (self names codes)
                (match
                  ((null? names) "")
                  ((eq? cls (first names)) (first codes))
                  (#t (self (rest names) (rest codes)))))))
      (go %paint-classes %paint-pal))))

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

; --- the span scan ---------------------------------------------------------
;
; The two loops below run per byte, so their comparisons are spelled in
; place rather than behind a predicate: a helper per test reads better and
; costs a closure call for every character of every line.

(def %paint-to-eol
  (fn (self s i n)
    (if (>= i n) i (if (= 10 (%pt-cint (%pt-bref s i))) i (self s (%pt+ i 1) n)))))

; To the closing quote, honouring backslash escapes.  An unterminated string
; runs to the end of the line rather than erroring: optimistic colouring is
; the only kind a half-typed line can have.
(def %paint-str-end
  (fn (self s i n)
    (if (>= i n) n
      (let ((b (%pt-cint (%pt-bref s i))))
        (if (= 92 b) (self s (%pt+ i 2) n)
          (if (= 34 b) (%pt+ i 1) (self s (%pt+ i 1) n)))))))

; To the end of a run of bytes that carry no colour: parens and whitespace.
; Emitting one segment per byte instead cost a substring and two list cells
; each -- 87 segments for a 70-byte line, and the join at the end walks all
; of them.
(def %paint-plain-end
  (fn (self s i n)
    (if (>= i n) i
      (let ((b (%pt-cint (%pt-bref s i))))
        (if (if (<= b 32) #t (if (= b 40) #t (= b 41)))
          (self s (%pt+ i 1) n) i)))))

; To the end of an atom: the first whitespace, paren or semicolon.  This is
; where a line spends most of its bytes.
(def %paint-atom-end
  (fn (self s i n)
    (if (>= i n) i
      (let ((b (%pt-cint (%pt-bref s i))))
        (if (if (<= b 32) #t (if (= b 40) #t (if (= b 41) #t (= b 59))))
          i (self s (%pt+ i 1) n))))))

; --- bracket depths -----------------------------------------------------------
;
; A mark for every paren in the line: (offset depth focused).  Depth is the
; nesting level, 0 at the top, and open and close share it, so a pair colours
; alike; a close paren with nothing to close is -1.  `focused` is true on the
; two halves of the pair the cursor is beside: a close just before the cursor
; is preferred, then an open under it, then the other two.  One forward walk
; that steps over strings, comments and character literals the same way the
; scan does; `open` is the stack of (offset . depth) for parens not yet
; closed.  Marks come back in source order.
(def %paint-depths
  (fn (_ s at)
    (let ((n (%pt-blen s)))
      ; The paren the cursor is beside, if any, by offset.
      (let ((before (if (> at 0) (%pt-cint (%pt-bref s (%pt- at 1))) 0))
            (here (if (< at n) (%pt-cint (%pt-bref s at)) 0)))
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
            (let ((go (fn (self i open depth acc)
                        (if (>= i n) (%reverse acc)
                          (let ((b (%pt-cint (%pt-bref s i))))
                            (match
                              ((= b 59) (self (%paint-to-eol s i n) open depth acc))
                              ((= b 34) (self (%paint-str-end s (%pt+ i 1) n) open depth acc))
                              ((and (= b 35) (and (< (%pt+ i 1) n) (= 34 (%pt-cint (%pt-bref s (%pt+ i 1))))))
                                (self (%paint-str-end s (%pt+ i 2) n) open depth acc))
                              ((and (= b 35) (and (< (%pt+ i 1) n) (= 92 (%pt-cint (%pt-bref s (%pt+ i 1))))))
                                (self (%paint-atom-end s (if (> (%pt+ i 3) n) n (%pt+ i 3)) n) open depth acc))
                              ((= b 40)
                                (self (%pt+ i 1) (pair (pair i depth) open) (%pt+ depth 1)
                                      (pair (list i depth #f) acc)))
                              ((= b 41)
                                (if (null? open)
                                  (self (%pt+ i 1) () 0 (pair (list i -1 (= i target)) acc))
                                  (let ((o (first (first open))) (d (rest (first open))))
                                    (let ((hit (if (= i target) #t (= o target))))
                                      (self (%pt+ i 1) (rest open) d
                                            (pair (list i d hit)
                                                  (if hit (flag acc o) acc)))))))
                              (#t (self (%pt+ i 1) open depth acc))))))))
              (go 0 () 0 ()))))))))

; The marks not yet passed: those at or beyond i.  Marks arrive in source
; order and the scan moves forward, so the ones behind it are dropped as it
; goes and the head of what remains is the only candidate for a cut, which
; keeps the cost per run at the head rather than a walk of the whole list.
(def %paint-marks-from
  (fn (self marks i)
    (if (null? marks) ()
      (if (< (first (first marks)) i) (self (rest marks) i) marks))))

; One coloured token onto the reversed segment list.  An empty code -- a
; class with no colour, or colour switched off -- pushes bare text, so
; nothing emits a stray reset.
(def %paint-seg
  (fn (_ segs code text)
    (if (= 0 (%pt-blen code)) (pair text segs)
      (pair %paint-rst (pair text (pair code segs))))))

(def %paint-scan
  (fn (self s i n segs marks)
    (if (>= i n) segs
      (let ((b (%pt-cint (%pt-bref s i))))
        (match
          ; a comment, to the end of the line
          ((= b 59)
            (let ((e (%paint-to-eol s i n)))
              (self s e n (%paint-seg segs %paint-c-comment
                                      (%pt-bsub s i (%pt- e i)))
                    marks)))
          ; a string, and the #"..." interpolating form: one colour, because
          ; the holes are part of the literal and colouring them apart would
          ; suggest they escape it, which they do not
          ((= b 34)
            (let ((e (%paint-str-end s (%pt+ i 1) n)))
              (self s e n (%paint-seg segs %paint-c-string
                                      (%pt-bsub s i (%pt- e i)))
                    marks)))
          ((and (= b 35) (and (< (%pt+ i 1) n) (= 34 (%pt-cint (%pt-bref s (%pt+ i 1))))))
            (let ((e (%paint-str-end s (%pt+ i 2) n)))
              (self s e n (%paint-seg segs %paint-c-string
                                      (%pt-bsub s i (%pt- e i)))
                    marks)))
          ; a character literal: #\ and the glyph after it, plus any name
          ; behind that, so #\( does not read as an open paren
          ((and (= b 35) (and (< (%pt+ i 1) n) (= 92 (%pt-cint (%pt-bref s (%pt+ i 1))))))
            (let ((e (%paint-atom-end s (if (> (%pt+ i 3) n) n (%pt+ i 3)) n)))
              (self s e n (%paint-seg segs (%paint-code (lit char))
                                      (%pt-bsub s i (%pt- e i)))
                    marks)))
          ; parens and whitespace carry no colour of their own, and go out as
          ; one run rather than one segment per byte -- unless a mark falls
          ; inside the run, in which case the run is cut there, the marked
          ; paren goes out in its depth's colour, and the scan resumes after
          ; it
          ((if (<= b 32) #t (if (= b 40) #t (= b 41)))
            (let ((e (%paint-plain-end s (%pt+ i 1) n))
                  (ms (%paint-marks-from marks i)))
              (if (if (null? ms) #t (>= (first (first ms)) e))
                (self s e n (pair (%pt-bsub s i (%pt- e i)) segs) ms)
                (let ((m (first ms)))
                  (let ((c (first m)))
                    (self s (%pt+ c 1) n
                      (%paint-seg (if (> c i) (pair (%pt-bsub s i (%pt- c i)) segs) segs)
                                  (%paint-depth-code (first (rest m)) (first (rest (rest m))))
                                  (%pt-bsub s c 1))
                      (rest ms)))))))
          ; everything else is an atom: its bytes go to the reader, and the
          ; answer picks the colour
          (#t
            (let ((e (%paint-atom-end s (%pt+ i 1) n)))
              (let ((text (%pt-bsub s i (%pt- e i))))
                (self s e n (%paint-seg segs (rest (%paint-entry text)) text)
                      marks)))))))))

; --- installation ----------------------------------------------------------
;
; Whether there is a terminal is a fact of the process, and so is what the
; colours are: repl/ansi.x recomputes its statics when a state image is
; loaded into a process that has a tty, and the palette baked here has to be
; rebuilt on the same beat.  The memo goes with it -- a lang that registers
; new literal syntax changes what the reader answers -- so one function
; rebuilds the lot and everything that can invalidate it calls this.
(def %paint-install!
  (fn (_)
    (set! %paint-kw (list (%paint-load-keywords)))
    (set! %paint-memo (Dict make))
    (set! %paint-memo-get (method-ref %paint-memo get-or))
    (set! %paint-memo-set (method-ref %paint-memo set!))
    (set! %paint-rst (Ansi reset))
    (set! %paint-pal
      (list (Ansi blue)                             ; symbol
            (%pt-append (Ansi bold) (Ansi magenta)) ; construct
            (Ansi yellow)                           ; number
            (Ansi green)                            ; string
            (Ansi magenta)                          ; char
            (Ansi bold-red)                         ; bool
            (Ansi dim)                              ; private
            (Ansi bold-cyan)                        ; class
            (Ansi dim)))                            ; comment
    (set! %paint-c-comment (%paint-code (lit comment)))
    (set! %paint-c-string  (%paint-code (lit string)))
    ; Parens cycle through three colours by nesting depth, the way editors
    ; colour bracket pairs, so open and close share a colour and the eye can
    ; pair them at a glance; a close with nothing to close is bold red, the
    ; palette's colour for a wrong answer; the pair beside the cursor is
    ; drawn inverse on top of its colour.
    (set! %paint-c-depth (list (Ansi yellow) (Ansi magenta) (Ansi cyan)))
    (set! %paint-c-depth-n 3)
    (set! %paint-c-lone (Ansi bold-red))
    (set! %paint-c-focus (%sgr "7"))
    (set! %paint-last-in ())
    (set! %paint-last-out ())
    (set! %paint-last-marks ())
    ()))

; --- the class: the cold-call API -----------------------------------------

(def-class Paint ()
  (doc "Syntax colouring for a line of x-lang that may still be half-typed. An atom's class comes from the READER -- the base is asked what the bytes read as -- so numbers, characters, strings and any literal a lang added all colour correctly without this class knowing their syntax."
    (note "Lexical at the span level: an unterminated string or an unclosed form colours optimistically rather than failing, which is the normal state of a line being typed.")
    (note "Returns a string rather than writing one, so the caller composes prompt and line and issues a single write; a redraw never tears.")
    (note "The scan itself is %-private over cached prims -- the hot-path rule reader/analyser.x states -- and this class is the cold-call surface over it.")
    (example "(Paint classify \"1/2\")" "'number")
    (see line) (see classify) (see forget!))

  (static
    (method line (self (param s STRING "The line as typed so far")
                       . (param marks LIST "Optional: (offset . kind) pairs to mark, from `focus`"))
      (doc "The line with ANSI colour codes inserted, and otherwise byte for byte -- the author's own spacing is preserved, because the cursor column is measured against it. With marks from `marks`, each paren is coloured by its nesting depth, a close with nothing to close is bold red, and the pair beside the cursor is inverse as well. Returns s unchanged when colour is off."
        (returns STRING "A string safe to write to the terminal")
        (sample "(Paint line \"(def x 42)\")" "the same text, with `def` and `42` wrapped in SGR codes")
        (sample "(Paint line \"(f (g))\" (Paint marks \"(f (g))\" 0))" "the outer parens yellow, the inner magenta"))
      (if (not (Ansi enabled?)) s
        (let ((ms (if (null? marks) () (first marks))))
          (if (if (%pt-same? s %paint-last-in) (%paint-same-marks? ms %paint-last-marks) #f)
            %paint-last-out
            (let ((out (Str8 join "" (List reverse (%paint-scan s 0 (%pt-blen s) () ms)))))
              (set! %paint-last-in s)
              (set! %paint-last-marks ms)
              (set! %paint-last-out out)
              out)))))

    (method marks (self (param s STRING "The line") (param at INT "The cursor, as a byte offset"))
      (doc "A mark for every paren in the line, as (offset depth focused): depth is the nesting level from 0, shared by both halves of a pair so they colour alike, and -1 for a close paren with nothing to close; focused is true on the two halves of the pair the cursor is beside, a close just before the cursor first, then an open under it. Strings, comments and character literals are stepped over, so #\\( is not an open paren and a paren inside a string is not counted."
        (returns LIST "((offset depth focused) ...) in source order")
        (example "(Paint marks \"(f (g))\" 0)" "((0 0 #t) (3 1 #f) (5 1 #f) (6 0 #t))")
        (example "(Paint marks \"f x)\" 4)" "((3 -1 #t))")
        (example "(null? (Paint marks \"f x\" 3))" "#t"))
      (%paint-depths s at))

    (method classify (self (param text STRING "One atom's bytes"))
      (doc "What an atom is, as a symbol: 'construct 'number 'string 'char 'bool 'private 'class or 'symbol. Constructs come from lib/x/constructs.x; everything else is decided by READING the bytes on the base and taking the type of the value, so the reader and the colour cannot disagree."
        (returns SYMBOL "The atom's class")
        (example "(list (Paint classify \"def\") (Paint classify \"3.14\") (Paint classify \"-\"))" "('construct 'number 'symbol)")
        (note "Memoised per distinct atom; forget! drops the memo."))
      (%paint-classify text))

    (method colour (self (param cls SYMBOL "A class from classify"))
      (doc "The SGR code a class is painted with -- the LSP semantic token mapping repl/ansi.x already uses for printed values, so a name looks the same being typed as it does coming back."
        (returns STRING "An SGR code, empty when colour is off")
        (example "(Str8 =? (Paint colour 'number) (Ansi yellow))" "#t"))
      (%paint-code cls))

    (method classes (self)
      (doc "Every class `classify` can answer, in palette order."
        (returns LIST "Class symbols"))
      %paint-classes)

    (method keywords (self)
      (doc "The construct set, as a Dict used as a set."
        (returns Dict "Construct name -> #t"))
      (first %paint-kw))

    (method enabled? (self)
      (doc "Whether painting will do anything -- false when colour is off, in which case `line` returns its argument unchanged."
        (returns BOOL "True when ANSI colour is on"))
      (Ansi enabled?))

    (method forget! (self)
      (doc "Rebuild the construct set, the memo and the palette. A lang that registers new literal syntax changes what the reader answers, and a state image loaded into a different process changes what the colours are; this is how a session says so."
        (returns NIL "Nothing; the caches are rebuilt"))
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

(def %paint-install-hook!
  (fn (_)
    (when (or (null? %repl-paint) (%pt-same? %repl-paint %paint-own))
      (set! %repl-paint (fn (_ s . marks) (Paint line s (if (null? marks) () (first marks)))))
      (set! %paint-own %repl-paint))
    (when (or (null? %repl-marks) (%pt-same? %repl-marks %paint-own-marks))
      (set! %repl-marks (fn (_ s at) (%paint-depths s at)))
      (set! %paint-own-marks %repl-marks))))

(%paint-install!)
(%paint-install-hook!)
(set! %image-recache-hooks
  (pair (fn (_) (do (%paint-install!) (%paint-install-hook!))) %image-recache-hooks))

(doc (provide x/repl/paint Paint)
  (note "An atom's class comes from the base: the bytes are read and the value's type decides, so a colour cannot disagree with the evaluator.")
  (note "Token SPANS are scanned here because the base offers none -- its reader is recursive and yields values. A primitive exposing the tokenizer's per-type scoring (span plus winning type) would move this last scanned piece onto the base too.")
  (note "The scan is %-private over cached prims and the palette is built once, not per render: class dispatch on a per-keystroke path costs more than the scanning between the doors.")
  (note "marks gives every paren its nesting depth with the scan's own rules for strings, comments and character literals; line colours them by depth when handed the result. The editor threads the two together on every redraw.")
  "Paint: ANSI syntax colouring for a REPL line that is still being typed.")
