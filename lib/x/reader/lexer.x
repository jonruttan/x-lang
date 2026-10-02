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
; form serves both realizations: compile-asm lowers it, and the twin is the
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
(import x/tool/compile compile-asm)

(def-class Lexer ()
  (doc "A tokenizer base built from data rules, its analyser states compiled to native code when the assembler lane is open and interpreted otherwise. Make one with (Lexer make rules), where each rule is made by run, skip, table, quoted, until or number; read with (l read-str s). A token is (tag text) or, from a number rule, (tag text label)."
    (note "The first rule in the list wins an equal-length tie; a longer match wins regardless. List a keyword table before the identifier run that would also read it.")
    (note "A character class is a list of byte codes, (lo . hi) pairs and strings (each byte a member), or one bare string; a character literal counts as its code.")
    (note "The base and its states are dropped before a state image is written and made again after a load: a consumer holds the Lexer, never its raw base.")
    (example "(let ((l (Lexer make (list (Lexer skip \" \") (Lexer run 'word (list (pair 97 122)) (list (pair 97 122))))))) (l read-str \"ab c\"))" "((word \"ab\") (word \"c\"))"))
  (doc (rules ()) "The rules the base is built from, in priority order")
  (doc (raw ()) "The raw tokenizer base, or nil between an image write and its load")
  (doc (states ()) "Every state installed on the base -- the compiled ones as native code, the rest as closures; held so the collector keeps them")
  (doc (compiled 0) "How many states the assembler lane compiled in the last make; 0 when the lane is closed")
  (doc (end " ") "Text appended to every read, so the last token meets a delimiter: a token is only read once a character ends it, and the engine drops an unterminated tail. One space by default; a C lexer wants a newline, which also ends a last line comment")

  (method read-str (self (param s STRING "Text to tokenize"))
    (doc "The tokens of s, in order, each (tag text) or (tag text label); dropped tokens (skip, an until rule with no tag) do not appear. The end text (a space unless set) is appended first, so the last token is seen."
      (returns LIST "The token list, nil for empty input")
      (example "(l read-str \"a b\")" "((word \"a\") (word \"b\"))"))
    ((Lexer %read-str) (self %base) (Str8 append s (self end))))

  (method %base (self)
    (if (null? (self raw)) (self remake!) (self raw)))

  (method remake! (self)
    (doc "Make the base and its states again from the rules -- what the recache hook does after an image load; a consumer never needs to call it."
      (returns ANY "The raw base"))
    (self states ())
    (self compiled 0)
    (self raw (Base raw-of (Base make-tok)))
    (Lexer %install! self (self rules))
    (self raw))

  (static
    ; --- the catalogue doors, fetched once at load ------------------------------
    (%read-str (prim-ref (lit tok) (lit read-str)))
    (%buffer-token (prim-ref (lit buf) (lit tok)))
    (%transient! (prim-ref (lit image) (lit transient!)))
    (%recache-hook! (prim-ref (lit image) (lit recache-hook!)))
    (%char->int (prim-ref (lit char) (lit ->int)))
    (%byte-ref (prim-ref (lit str) (lit byte-ref)))
    (%byte-len (prim-ref (lit str) (lit byte-len)))
    ; Is the assembler lane open?  Probed by one state in the form every state
    ; takes; probed again after an image load, when the compiler has its
    ; addresses back.
    (%jit-cell (pair () ()))
    (%skip-count (pair 0 ()))

    (method make (self (param rules LIST "Rules in priority order, each from run, skip, table, quoted, until or number"))
      (doc "A lexer over rules: a tokenizer base with one type a rule, its states compiled where the lane allows."
        (returns Lexer "The lexer")
        (example "(Lexer make (list (Lexer skip \" \\n\") (Lexer number 'num ()) (Lexer run 'id \"abc\" \"abc\")))" "a lexer of numbers and words"))
      (let ((raw ()) (states ()) (compiled 0) (end " "))
        (def l (new Lexer rules rules raw raw states states compiled compiled end end))
        (l remake!)
        ((Lexer %transient!) (fn (_) (l raw ()) (l states ())))
        ((Lexer %recache-hook!) (fn (_) (Lexer %jit-probe!) (l remake!)))
        l))

    (method %jit-probe! (self)
      (%set-first! (Lexer %jit-cell)
        (guard (_ #f)
          (do (compile-asm (lit (fn (me buffer score chr) (if (= chr 32) me k)))
                           (list (pair (lit k) 1)) #t)
              #t))))

    (method %jit? (self)
      (if (null? (first (Lexer %jit-cell)))
        (do (Lexer %jit-probe!) (first (Lexer %jit-cell)))
        (first (Lexer %jit-cell))))

    ; --- rules --------------------------------------------------------------
    ; A rule is (kind name tag . args); %install! builds each one's states.

    (method run (self (param tag SYMBOL "The token's tag")
                      (param first LIST "Class of the first character")
                      (param rest LIST "Class of every following character"))
      (doc "A rule for a run of characters: one of first, then any number of rest. Identifiers, words."
        (returns LIST "The rule")
        (example "(Lexer run 'id (list (pair 97 122) 95) (list (pair 97 122) (pair 48 57) 95))" "C-style identifiers"))
      (list (lit run) (Str8 str tag) tag first rest))

    (method skip (self (param class LIST "Class of the characters to drop"))
      (doc "A rule that drops a run of characters: whitespace."
        (returns LIST "The rule")
        (example "(Lexer skip \" \\t\\n\")" "drop blanks and newlines"))
      (%set-first! (Lexer %skip-count) (+ 1 (first (Lexer %skip-count))))
      (list (lit skip) (Str8 append "SKIP-" (%number->str (first (Lexer %skip-count)))) () class))

    (method table (self (param tag SYMBOL "The token's tag")
                        (param strings LIST "The literal strings to match"))
      (doc "A rule for a table of literals, longest match: operators, keywords."
        (returns LIST "The rule")
        (example "(Lexer table 'op (list \"<\" \"<<\" \"<<=\"))" "three operators, the longest present wins"))
      (list (lit table) (Str8 str tag) tag strings))

    (method quoted (self (param tag SYMBOL "The token's tag")
                         (param open INTEGER "The opening byte")
                         (param close INTEGER "The closing byte")
                         (param esc ANY "The escape byte, or nil for none"))
      (doc "A rule for a quoted literal: open, a body in which esc takes the next byte literally, close. The token's text is the raw literal with its quotes; decoding escapes is the reader's work, done once per token rather than per character."
        (returns LIST "The rule")
        (example "(Lexer quoted 'str 34 34 92)" "a C string literal"))
      (list (lit quoted) (Str8 str tag) tag open close esc))

    (method until (self (param tag ANY "The token's tag, or nil to drop the token")
                        (param open STRING "The opening literal")
                        (param close STRING "The closing literal, one or two bytes"))
      (doc "A rule for a span from open to close: comments. A one-byte close is left for the next token (a newline ends a line comment and is then read on its own); a two-byte close is taken."
        (returns LIST "The rule")
        (example "(Lexer until () \"/*\" \"*/\")" "drop block comments"))
      (list (lit until) (if (null? tag) "UNTIL" (Str8 str tag)) tag open close))

    (method number (self (param tag SYMBOL "The token's tag")
                         (param suffix LIST "Class of suffix bytes taken after the digits, or nil"))
      (doc "A rule for a number: decimal digits, an optional fraction and exponent, or 0x and hex digits; then any bytes of suffix. The token carries a label: 1 integer, 2 fraction or exponent, 3 hex."
        (returns LIST "The rule")
        (example "(Lexer number 'num \"uUlL\")" "C integer and floating literals"))
      (list (lit number) (Str8 str tag) tag suffix))

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
      ; a bare string is the class of its bytes
      (let ((ts (tests (if (str? class) (list class) class) ())))
        (if (null? ts) (lit (= chr -1))
          (if (null? (rest ts)) (first ts) (pair (lit or) ts)))))

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

    (method %state (self l form fvars)
      (def made
        (if (Lexer %jit?)
          (guard (_ ())
            (compile-asm form fvars #t))
          ()))
      (def st
        (if (null? made)
          (eval (Lexer %subst form fvars) (Lexer %env))
          (do (l compiled (+ 1 (l compiled))) made)))
      (l states (pair st (l states)))
      st)

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

    (method %run-states (self l first rest)
      (let ((body (Lexer %state l
                    (Lexer %state-form
                      (list (lit if) (Lexer %class-form rest) (lit me) (Lexer %accept)))
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

    (%fvar-names (lit (a b c d e f g h i j k l m n o p q r s t u v w x y z)))

    (method %trie-state (self l node)
      (def kids
        ((fn (self ks acc)
           (if (null? ks) acc
             (self (rest ks) (pair (pair (first (first ks)) (Lexer %trie-state l (rest (first ks)))) acc))))
         (rest node) ()))
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
          (dispatch kids (Lexer %fvar-names) (if (first node) (Lexer %accept) ())))
        (fvars kids (Lexer %fvar-names) ())))

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
          ; The escape state needs the body and the body the escape state.
          ; The escape is interpreted and rare: it takes its byte and answers
          ; the body through a cell filled below, as x-python's does.
          (let ((after (fn (_ buffer score chr) (first body-cell))))
            (l states (pair after (l states)))
            (Lexer %state l
              (Lexer %state-form
                (list (lit if) (list (lit =) (lit chr) (Lexer %code close)) (Lexer %take)
                  (list (lit if) (list (lit =) (lit chr) (Lexer %code esc)) (lit esc) (lit me))))
              (list (pair (lit esc) after))))))
      (%set-first! body-cell body)
      (Lexer %state l
        (Lexer %state-form
          (list (lit if) (list (lit =) (lit chr) (Lexer %code open)) (lit body) ()))
        (list (pair (lit body) body))))

    ; A span from open to close.  Open is matched byte by byte through a
    ; chain of states; the body loops until the close's first byte, and a
    ; two-byte close confirms its second byte before taking the token.
    (method %until-states (self l tag open close)
      (def c0 ((Lexer %char->int) ((Lexer %byte-ref) close 0)))
      (def two? (> ((Lexer %byte-len) close) 1))
      (def end-unread (if (null? tag) (Lexer %drop) (Lexer %accept)))
      (def body-cell (pair () ()))
      (def body
        (if two?
          (let ((c1 ((Lexer %char->int) ((Lexer %byte-ref) close 1))))
            ; The state after the close's first byte needs the body back on a
            ; miss, and the body needs it: interpreted and rare, it answers
            ; the body through the cell, as the escape state above does.
            (def second
              (if (null? tag)
                (fn (me buffer score chr)
                  (if (= chr c1) (%score-set score -1 buffer)
                    (if (= chr c0) me (first body-cell))))
                (fn (me buffer score chr)
                  (if (= chr c1) (%score-set score 1 buffer)
                    (if (= chr c0) me (first body-cell))))))
            (l states (pair second (l states)))
            (Lexer %state l
              (Lexer %state-form
                (list (lit if) (list (lit =) (lit chr) c0) (lit second) (lit me)))
              (list (pair (lit second) second))))
          (Lexer %state l
            (Lexer %state-form
              (list (lit if) (list (lit =) (lit chr) c0) end-unread (lit me)))
            ())))
      (%set-first! body-cell body)
      ; the open chain, last byte first
      ((fn (self i next)
         (if (< i 0) next
           (self (- i 1)
             (Lexer %state l
               (Lexer %state-form
                 (list (lit if) (list (lit =) (lit chr) ((Lexer %char->int) ((Lexer %byte-ref) open i))) (lit next) ()))
               (list (pair (lit next) next))))))
       (- ((Lexer %byte-len) open) 1) body))

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

    ; --- installing ---------------------------------------------------------
    ; The read handler of a tagged rule: (tag text), with the label when one
    ; was declared.  A rule with no tag has no read handler, and its tokens
    ; are dropped.
    ; The door is captured outside the closure: a static read is a class
    ; dispatch, and this runs once a token.
    (method %reader (self tag labelled?)
      (let ((tok (Lexer %buffer-token)))
        (if labelled?
          (fn (_ . args) (list tag (tok (first args)) (%read-label args)))
          (fn (_ . args) (list tag (tok (first args)))))))

    (method %handlers (self l rule)
      (def kind (first rule))
      (def tag (first (rest (rest rule))))
      (def args (rest (rest (rest rule))))
      (def entry
        (match
          ((eq? kind (lit run)) (Lexer %run-states l (first args) (first (rest args))))
          ((eq? kind (lit skip)) (Lexer %skip-states l (first args)))
          ((eq? kind (lit table)) (Lexer %table-states l (first args)))
          ((eq? kind (lit quoted)) (Lexer %quoted-states l (first args) (first (rest args)) (first (rest (rest args)))))
          ((eq? kind (lit until)) (Lexer %until-states l tag (first args) (first (rest args))))
          ((eq? kind (lit number)) (Lexer %number-states l (first args)))
          (#t (Err raise (lit lexer) "Lexer: unknown rule kind" kind))))
      (if (null? tag)
        (list (pair (lit analyse) entry))
        (list (pair (lit analyse) entry)
              (pair (lit read) (Lexer %reader tag (eq? kind (lit number)))))))

    ; Register in list order: the type registered first wins a tie.
    (method %install! (self l rules)
      (if (null? rules) ()
        (do
          (Base make-type (l raw) (first (rest (first rules))) (Lexer %handlers l (first rules)))
          (Lexer %install! l (rest rules)))))))

(doc (provide x/reader/lexer Lexer)
  (note "Rules are data: run, skip, table, quoted, until, number. (Lexer make rules) builds the base; (l read-str s) reads.")
  (note "Every analyser state is one form, compiled through compile-asm when the lane is open and evaluated as the interpreted twin otherwise; the base is remade after an image load.")
  "Tokenizer bases from data rules, with compiled analysers.")
