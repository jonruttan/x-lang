; tokens.x -- Shell token types for ash personality
;
; Each type is registered on a separate base via base-make-type.
; The shell base has its own type-alist, isolating shell token types
; from sexp types (which would conflict: ; is sexp comment vs shell
; separator, # is sexp dispatch vs shell comment, etc.).
;
; Token types: sh-whitespace, sh-newline, sh-comment, sh-operator,
;              sh-sq-string, sh-dq-string, sh-word
;
; Usage:
;   (def tokens (sh-tokenize "echo hello | grep h"))
;   ; -> ((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))
; --- Create shell tokenizer base (bare, no sexp types) ---

(def %sh-base (make-token-base))
; --- Intrinsic scoring helpers ---
;
; These wrap the generic integer accessor/mutator primitives for
; the tokenizer protocol. Scripts follow the same protocol as
; C-level analysers: consume chars, un-read delimiter, set score
; and reader on p_score, return p_score.
;
; Buffer layout: (val . (read . write)) — all char pointers.
; Score layout:  (int-score . reader) — raw int + object pointer.

(def buffer-len
  (fn (buffer)
    (- (first-int (rest buffer)) (first-int buffer))))

(def buffer-unread
  (fn (buffer)
    (set-first-int
      (rest buffer)
      (- (first-int (rest buffer)) 1))))

(def score-set
  (fn (score sign buffer)
    (set-first-int score (* sign (buffer-len buffer)))))
; --- Helpers ---
; Predicate: is chr a shell whitespace (space or tab, NOT newline)?

(def %sh-ws?
  (fn (c)
    (or
      (= c (char->integer #\space))
      (= c (char->integer #\tab)))))
; Predicate: is chr a shell operator start character?
; | & ; < > ( )

(def %sh-op-start?
  (fn (c)
    (or
      (= c (char->integer #\|))
      (= c (char->integer #\&))
      (= c (char->integer #\;))
      (= c (char->integer #\<))
      (= c (char->integer #\>))
      (= c (char->integer #\())
      (= c (char->integer #\))))))
; Predicate: is chr a word-break character?
; whitespace, newline, operator-start, single-quote, double-quote, #

(def %sh-word-break?
  (fn (c)
    (or
      (%sh-ws? c)
      (= c (char->integer #\newline))
      (%sh-op-start? c)
      (= c (char->integer #\'))
      (= c (char->integer #\"))
      (= c (char->integer #\#)))))
; --- Token constructors ---

(def mk-tok-newline (fn () (list (lit tok-newline))))

(def mk-tok-op (fn (s) (list (lit tok-op) s)))

(def mk-tok-word (fn (s) (list (lit tok-word) s)))

(def mk-tok-sq (fn (s) (list (lit tok-sq) s)))

(def mk-tok-dq (fn (s) (list (lit tok-dq) s)))
; --- Shared reader: extract consumed text as word token ---

(def %sh-word-reader
  (fn args (mk-tok-word (buffer-token (first args)))))
; --- sh-whitespace: spaces/tabs (discarded, negative/greedy) ---

(def %sh-ws-continue ())

(set %sh-ws-continue
  (fn (buffer score chr)
    (if (%sh-ws? chr)
      %sh-ws-continue
      (do
        (buffer-unread buffer)
        (score-set score (- 0 1) buffer)))))

(base-make-type
  %sh-base
  "SH-WS"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (%sh-ws? chr)
          (do (score-set score (- 0 1) buffer) %sh-ws-continue)
          ())))))
; --- sh-newline: \n as a token (positive/deterministic) ---

(def %sh-nl-read (fn args (mk-tok-newline)))

(base-make-type
  %sh-base
  "SH-NL"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\newline))
          (score-set score 1 buffer)
          ())))
    (pair (lit read) %sh-nl-read)))
; --- sh-comment: # to end of line (discarded, negative/greedy) ---

(def %sh-comment-body ())

(set %sh-comment-body
  (fn (buffer score chr)
    (if (= chr (char->integer #\newline))
      (do
        (buffer-unread buffer)
        (score-set score (- 0 1) buffer))
      %sh-comment-body)))

(base-make-type
  %sh-base
  "SH-COMMENT"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\#))
          (do (score-set score (- 0 1) buffer) %sh-comment-body)
          ())))))
; --- sh-operator: single and multi-character operators (positive) ---
;
; Single: | & ; < > ( )
; Double: || && ;; << >> <& >& <> >|
; Triple: <<-
;
; Uses buffer-token to extract the operator string.

(def %sh-op-reader
  (fn args (mk-tok-op (buffer-token (first args)))))
; Check for triple operator <<-

(def %sh-op-triple
  (fn (c1 c2)
    (fn (buffer score chr)
      (if (and
            (= c1 (char->integer #\<))
            (= c2 (char->integer #\<))
            (= chr (char->integer #\-)))
        (score-set score 1 buffer)
        (do (buffer-unread buffer) (score-set score 1 buffer))))))
; Check for double operators

(def %sh-op-double
  (fn (c1)
    (fn (buffer score chr)
      (match
        ; Same char doubled: ||, &&, ;;, <<, >>

        ((= chr c1)
          (if (or (= c1 (char->integer #\<)) (= c1 (char->integer #\>)))
            ; < or > can extend to triple

            (do
              (score-set score 1 buffer)
              (%sh-op-triple c1 (+ chr 0)))
            (score-set score 1 buffer)))
        ; <& or >&

        ((and
           (or (= c1 (char->integer #\<)) (= c1 (char->integer #\>)))
           (= chr (char->integer #\&)))
          (score-set score 1 buffer))
        ; <> (c1 = <, chr = >)

        ((and
           (= c1 (char->integer #\<))
           (= chr (char->integer #\>)))
          (score-set score 1 buffer))
        ; >| (c1 = >, chr = |)

        ((and
           (= c1 (char->integer #\>))
           (= chr (char->integer #\|)))
          (score-set score 1 buffer))
        ; Not a double — un-read, score the single

        (#t (do (buffer-unread buffer) (score-set score 1 buffer)))))))

(base-make-type
  %sh-base
  "SH-OP"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (%sh-op-start? chr)
          ; ( and ) are always single-char

          (if (or
                (= chr (char->integer #\())
                (= chr (char->integer #\))))
            (score-set score 1 buffer)
            (do (score-set score 1 buffer) (%sh-op-double (+ chr 0))))
          ())))
    (pair (lit read) %sh-op-reader)))
; --- sh-sq-string: single-quoted strings (positive) ---
;
; Everything between ' and ' is literal (no escapes).
; Accumulates chars into a list; score is computed from bufferlen.

(def %sh-sq-read-data ())

(def %sh-sq-read (fn args (mk-tok-sq %sh-sq-read-data)))

(def %sh-sq-body ())

(set %sh-sq-body
  (fn (acc)
    (fn (buffer score chr)
      (if (= chr (char->integer #\'))
        (do
          (set %sh-sq-read-data (list->string (reverse acc)))
          (score-set score 1 buffer))
        (%sh-sq-body (pair (integer->char (+ chr 0)) acc))))))

(base-make-type
  %sh-base
  "SH-SQ"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\')) (%sh-sq-body ()) ())))
    (pair (lit read) %sh-sq-read)))
; --- sh-dq-string: double-quoted strings (positive) ---
;
; Phase 1: treat $expansions as literal text (no expansion).
; Handles backslash escapes for: $ ` " \ newline

(def %sh-dq-escape ())

(def %sh-dq-body ())

(set %sh-dq-escape
  (fn (acc)
    (fn (buffer score chr)
      (match
        ; Escapable characters inside double quotes: $ ` " \ newline

        ((or
           (= chr (char->integer #\$))
           (= chr (char->integer #\`))
           (= chr (char->integer #\"))
           (= chr (char->integer #\\))
           (= chr (char->integer #\newline)))
          (%sh-dq-body (pair (integer->char (+ chr 0)) acc)))
        ; Not escapable: keep the backslash and the character

        (#t
          (%sh-dq-body
            (pair (integer->char (+ chr 0)) (pair #\\ acc))))))))

(def %sh-dq-read-data ())

(def %sh-dq-read (fn args (mk-tok-dq %sh-dq-read-data)))

(set %sh-dq-body
  (fn (acc)
    (fn (buffer score chr)
      (match
        ; Closing quote

        ((= chr (char->integer #\"))
          (do
            (set %sh-dq-read-data (list->string (reverse acc)))
            (score-set score 1 buffer)))
        ; Backslash escape

        ((= chr (char->integer #\\)) (%sh-dq-escape acc))
        ; Regular character (including $, `, etc. — literal in Phase 1)

        (#t (%sh-dq-body (pair (integer->char (+ chr 0)) acc)))))))

(base-make-type
  %sh-base
  "SH-DQ"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (= chr (char->integer #\")) (%sh-dq-body ()) ())))
    (pair (lit read) %sh-dq-read)))
; --- sh-word: unquoted words (catch-all, negative/greedy) ---
;
; Accumulates characters until a word-break character.
; Uses negative score so other types take priority.
; Uses buffer-token to extract the word text.

(def %sh-word-body ())

(set %sh-word-body
  (fn (buffer score chr)
    (if (%sh-word-break? chr)
      (do
        (buffer-unread buffer)
        (score-set score (- 0 1) buffer))
      %sh-word-body)))

(base-make-type
  %sh-base
  "SH-WORD"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (not (%sh-word-break? chr))
          (do (score-set score (- 0 1) buffer) %sh-word-body)
          ())))
    (pair (lit read) %sh-word-reader)))
; --- INTEGER: pre-register with shell-compatible reader (positive) ---
;
; Arithmetic in analyse hooks auto-registers the INTEGER type on the
; token base. Pre-registering with a digit-matching state machine that
; produces tok-word tokens ensures digit sequences appear as shell words.
; For digit-starting mixed words (10abc), returns () to let SH-WORD handle.

(def %sh-digit?
  (fn (c)
    (and (>= c (char->integer #\0)) (<= c (char->integer #\9)))))

(def %sh-int-body ())

(set %sh-int-body
  (fn (buffer score chr)
    (match
      ((%sh-digit? chr) %sh-int-body)
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      (#t ()))))

(base-make-type
  %sh-base
  "INTEGER"
  (list
    (pair
      (lit analyse)
      (fn (buffer score chr)
        (if (%sh-digit? chr)
          (do (score-set score 1 buffer) %sh-int-body)
          ())))
    (pair (lit read) %sh-word-reader)))
; --- Convenience: tokenize a string ---

(def sh-tokenize
  (fn (input) (token-read-string %sh-base input)))
