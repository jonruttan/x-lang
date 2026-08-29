; reader/indent.x -- Indent: the stack discipline under indentation-sensitive
; grouping (#520).
;
; Two surfaces in this ecosystem grouped tokens by indent level, independently,
; with no shared module: apps/logo/indent.x (an explicit stack over a buffered
; token list) and x-sweet's sweet/indent.x + sweet/ws.x (the same algorithm as
; mutual recursion over a base column, on the live stream). A third is coming.
; The drivers differ and should; the arithmetic underneath has no Logo and no
; sweet in it, and the proof is that two independent implementations reached the
; same shape.
;
; ## WHAT WAS ACTUALLY DIFFERENT
;
; The issue named tabs and blank lines. Diffing the two against green suites
; found THREE disagreements, and the third was a bug nobody could see:
;
;   1. TAB WIDTH. Logo counted a tab as one column (types.x %count-indent steps
;      i by 1 for space and tab alike); sweet counted it as eight.
;
;   2. TAB SEMANTICS. Sweet added 8 to the column. SRFI-110 -- and CPython's
;      tokenizer, and every editor -- advance to the NEXT MULTIPLE of 8. Those
;      differ the moment a tab is not the first thing on the line: for
;      "<space><tab>x", +8 says column 9 and a tab stop says column 8. x-sweet's
;      suite has no tab case, so nothing caught it. `tab-stop` below is the
;      corrected reading, and it subsumes Logo's answer rather than overruling
;      it: advancing to the next multiple of ONE is exactly adding one.
;
;   3. A DEDENT THAT MATCHES NO OPEN LEVEL. Logo pops every deeper level and
;      then OPENS a new one at the incoming column. Sweet's recursion returns
;      through every enclosing level, unwinding further than the nearest match.
;      Python raises IndentationError. All three are defensible and none was
;      written down, which is the actual complaint in #520.
;
; So: mechanism here, policy in the constructor. `tab-stop` and `mismatch` are
; the two questions, and a consumer that does not state them gets SRFI-110's
; answers, because that is the only one of the three with a specification behind
; it.
;
; ## WHAT IS NOT HERE
;
; Blank lines and comment-only lines. Both existing consumers make them
; transparent, and both do it WITHOUT this module ever hearing about them --
; Logo's LOGO-INDENT analyser never forms a token for a line with no word on it,
; and sweet's reader loop keeps reading when a line ends with nothing
; accumulated. A line that produces no column never reaches `feed`, so
; transparency is the caller's silence rather than a flag here. That is the
; right seam: what counts as an empty line is a fact about a surface's comment
; syntax, and apps/logo/entry.x is right that such things "live HERE, in the
; dialect, never in shared machinery."
;
; ## TWO LAYERS, AND CONSUMERS TAKE WHAT THEY NEED
;
; MEASUREMENT (advance/measure) answers "what column is this?". THE STACK
; (make/feed/close-all) answers "what opened and what closed?". Logo takes both.
; A recursive consumer like sweet takes measurement and `classify` and keeps its
; own control flow -- the rules stop being its business without its shape having
; to change.
;
; ## ALLOCATION
;
; `advance` runs per character inside a tokenizer callback, where a collection
; mid-token is a hazard and class dispatch allocates. So the logic lives in
; %-private functions registered in the catalog under ns `indent`; reader-hot
; callers fetch the raw ref once and call it directly, the discipline
; reader/analyser.x uses for its terminators. The Indent methods are the
; cold-call API over the same functions.
(import x/type/class)
(import x/type/list)
(import x/type/err)

; Raw integer division and modulo, not (Num quotient ...): the tab-stop
; arithmetic is on the per-character path and immediates allocate nothing.
(def %ind-div (prim-ref (lit int) (lit /)))
; measure runs inside Logo's LOGO-INDENT read handler, which is a reader
; callback like advance's caller: the cast is fetched, never dispatched.
(def %ind-char->int (prim-ref (lit char) (lit ->int)))

; --- Measurement -------------------------------------------------------------

; (%indent-advance col chr tab-stop) -- the column after one character.
;
; A space is one column. A tab advances to the next multiple of tab-stop, which
; is 8 for SRFI-110 and for Python, and 1 for a surface that wants a tab to be
; one column -- there is no separate mode, because the next multiple of 1 after
; n is n+1. Anything else is not indentation and leaves the column alone; the
; caller decides that the run has ended.
;
; Nested if, never cond: operatives expand per evaluation and this runs per
; character of every leading whitespace run (#343).
(def %indent-advance
  (fn (_ col chr tab-stop)
    (if (= chr #\space)
      (+ col 1)
      (if (= chr #\tab)
        (* tab-stop (+ 1 (%ind-div col tab-stop)))
        col))))

; (%indent-scan s start tab-stop) -- (COLUMN . END-INDEX) for the run of spaces
; and tabs beginning at index `start`, for a consumer holding a whole line
; rather than driving a character at a time.
;
; BOTH FACTS FROM ONE WALK, and that is not tidiness. A column and an index are
; the same number only while a tab is one column; the moment tab-stop is 8 they
; diverge, and a consumer that computed the index by adding the column to
; `start` -- which is exactly what Logo did -- would slice its line in the wrong
; place. Handing back both is what makes the tab stop safe to change.
(def %indent-scan
  (fn (_ s start tab-stop)
    (def len (Str8 length s))
    (def %go
      (fn (self i col)
        (if (>= i len)
          (pair col i)
          (let ((c (%ind-char->int (Str8 ref i s))))
            (if (if (= c #\space) #t (= c #\tab))
              (self (+ i 1) (%indent-advance col c tab-stop))
              (pair col i))))))
    (%go start 0)))

; The column alone, for a consumer with no slicing to do.
(def %indent-measure
  (fn (_ s start tab-stop)
    (first (%indent-scan s start tab-stop))))

; --- The three rules ---------------------------------------------------------

; (%indent-classify col ref) -- deeper, same or shallower. The whole of what an
; indentation-sensitive surface asks about a line, and the reason a consumer
; that keeps its own control flow still stops owning the rules.
(def %indent-classify
  (fn (_ col ref)
    (if (> col ref)
      (lit deeper)
      (if (= col ref) (lit same) (lit shallower)))))

(prim-reg! (lit indent) (lit advance)  %indent-advance)
(prim-reg! (lit indent) (lit scan)     %indent-scan)
(prim-reg! (lit indent) (lit measure)  %indent-measure)
(prim-reg! (lit indent) (lit classify) %indent-classify)

; --- The stack ---------------------------------------------------------------

; The stack is a list of open columns, deepest first, and it always ends in 0:
; column 0 is open from the first character and closes only at end of input.
; feed's contract is one line, and every consumer below depends on it:
;
;   FEED RETURNS ZERO OR MORE `close` EVENTS FOLLOWED BY EXACTLY ONE `open` OR
;   `same`.
;
; So a consumer never has to ask how many levels a dedent crossed, which is the
; question both previous implementations answered with their own loop.
(def-class Indent ()
  (doc "The stack discipline under indentation-sensitive grouping: feed it a column, it tells you what opened and what closed. Policy -- tab width and what an unmatched dedent means -- is set at construction, never assumed."
    (note "(Indent advance ...) allocates via class dispatch. Per-character callers inside a tokenizer callback must fetch the raw ref -- (prim-ref 'indent 'advance) -- and call the cached ref.")
    (example "(let ((i (Indent make))) (i feed 4))" "('open)")
    (see feed) (see make))

  tab       ; tab stop: a tab advances to the next multiple of this
  mode      ; what an unmatched dedent means: open | close | error
  cols      ; open columns, deepest first, always ending in 0

  (static
    (method make (self . (param opts LIST "Optional (TAB-STOP MISMATCH-MODE); defaults 8 and 'error"))
      (doc "An indenter with nothing but column 0 open. Defaults are SRFI-110's and Python's: a tab advances to the next multiple of 8, and a dedent matching no open level is an error -- the only one of the three historical answers with a specification behind it."
        (returns Indent "A fresh indenter")
        (example "((Indent make 1 'open) feed 3)" "('open)"))
      (new-from self
        (list 'tab  (if (null? opts) 8 (first opts))
              'mode (if (null? opts) (lit error)
                      (if (null? (rest opts)) (lit error) (first (rest opts))))
              'cols (list 0))))

    (method advance (self (param col INT "Column so far")
                          (param chr INT "The character")
                          (param tab-stop INT "A tab advances to the next multiple of this"))
      (doc "The column after one character: a space is one, a tab advances to the next multiple of tab-stop, anything else leaves it alone."
        (returns INT "The new column")
        (example "(Indent advance 1 #\\tab 8)" "8"))
      (%indent-advance col chr tab-stop))

    (method measure (self (param s STRING "The line")
                          (param start INT "Index the leading run begins at")
                          (param tab-stop INT "A tab advances to the next multiple of this"))
      (doc "The column reached by the run of spaces and tabs at `start`, for a consumer holding a whole line rather than driving characters."
        (returns INT "The column")
        (example "(Indent measure \"    x\" 0 8)" "4"))
      (%indent-measure s start tab-stop))

    (method scan (self (param s STRING "The line")
                       (param start INT "Index the leading run begins at")
                       (param tab-stop INT "A tab advances to the next multiple of this"))
      (doc "(COLUMN . END-INDEX) for the leading run of spaces and tabs at `start` -- both from one walk, because a column and an index stop being the same number as soon as a tab is worth more than one."
        (returns PAIR "(column . index of the first character that is neither)")
        (example "(Indent scan \"  x\" 0 8)" "(2 . 2)"))
      (%indent-scan s start tab-stop))

    ; --- %-statics: the stack arithmetic, homed on the class -----------------
    ; Cold by comparison with `advance` -- once per LINE, from the two methods
    ; below -- so these pay dispatch rather than a top-level %-global. Classes
    ; are namespaces; see lib/x/tool/pin.x for the worked example.

    (method %pop (self cols col acc)
      (doc "Pop levels deeper than col, accumulating a `close` for each. Never pops the base: column 0 closes only at end of input."
        (returns PAIR "(remaining-stack . closes)"))
      (if (null? (rest cols))
        (pair cols acc)
        (if (> (first cols) col)
          (Indent %pop (rest cols) col (pair (lit close) acc))
          (pair cols acc))))

    (method %feed (self cols col mode)
      (doc "The stack and the events for a line at col. Every result ends with exactly one `open` or `same`, so no caller counts levels."
        (returns PAIR "(new-stack . events)"))
      (let ((popped (Indent %pop cols col ())))
        (let ((rest-cols (first popped))
              (closes (rest popped)))
          (if (= (first rest-cols) col)
            ; Same level: the line continues the block already open.
            (pair rest-cols (List reverse (pair (lit same) closes)))
            ; Deeper. Two ways to arrive and they are one event: a genuine
            ; indent, or a dedent that landed between two open levels -- which
            ; is only reachable when mode is `open`, the other two modes having
            ; been intercepted here.
            (if (if (null? closes) #t (eq? mode (lit open)))
              (pair (pair col rest-cols) (List reverse (pair (lit open) closes)))
              (if (eq? mode (lit close))
                ; The dedent stands; the odd column opens nothing.
                (pair rest-cols (List reverse (pair (lit same) closes)))
                (Err raise (lit indent)
                  "unindent does not match any outer indentation level" col)))))))

    (method classify (self (param col INT "The incoming column")
                           (param ref INT "The column being compared against"))
      (doc "deeper, same or shallower -- the three rules, for a consumer that keeps its own control flow and only wants to stop owning them."
        (returns SYMBOL "deeper | same | shallower")
        (example "(Indent classify 4 0)" "'deeper"))
      (%indent-classify col ref)))

  (method reset! (self)
    (doc "Close everything and start again at column 0. The state a fresh instance has."
      (returns Indent "self"))
    (set-member! 'cols (list 0))
    self)

  (method column (self)
    (doc "The innermost open column."
      (returns INT "The column"))
    (first (member 'cols)))

  (method depth (self)
    (doc "How many levels are open. A fresh indenter is 1: column 0 counts."
      (returns INT "The depth"))
    (List length (member 'cols)))

  (method feed (self (param col INT "The column this line begins at"))
    (doc "Advance to a line at `col`. Returns zero or more `close` events followed by exactly one `open` or `same` -- so a caller never counts levels itself, which is the loop both previous implementations owned. Raises 'indent when the column matches no open level and the mode is 'error."
      (returns LIST "The events, outermost close first")
      (example "(let ((i (Indent make))) (i feed 4) (i feed 0))" "('close 'same)"))
    (let ((r (Indent %feed (member 'cols) col (member 'mode))))
      (set-member! 'cols (first r))
      (rest r)))

  (method close-all (self)
    (doc "The events for end of input: one `close` per open level above column 0. Leaves the indenter reset."
      (returns LIST "The close events")
      (example "(let ((i (Indent make))) (i feed 4) (i close-all))" "('close)"))
    (let ((r (Indent %feed (member 'cols) 0 (lit close))))
      (set-member! 'cols (list 0))
      ; feed's contract ends every result with open or same; at end of input
      ; there is no line to continue, so the trailing `same` is dropped rather
      ; than reported as a block that opened.
      (List reverse (rest (List reverse (rest r)))))))

(doc (provide x/reader/indent Indent
       %indent-advance %indent-scan %indent-measure %indent-classify)
  (note "Policy is constructor-set: tab stop and what an unmatched dedent means. Defaults are SRFI-110's, which are also Python's.")
  (note "Blank and comment-only lines are the CALLER's business: a line that produces no column never reaches feed.")
  (note "Registered under catalog ns `indent` (advance/scan/measure/classify) for per-character callers who must not dispatch.")
  "The stack discipline under indentation-sensitive grouping (#520).")
