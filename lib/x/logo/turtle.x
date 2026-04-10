; turtle.x -- Logo turtle graphics interpreter
;
; Creates a separate Logo tokenizer base with only the types Logo needs:
; integers, whitespace, comments, Logo words, and brackets. No symbol type.
; The main x-lang base is untouched — Logo tokenization uses the Logo base,
; execution uses the main base.

(import x/num/float)
(import x/sys/token)
(import x/type/string)

; ============================================================
; Turtle state
; ============================================================

(def %turtle-x (exact->inexact 0))
(def %turtle-y (exact->inexact 0))
(def %turtle-heading (exact->inexact 0))
(def %turtle-pen #t)
(def %turtle-segments ())

(def %deg->rad
  (fn (_ deg)
    (f/ (f* (if (float? deg) deg (exact->inexact deg)) %pi)
        (exact->inexact 180))))

(def %as-float
  (fn (_ n) (if (float? n) n (exact->inexact n))))

(def %as-int
  (fn (_ n) (if (float? n) (inexact->exact n) n)))

; ============================================================
; Turtle movement
; ============================================================

; Hook called after each new segment — set by server for append-only writes
(def %turtle-on-segment ())

(def turtle-forward
  (fn (_ n)
    (def dist (%as-float n))
    (def rad (%deg->rad %turtle-heading))
    (def nx (f+ %turtle-x (f* dist (fsin rad))))
    (def ny (f- %turtle-y (f* dist (fcos rad))))
    (def seg (list %turtle-x %turtle-y nx ny %turtle-pen %turtle-heading))
    (set! %turtle-segments (pair seg %turtle-segments))
    (set! %turtle-x nx)
    (set! %turtle-y ny)
    (if (null? %turtle-on-segment) () (%turtle-on-segment seg))))

(def turtle-back
  (fn (_ n) (turtle-forward (- n))))

(def %update-last-heading
  (fn ()
    (if (null? %turtle-segments) ()
      (set-first!
        (rest (rest (rest (rest (rest (first %turtle-segments))))))
        %turtle-heading))))

(def turtle-right
  (fn (_ n)
    (set! %turtle-heading (f+ %turtle-heading (%as-float n)))
    (%update-last-heading)))

(def turtle-left
  (fn (_ n)
    (set! %turtle-heading (f- %turtle-heading (%as-float n)))
    (%update-last-heading)))

(def turtle-penup   (fn () (set! %turtle-pen #f)))
(def turtle-pendown (fn () (set! %turtle-pen #t)))

(def %turtle-on-clear ())

(def turtle-clearscreen
  (fn ()
    (set! %turtle-x (exact->inexact 0))
    (set! %turtle-y (exact->inexact 0))
    (set! %turtle-heading (exact->inexact 0))
    (set! %turtle-pen #t)
    (set! %turtle-segments ())
    (if (null? %turtle-on-clear) () (%turtle-on-clear))))

; ============================================================
; Logo tokenizer base
; ============================================================
; A separate base with only Logo-relevant types.
; No symbol type — Logo words are the sole identifier type.

(def %logo-block-close (pair (lit logo-block-close) ()))

(def %logo-alpha?
  (fn (_ chr)
    (if (and (>= chr 65) (<= chr 90)) #t
      (if (and (>= chr 97) (<= chr 122)) #t #f))))

(def %logo-word-continue
  (fn (self buffer score chr)
    (if (if (%logo-alpha? chr) #t
          (if (= chr 46) #t
            (if (and (>= chr 48) (<= chr 57)) #t #f)))
      self
      (token-accept buffer score chr))))

(def %logo ())
(def %logo-indent ())
(def %logo-block ())
(def logo-process-tokens ())
(def logo-process-to ())

; Detect whitespace type: has delimit handler, no read handler
(def %is-ws-type?
  (fn (_ entry)
    (def io (type-io (rest entry)))
    ; IO: (analyse-cell (delimit-cell (read-cell ...)))
    (def delimit (first (first (rest io))))
    (def read-h (first (first (rest (rest io)))))
    (if (null? delimit) #f (null? read-h))))

; Build the Logo tokenizer base.
; Starts from make-base (full types), removes SYMBOL and WHITESPACE,
; adds Logo-specific types including indent-aware whitespace.
(def %logo-base
  (let ((base (make-base)))
    (def %cell (first (first (first (rest (first base))))))
    (def %sym-name (type-of (lit x)))
    ; Remove SYMBOL and WHITESPACE types
    (def %filter
      (fn (self al)
        (if (null? al) ()
          (if (eq? (first (first al)) %sym-name)
            (self (rest al))
            (if (%is-ws-type? (first al))
              (self (rest al))
              (pair (first al) (self (rest al))))))))
    (set-first! %cell (%filter (first %cell)))

    ; Register Logo types on the new base
    (set! %logo-block
      (base-make-type base "LOGO-BLOCK"
        (list
          (pair (lit write) (fn (_ self) (display "[ ... ]")))
          (pair (lit eval) (fn (_ self) (logo-process-tokens (first self)))))))

    (base-make-type base "LOGO-CLOSE"
      (list
        (pair (lit first-chars) "]")
        (pair (lit analyse)
          (make-char-state (char->integer #\]) token-accept ()))
        (pair (lit read) (fn (_ . args) %logo-block-close))))

    (base-make-type base "LOGO-OPEN"
      (list
        (pair (lit first-chars) "[")
        (pair (lit analyse)
          (make-char-state (char->integer #\[) token-accept ()))
        (pair (lit read)
          (fn (_ . args)
            (def buf (first args))
            (def %rb
              (fn (self acc)
                (def tok (token-read buf))
                (if (null? tok)
                  (make-instance %logo-block (reverse acc))
                  (if (eq? tok %logo-block-close)
                    (make-instance %logo-block (reverse acc))
                    (self (pair tok acc))))))
            (%rb ())))))

    (set! %logo
      (base-make-type base "LOGO"
        (list
          (pair (lit first-chars) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
          (pair (lit analyse)
            (fn (_ buffer score chr)
              (if (%logo-alpha? chr) %logo-word-continue ())))
          (pair (lit read)
            (fn (_ . args)
              (make-instance %logo (buffer-token (first args)))))
          (pair (lit write)
            (fn (_ self) (display (first self)))))))

    ; LOGO-WS: spaces and tabs only (not newlines), discard
    (base-make-type base "LOGO-WS"
      (list
        (pair (lit analyse)
          (fn (self buffer score chr)
            (if (if (= chr 32) #t (= chr 9))  ; space or tab
              self
              (if (> (- (buffer-len buffer) 1) 0)
                (do (buffer-unread buffer)
                    (score-set score 1 buffer))
                ()))))
        (pair (lit delimit)
          (fn (_ buffer score chr)
            (if (if (= chr 32) #t (= chr 9))
              (do (buffer-unread buffer) buffer)
              ())))))

    ; LOGO-NEWLINE: bare newline (discard). Matches \n not followed by
    ; indent+word (those are handled by LOGO-INDENT which scores higher).
    (base-make-type base "LOGO-NEWLINE"
      (list
        (pair (lit first-chars) "\n")
        (pair (lit analyse)
          (make-char-state 10 token-accept ()))))

    ; LOGO-INDENT: \n + spaces/tabs + word → indented Logo word
    ; Scores higher than LOGO-NEWLINE (longer match) when a word follows.
    (def %indent-after-nl
      ; State: consuming spaces/tabs after newline
      (fn (self buffer score chr)
        (if (if (= chr 32) #t (= chr 9))
          self  ; more whitespace
          (if (%logo-alpha? chr)
            %logo-word-continue  ; transition to word matching
            ; No word — fail (LOGO-NEWLINE will handle bare newline)
            ()))))

    (set! %logo-indent
      (base-make-type base "LOGO-INDENT"
        (list
          (pair (lit first-chars) "\n")
          (pair (lit analyse)
            (fn (_ buffer score chr)
              (if (= chr 10) %indent-after-nl ())))
          (pair (lit read)
            (fn (_ . read-args)
              (def text (buffer-token (first read-args)))
              ; text = "\n    WORD" — count indent, extract word
              (def len (str-length text))
              (def %count-indent
                (fn (self i)
                  (if (>= i len) i
                    (if (if (char=? (text i) #\space) #t
                          (char=? (text i) #\tab))
                      (self (+ i 1))
                      i))))
              (def indent-end (%count-indent 1))  ; skip \n at pos 0
              (def indent (- indent-end 1))       ; indent level
              (def word (substring text indent-end len))
              (make-instance %logo-indent (pair indent word))))
          (pair (lit write)
            (fn (_ self)
              (display (first (rest (first self))))  ; word part
              )))))

    base))

; Tag for blocks created by the indent pre-processor (can't use make-instance
; on the main base for types registered on the Logo base).
(def %indent-block-tag (pair (lit indent-block) ()))

(def %is-block?
  (fn (_ tok)
    (if (type? tok %logo-block) #t
      (if (pair? tok) (eq? (first tok) %indent-block-tag) #f))))

(def %block-contents
  (fn (_ tok)
    (if (type? tok %logo-block) (first tok)
      (rest tok))))  ; tagged pair: (tag . contents)

(def %make-indent-block
  (fn (_ tokens)
    (pair %indent-block-tag tokens)))

; ============================================================
; Command dispatch (token-list based)
; ============================================================

(def %logo-commands
  (list
    (list "FORWARD" 1 (fn (_ n) (turtle-forward n)))
    (list "FD"      1 (fn (_ n) (turtle-forward n)))
    (list "BACK"    1 (fn (_ n) (turtle-back n)))
    (list "BK"      1 (fn (_ n) (turtle-back n)))
    (list "RIGHT"   1 (fn (_ n) (turtle-right n)))
    (list "RT"      1 (fn (_ n) (turtle-right n)))
    (list "LEFT"    1 (fn (_ n) (turtle-left n)))
    (list "LT"      1 (fn (_ n) (turtle-left n)))
    (list "PENUP"   0 (fn () (turtle-penup)))
    (list "PU"      0 (fn () (turtle-penup)))
    (list "PENDOWN" 0 (fn () (turtle-pendown)))
    (list "PD"      0 (fn () (turtle-pendown)))
    (list "CLEARSCREEN" 0 (fn () (turtle-clearscreen)))
    (list "CS"      0 (fn () (turtle-clearscreen)))
    (list "SETHEADING" 1 (fn (_ n) (set! %turtle-heading (%as-float n))))
    (list "SETH"    1 (fn (_ n) (set! %turtle-heading (%as-float n))))
    (list "HEADING" 0 (fn () %turtle-heading))
    (list "XCOR"    0 (fn () %turtle-x))
    (list "YCOR"    0 (fn () %turtle-y))
    (list "REPEAT"  -1 ())
    (list "TO"      -1 ())))

(def %logo-lookup
  (fn (_ word)
    (def uword (str-upcase word))
    (def %find
      (fn (self cmds)
        (if (null? cmds) ()
          (if (str=? uword (first (first cmds)))
            (first cmds)
            (self (rest cmds))))))
    (%find %logo-commands)))

; Logo variable stack — for procedure parameters (dynamic scoping)
(def %logo-vars ())

; Extract the word string from a Logo or Logo-indent token
(def %logo-word
  (fn (_ tok)
    (if (type? tok %logo) (first tok)
      (if (type? tok %logo-indent) (rest (first tok))
        ()))))

(def %logo-eval-tok
  (fn (_ tok)
    (def word (%logo-word tok))
    (if (null? word)
      (if (%is-block? tok)
        tok
        (eval! tok))
      ; Logo word — check variable stack, then x-lang env
      (let ((var (assoc word %logo-vars str=?)))
        (if (null? var)
          (eval (str->symbol word))
          (rest var))))))

(def %logo-consume-arg
  (fn (_ tokens)
    (if (null? tokens) (error "Expected argument")
      (pair (%logo-eval-tok (first tokens)) (rest tokens)))))

; Consume N arguments, return (args-list . remaining-tokens)
(def %logo-consume-n-args
  (fn (_ n tokens)
    (def %consume
      (fn (self i toks acc)
        (if (= i 0)
          (pair (reverse acc) toks)
          (let ((r (%logo-consume-arg toks)))
            (self (- i 1) (rest r) (pair (first r) acc))))))
    (%consume n tokens ())))

(set! logo-process-tokens
  (fn (_ tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens))
            (remaining (rest tokens)))
        (def word (%logo-word tok))
        (if (null? word)
          ; Non-word token — skip
          (logo-process-tokens remaining)
          ; Logo word (plain or indented) — dispatch
          (let ((entry (%logo-lookup word)))
            (if (null? entry)
              (logo-process-tokens remaining)
              (let ((arity (first (rest entry)))
                    (handler (first (rest (rest entry)))))
                (if (= arity 0)
                  (do (handler) (logo-process-tokens remaining))
                  (if (>= arity 1)
                    ; General N-arity: consume N args, call handler
                    (let ((result (%logo-consume-n-args arity remaining)))
                      (apply handler (first result))
                      (logo-process-tokens (rest result)))
                    (if (str=? (str-upcase word) "REPEAT")
                      (let ((r1 (%logo-consume-arg remaining)))
                        (let ((r2 (%logo-consume-arg (rest r1))))
                          (def count (%as-int (first r1)))
                          (def block (first r2))
                          (def %rep
                            (fn (self i)
                              (if (> i 0)
                                (do
                                  (logo-process-tokens (%block-contents block))
                                  (self (- i 1)))
                                ())))
                          (%rep count)
                          (logo-process-tokens (rest r2))))
                      (if (str=? (str-upcase word) "TO")
                        (logo-process-to remaining)
                        (do
                          (error (str "Unknown special: " word))
                          (logo-process-tokens remaining)))))))))))))))


(set! logo-process-to
  (fn (_ tokens)
    (if (null? tokens) (error "TO: expected name")
      (let ((name-tok (first tokens))
            (rest-toks (rest tokens)))
        (def name (str-upcase (%logo-word name-tok)))
        (def %read-params
          (fn (self params toks)
            (if (null? toks) (error "TO: expected [ body ]")
              (let ((tok (first toks)))
                (if (%is-block? tok)
                  (list params tok (rest toks))
                  (self (pair (%logo-word tok) params) (rest toks)))))))
        (def result (%read-params () rest-toks))
        (def param-names (reverse (first result)))
        (def body (first (rest result)))
        (def remaining (first (rest (rest result))))
        (def proc
          (fn (_ . logo-args)
            ; Push params onto Logo variable stack
            (def saved-vars %logo-vars)
            (def %push
              (fn (self names vals)
                (if (null? names) ()
                  (do
                    (set! %logo-vars
                      (pair (pair (first names) (first vals)) %logo-vars))
                    (self (rest names) (rest vals))))))
            (%push param-names logo-args)
            (logo-process-tokens (%block-contents body))
            ; Restore variable stack
            (set! %logo-vars saved-vars)))
        (set! %logo-commands
          (pair (list name (length param-names) proc) %logo-commands))
        (logo-process-tokens remaining)))))

; ============================================================
; Line reader
; ============================================================

(def %read-line
  (fn ()
    (def %rl
      (fn (self acc)
        (def ch (read-char))
        (if (null? ch)
          (if (null? acc) () (list->str (reverse acc)))
          (if (= ch 10)
            (list->str (reverse acc))
            (self (pair (integer->char ch) acc))))))
    (%rl ())))

; ============================================================
; Indent-to-blocks pre-processor
; ============================================================
; Converts indent tokens into LOGO-BLOCK instances so the existing
; logo-process-tokens handles them. Works by tracking indent level
; on a stack.

(def %logo-indent-to-blocks
  (fn (_ tokens)
    ; Stack entries: (indent-level . accumulated-tokens-reversed)

    ; Pop stack levels deeper than target, wrapping each in a block
    (def %pop-to
      (fn (self target stack)
        (if (null? (rest stack)) stack
          (if (<= (first (first stack)) target)
            stack
            (let ((top (first stack))
                  (parent (first (rest stack)))
                  (rest-stack (rest (rest stack))))
              (def block (%make-indent-block (reverse (rest top))))
              (self target
                (pair (pair (first parent) (pair block (rest parent)))
                      rest-stack)))))))

    ; Flush entire stack into nested blocks
    (def %flush-stack
      (fn (self stack)
        (if (null? (rest stack))
          (reverse (rest (first stack)))
          (let ((top (first stack))
                (parent (first (rest stack)))
                (rest-stack (rest (rest stack))))
            (def block (%make-indent-block (reverse (rest top))))
            (self (pair (pair (first parent) (pair block (rest parent)))
                        rest-stack))))))

    ; Walk tokens, collect into nested blocks based on indent level
    (def %process
      (fn (self toks stack)
        (if (null? toks)
          (%flush-stack stack)
          (let ((tok (first toks))
                (rest-toks (rest toks)))
            (if (type? tok %logo-indent)
              (let ((indent (first (first tok)))
                    (word (rest (first tok))))
                (def new-stack (%pop-to indent stack))
                (def top (first new-stack))
                (if (= (first top) indent)
                  ; Same level — add to current accumulator (keep indent token)
                  (self rest-toks
                    (pair (pair indent (pair tok (rest top)))
                          (rest new-stack)))
                  ; Deeper level — push new
                  (self rest-toks
                    (pair (pair indent (list tok)) new-stack))))
              (let ((top (first stack)))
                (self rest-toks
                  (pair (pair (first top) (pair tok (rest top)))
                        (rest stack)))))))))

    (%process tokens (list (pair 0 ())))))

; ============================================================
; Logo REPL — reads blocks, tokenizes, pre-processes indentation
; ============================================================

(def %logo-prompt "? ")
(def %logo-on-exit ())
(def %logo-on-command ())

; Read a block: accumulate lines until blank line or dedent to col 0
; after seeing indented lines.
(def %read-block
  (fn ()
    (def %rb
      (fn (self lines saw-indent)
        (def line (%read-line))
        (if (null? line)
          ; EOF
          (if (null? lines) () (apply str (reverse lines)))
          (if (str=? line "")
            ; Blank line — skip if no content yet, end block otherwise
            (if (null? lines)
              (self () #f)  ; Skip leading blank lines
              (apply str (reverse lines)))
            ; Non-empty line
            (let ((has-indent (if (char=? (line 0) #\space) #t
                               (if (char=? (line 0) #\tab) #t #f))))
              (if (if saw-indent #t #f)
                (if has-indent
                  ; Still indented — continue
                  (self (pair (str "\n" line) lines) #t)
                  ; Dedent to col 0 — end of block, include this line
                  (apply str (reverse (pair (str "\n" line) lines))))
                ; First line — check if it needs continuation
                (if has-indent
                  ; Indented line — accumulate
                  (self (pair (str "\n" line) lines) #t)
                  (if (null? lines)
                    ; First line, no indent — return immediately unless it's TO
                    (if (if (>= (str-length line) 3)
                          (str=? (str-upcase (substring line 0 3)) "TO ") #f)
                      (self (pair (str "\n" line) ()) #t)  ; TO needs body
                      (str "\n" line))  ; Single line — return now
                    (apply str (reverse (pair (str "\n" line) lines)))))))))))

    (%rb () #f)))

(def logo-repl
  (op ()
    ()
    (display %logo-prompt)
    (def block (%read-block))
    (if (null? block)
      ; EOF — call exit handler if set
      (if (null? %logo-on-exit) () (%logo-on-exit))
      (do
        (guard (err
            (%stderr "Error: ")
            (%stderr (if (str? err) err
                      (if (number? err) (number->str err)
                        (symbol->str err))))
            (%stderr "\n"))
          (def tokens (token-read-string %logo-base (str block " ")))
          (def processed (%logo-indent-to-blocks tokens))
          (logo-process-tokens processed)
          (if (null? %logo-on-command) () (%logo-on-command)))
        (logo-repl)))))

; ============================================================
; JSON output
; ============================================================

(def turtle-json
  (fn ()
    (display "[")
    (def segs (reverse %turtle-segments))
    (def %out
      (fn (self segs first?)
        (if (null? segs) ()
          (do
            (if first? () (display ","))
            (def s (first segs))
            (def x1 (first s))
            (def y1 (first (rest s)))
            (def x2 (first (rest (rest s))))
            (def y2 (first (rest (rest (rest s)))))
            (def pen (first (rest (rest (rest (rest s))))))
            (def hdg (first (rest (rest (rest (rest (rest s)))))))
            (display "\n{\"x1\":") (display x1)
            (display ",\"y1\":") (display y1)
            (display ",\"x2\":") (display x2)
            (display ",\"y2\":") (display y2)
            (display ",\"pen\":")
            (display (if pen "true" "false"))
            (display ",\"heading\":") (display hdg)
            (display "}")
            (self (rest segs) #f)))))
    (%out segs #t)
    (display "\n]\n")))

(def turtle-json-str
  (fn ()
    (def segs (reverse %turtle-segments))
    (def %seg-json
      (fn (_ s)
        (def x1 (write-to-str (first s)))
        (def y1 (write-to-str (first (rest s))))
        (def x2 (write-to-str (first (rest (rest s)))))
        (def y2 (write-to-str (first (rest (rest (rest s))))))
        (def pen (first (rest (rest (rest (rest s))))))
        (def hdg (write-to-str (first (rest (rest (rest (rest (rest s))))))))
        (str "{\"x1\":" x1
             ",\"y1\":" y1
             ",\"x2\":" x2
             ",\"y2\":" y2
             ",\"pen\":" (if pen "true" "false")
             ",\"heading\":" hdg "}")))
    (def %join
      (fn (self segs first?)
        (if (null? segs) ""
          (str (if first? "" ",\n")
               (%seg-json (first segs))
               (self (rest segs) #f)))))
    (str "[\n" (%join segs #t) "\n]\n")))

(provide x/logo/turtle
  turtle-forward turtle-back turtle-right turtle-left
  turtle-penup turtle-pendown turtle-clearscreen
  turtle-json turtle-json-str logo-repl logo-process-tokens
  %logo-base %logo %logo-on-exit)
