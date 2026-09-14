; repl/paint.x -- Paint: colouring a line that is still being typed.
;
; WHAT DECIDES A COLOUR HERE IS THE READER, not this file.  An atom's class
; is settled by handing its bytes to the base and taking the type of the
; value that comes back -- the same verdict the evaluator will reach on the
; same bytes.  The first draft had its own rules for what counts as a number
; and they were wrong in the ordinary way hand-written rules are wrong: 3.14
; needed a clause, then 1/2, then 0xff, and a lang adding a literal syntax
; would have needed another.  Asking the reader costs one call per DISTINCT
; atom -- they are memoised, and a line being typed re-asks about almost
; nothing -- and it cannot drift, because there is no second opinion to
; drift from.
;
; WHAT IS STILL SCANNED HERE IS WHERE TOKENS BEGIN AND END, and that is not
; a preference.  The base's reader is recursive: (tok read) on `(def x 42)`
; consumes the whole form and answers with a list, leaving (buf tok) empty,
; so it yields VALUES and never spans.  The per-type analyser scoring that
; does know spans lives inside x_token_read and has no primitive.  A painter
; must keep the author's own bytes, spacing included, or the cursor column
; stops matching the buffer -- so it needs spans, and splits the line itself
; into whitespace, parens, comments, strings and atoms.  That is a far
; smaller surface than classification, and it is the piece an engine
; primitive could take over later (see the provide note).
;
; THE HOT PATH DOES NOT DISPATCH, which is the rule this tree already states
; in reader/analyser.x and type/buf.x: class doors allocate, and a redraw runs
; on every keystroke.  It is not a small effect.  Measured on this machine, on
; a 70-byte line: x/tool/highlight -- which classifies the same grammar and is
; the obvious thing to have reused -- renders in 30.6ms, against 2.2ms for a
; bare walk of the same bytes, because it builds HTML and scans keywords
; through class doors.  A first draft here, written in ordinary style with the
; palette read off the Ansi statics and the segments pushed through static
; methods, managed 80ms; reaching through the class once per atom instead of
; once per render still cost 27ms.  One class door is 0.3-1.0ms, which dwarfs
; the byte scanning between them.  So the scan is %-private functions over
; cached prims, the palette is built once rather than per render, and the memo
; is reached through instance-bound method-refs: 19ms, and 0.24ms for a redraw
; whose text has not changed.  The Paint class is the cold-call API over them,
; the way Analyser is over its builders.
;
; THE PALETTE IS repl/ansi.x's, so NO_COLOR, TERM=dumb and --no-color reach
; this for free -- and a colourless terminal short-circuits the whole walk.

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
; The last line painted, and what it painted to.  A redraw repaints only
; because the TEXT changed: moving the cursor, walking history onto a line
; already seen, and a resize all ask for the same bytes again, and holding an
; arrow key down asks thirty times a second.  Identity, not equality -- the
; buffer builds a new string whenever it edits and keeps the old one
; whenever it does not, which is exactly the question being asked.
(def %paint-last-in ())
(def %paint-last-out ())

; The classes, in the order %paint-pal holds their codes.  A symbol list
; rather than a Dict: the lookup is nine eq? tests on the hot path, which
; costs less than one hash through a class door.
(def %paint-classes
  (list (lit symbol) (lit construct) (lit number) (lit string) (lit char)
        (lit bool) (lit private) (lit class) (lit comment)))

; --- the construct vocabulary --------------------------------------------
; The same list the formatter, the linter, the coverage tool and the
; documentation renderer read, so a construct added there colours here
; without this file being touched.  An unreadable file yields an empty set:
; that costs colour on constructs and nothing else.
(def %paint-load-keywords
  (fn (_)
    (guard (_ (Dict make))
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

; THE MEMO HOLDS BOTH ANSWERS.  An entry is (class . code): the class is what
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
; EACH -- 87 segments for a 70-byte line, and the join at the end walks all
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

; One coloured token onto the reversed segment list.  An empty code -- a
; class with no colour, or colour switched off -- pushes bare text, so
; nothing emits a stray reset.
(def %paint-seg
  (fn (_ segs code text)
    (if (= 0 (%pt-blen code)) (pair text segs)
      (pair %paint-rst (pair text (pair code segs))))))

(def %paint-scan
  (fn (self s i n segs)
    (if (>= i n) segs
      (let ((b (%pt-cint (%pt-bref s i))))
        (match
          ; a comment, to the end of the line
          ((= b 59)
            (let ((e (%paint-to-eol s i n)))
              (self s e n (%paint-seg segs %paint-c-comment
                                      (%pt-bsub s i (%pt- e i))))))
          ; a string, and the #"..." interpolating form: ONE colour, because
          ; the holes are part of the literal and colouring them apart would
          ; suggest they escape it, which they do not
          ((= b 34)
            (let ((e (%paint-str-end s (%pt+ i 1) n)))
              (self s e n (%paint-seg segs %paint-c-string
                                      (%pt-bsub s i (%pt- e i))))))
          ((and (= b 35) (and (< (%pt+ i 1) n) (= 34 (%pt-cint (%pt-bref s (%pt+ i 1))))))
            (let ((e (%paint-str-end s (%pt+ i 2) n)))
              (self s e n (%paint-seg segs %paint-c-string
                                      (%pt-bsub s i (%pt- e i))))))
          ; parens and whitespace carry no colour of their own, and go out as
          ; one run rather than one segment per byte
          ((if (<= b 32) #t (if (= b 40) #t (= b 41)))
            (let ((e (%paint-plain-end s (%pt+ i 1) n)))
              (self s e n (pair (%pt-bsub s i (%pt- e i)) segs))))
          ; everything else is an atom: its bytes go to the reader, and the
          ; answer picks the colour
          (#t
            (let ((e (%paint-atom-end s (%pt+ i 1) n)))
              (let ((text (%pt-bsub s i (%pt- e i))))
                (self s e n (%paint-seg segs (rest (%paint-entry text)) text))))))))))

; --- installation ----------------------------------------------------------
;
; WHETHER THERE IS A TERMINAL IS A FACT OF THE PROCESS, and so is what the
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
    (set! %paint-last-in ())
    (set! %paint-last-out ())
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
    (method line (self (param s STRING "The line as typed so far"))
      (doc "The line with ANSI colour codes inserted, and otherwise byte for byte -- the author's own spacing is preserved, because the cursor column is measured against it. Returns s unchanged when colour is off."
        (returns STRING "A string safe to write to the terminal")
        (sample "(Paint line \"(def x 42)\")" "the same text, with `def` and `42` wrapped in SGR codes"))
      (if (not (Ansi enabled?)) s
        (if (%pt-same? s %paint-last-in) %paint-last-out
          (let ((out (Str8 join "" (List reverse (%paint-scan s 0 (%pt-blen s) ())))))
            (set! %paint-last-in s)
            (set! %paint-last-out out)
            out))))

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
; AND IT IS ONLY OURS TO MOVE WHEN NOBODY ELSE HAS MOVED IT.  %repl-paint is
; the seam a lang sets to colour its OWN syntax, and this file loads with the
; line editor, which is after a lang's entry has run.  Installing
; unconditionally would take a lang's painter away and colour its lines as
; x-lang -- the same mistake repl/ansi.x guards against for the printer and
; repl/line.x for the loop, and guarded here the same way: install over nil,
; or over the painter this file last installed, and over nothing else.
(def %paint-own ())

(def %paint-install-hook!
  (fn (_)
    (when (or (null? %repl-paint) (%pt-same? %repl-paint %paint-own))
      (set! %repl-paint (fn (_ s) (Paint line s)))
      (set! %paint-own %repl-paint))))

(%paint-install!)
(%paint-install-hook!)
(set! %image-recache-hooks
  (pair (fn (_) (do (%paint-install!) (%paint-install-hook!))) %image-recache-hooks))

(doc (provide x/repl/paint Paint)
  (note "An atom's class comes from the base: the bytes are read and the value's type decides, so a colour cannot disagree with the evaluator.")
  (note "Token SPANS are scanned here because the base offers none -- its reader is recursive and yields values. A primitive exposing the tokenizer's per-type scoring (span plus winning type) would move this last scanned piece onto the base too.")
  (note "The scan is %-private over cached prims and the palette is built once, not per render: class dispatch on a per-keystroke path costs more than the scanning between the doors.")
  "Paint: ANSI syntax colouring for a REPL line that is still being typed.")
