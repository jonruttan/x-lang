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

(def turtle-forward
  (fn (_ n)
    (def dist (%as-float n))
    (def rad (%deg->rad %turtle-heading))
    (def nx (f+ %turtle-x (f* dist (fsin rad))))
    (def ny (f- %turtle-y (f* dist (fcos rad))))
    (set! %turtle-segments
      (pair (list %turtle-x %turtle-y nx ny %turtle-pen %turtle-heading)
            %turtle-segments))
    (set! %turtle-x nx)
    (set! %turtle-y ny)))

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

(def turtle-clearscreen
  (fn ()
    (set! %turtle-x (exact->inexact 0))
    (set! %turtle-y (exact->inexact 0))
    (set! %turtle-heading (exact->inexact 0))
    (set! %turtle-pen #t)
    (set! %turtle-segments ())))

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
(def %logo-block ())
(def logo-process-tokens ())

; Build the Logo tokenizer base.
; Starts from make-base (full types), removes SYMBOL, adds Logo types.
(def %logo-base
  (let ((base (make-base)))
    (def %cell (first (first (first (rest (first base))))))
    (def %sym-name (type-of (lit x)))
    ; Remove SYMBOL type — Logo words replace it
    (def %filter
      (fn (self al)
        (if (null? al) ()
          (if (eq? (first (first al)) %sym-name)
            (self (rest al))
            (pair (first al) (self (rest al)))))))
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

    base))

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

(def %logo-eval-tok
  (fn (_ tok)
    (if (type? tok %logo)
      (eval (str->symbol (first tok)))
      (if (type? tok %logo-block)
        tok
        (eval! tok)))))

(def %logo-consume-arg
  (fn (_ tokens)
    (if (null? tokens) (error "Expected argument")
      (pair (%logo-eval-tok (first tokens)) (rest tokens)))))

(set! logo-process-tokens
  (fn (_ tokens)
    (if (null? tokens) ()
      (let ((tok (first tokens))
            (remaining (rest tokens)))
        (if (type? tok %logo)
          (let ((word (first tok)))
            (def entry (%logo-lookup word))
            (if (null? entry)
              (logo-process-tokens remaining)
              (let ((arity (first (rest entry)))
                    (handler (first (rest (rest entry)))))
                (if (= arity 0)
                  (do (handler) (logo-process-tokens remaining))
                  (if (= arity 1)
                    (let ((r (%logo-consume-arg remaining)))
                      (handler (first r))
                      (logo-process-tokens (rest r)))
                    (if (str=? (str-upcase word) "REPEAT")
                      (let ((r1 (%logo-consume-arg remaining)))
                        (let ((r2 (%logo-consume-arg (rest r1))))
                          (def count (%as-int (first r1)))
                          (def block (first r2))
                          (def %rep
                            (fn (self i)
                              (if (> i 0)
                                (do
                                  (logo-process-tokens (first block))
                                  (self (- i 1)))
                                ())))
                          (%rep count)
                          (logo-process-tokens (rest r2))))
                      (if (str=? (str-upcase word) "TO")
                        (logo-process-to remaining)
                        (do
                          (error (str "Unknown special: " word))
                          (logo-process-tokens remaining)))))))))
          (logo-process-tokens remaining))))))

(def logo-process-to
  (fn (_ tokens)
    (if (null? tokens) (error "TO: expected name")
      (let ((name-tok (first tokens))
            (rest-toks (rest tokens)))
        (def name (str-upcase (first name-tok)))
        (def %read-params
          (fn (self params toks)
            (if (null? toks) (error "TO: expected [ body ]")
              (let ((tok (first toks)))
                (if (type? tok %logo-block)
                  (list params tok (rest toks))
                  (self (pair (first tok) params) (rest toks)))))))
        (def result (%read-params () rest-toks))
        (def param-names (reverse (first result)))
        (def body (first (rest result)))
        (def remaining (first (rest (rest result))))
        (def proc
          (fn logo-user-proc args
            (def %bind-params
              (fn (self names vals)
                (if (null? names) ()
                  (do
                    (eval (list (lit def)
                      (str->symbol (first names))
                      (list (lit lit) (first vals))))
                    (self (rest names) (rest vals))))))
            (%bind-params param-names args)
            (logo-process-tokens (first body))))
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
; Logo REPL — tokenizes with the Logo base, executes on the main base
; ============================================================

(def %logo-prompt "? ")
(def %logo-on-exit ())

(def logo-repl
  (op ()
    ()
    (display %logo-prompt)
    (def line (%read-line))
    (if (null? line)
      ; EOF — call exit handler if set
      (if (null? %logo-on-exit) () (%logo-on-exit))
      (do
        (if (str=? line "") ()
          (guard (err
              (%stderr "Error: ")
              (%stderr (if (str? err) err
                        (if (number? err) (number->str err)
                          (symbol->str err))))
              (%stderr "\n"))
            (def tokens (token-read-string %logo-base (str line " ")))
            (logo-process-tokens tokens)))
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
