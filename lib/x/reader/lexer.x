; lexer.x -- Lexer: a tokenizer base built from data rules, its analysers
; compiled
;
; A lexer is a child base ((Base make-tok)) carrying one tokenizer type a rule.
; The engine's token loop drives those types a character at a time, and an
; analyser state is native code when the assembler lane is open and the
; interpreted twin of the same form when it is not: 0.2 us a byte compiled,
; against 40-130 us for a byte walk written in x (x/lexing-survey.md).
;
; Rules are data.  Each is made by a static below and names the kind of
; token it reads; (Lexer make rules) turns the list into the base.  Every
; state is spelled as a (fn (me buffer score chr) ...) FORM in the assembler
; lane's dialect -- nested if, and, or, %seq, the %buffer-* and %score-*
; doors, `me` for the self loop, other states as free variables -- so one
; form serves both realizations: the assembler lane lowers it, and the twin is the
; same form evaluated with its free variables substituted.
;
; The token loop hands a tie to the type registered first, so the first
; rule in the list wins an equal-length match: list a keyword table before
; the identifier run that would also read it.  A longer match wins over a
; shorter one whatever the order.
;
; The base is process state: (Base make-tok) allocates it on a chain of its
; own that no state image can carry, and compiled code lives in a page this
; process mapped.  So make registers a transient that drops the base and
; the states before an image is written, and a recache hook that makes them
; again, from the rules, after a load.  A consumer holds the Lexer and
; nothing else.
(module x/reader/lexer)

(import x/type/class)
(import x/type/base)
(import x/type/buf)
(import x/protocol/str/str8)

(def-class Lexer ()
  (doc "A tokenizer base built from data rules, its analyser states compiled to native code when the assembler lane is open and interpreted otherwise. Make one with (Lexer make rules), where each rule is made by run, skip, table, quoted, until, number, nested, word, escape, pattern, any or record; read text with (l read-str s), a span of bytes with (l read-span s start len). A token is (tag text); from a number rule (tag text label), from a record rule (tag bytes length)."
    (note "The first rule in the list wins an equal-length tie; a longer match wins regardless. List a keyword table before the identifier run that would also read it.")
    (note "A character class is a list of byte codes, (lo . hi) pairs and strings (each byte a member), or one bare string; a character literal counts as its code.")
    (note "The base and its states are dropped before a state image is written and made again after a load: a consumer holds the Lexer, never its raw base.")
    (note "A make with every state compiled records a plan in its cache group, and a later make of the same rules -- in this heap, or in a process that reads the group file -- rebuilds the states from it with no form made, printed or checked; the replayed field says which make ran.")
    (note "The first make in a process imports x/tool/asm-cache. A bundle that writes a state image and makes its lexer outside it reads that module from source at the first make, which under a lang whose reader analysers make every later read dear (the numeric tower) costs seconds: import x/tool/asm-cache where the image is written.")
    (example "(let ((l (Lexer make (list (Lexer skip \" \") (Lexer run 'word (list (pair 97 122)) (list (pair 97 122))))))) (l read-str \"ab c\"))" "(('word \"ab\") ('word \"c\"))"))
  (doc (rules ()) "The rules the base is built from, in priority order")
  (doc (raw ()) "The raw tokenizer base, or nil between an image write and its load")
  (doc (states ()) "Every state installed on the base -- the compiled ones as native code, the rest as closures; held so the collector keeps them")
  (doc (compiled 0) "How many states the assembler lane compiled in the last make; 0 when the lane is closed")
  (doc (replayed #f) "Whether the last make rebuilt the states from the plan its cache group holds, with no form made, rather than making them")
  (doc (reader ()) "The closure read-str calls: the tokenizing door, the raw base and the end text bound once, so a read costs no class dispatch. Made with the base, and nil while the base is")
  (doc (resets ()) "A state for each nested and word rule that puts its return stack at depth 0, called before every read: a read that ended inside an open span leaves the depth where it stopped")
  (doc (end " ") "Text appended to every read, so the last token meets a delimiter: a token is only read once a character ends it, and the engine drops an unterminated tail. One space unless make was given another; a C lexer wants a newline, which also ends a last line comment. An any rule is built to refuse its bytes, so setting it after make wants a remake!")

  (method read-str (self (param s STRING "Text to tokenize"))
    (doc "The tokens of s, in order, each (tag text) or (tag text label); dropped tokens (skip, an until rule with no tag) do not appear. The end text (a space unless set) is appended first, so the last token is seen."
      (returns LIST "The token list, nil for empty input")
      (example "(let ((l (Lexer make (list (Lexer skip \" \") (Lexer run 'word \"ab\" \"ab\"))))) (l read-str \"a b\"))" "(('word \"a\") ('word \"b\"))"))
    ; One field read and a call: the reader closes over everything a read
    ; needs, so a short read pays for the tokens, not for class dispatch.
    (def r (self reader))
    (if (null? r) (do (self remake!) ((self reader) s)) (r s)))

  (method read-span (self (param s STRING "Bytes, NULs included: a (str make) region, a file read whole")
                          (param start INTEGER "Byte offset of the span")
                          (param len INTEGER "Its length in bytes"))
    (doc "The tokens of the len bytes of s at start, in order. Nothing is appended: a record ends on its own last byte, so a span of them needs no end text, and the read stops at the first byte no rule claims -- the end of the records. Needs an engine whose tok read-str takes a span (x-engine-c after v0.2.20); raises a label 'lexer Err on one that does not."
      (returns LIST "The token list, nil when the span starts with no token")
      (sample "(l read-span story pc 64)" "the instructions at pc, up to the first byte that starts none"))
    (Lexer %span-check)
    (if (null? (self raw)) (self remake!) ())
    ((fn (self rs) (if (null? rs) () (do ((first rs) () () () 0) (self (rest rs))))) (self resets))
    ((fn (self ts acc)
       (if (null? ts)
         ((fn (self xs out) (if (null? xs) out (self (rest xs) (pair (first xs) out)))) acc ())
         (self (rest ts) (if (eq? (first ts) (Lexer %dropped)) acc (pair (first ts) acc)))))
     ((Lexer %read-str) (self raw) s start len) ()))

  (method remake! (self)
    (doc "Make the base and its states again from the rules -- what the recache hook does after an image load; a consumer never needs to call it."
      (returns ANY "The raw base"))
    (self states ())
    (self compiled 0)
    (self replayed #f)
    (self resets ())
    (self raw (Base raw-of (Base make-tok)))
    ; One rule list makes the same states in every process, so their compiles
    ; run as one cache group keyed by the rules and the end text: a later
    ; process loads all of them in one read instead of hashing and reading
    ; each state's entry.  A make with every state compiled also records a
    ; plan in the group -- each state's entry and what its free variables
    ; are -- and a later make whose group holds every entry rebuilds the
    ; states from it, with no form made, printed or checked.
    (if (Lexer %jit?)
      ((prim-ref (lit compile) (lit asm-cache-group))
        (Str8 append "lexer:" (%number->str (Lexer %plan-version)) ":"
          ((prim-ref (lit io) (lit write-to-str)) (pair (self end) (self rules))))
        (fn (_)
          (if (Lexer %replay! self)
            (self replayed #t)
            (Lexer %install-recording! self))))
      (Lexer %install! self (self rules)))
    (self reader (Lexer %reader-for self))
    (self raw))

  (static
    ; --- the catalogue doors, fetched once at load ------------------------------
    (%read-str (prim-ref (lit tok) (lit read-str)))
    (%buffer-token (prim-ref (lit buf) (lit tok)))
    (%transient! (prim-ref (lit image) (lit transient!)))
    (%recache-hook! (prim-ref (lit image) (lit recache-hook!)))
    (%char->int (prim-ref (lit char) (lit ->int)))
    (%base-eval (prim-ref (lit base) (lit eval)))
    (%byte-ref (prim-ref (lit str) (lit byte-ref)))
    (%byte-len (prim-ref (lit str) (lit byte-len)))
    (%make-str (prim-ref (lit str) (lit make)))
    (%i+ (prim-ref (lit int) (lit +)))
    (%i- (prim-ref (lit int) (lit -)))
    (%i= (prim-ref (lit int) (lit =)))
    (%i< (prim-ref (lit int) (lit <)))
    ; Is the assembler lane open?  Probed by one state in the form every state
    ; takes; probed again after an image load, when the compiler has its
    ; addresses back.
    (%jit-cell (pair () ()))
    (%skip-count (pair 0 ()))
    ; what a dropped span's read handler answers; read-str leaves it out
    (%dropped (pair (lit dropped) ()))
    ; The version of the states a rule list makes.  It is part of every group
    ; key and every plan, so a change to how states are made -- a form, an
    ; fvar's name or value, a state added or dropped -- MUST bump it: a plan
    ; recorded by the old code would otherwise be replayed as the new.  The
    ; digest case in tests/x/specs/lib/lexer-plan.spec.md fails on any such
    ; change until both it and this number are updated.
    (%plan-version 2)
    ; The recorder a full make runs under: on, then the states made, newest
    ; first, as (state text fvars) -- TEXT the cache key, nil for a twin -- and
    ; the rules' first states, newest first.
    (%rec-on (pair #f ()))
    (%rec-states (pair () ()))
    (%rec-entries (pair () ()))

    (method make (self (param rules LIST "Rules in priority order, each from run, skip, table, quoted, until, number, nested, word, escape, pattern, any or record")
                       . (param more ANY "Optionally the end text, a space when left out: see the end field"))
      (doc "A lexer over rules: a tokenizer base with one type a rule, its states compiled where the lane allows."
        (returns Lexer "The lexer")
        (sample "(Lexer make (list (Lexer skip \" \\n\") (Lexer number 'num ()) (Lexer run 'id \"abc\" \"abc\")))" "a lexer of numbers and words")
        (sample "(Lexer make c-rules \"\\n\")" "a lexer whose last line comment ends"))
      (let ((raw ()) (states ()) (compiled 0) (replayed #f) (reader ()) (resets ()) (end (if (null? more) " " (first more))))
        (def l (new Lexer rules rules raw raw states states compiled compiled replayed replayed reader reader resets resets end end))
        (l remake!)
        ((Lexer %transient!) (fn (_) (l raw ()) (l states ()) (l reader ())))
        ((Lexer %recache-hook!) (fn (_) (Lexer %jit-probe!) (l remake!)))
        l))

    ; The assembler lane's door is the byte cache (x/tool/asm-cache), which
    ; registers itself in the catalogue as (compile asm-cached) and loads the
    ; compiler only on a miss.  compile.x's compile-asm is a stub over the same
    ; door, but importing compile.x also loads the C lane -- posix, proc, file,
    ; the emitter and the pipeline -- which a lexer never uses: 490 ms against
    ; 290 ms for the cache door alone.  Imported on first use, so a module that
    ; imports the Lexer and never makes one pays neither.
    (method %compile (self form fvars)
      (import x/tool/asm-cache)
      ((prim-ref (lit compile) (lit asm-cached)) form fvars #t))

    ; The read for lexer L, made when its base is: the tokenizing door, the raw
    ; base, the end text and the string append bound here rather than fetched
    ; per read.  Fetching them per read was nine tenths of a short read --
    ; 1,049 us for ten bytes, the engine's own share 61 us.  A dropped span's
    ; handler answers the dropped marker, so only a rule list with one filters,
    ; and with a local loop: List's reverse is a class call per read.
    (method %reader-for (self l)
      (def drops?
        ((fn (self rs)
           (if (null? rs) #f
             (if (if (eq? (first (first rs)) (lit until)) (null? (first (rest (rest (first rs))))) #f)
               #t (self (rest rs)))))
         (l rules)))
      ; A nested or word rule's reset puts its return stack at depth 0 before
      ; each read, since a read that ended inside an open span leaves the depth
      ; where it stopped; a rule list with none has nothing to run.
      ((fn (_ read base end append dropped resets)
         (def tokens
           (if (null? resets)
             (fn (_ s) (read base (append s end)))
             (fn (_ s)
               ((fn (self rs) (if (null? rs) () (do ((first rs) () () () 0) (self (rest rs)))))
                resets)
               (read base (append s end)))))
         (if drops?
           (fn (_ s)
             ((fn (self ts acc)
                (if (null? ts)
                  ((fn (self xs out) (if (null? xs) out (self (rest xs) (pair (first xs) out)))) acc ())
                  (self (rest ts) (if (eq? (first ts) dropped) acc (pair (first ts) acc)))))
              (tokens s) ()))
           tokens))
       (Lexer %read-str) (l raw) (l end) (prim-ref (lit str) (lit append)) (Lexer %dropped)
       (l resets)))

    (method %jit-probe! (self)
      (%set-first! (Lexer %jit-cell)
        (guard (_ #f)
          (do (Lexer %compile (lit (fn (me buffer score chr) (if (= chr 32) me k)))
                              (list (pair (lit k) 1)))
              #t))))

    ; Does the engine read a span?  One that does not ignores read-str's
    ; start and length and reads the whole string, which would hand a caller
    ; the wrong tokens without a word; so the first read-span asks: from
    ; "ab", the one byte at 1 is one token, the whole string two.
    (%span-cell (pair () ()))
    (method %span-check (self)
      (if (null? (first (Lexer %span-cell)))
        (let ((probe (Lexer make (list (Lexer any (lit b))))))
          (%set-first! (Lexer %span-cell)
            (if (= (List length ((Lexer %read-str) (probe raw) "ab" 1 1)) 1) (lit yes) (lit no))))
        ())
      (if (eq? (first (Lexer %span-cell)) (lit yes)) ()
        (Err raise (lit lexer) "Lexer read-span: this engine's tok read-str does not take a span" ())))

    (method %jit? (self)
      (if (null? (first (Lexer %jit-cell)))
        (do (Lexer %jit-probe!) (first (Lexer %jit-cell)))
        (first (Lexer %jit-cell))))

    ; --- rules --------------------------------------------------------------
    ; A rule is (kind name tag . args); %install! builds each one's states.

    (method run (self (param tag SYMBOL "The token's tag")
                      (param first LIST "Class of the first character")
                      (param rest LIST "Class of every following character")
                      . (param follow LIST "Optionally the class of the byte that must come next"))
      (doc "A rule for a run of characters: one of first, then any number of rest. Identifiers, words. Given follow, the run is a token only when the byte after it is in follow; that byte is left for the next token."
        (returns LIST "The rule")
        (sample "(Lexer run 'id (list (pair 97 122) 95) (list (pair 97 122) (pair 48 57) 95))" "C-style identifiers")
        (sample "(Lexer run 'io (list (pair 48 57)) (list (pair 48 57)) \"<>\")" "a shell descriptor: the digits of 2>, not of 2 alone"))
      (list (lit run) (Str8 str tag) tag first rest follow))

    (method skip (self (param class LIST "Class of the characters to drop"))
      (doc "A rule that drops a run of characters: whitespace."
        (returns LIST "The rule")
        (sample "(Lexer skip \" \\t\\n\")" "drop blanks and newlines"))
      (%set-first! (Lexer %skip-count) (+ 1 (first (Lexer %skip-count))))
      (list (lit skip) (Str8 append "SKIP-" (%number->str (first (Lexer %skip-count)))) () class))

    (method table (self (param tag SYMBOL "The token's tag")
                        (param strings LIST "The literal strings to match"))
      (doc "A rule for a table of literals, longest match: operators, keywords."
        (returns LIST "The rule")
        (sample "(Lexer table 'op (list \"<\" \"<<\" \"<<=\"))" "three operators, the longest present wins"))
      (list (lit table) (Str8 str tag) tag strings))

    (method quoted (self (param tag SYMBOL "The token's tag")
                         (param open INTEGER "The opening byte")
                         (param close INTEGER "The closing byte")
                         (param esc ANY "The escape byte, or nil for none"))
      (doc "A rule for a quoted literal: open, a body in which esc takes the next byte literally, close. The token's text is the raw literal with its quotes; decoding escapes is the reader's work, done once per token rather than per character."
        (returns LIST "The rule")
        (sample "(Lexer quoted 'str 34 34 92)" "a C string literal"))
      (list (lit quoted) (Str8 str tag) tag open close esc))

    (method until (self (param tag ANY "The token's tag, or nil to drop the token")
                        (param open STRING "The opening literal")
                        (param close STRING "The closing literal, one or two bytes")
                        . (param flags LIST "Optionally take, to-end, or both"))
      (doc "A rule for a span from open to close: comments, delimited patterns. A one-byte close is left for the next token (a newline ends a line comment and is then read on its own) unless the flag take is given, which makes it part of the token; a two-byte close is always taken. With the flag to-end a span that meets no close runs to the end of the text and is a token all the same, the end text not part of it; without it, such a span is not a token."
        (returns LIST "The rule")
        (sample "(Lexer until () \"/*\" \"*/\")" "drop block comments")
        (sample "(Lexer until 'pat \"/\" \"/\" 'take 'to-end)" "an ex-style /pattern/, whose closing / may be missing"))
      ((fn (self fs)
         (unless (null? fs)
           (do (unless (if (eq? (first fs) (lit take)) #t (eq? (first fs) (lit to-end)))
                 (Err raise (lit lexer) "Lexer until: a flag is take or to-end" (first fs)))
               (self (rest fs)))))
       flags)
      (list (lit until) (if (null? tag) "UNTIL" (Str8 str tag)) tag open close flags))

    (method number (self (param tag SYMBOL "The token's tag")
                         (param suffix LIST "Class of suffix bytes taken after the digits, or nil"))
      (doc "A rule for a number: decimal digits, an optional fraction and exponent, or 0x and hex digits; then any bytes of suffix. The token carries a label: 1 integer, 2 fraction or exponent, 3 hex."
        (returns LIST "The rule")
        (sample "(Lexer number 'num \"uUlL\")" "C integer and floating literals"))
      (list (lit number) (Str8 str tag) tag suffix))

    (method any (self (param tag SYMBOL "The token's tag"))
      (doc "A rule for one byte that no other rule reads. The engine stops a read at the first byte no type claims, silently; listed last, this rule claims that byte as a one-byte token, so a reader can refuse it by name. It loses every tie, so it never takes a byte another rule reads."
        (returns LIST "The rule")
        (sample "(Lexer any 'bad)" "every stray byte becomes (bad \"@\")"))
      (list (lit any) (Str8 str tag) tag))

    (method nested (self (param tag SYMBOL "The token's tag")
                         (param open STRING "The opening literal")
                         (param start SYMBOL "The context the body after open is read in")
                         (param contexts LIST "Each (NAME CLOSE ESC OPENS): see the doc")
                         . (param flags LIST "Optionally to-end"))
      (doc "A rule for a span whose body holds spans of its own: open, then a body read in the context start, to the byte that closes start. A context is (NAME CLOSE ESC OPENS): CLOSE the byte that ends it, ESC the byte that takes the next byte literally (nil for none), OPENS a list of (LITERAL . CONTEXT), each literal entering that context, whose close returns to the one it was entered from. The token's text is the whole span, raw; contexts nest up to 63 deep, and a deeper one ends the match there. With the flag to-end a span still open at the end of the text is a token all the same, the end text not part of it; without it, such a span is not a token."
        (returns LIST "The rule")
        (note "Within a context no opening literal may be a prefix of another, and none may start with the context's close or escape byte; make refuses such a rule.")
        (sample "(Lexer nested 'dq \"\\\"\" 'dq (list (list 'dq 34 92 (list (pair \"$(\" 'cmd))) (list 'cmd 41 92 (list (pair \"(\" 'cmd) (pair \"\\\"\" 'dq) (pair \"'\" 'sq))) (list 'sq 39 () ())))" "a shell double-quoted string, $(...) inside it read whole, quotes in that included"))
      (Lexer %to-end-only "Lexer nested: a flag is to-end" flags)
      (list (lit nested) (Str8 str tag) tag open start contexts flags))

    (method word (self (param tag SYMBOL "The token's tag")
                       (param start SYMBOL "The context the word is read in")
                       (param contexts LIST "Each (NAME CLOSE ESC OPENS), as nested takes them; start's CLOSE may be nil")
                       (param stop LIST "Class of the bytes that end the word, at depth 0")
                       . (param flags LIST "Optionally to-end"))
      (doc "A rule for a word whose bytes may hold spans: a nested span with no opening literal, read in the context start from its first byte, and ending before a byte of stop met at depth 0 -- that byte is left for the next token. A first byte in stop is no word. Spans opened inside it read as nested reads them, a stop byte inside one being an ordinary byte. With the flag to-end a word whose span is still open at the end of the text is a token all the same, the end text not part of it; without it, such a word is not a token."
        (returns LIST "The rule")
        (sample "(Lexer word 'word 'w (list (list 'w () 92 (list (pair \"\\\"\" 'dq) (pair \"$(\" 'cmd))) (list 'dq 34 92 (list (pair \"$(\" 'cmd))) (list 'cmd 41 92 (list (pair \"(\" 'cmd) (pair \"\\\"\" 'dq)))) \" \\t\\n;&|<>()\")" "a shell word: a\\ b\"c d\"$(e f) is one token")
        (sample "(Lexer word 'word 'w contexts \" \\t\\n\" 'to-end)" "an unclosed ${x at the end is the word ${x"))
      (Lexer %to-end-only "Lexer word: a flag is to-end" flags)
      (list (lit word) (Str8 str tag) tag start contexts stop flags))

    ; Refuse a flag other than to-end, naming the rule in WHY.
    (method %to-end-only (self why flags)
      (unless (null? flags)
        (do (unless (eq? (first flags) (lit to-end)) (Err raise (lit lexer) why (first flags)))
            (Lexer %to-end-only why (rest flags)))))

    (method escape (self (param tag SYMBOL "The token's tag")
                         (param byte ANY "The escaping byte, a code or a character"))
      (doc "A rule for an escape: byte, then whichever byte follows it, as one two-byte token."
        (returns LIST "The rule")
        (sample "(Lexer escape 'esc 92)" "a backslash and the byte it escapes"))
      (list (lit escape) (Str8 str tag) tag byte))

    (method record (self (param tag SYMBOL "The token's tag")
                         (param shapes LIST "Each (CLASS . STEPS): a first byte in CLASS starts a record whose following bytes STEPS count"))
      (doc "A rule for a binary record whose length is read from its own bytes: a machine instruction, a tagged field. Its first byte picks the first shape whose CLASS holds it, and that shape's steps count the bytes after it, in order: (bytes N), N more; (fields K SIZES), K bytes each read as four 2-bit fields from the high end, a field of value i adding (SIZES i) bytes and a field whose size is stop ending the fields (the K bytes are read all the same); (flag MASK N), one byte, then N more when it has no bit of MASK set; (units W BIT), W-byte units until one whose first byte has a bit of BIT set, that unit included. The record ends on its own last byte, so it needs nothing after it -- read-span reads a run of them -- and a first byte in no CLASS is no record. Its token is (tag bytes length): the bytes may hold a NUL, where a string's own length stops."
        (returns LIST "The rule")
        (note "A step is a plain list, as (lit (bytes 2)) or (list (lit fields) 1 (lit (2 1 1 stop)))) spells it.")
        (sample "(Lexer record 'insn (list (pair (list (pair 0 127)) (lit ((bytes 2)))) (pair (list (pair 192 255)) (lit ((fields 1 (2 1 1 stop)))))))" "a long-form instruction is two operand bytes; a variable-form one's operand-type byte says how many")
        (example "(let ((l (Lexer make (list (Lexer record 'rec (list (pair \"ab\" (lit ((bytes 1)))) (pair \"z\" (lit ((units 1 32)))))))))) (l read-str \"a1b2zDq\"))" "(('rec \"a1\" 2) ('rec \"b2\" 2) ('rec \"zDq\" 3))"))
      (Lexer %record-check shapes)
      (list (lit record) (Str8 str tag) tag shapes))

    ; Refuse a record rule whose steps its states could not count.
    (method %record-check (self shapes)
      (def bad (fn (_ why what) (Err raise (lit lexer) (Str8 append "Lexer record: " why) what)))
      (def n? (fn (_ x lo) (if (number? x) (>= x lo) #f)))
      (def mask? (fn (_ x) (if (number? x) (if (>= x 1) (<= x 255) #f) #f)))
      (def size? (fn (_ x) (if (eq? x (lit stop)) #t (n? x 0))))
      (def step
        (fn (_ s)
          (def kind (if (pair? s) (first s) ()))
          (def a (if (pair? s) (rest s) ()))
          (match
            ((eq? kind (lit bytes))
              (if (n? (first a) 0) () (bad "(bytes N) wants a count" s)))
            ((eq? kind (lit fields))
              (if (if (n? (first a) 1) (if (= (List length (first (rest a))) 4)
                    (List all? size? (first (rest a))) #f) #f)
                () (bad "(fields K SIZES) wants a count and four sizes" s)))
            ((eq? kind (lit flag))
              (if (if (mask? (first a)) (n? (first (rest a)) 0) #f) () (bad "(flag MASK N) wants a byte mask and a count" s)))
            ((eq? kind (lit units))
              (if (if (n? (first a) 1) (mask? (first (rest a))) #f) () (bad "(units W BIT) wants a width and a byte mask" s)))
            (#t (bad "a step is bytes, fields, flag or units" s)))))
      (List map
        (fn (_ shape)
          (if (pair? shape) () (bad "a shape is (CLASS . STEPS)" shape))
          (List map step (rest shape)))
        shapes)
      ())

    (method pattern (self (param tag SYMBOL "The token's tag")
                          (param steps LIST "Each (CLASS FEWEST MOST): a class, the fewest bytes of it, and the most, or nil for no bound; #t as a class is every byte"))
      (doc "A rule for a pattern: the steps in order, each a class and how many bytes of it, as many as there are. A step whose fewest is 0 may be absent. The token ends after the last step, the byte that completes a bounded last step taken: printf directives, numeric escapes."
        (returns LIST "The rule")
        (note "A step reads as many bytes of its class as there are and never gives one back, so a step's class should not run into the next step's; a pattern whose every step may be absent is refused, since it would read an empty token.")
        (sample "(Lexer pattern 'dir (list (list \"%\" 1 1) (list \"-+ #0123456789.\" 0 ()) (list #t 1 1)))" "a printf directive: %, flags, width and precision, the conversion byte")
        (sample "(Lexer pattern 'esc (list (list \"\\\\\" 1 1) (list \"01234567\" 1 3)))" "an octal escape, three digits at most"))
      (def step?
        (fn (_ s)
          (if (if (pair? s) (= (List length s) 3) #f)
            (let ((fewest (first (rest s))) (most (first (rest (rest s)))))
              (if (if (number? fewest) (>= fewest 0) #f)
                (if (null? most) #t
                  (if (number? most) (if (>= most 1) (>= most fewest) #f) #f))
                #f))
            #f)))
      ((fn (self ss)
         (unless (null? ss)
           (do (unless (step? (first ss))
                 (Err raise (lit lexer) "Lexer pattern: a step is (CLASS FEWEST MOST)" (first ss)))
               (self (rest ss)))))
       steps)
      (unless ((fn (self ss) (if (null? ss) #f (if (> (first (rest (first ss))) 0) #t (self (rest ss))))) steps)
        (Err raise (lit lexer) "Lexer pattern: a step must have a fewest of 1 or more" steps))
      (list (lit pattern) (Str8 str tag) tag steps))

    ; --- forms --------------------------------------------------------------
    ; The lane's dialect.  A class test is an or of ranges and codes; accept
    ; unreads the character that ended the token and scores; take keeps it.

    (method %code (self c)
      (if (char? c) ((Lexer %char->int) c) c))

    (method %class-form (self class)
      (def one
        (fn (_ c)
          (if (pair? c)
            (list (lit and) (list (lit >=) (lit chr) (Lexer %code (first c)))
                            (list (lit <=) (lit chr) (Lexer %code (rest c))))
            (list (lit =) (lit chr) (Lexer %code c)))))
      (def bytes
        (fn (self s i acc)
          (if (< i 0) acc (self s (- i 1) (pair (one ((Lexer %byte-ref) s i)) acc)))))
      (def tests
        (fn (self l acc)
          (if (null? l) acc
            (self (rest l)
              (if (str? (first l))
                (bytes (first l) (- ((Lexer %byte-len) (first l)) 1) acc)
                (pair (one (first l)) acc))))))
      ; a bare string is the class of its bytes; #t is every byte, whichever
      ; way the engine hands a high one over
      (if (eq? class #t)
        (lit (and (>= chr -128) (<= chr 255)))
        (let ((ts (tests (if (str? class) (list class) class) ())))
          (if (null? ts) (lit (= chr -1))
            (if (null? (rest ts)) (first ts) (pair (lit or) ts))))))

    (%accept (lit (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
    (%take (lit (%score-set score 1 buffer)))
    (%drop (lit (%seq (%buffer-unread buffer) (%score-set score -1 buffer))))
    (method %accept-label (self k)
      (list (lit %seq) (lit (%buffer-unread buffer))
        (list (lit %seq) (list (lit %score-label!) (lit score) k) (lit (%score-set score 1 buffer)))))

    (method %state-form (self body)
      (list (lit fn) (lit (me buffer score chr)) body))

    ; --- realizing a state --------------------------------------------------
    ; (Lexer %state l form fvars): the compiled state when the lane is open
    ; and the compile succeeds, the interpreted twin otherwise.  FVARS is an
    ; alist of (symbol . state); the twin binds each by substitution, so the
    ; form itself is what runs either way.  Every state goes on the lexer's
    ; list: a compiled state is not seen by the collector through the base.

    (method %state (self l form fvars . twin)
      ; TWIN, when given, binds names differently in the interpreted twin
      ; than FVARS does in the compiled form: the nested rule's stack is a
      ; scratch string there and a list of cells here.
      (def r (Lexer %realize form fvars (if (null? twin) fvars (List append (first twin) fvars))))
      (if (rest r) (l compiled (+ 1 (l compiled))) ())
      (l states (pair (first r) (l states)))
      (Lexer %rec-state! (first r)
        (if (rest r) ((prim-ref (lit compile) (lit asm-cache-last-text))) ())
        fvars)
      (first r))

    ; FORM realized: (STATE . COMPILED?), the compiled state when the lane
    ; is open and the compile succeeds, the interpreted twin bound by
    ; TWIN-FVARS otherwise.
    (method %realize (self form fvars twin-fvars)
      (def made
        (if (Lexer %jit?)
          (guard (_ ())
            (Lexer %compile form fvars))
          ()))
      (if (null? made)
        (pair (eval (Lexer %subst form twin-fvars) (Lexer %env)) #f)
        (pair made #t)))

    (method state (self (param form LIST "A state, as a (fn (me buffer score chr) ...) form in the assembler lane's dialect")
                        (param fvars LIST "Alist of (SYMBOL . STATE): the states the form's free variables name"))
      (doc "An analyser state for a type built by hand on a tokenizer base -- one the rules cannot express: typed instances, a live stream, a read that recurses. The form is compiled to native code when the assembler lane is open and the compile succeeds, and is its own interpreted twin otherwise, the free variables substituted, so one form serves either way. Answers (STATE . COMPILED?)."
        (returns PAIR "The state and whether it was compiled")
        (note "The caller holds every state it makes: a compiled state is not seen by the collector through the base, and a collect frees it under the type. A state is process state, like a base: make it again after an image load.")
        (note "Only the lane's dialect: nested if, and, or, =, <, <=, >, >=, %seq, me for the self loop, the %buffer-* and %score-* doors, a free variable for another state; never match, a literal #f, or a call into x.")
        (sample "(Lexer state '(fn (me buffer score chr) (if (= chr 97) me (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))) ())" "a run of a, accepted before the byte that ends it")
        (sample "(Lexer state '(fn (me buffer score chr) (if (= chr 34) body ())) (list (pair 'body (first string-body))))" "an opening quote handing to the body state made before it"))
      (Lexer %realize form fvars fvars))

    (%env ((op () e e)))

    (method %subst (self form fvars)
      (if (pair? form)
        (pair (Lexer %subst (first form) fvars) (Lexer %subst (rest form) fvars))
        (if (symbol? form)
          (let ((hit (Lexer %assoc form fvars)))
            (if (null? hit) form (list (lit lit) (rest hit))))
          form)))

    (method %assoc (self k al)
      (if (null? al) ()
        (if (eq? (first (first al)) k) (first al) (Lexer %assoc k (rest al)))))

    ; --- a rule's states ----------------------------------------------------
    ; Each builder answers the entry state; the entry runs at every token
    ; start and hands the body back for the rest.

    ; With a follow class the body refuses a byte in neither class, so the run
    ; is no token there.  FOLLOW is the rule's optional tail, a one-member
    ; class list when given -- a class already.
    (method %run-states (self l first rest follow)
      (let ((body (Lexer %state l
                    (Lexer %state-form
                      (list (lit if) (Lexer %class-form rest) (lit me)
                        (if (null? follow) (Lexer %accept)
                          (list (lit if) (Lexer %class-form follow) (Lexer %accept) ()))))
                    ())))
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) (Lexer %class-form first) (lit body) ()))
          (list (pair (lit body) body)))))

    (method %skip-states (self l class)
      (let ((body (Lexer %state l
                    (Lexer %state-form
                      (list (lit if) (Lexer %class-form class) (lit me) (Lexer %drop)))
                    ())))
        ; a dropped token scores at entry as well, as x-python's blanks do
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) (Lexer %class-form class)
              (lit (%seq (%score-set score -1 buffer) body)) ()))
          (list (pair (lit body) body)))))

    ; One byte, whatever it is, taken -- except a byte a skip rule drops, and
    ; the end text's: the engine lets a positive score beat a negative one
    ; whatever the order, so the skip classes are refused here rather than
    ; contested; and at the buffer's end only a state that accepts on its own
    ; byte can win, which would hand the appended end text to this rule.
    (method %any-states (self l)
      (def refused
        ((fn (self rs acc)
           (if (null? rs) acc
             (self (rest rs)
               (if (eq? (first (first rs)) (lit skip))
                 (pair (Lexer %class-form (first (rest (rest (rest (first rs)))))) acc)
                 acc))))
         (l rules) (list (Lexer %class-form (l end)))))
      (Lexer %state l
        (Lexer %state-form
          (list (lit if) (pair (lit or) refused) () (Lexer %take)))
        ()))

    ; A trie node is (terminal? . kids), kids an alist of (code . node); a
    ; node's state dispatches on the next byte to a child's, and a terminal
    ; with no child for the byte accepts.  Children are the state's free
    ; variables, named a, b, c, ... in order.
    (method %trie-add (self node s i)
      (if (>= i ((Lexer %byte-len) s))
        (pair #t (rest node))
        (let ((c ((Lexer %char->int) ((Lexer %byte-ref) s i))))
          (def kid (Lexer %assoc c (rest node)))
          (def sub (Lexer %trie-add (if (null? kid) (pair () ()) (rest kid)) s (+ i 1)))
          (def without
            ((fn (self ks acc)
               (if (null? ks) acc
                 (self (rest ks) (if (= (first (first ks)) c) acc (pair (first ks) acc)))))
             (rest node) ()))
          (pair (first node) (pair (pair c sub) without)))))

    ; A node's children are its state's free variables, one name each: k0,
    ; k1, ... as many as the node has (a C operator table's root has more
    ; than an alphabet's worth).
    (method %fvar-names (self n)
      ((fn (self i acc)
         (if (< i 0) acc
           (self (- i 1) (pair (Str8 ->sym (Str8 append "k" (%number->str i))) acc))))
       (- n 1) ()))

    (method %trie-state (self l node)
      (def kids
        ((fn (self ks acc)
           (if (null? ks) acc
             (self (rest ks) (pair (pair (first (first ks)) (Lexer %trie-state l (rest (first ks)))) acc))))
         (rest node) ()))
      (def names (Lexer %fvar-names (List length kids)))
      (def dispatch
        (fn (self ks names tail)
          (if (null? ks) tail
            (list (lit if) (list (lit =) (lit chr) (first (first ks))) (first names)
              (self (rest ks) (rest names) tail)))))
      (def fvars
        (fn (self ks names acc)
          (if (null? ks) acc
            (self (rest ks) (rest names) (pair (pair (first names) (rest (first ks))) acc)))))
      (Lexer %state l
        (Lexer %state-form
          (dispatch kids names (if (first node) (Lexer %accept) ())))
        (fvars kids names ())))

    (method %table-states (self l strings)
      (def root
        ((fn (self ss node)
           (if (null? ss) node (self (rest ss) (Lexer %trie-add node (first ss) 0))))
         strings (pair () ())))
      (Lexer %trie-state l root))

    ; A quoted body loops until close; esc hands the next byte, whatever it
    ; is, back to the body.  The closing byte is taken into the token.
    (method %quoted-states (self l open close esc)
      (def body-cell (pair () ()))
      (def body
        (if (null? esc)
          (Lexer %state l
            (Lexer %state-form
              (list (lit if) (list (lit =) (lit chr) (Lexer %code close)) (Lexer %take) (lit me)))
            ())
          ; The escape state needs the body and the body the escape state, so
          ; the escape reads the body out of a cell when it runs -- (first
          ; cell), the lane's door for states that hand to each other -- and
          ; the cell is filled below.  Compiled like every other state: an
          ; interpreted state's one comparison registers the engine's INTEGER
          ; type on the child, with its s-expression analyser.
          (let ((after (Lexer %state l
                         (Lexer %state-form (lit (first cell)))
                         (list (pair (lit cell) body-cell)))))
            (Lexer %state l
              (Lexer %state-form
                (list (lit if) (list (lit =) (lit chr) (Lexer %code close)) (Lexer %take)
                  (list (lit if) (list (lit =) (lit chr) (Lexer %code esc)) (lit esc) (lit me))))
              (list (pair (lit esc) after))))))
      (%set-first! body-cell body)
      ; the cell is reached only through the compiled states' baked address, so
      ; the lexer holds it, or a collect frees it under them
      (l states (pair body-cell (l states)))
      (Lexer %state l
        (Lexer %state-form
          (list (lit if) (list (lit =) (lit chr) (Lexer %code open)) (lit body) ()))
        (list (pair (lit body) body))))

    ; A span from open to close.  Open is matched byte by byte through a
    ; chain of states; the body loops until the close's first byte, and a
    ; two-byte close confirms its second byte before taking the token.
    ; A dropped span scores POSITIVE all the same: the engine lets a
    ; negative score lose to any positive one, so a comment scored -1 would
    ; lose to the `/` operator that opens it.  Its read handler answers the
    ; dropped marker, which %handlers arranges for a rule with no tag.
    ;
    ; TAKE makes a one-byte close part of the token.  TO-END scores the span
    ; once its opener has matched, so that the engine, which accepts at the end
    ; of the text whatever has a score, takes a span the close never ended; the
    ; read handler then cuts the end text off it (%reader).
    (method %until-states (self l tag open close take? to-end?)
      (def c0 ((Lexer %char->int) ((Lexer %byte-ref) close 0)))
      (def two? (> ((Lexer %byte-len) close) 1))
      (def body-cell (pair () ()))
      (def body
        (if two?
          (let ((c1 ((Lexer %char->int) ((Lexer %byte-ref) close 1))))
            ; The state after the close's first byte needs the body back on a
            ; miss, and the body needs it: it reads the body out of the cell,
            ; as the escape state above does.
            (def second
              (Lexer %state l
                (Lexer %state-form
                  (list (lit if) (list (lit =) (lit chr) c1) (Lexer %take)
                    (list (lit if) (list (lit =) (lit chr) c0) (lit me) (lit (first cell)))))
                (list (pair (lit cell) body-cell))))
            (Lexer %state l
              (Lexer %state-form
                (list (lit if) (list (lit =) (lit chr) c0) (lit second) (lit me)))
              (list (pair (lit second) second))))
          (Lexer %state l
            (Lexer %state-form
              (list (lit if) (list (lit =) (lit chr) c0) (if take? (Lexer %take) (Lexer %accept)) (lit me)))
            ())))
      (%set-first! body-cell body)
      ; the cell is reached only through the compiled states' baked address, so
      ; the lexer holds it, or a collect frees it under them
      (l states (pair body-cell (l states)))
      ; the open chain, last byte first; the last byte of the opener hands to
      ; the body, scoring the span first when it may run to the end
      (def last (- ((Lexer %byte-len) open) 1))
      ((fn (self i next)
         (if (< i 0) next
           (self (- i 1)
             (Lexer %state l
               (Lexer %state-form
                 (list (lit if) (list (lit =) (lit chr) ((Lexer %char->int) ((Lexer %byte-ref) open i)))
                   (if (if to-end? (= i last) #f)
                     (lit (%seq (%score-set score 1 buffer) next))
                     (lit next))
                   ()))
               (list (pair (lit next) next))))))
       last body))

    ; Numbers: digits, then a fraction or an exponent, or 0x then hex digits;
    ; then any suffix bytes.  Each accepting state declares its label.
    (method %number-states (self l suffix)
      (def digit (lit (and (>= chr 48) (<= chr 57))))
      (def xdigit (lit (or (and (>= chr 48) (<= chr 57)) (and (>= chr 97) (<= chr 102)) (and (>= chr 65) (<= chr 70)))))
      (def suffix? (not (null? suffix)))
      (def suffix-form (if suffix? (Lexer %class-form suffix) ()))
      ; the end of a literal with label K: suffix bytes if any, then accept
      (def ender
        (fn (_ k)
          (if suffix?
            (let ((s (Lexer %state l
                       (Lexer %state-form
                         (list (lit if) suffix-form (lit me) (Lexer %accept-label k)))
                       ())))
              (pair (lit s) s))
            ())))
      (def end-form
        (fn (_ k e)
          (if (null? e) (Lexer %accept-label k)
            (list (lit if) suffix-form (lit s) (Lexer %accept-label k)))))
      (def e1 (ender 1))
      (def e2 (ender 2))
      (def e3 (ender 3))
      (def fv (fn (_ e more) (if (null? e) more (pair e more))))
      (def hex-digits
        (Lexer %state l
          (Lexer %state-form (list (lit if) xdigit (lit me) (end-form 3 e3)))
          (fv e3 ())))
      (def hex-first
        (Lexer %state l
          (Lexer %state-form (list (lit if) xdigit (lit k) ()))
          (list (pair (lit k) hex-digits))))
      (def exp-digits
        (Lexer %state l
          (Lexer %state-form (list (lit if) digit (lit me) (end-form 2 e2)))
          (fv e2 ())))
      (def exp-first
        (Lexer %state l
          (Lexer %state-form (list (lit if) digit (lit k) ()))
          (list (pair (lit k) exp-digits))))
      (def exp-sign
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) digit (lit k)
              (list (lit if) (lit (or (= chr 43) (= chr 45))) (lit f) ())))
          (list (pair (lit k) exp-digits) (pair (lit f) exp-first))))
      (def frac-digits
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) digit (lit me)
              (list (lit if) (lit (or (= chr 101) (= chr 69))) (lit es) (end-form 2 e2))))
          (fv e2 (list (pair (lit es) exp-sign)))))
      ; after a leading dot a digit must follow; after digits and a dot the
      ; literal is already a fraction (1. is 1.0 in C and Python)
      (def frac-first
        (Lexer %state l
          (Lexer %state-form (list (lit if) digit (lit k) ()))
          (list (pair (lit k) frac-digits))))
      (def frac-after-int
        (Lexer %state l
          (Lexer %state-form (list (lit if) digit (lit k) (end-form 2 e2)))
          (fv e2 (list (pair (lit k) frac-digits)))))
      (def int-digits
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) digit (lit me)
              (list (lit if) (lit (= chr 46)) (lit frac)
                (list (lit if) (lit (or (= chr 101) (= chr 69))) (lit es) (end-form 1 e1)))))
          (fv e1 (list (pair (lit frac) frac-after-int) (pair (lit es) exp-sign)))))
      (def zero
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) (lit (or (= chr 120) (= chr 88))) (lit hex)
              (list (lit if) digit (lit me)
                (list (lit if) (lit (= chr 46)) (lit frac)
                  (list (lit if) (lit (or (= chr 101) (= chr 69))) (lit es) (end-form 1 e1))))))
          (fv e1 (list (pair (lit hex) hex-first) (pair (lit frac) frac-after-int) (pair (lit es) exp-sign)))))
      (Lexer %state l
        (Lexer %state-form
          (list (lit if) (lit (= chr 48)) (lit zero)
            (list (lit if) digit (lit body)
              (list (lit if) (lit (= chr 46)) (lit dot) ()))))
        (list (pair (lit zero) zero) (pair (lit body) int-digits) (pair (lit dot) frac-first))))

    ; An escape: its byte, then any byte, taken.
    (method %escape-states (self l byte)
      (let ((after (Lexer %state l (Lexer %state-form (Lexer %take)) ())))
        (Lexer %state l
          (Lexer %state-form
            (list (lit if) (list (lit =) (lit chr) (Lexer %code byte)) (lit next) ()))
          (list (pair (lit next) after)))))

    ; A pattern: the steps in order, each a class with the fewest and the
    ; most bytes of it.  A state is a step and how many of its bytes are
    ; read: a byte of the class reads on, and another byte, once the step has
    ; its fewest, is decided for the next step there and then -- the next
    ; step's opening decision is written into the state -- so each byte costs
    ; one state.  The byte that completes the last step is taken; a byte no
    ; remaining step reads, when every one of them may be absent, ends the
    ; token before it.  A bounded step has a state a byte; an unbounded one
    ; has a state a byte up to its fewest, and the last loops.  The states
    ; are named pI-K and made from the last back, each referring to later
    ; ones by name, so the alist of those made is every state's free
    ; variables.
    (method %pattern-states (self l steps)
      (def n (List length steps))
      (def nth (fn (self l i) (if (= i 0) (first l) (self (rest l) (- i 1)))))
      (def class (fn (_ s) (first s)))
      (def fewest (fn (_ s) (first (rest s))))
      (def most (fn (_ s) (first (rest (rest s)))))
      (def name
        (fn (_ i k)
          (Str8 ->sym (Str8 append "p" (Str8 append (%number->str i) (Str8 append "-" (%number->str k)))))))
      (def made (pair () ()))
      ; what a byte of step I, read with K of it already read, leads to
      (def target
        (fn (_ i k)
          (def s (nth steps i))
          (match
            ((null? (most s)) (if (< k (fewest s)) (name i (+ k 1)) (lit me)))
            ((< (+ k 1) (most s)) (name i (+ k 1)))
            ((= i (- n 1)) (Lexer %take))
            (#t (name (+ i 1) 0)))))
      ; the decision for step J on a byte no step before it read
      (def open
        (fn (self j)
          (if (= j n) (Lexer %accept)
            (let ((s (nth steps j)))
              (list (lit if) (Lexer %class-form (class s)) (target j 0)
                (if (= (fewest s) 0) (self (+ j 1)) ()))))))
      (def form
        (fn (_ i k)
          (def s (nth steps i))
          (Lexer %state-form
            (list (lit if) (Lexer %class-form (class s)) (target i k)
              (if (>= k (fewest s)) (open (+ i 1)) ())))))
      (def make-step
        (fn (self i k)
          (unless (< k 0)
            (do (%set-first! made
                  (pair (pair (name i k) (Lexer %state l (form i k) (first made))) (first made)))
                (self i (- k 1))))))
      ((fn (self i)
         (unless (< i 0)
           (let ((s (nth steps i)))
             (do (make-step i (if (null? (most s)) (fewest s) (- (most s) 1)))
                 (self (- i 1))))))
       (- n 1))
      (rest (first (first made))))

    ; A nested span.  Every context has a body state, an escape state when it
    ; has an escape byte, and a state for each byte inside an opening literal
    ; longer than one byte.  The states reach one another through cells --
    ; (first SLOT), each slot an fvar holding a cell set once every state
    ; exists -- so contexts may enter one another in any order.
    ;
    ; The return stack is a scratch buffer of 64 words, through the lane's
    ; %mem-* forms: word 0 the depth, word D the body to go back to when the
    ; context entered at depth D closes.  Opening a literal pushes the body
    ; it was read in and goes to its context's body; a close pops, or at
    ; depth 0 takes the byte and ends the token.  The interpreted twin keeps
    ; the same stack in a list of cells, its %mem-* forms bound to closures.
    ; MORE is (STOP TO-END?): a word's stop class, and whether a span still
    ; open at the end of the text is a token.  TO-END scores the span once it
    ; is committed -- a word at its first byte, a nested span at its opener's
    ; last -- so that the engine, which accepts at the end of the text
    ; whatever has a score, takes one the close never ended; its read handler
    ; then cuts the end text off it, as an until span's does.
    (method %nested-states (self l open start contexts . more)
      (def stop (if (null? more) () (first more)))
      (def to-end? (if (null? more) #f (if (null? (rest more)) #f (first (rest more)))))
      (def scored (fn (_ form) (if to-end? (list (lit %seq) (lit (%score-set score 1 buffer)) form) form)))
      (Lexer %nested-check open start contexts stop)
      (def slots (pair () ()))
      (def count (pair 0 ()))
      (def slot!
        (fn (_)
          (%set-first! count (+ 1 (first count)))
          (def name (Str8 ->sym (Str8 append "s" (%number->str (first count)))))
          (%set-first! slots (pair (pair name (pair () ())) (first slots)))
          name))
      (def forms (pair () ()))
      ; The cells, the forms still to compile and the stacks are held on the
      ; lexer from the start: the compiler collects as it goes, and what only
      ; this frame holds is freed under it (and every cell is reached by the
      ; finished states only through baked addresses).
      (l states (pair slots (pair forms (l states))))
      (def emit! (fn (_ slot body) (%set-first! forms (pair (pair slot (Lexer %state-form body)) (first forms)))))
      (def ref (fn (_ slot) (list (lit first) slot)))
      (def bodies (List map (fn (_ c) (pair (first c) (slot!))) contexts))
      (def body-of (fn (_ name) (rest (Lexer %assoc name bodies))))
      ; an opener past the stack's 63 refuses, and puts the depth back at 0
      ; for the token the read goes on to
      (def push-form
        (fn (_ from to)
          (list (lit if) (lit (>= (%mem-ref (first stk) 0) 63)) (lit (%seq (%mem-set! (first stk) 0 0) ()))
            (list (lit %seq) (lit (%mem-set! (first stk) 0 (+ (%mem-ref (first stk) 0) 1)))
              (list (lit %seq) (list (lit %mem-set-at!) (lit (first stk)) (lit (%mem-ref (first stk) 0)) (ref (body-of from)))
                (ref (body-of to)))))))
      (def close-form
        (lit (if (= (%mem-ref (first stk) 0) 0) (%score-set score 1 buffer)
               (%seq (%mem-set! (first stk) 0 (- (%mem-ref (first stk) 0) 1))
                     (%mem-ref-at (first stk) (+ (%mem-ref (first stk) 0) 1))))))
      ; OPENS grouped by their byte at I, in order: ((code . opens) ...)
      (def groups
        (fn (_ opens i)
          ((fn (self os acc)
             (if (null? os) (List reverse acc)
               (let ((c ((Lexer %char->int) ((Lexer %byte-ref) (first (first os)) i))))
                 (def hit (Lexer %assoc c acc))
                 (self (rest os)
                   (if (null? hit) (pair (pair c (list (first os))) acc)
                     (List map (fn (_ g) (if (eq? g hit) (pair c (List append (rest g) (list (first os)))) g)) acc))))))
           opens ())))
      ; the tests on chr for the groups of OPENS at byte I, OTHER when none
      ; matches: a literal ending at I pushes, a longer one goes to the state
      ; for its next byte, whose own miss reads chr as the context's body would
      (def dispatch ())
      ; a literal's next-byte state is made once, found again by its context,
      ; its byte and the literals it reads: the miss of every such state
      ; reads chr through the context's dispatch, which names the same states
      (def made (pair () ()))
      (def key
        (fn (_ name opens i)
          (Str8 append (Str8 str name) ":" (%number->str i) ":"
            ((fn (self os acc) (if (null? os) acc (self (rest os) (Str8 append acc " " (first (first os))))))
             opens ""))))
      (def next-state
        (fn (_ tests name opens i)
          (def k (key name opens i))
          (def hit ((fn (self ms) (if (null? ms) () (if (Str8 =? (first (first ms)) k) (first ms) (self (rest ms))))) (first made)))
          (if (null? hit)
            (let ((s (slot!)))
              (%set-first! made (pair (pair k s) (first made)))
              (emit! s (tests name opens i (dispatch name (ref (body-of name)))))
              s)
            (rest hit))))
      (def opens-tests
        (fn (self name opens i other)
          ((fn (walk gs)
             (if (null? gs) other
               (let ((g (first gs)))
                 (list (lit if) (list (lit =) (lit chr) (first g))
                   (if (if (null? (rest (rest g))) (= ((Lexer %byte-len) (first (first (rest g)))) (+ i 1)) #f)
                     (push-form name (rest (first (rest g))))
                     (ref (next-state self name (rest g) (+ i 1))))
                   (walk (rest gs))))))
           (groups opens i))))
      (def escs
        (List map (fn (_ c) (pair (first c) (if (null? (first (rest (rest c)))) () (slot!)))) contexts))
      ; a word's start context, at depth 0, ends before a stop byte, which it
      ; leaves for the next token
      (def stop-form (if (null? stop) () (Lexer %class-form stop)))
      (set! dispatch
        (fn (_ name other)
          (def c (Lexer %assoc name contexts))
          (def esc (rest (Lexer %assoc name escs)))
          (def tests (opens-tests name (Lexer %nested-opens c) 0 other))
          (def escaped
            (if (null? esc) tests
              (list (lit if) (list (lit =) (lit chr) (Lexer %code (first (rest (rest c))))) (ref esc) tests)))
          (def closed
            (if (null? (first (rest c))) escaped
              (list (lit if) (list (lit =) (lit chr) (Lexer %code (first (rest c)))) close-form escaped)))
          (if (if (null? stop) #f (eq? name start))
            (list (lit if) (list (lit and) (lit (= (%mem-ref (first stk) 0) 0)) stop-form) (Lexer %accept) closed)
            closed)))
      (List map
        (fn (_ c)
          (emit! (body-of (first c)) (dispatch (first c) (lit me)))
          (def esc (rest (Lexer %assoc (first c) escs)))
          (if (null? esc) () (emit! esc (ref (body-of (first c))))))
        contexts)
      ; the stack, and the twin's
      (def buf ((Lexer %make-str) 512))
      (def tstack ((fn (self k acc) (if (= k 0) acc (self (- k 1) (pair (pair 0 ()) acc)))) 64 ()))
      (def tcell (fn (self s i) (if (= i 0) (first s) (self (rest s) (- i 1)))))
      (def tref (fn (_ s i) (first (tcell s i))))
      (def tset (fn (_ s i v) (%set-first! (tcell s i) v) v))
      (def twin (list (pair (lit stk) (pair tstack ())) (pair (lit %mem-ref) tref) (pair (lit %mem-ref-at) tref)
                      (pair (lit %mem-set!) tset) (pair (lit %mem-set-at!) tset)))
      (def fvars (pair (pair (lit stk) buf) (first slots)))
      (l states (pair buf (pair twin (pair fvars (l states)))))
      (List map
        (fn (_ f) (%set-first! (rest (Lexer %assoc (first f) (first slots))) (Lexer %state l (rest f) fvars twin)))
        (first forms))
      ; the forms are compiled; the cells stay held through slots
      (%set-first! forms ())
      ; the state read-str calls first, which puts the stack at depth 0
      (l resets (pair (Lexer %state l (Lexer %state-form (lit (%mem-set! (first stk) 0 0))) fvars twin)
                      (l resets)))
      (def first-body (body-of start))
      ; A word has no opening literal: its first byte, unless it stops the
      ; word, is read as the start context's body reads a byte, the stack
      ; already at depth 0.  Otherwise the open chain, last byte first; its
      ; last byte starts the stack.
      (if (null? open)
        (Lexer %state l
          (Lexer %state-form (list (lit if) stop-form () (scored (dispatch start (ref first-body)))))
          fvars twin)
      ((fn (self i next)
         (if (< i 0) next
           (self (- i 1)
             (Lexer %state l
               (Lexer %state-form
                 (list (lit if) (list (lit =) (lit chr) ((Lexer %char->int) ((Lexer %byte-ref) open i)))
                   (if (null? next)
                     (scored (list (lit %seq) (lit (%mem-set! (first stk) 0 0)) (ref first-body)))
                     (lit next))
                   ()))
               (if (null? next) fvars (pair (pair (lit next) next) fvars))
               twin))))
       (- ((Lexer %byte-len) open) 1) ())))

    ; A record.  The entry state reads the first byte and picks its shape; the
    ; shape's steps are a chain of states, built from the last step back.  A
    ; continuation is (FORM . FVARS): what the state that reads a step's last
    ; byte does next -- take the token, or answer the next step's first state
    ; -- and the states FORM names.  A fields step keeps its running count in
    ; a two-word scratch buffer (word 0 the bytes still owed, word 1 set once a
    ; field said stop), through the lane's %mem-* forms; a units step loops
    ; back through a cell.  The twin keeps the two words in cells, as the
    ; nested rule's twin keeps its stack.  Bytes reach an analyser signed, so a
    ; class test reads (& chr 255).
    (method %record-states (self l shapes)
      (def cnt ((Lexer %make-str) 16))
      (def tw (list (pair 0 ()) (pair 0 ())))
      (def tref (fn (_ s i) (first (if (= i 0) (first s) (first (rest s))))))
      (def tset (fn (_ s i v) (%set-first! (if (= i 0) (first s) (first (rest s))) v) v))
      (def twin (list (pair (lit cnt) (pair tw ())) (pair (lit %mem-ref) tref) (pair (lit %mem-set!) tset)))
      (def held (pair () ()))
      (l states (pair cnt (pair twin (pair held (l states)))))
      (def count (pair 0 ()))
      (def fresh
        (fn (_)
          (%set-first! count (+ 1 (first count)))
          (Str8 ->sym (Str8 append "r" (%number->str (first count))))))
      (def mk
        (fn (_ body fvars)
          (Lexer %state l (Lexer %state-form body) (pair (pair (lit cnt) cnt) fvars) twin)))
      (def take (pair (Lexer %take) ()))
      (def to (fn (_ st) (def nm (fresh)) (pair nm (list (pair nm st)))))
      ; N more bytes, then K
      (def bytes
        (fn (_ n k)
          (if (= n 0) k
            ((fn (self i st)
               (if (= i 1) (to st)
                 (self (- i 1) (mk (lit next) (list (pair (lit next) st))))))
             n (mk (first k) (rest k))))))
      (def owed (lit (%mem-ref (first cnt) 0)))
      ; one field of a fields byte: the field at SHIFT adds its size, unless
      ; a field before it said stop
      (def field
        (fn (_ shift sizes)
          (def f (list (lit &) (list (lit >>) (lit chr) shift) 3))
          (def add
            (fn (_ s)
              (if (eq? s (lit stop)) (lit (%mem-set! (first cnt) 1 1))
                (if (= s 0) () (list (lit %mem-set!) (lit (first cnt)) 0 (list (lit +) owed s))))))
          (list (lit if) (lit (= (%mem-ref (first cnt) 1) 0))
            (list (lit if) (list (lit =) f 0) (add (first sizes))
              (list (lit if) (list (lit =) f 1) (add (first (rest sizes)))
                (list (lit if) (list (lit =) f 2) (add (first (rest (rest sizes))))
                  (add (first (rest (rest (rest sizes))))))))
            ())))
      (def fields-form
        (fn (_ sizes then)
          (list (lit %seq) (field 6 sizes)
            (list (lit %seq) (field 4 sizes)
              (list (lit %seq) (field 2 sizes)
                (list (lit %seq) (field 0 sizes) then))))))
      (def fields
        (fn (_ n sizes k)
          ; owed bytes, one a call, then K
          (def skip
            (mk (list (lit if) (lit (= (%mem-ref (first cnt) 0) 1)) (first k)
                  (lit (%seq (%mem-set! (first cnt) 0 (- (%mem-ref (first cnt) 0) 1)) me)))
                (rest k)))
          (def sk (fresh))
          (def last
            (mk (fields-form sizes (list (lit if) (lit (= (%mem-ref (first cnt) 0) 0)) (first k) sk))
                (pair (pair sk skip) (rest k))))
          ; the field bytes between the first and the last
          (def middle
            ((fn (self i st)
               (if (< i 2) st
                 (self (- i 1) (mk (fields-form sizes (lit next)) (list (pair (lit next) st))))))
             (- n 1) last))
          ; the first fields byte starts the count
          (to (mk (list (lit %seq) (lit (%mem-set! (first cnt) 0 0))
                    (list (lit %seq) (lit (%mem-set! (first cnt) 1 0))
                      (fields-form sizes (if (= n 1) (list (lit if) (lit (= (%mem-ref (first cnt) 0) 0)) (first k) sk) (lit next)))))
                  (if (= n 1) (pair (pair sk skip) (rest k)) (list (pair (lit next) middle)))))))
      (def flag
        (fn (_ m n k)
          (def more (bytes n k))
          (to (mk (list (lit if) (list (lit =) (list (lit &) (lit chr) m) 0) (first more) (first k))
                  (List append (rest more) (rest k))))))
      (def units
        (fn (_ w b k)
          (def cell (pair () ()))
          (%set-first! held (pair cell (first held)))
          (def nm (fresh))
          (def again (bytes (- w 1) (pair (list (lit first) nm) (list (pair nm cell)))))
          (def done (bytes (- w 1) k))
          (def u (mk (list (lit if) (list (lit =) (list (lit &) (lit chr) b) 0) (first again) (first done))
                     (List append (rest again) (rest done))))
          (%set-first! cell u)
          (to u)))
      (def chain
        (fn (self steps k)
          (if (null? steps) k
            (do
              (def s (first steps))
              (def after (self (rest steps) k))
              (def a (rest s))
              (match
                ((eq? (first s) (lit bytes)) (bytes (first a) after))
                ((eq? (first s) (lit fields)) (fields (first a) (first (rest a)) after))
                ((eq? (first s) (lit flag)) (flag (first a) (first (rest a)) after))
                (#t (units (first a) (first (rest a)) after)))))))
      ; the entry: each shape's class, tested on the byte as unsigned
      (def unsigned
        (fn (self f)
          (if (pair? f) (pair (self (first f)) (self (rest f)))
            (if (eq? f (lit chr)) (lit (& chr 255)) f))))
      (def entry
        (fn (self ss)
          (if (null? ss) (pair () ())
            (do
              (def k (chain (rest (first ss)) take))
              (def others (self (rest ss)))
              (pair (list (lit if) (unsigned (Lexer %class-form (first (first ss)))) (first k) (first others))
                    (List append (rest k) (rest others)))))))
      (def e (entry shapes))
      (mk (first e) (rest e)))

    ; A context's opening literals, as (literal . context) pairs
    (method %nested-opens (self c) (first (rest (rest (rest c)))))

    ; Refuse a nested rule its states could not read: an unknown context, a
    ; literal that is a prefix of another in its context, or one that starts
    ; with the context's close or escape byte.
    (method %nested-check (self open start contexts stop)
      (def known? (fn (_ n) (not (null? (Lexer %assoc n contexts)))))
      (def bad (fn (_ why what) (Err raise (lit lexer) (Str8 append "Lexer nested: " why) what)))
      (if (not (known? start)) (bad "no context named start" start) ())
      (if (null? open)
        (if (null? stop) (bad "neither an opening literal nor a stop class" start) ())
        (if (< ((Lexer %byte-len) open) 1) (bad "an empty opening literal" open) ()))
      (List map
        (fn (_ c)
          (def close (if (null? (first (rest c))) -1 (Lexer %code (first (rest c)))))
          (if (if (= close -1) (not (if (eq? (first c) start) (not (null? stop)) #f)) #f)
            (bad "a context with no close byte other than a word's start" (first c)) ())
          (def esc (first (rest (rest c))))
          (List map
            (fn (_ o)
              (def b ((Lexer %char->int) ((Lexer %byte-ref) (first o) 0)))
              (if (not (known? (rest o))) (bad "no context named" (rest o)) ())
              (if (= b close) (bad "a literal starts with its context's close" (first o)) ())
              (if (if (null? esc) #f (= b (Lexer %code esc))) (bad "a literal starts with its context's escape" (first o)) ())
              (List map
                (fn (_ p)
                  (if (if (eq? p o) #f (Lexer %prefix? (first o) (first p)))
                    (bad "a literal is a prefix of another" (first o)) ()))
                (Lexer %nested-opens c)))
            (Lexer %nested-opens c)))
        contexts)
      ())

    ; Is A a prefix of B?
    (method %prefix? (self a b)
      (def n ((Lexer %byte-len) a))
      (if (> n ((Lexer %byte-len) b)) #f
        ((fn (self i)
           (if (= i n) #t
             (if (= ((Lexer %char->int) ((Lexer %byte-ref) a i)) ((Lexer %char->int) ((Lexer %byte-ref) b i)))
               (self (+ i 1)) #f)))
         0)))

    ; --- installing ---------------------------------------------------------
    ; The read handler of a tagged rule: (tag text), with the label when one
    ; was declared.  A rule with no tag has no read handler, and its tokens
    ; are dropped.
    ; THE TOKEN IS MADE IN THE PARENT BASE.  The engine calls a read handler
    ; inside the tokenizer base, and an object made there registers its
    ; built-in type on that base -- with the type's s-expression analyser,
    ; so one integer label would have the child read `+1` as an integer from
    ; then on.  So the handler evaluates the token's construction in the
    ; base that made the lexer, through base-eval, whose allocations are the
    ; target's: the text, the label and the list are all parent objects, and
    ; the child registers nothing.  The doors are captured outside the
    ; closure: a static read is a class dispatch, and this runs once a token.
    ;
    ; THE END TEXT IS NEVER PART OF A TOKEN.  A token the engine took at the
    ; end of the buffer -- a span that ran to the end, an escape or a pattern
    ; whose last byte was the end text's, a directive `%` with nothing after
    ; it -- holds bytes read-str appended, and is cut back by as many as it
    ; holds: the bytes the read cursor has gone past the point the end text
    ; starts at, the write cursor less the end text's length.  The cursors
    ; are the first and second words of the buffer's inner object.  A token
    ; that stopped before the end text costs one comparison here.
    (method %reader (self tag labelled? end-len)
      (let ((tok (Lexer %buffer-token)) (ev (Lexer %base-eval)) (parent (%base))
            (sub (prim-ref (lit str) (lit byte-sub))) (len (Lexer %byte-len))
            (write-at (%data-word-off 1)))
        (def text-of
          (fn (_ args)
            (def text (tok (first args)))
            (def inner (rest (first args)))
            (def over (- (%cell-int inner) (- (%ptr-ref-word (%obj->ptr inner) write-at) end-len)))
            (if (> over 0) (sub text 0 (- (len text) over)) text)))
        (def mk
          (if labelled?
            (fn (_ args) (list tag (text-of args) (%read-label args)))
            (fn (_ args) (list tag (text-of args)))))
        (fn (_ . args)
          (ev parent (list (list (lit lit) mk) (list (lit lit) args))))))

    ; The read handler of a record rule: (tag text length).  A record's bytes
    ; may hold a NUL, and a string's length is counted to its first, so the
    ; length comes from the buffer: its read cursor (the inner object's first
    ; word) less its start (the buffer's own first), the token being the
    ; bytes between them.
    (method %reader-record (self tag)
      (let ((tok (Lexer %buffer-token)) (ev (Lexer %base-eval)) (parent (%base)))
        (def mk
          (fn (_ args)
            (def b (first args))
            (list tag (tok b) (- (%cell-int (rest b)) (%cell-int b)))))
        (fn (_ . args)
          (ev parent (list (list (lit lit) mk) (list (lit lit) args))))))

    (method %handlers (self l rule)
      (def kind (first rule))
      (def tag (first (rest (rest rule))))
      (def args (rest (rest (rest rule))))
      ; an until rule's flags are its third argument, a list
      (def %until-flag?
        (fn (_ as f)
          ((fn (self fs) (if (null? fs) #f (if (eq? (first fs) f) #t (self (rest fs)))))
           (first (rest (rest as))))))
      ; whether a span may run to the end: an until rule's flags are its third
      ; argument, a nested or word rule's its fourth
      (def %to-end?
        (fn (_ k as)
          (match
            ((eq? k (lit until)) (%until-flag? as (lit to-end)))
            ((if (eq? k (lit nested)) #t (eq? k (lit word)))
              (not (null? (first (rest (rest (rest as)))))))
            (#t #f))))
      (def entry
        (match
          ((eq? kind (lit run)) (Lexer %run-states l (first args) (first (rest args)) (first (rest (rest args)))))
          ((eq? kind (lit skip)) (Lexer %skip-states l (first args)))
          ((eq? kind (lit table)) (Lexer %table-states l (first args)))
          ((eq? kind (lit quoted)) (Lexer %quoted-states l (first args) (first (rest args)) (first (rest (rest args)))))
          ((eq? kind (lit until))
            (Lexer %until-states l tag (first args) (first (rest args))
              (%until-flag? args (lit take)) (%until-flag? args (lit to-end))))
          ((eq? kind (lit number)) (Lexer %number-states l (first args)))
          ((eq? kind (lit any)) (Lexer %any-states l))
          ((eq? kind (lit nested))
            (Lexer %nested-states l (first args) (first (rest args)) (first (rest (rest args)))
              () (%to-end? kind args)))
          ((eq? kind (lit escape)) (Lexer %escape-states l (first args)))
          ((eq? kind (lit pattern)) (Lexer %pattern-states l (first args)))
          ((eq? kind (lit record)) (Lexer %record-states l (first args)))
          ((eq? kind (lit word))
            (Lexer %nested-states l () (first args) (first (rest args)) (first (rest (rest args)))
              (%to-end? kind args)))
          (#t (Err raise (lit lexer) "Lexer: unknown rule kind" kind))))
      (Lexer %rec-entry! entry)
      (Lexer %handlers-for l rule entry))

    ; The handlers of RULE's type around ENTRY, its first state: the analyser,
    ; and the read handler its kind and tag call for.
    (method %handlers-for (self l rule entry)
      (def kind (first rule))
      (def tag (first (rest (rest rule))))
      ; A rule with no tag is a skip, scored negative, which the engine never
      ; reads, or a dropped span, scored positive so that it beats the
      ; operator that opens it: the engine reads a positive match, and with
      ; no handler its default read would allocate in the child, so the
      ; handler answers the marker read-str filters out and allocates nothing.
      (if (null? tag)
        (if (eq? kind (lit skip))
          (list (pair (lit analyse) entry))
          (list (pair (lit analyse) entry)
                (pair (lit read) (let ((m (Lexer %dropped))) (fn (_ . args) m)))))
        (list (pair (lit analyse) entry)
              (pair (lit read)
                (if (eq? kind (lit record))
                  (Lexer %reader-record tag)
                  (Lexer %reader tag (eq? kind (lit number)) ((Lexer %byte-len) (l end))))))))

    ; Register in list order: the type registered first wins a tie.
    (method %install! (self l rules)
      (if (null? rules) ()
        (do
          (Base make-type (l raw) (first (rest (first rules))) (Lexer %handlers l (first rules)))
          (Lexer %install! l (rest rules)))))

    ; --- the plan -----------------------------------------------------------
    ; A make with the lane open runs under the recorder, and when every state
    ; it made was compiled it leaves the group a PLAN: for each state, oldest
    ; first, the place of its cache key among the group's texts and what each
    ; of its free variables is -- an earlier state, a cell the make fills, a
    ; scratch buffer of a size, or an integer -- then what each cell holds,
    ; each rule's first state, and the reset states.  A later make whose group
    ; holds every entry pours the states from it in the same order, so each
    ; free variable is the object it was, and no form is made, printed or
    ; checked.  Anything the plan cannot name means no plan, and the next make
    ; is a full one again.

    (method %rec-state! (self st text fvars)
      (when (first (Lexer %rec-on))
        (%set-first! (Lexer %rec-states) (pair (list st text fvars) (first (Lexer %rec-states))))))

    (method %rec-entry! (self st)
      (when (first (Lexer %rec-on))
        (%set-first! (Lexer %rec-entries) (pair st (first (Lexer %rec-entries))))))

    (method %install-recording! (self l)
      (%set-first! (Lexer %rec-states) ())
      (%set-first! (Lexer %rec-entries) ())
      (%set-first! (Lexer %rec-on) #t)
      (guard (e (do (%set-first! (Lexer %rec-on) #f) (error e)))
        (Lexer %install! l (l rules)))
      (%set-first! (Lexer %rec-on) #f)
      (def plan
        (guard (_ ())
          (Lexer %plan l (Lexer %rev (first (Lexer %rec-states)) ())
                         (Lexer %rev (first (Lexer %rec-entries)) ()))))
      (%set-first! (Lexer %rec-states) ())
      (%set-first! (Lexer %rec-entries) ())
      (unless (null? plan)
        ((prim-ref (lit compile) (lit asm-cache-group-extra!)) (Lexer %plan-text plan))))

    (method %rev (self l acc)
      (if (null? l) acc (Lexer %rev (rest l) (pair (first l) acc))))

    ; The list helpers the plan and the replay share, over the integer doors,
    ; as one closure each: the plan and the replay walk a list a state, and
    ; a class call or a generic operator a step would cost more than the
    ; forms they save.  Answers (nth pos map1 len rev append2).
    (method %kit (self)
      (def i+ (Lexer %i+))
      (def i- (Lexer %i-))
      (def i= (Lexer %i=))
      (list
        (fn (self l i) (if (i= i 0) (first l) (self (rest l) (i- i 1))))
        (fn (_ x l same?)
          ((fn (self l i) (if (null? l) -1 (if (same? x (first l)) i (self (rest l) (i+ i 1)))))
           l 0))
        (fn (self f l) (if (null? l) () (pair (f (first l)) (self f (rest l)))))
        (fn (_ l) ((fn (self l n) (if (null? l) n (self (rest l) (i+ n 1)))) l 0))
        (fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc))))
        (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b))))))

    ; The plan for RECS, the states made oldest first as (state text fvars),
    ; and ENTRIES, each rule's first state; raises when a state is a twin or a
    ; free variable is a thing a plan cannot name.  A free variable is written
    ; (NAME KIND N) -- NAME its symbol's text, KIND 0 for the N-th state, 1 for
    ; the N-th cell, 2 for the N-th buffer, 3 for the integer N -- so the plan
    ; is strings and integers only, which print and read back as themselves.
    (method %plan (self l recs entries)
      (def kit (Lexer %kit))
      (def pos (first (rest kit)))
      (def map1 (first (rest (rest kit))))
      (def len (first (rest (rest (rest kit)))))
      (def rev (first (rest (rest (rest (rest kit))))))
      (def i+ (Lexer %i+))
      (def i- (Lexer %i-))
      (def i< (Lexer %i<))
      (def no (fn (_ why) (Err raise (lit lexer) why ())))
      (def eq (fn (_ a b) (eq? a b)))
      (def texts
        (rev ((fn (self rs acc)
                (if (null? rs) acc
                  (do (def t (first (rest (first rs))))
                      (if (null? t) (no "a twin state") ())
                      (self (rest rs)
                        (if (i< (pos t acc str=?) 0) (pair t acc) acc)))))
              recs ())
             ()))
      (def sts (map1 (fn (_ r) (first r)) recs))
      ; cells and buffers met, newest first, with how many: a thing's number
      ; is how many were met before it
      (def cells (pair () 0))
      (def bufs (pair () 0))
      (def number!
        (fn (_ seen x)
          (def at (pos x (first seen) eq))
          (if (i< at 0)
            (do (def n (rest seen))
                (%set-first! seen (pair x (first seen)))
                (%set-rest! seen (i+ n 1))
                n)
            (i- (i- (rest seen) 1) at))))
      (def recipe
        (fn (_ fv)
          (def v (rest fv))
          (def k (pos v sts eq))
          (def name (symbol->str (first fv)))
          (match
            ((not (i< k 0)) (list name 0 k))
            ((pair? v) (list name 1 (number! cells v)))
            ((str? v) (list name 2 (number! bufs v)))
            ((number? v) (list name 3 v))
            (#t (no "a free variable a plan cannot name")))))
      (def states
        (map1 (fn (_ r) (pair (pos (first (rest r)) texts str=?) (map1 recipe (first (rest (rest r))))))
              recs))
      (def state-at
        (fn (_ s)
          (def k (pos s sts eq))
          (if (i< k 0) (no "a state the make did not record") k)))
      (list (Lexer %plan-version) (len texts) states
            (map1 (fn (_ c) (if (null? (first c)) () (state-at (first c)))) (rev (first cells) ()))
            (map1 (fn (_ b) ((Lexer %byte-len) b)) (rev (first bufs) ()))
            (map1 state-at entries)
            (map1 state-at (l resets))))

    ; The plan as the group keeps it: its integers and names as words between
    ; spaces, each list led by its length, a cell that holds nothing as `-`.
    ; Read back by one walk over the bytes, where the s-expression reader cost
    ; a make 42 us a byte of the plan -- half of a replayed make.  A name is a
    ; free variable's symbol text, which holds no space.
    (method %plan-text (self plan)
      (def kit (Lexer %kit))
      (def nth (first kit))
      (def len (first (rest (rest (rest kit)))))
      (def rev (first (rest (rest (rest (rest kit))))))
      (def out (pair () ()))
      (def put (fn (_ t) (%set-first! out (pair t (first out)))))
      (def int (fn (_ n) (put (%number->str n))))
      (def each (fn (_ l f) (int (len l)) ((fn (self l) (unless (null? l) (do (f (first l)) (self (rest l))))) l)))
      (int (nth plan 0))
      (int (nth plan 1))
      (each (nth plan 2)
        (fn (_ s)
          (int (first s))
          (each (rest s) (fn (_ fv) (put (first fv)) (int (nth fv 1)) (int (nth fv 2))))))
      (each (nth plan 3) (fn (_ c) (if (null? c) (put "-") (int c))))
      (each (nth plan 4) int)
      (each (nth plan 5) int)
      (each (nth plan 6) int)
      (Str8 join " " (rev (first out) ())))

    ; The plan %plan-text wrote, or () when S is not one: its words in one walk,
    ; an integer read as it is walked, then the lists rebuilt from their
    ; lengths.
    (method %plan-read (self s)
      (def rev (first (rest (rest (rest (rest (Lexer %kit)))))))
      (def i+ (Lexer %i+))
      (def i- (Lexer %i-))
      (def i< (Lexer %i<))
      (def i= (Lexer %i=))
      (def i* (prim-ref (lit int) (lit *)))
      (def n ((Lexer %byte-len) s))
      (def bref (Lexer %byte-ref))
      (def cint (Lexer %char->int))
      (def byte (fn (_ i) (cint (bref s i))))
      (def sub (prim-ref (lit str) (lit byte-sub)))
      ; The end of the word at J, and its value while every byte is a digit:
      ; (end . value), value () once a byte is not one.
      (def scan
        (fn (self j v)
          (if (if (i< j n) (not (i= (byte j) 32)) #f)
            (do
              (def b (byte j))
              (self (i+ j 1)
                (if (null? v) ()
                  (if (if (i< b 48) #t (i< 57 b)) () (i+ (i* v 10) (i- b 48))))))
            (pair j v))))
      ; the words, newest first: an integer, a name, or () for `-`
      (def words
        ((fn (self i acc)
           (if (i< i n)
             (if (i= (byte i) 32) (self (i+ i 1) acc)
               (do
                 (def neg? (i= (byte i) 45))
                 (def from (if neg? (i+ i 1) i))
                 (def r (scan from 0))
                 (def end (first r))
                 (self end
                   (pair
                     (match
                       ((if (null? (rest r)) #f (i< from end)) (if neg? (i- 0 (rest r)) (rest r)))
                       ((i= end from) ())
                       (#t (sub s i (i- end i))))
                     acc))))
             acc))
         0 ()))
      (def at (pair (rev words ()) ()))
      (def take
        (fn (_)
          (if (null? (first at)) (Err raise (lit lexer) "plan: it ends early" ()) ())
          (def w (first (first at)))
          (%set-first! at (rest (first at)))
          w))
      (def int (fn (_) (def w (take)) (if (number? w) w (Err raise (lit lexer) "plan: an integer" w))))
      (def many (fn (_ f) ((fn (self k acc) (if (i= k 0) (rev acc ()) (self (i- k 1) (pair (f) acc)))) (int) ())))
      (guard (_ ())
        (do
          (def version (int))
          (def ntexts (int))
          (def states (many (fn (_) (pair (int) (many (fn (_) (def name (take)) (list name (int) (int))))))))
          (def cells (many (fn (_) (def w (take)) (if (null? w) () (if (number? w) w (Err raise (lit lexer) "plan: a cell" w))))))
          (def bufs (many int))
          (def entries (many int))
          (def resets (many int))
          (if (null? (first at))
            (list version ntexts states cells bufs entries resets)
            ()))))

    ; Rebuild L's states from the open group's plan; #f, with L as it was,
    ; when there is none or it does not fit.
    (method %replay! (self l)
      (def held ((prim-ref (lit compile) (lit asm-cache-group-held))))
      (def extra (if (null? held) () (rest held)))
      (def plan (if (str? extra) (Lexer %plan-read extra) ()))
      (def kit (Lexer %kit))
      (def nth (first kit))
      (def map1 (first (rest (rest kit))))
      (def len (first (rest (rest (rest kit)))))
      (def rev (first (rest (rest (rest (rest kit))))))
      (def append2 (first (rest (rest (rest (rest (rest kit)))))))
      (def i+ (Lexer %i+))
      (def i- (Lexer %i-))
      (def i= (Lexer %i=))
      (def texts (if (null? held) () (first held)))
      (def fits?
        (if (pair? plan)
          (if (i= (first plan) (Lexer %plan-version))
            (if (i= (nth plan 1) (len texts))
              (i= (len (nth plan 5)) (len (l rules)))
              #f)
            #f)
          #f))
      (if (not fits?) #f
        (do
          (def cells (map1 (fn (_ c) (pair () ())) (nth plan 3)))
          (def bufs (map1 (fn (_ n) ((Lexer %make-str) n)) (nth plan 4)))
          (def pour (prim-ref (lit compile) (lit asm-cache-held-pour)))
          (def sym (prim-ref (lit str) (lit ->sym)))
          ; the states poured so far, newest first, and how many; () when a
          ; pour misses
          (def made
            ((fn (self ss acc n)
               (if (null? ss) acc
                 (do
                   (def r (first ss))
                   (def fvars
                     (map1
                       (fn (_ fv)
                         (def how (first (rest fv)))
                         (def at (first (rest (rest fv))))
                         (pair (sym (first fv))
                           (match
                             ((i= how 0) (nth acc (i- (i- n 1) at)))
                             ((i= how 1) (nth cells at))
                             ((i= how 2) (nth bufs at))
                             (#t at))))
                       (rest r)))
                   (def st (pour (nth texts (first r)) fvars))
                   (if (null? st) ()
                     (self (rest ss) (pair st acc) (i+ n 1))))))
             (nth plan 2) () 0))
          (if (not (i= (len made) (len (nth plan 2)))) #f
            (do
              (def sts (rev made ()))
              ((fn (self cs ks)
                 (unless (null? cs)
                   (do (unless (null? (first ks)) (%set-first! (first cs) (nth sts (first ks))))
                       (self (rest cs) (rest ks)))))
               cells (nth plan 3))
              (l states (append2 sts (append2 cells bufs)))
              (l compiled (len sts))
              (l resets (map1 (fn (_ k) (nth sts k)) (nth plan 6)))
              ; A type registered and then a raise would leave the base half
              ; made: on any raise here the base is made again, empty, for
              ; the full make that follows.
              (guard (_ (do (l raw (Base raw-of (Base make-tok))) (l states ())
                            (l compiled 0) (l resets ()) #f))
                (do
                  ((fn (self rs ks)
                     (unless (null? rs)
                       (do (Base make-type (l raw) (first (rest (first rs)))
                             (Lexer %handlers-for l (first rs) (nth sts (first ks))))
                           (self (rest rs) (rest ks)))))
                   (l rules) (nth plan 5))
                  #t)))))))))

(doc (provide x/reader/lexer Lexer)
  (note "Rules are data: run, skip, table, quoted, until, number, nested, word, escape, pattern, any, record. (Lexer make rules) builds the base; (l read-str s) reads text, (l read-span s start len) a span of bytes.")
  (note "Every analyser state is one form, compiled through compile-asm when the lane is open and evaluated as the interpreted twin otherwise; the base is remade after an image load.")
  (note "With the lane closed the twins run inside the child base, and their first comparison registers the engine's INTEGER type there with its s-expression analyser: a signed digit run such as +1 then reads as an integer wherever it outranks a one-byte rule. Compiled states register nothing.")
  "Tokenizer bases from data rules, with compiled analysers.")
