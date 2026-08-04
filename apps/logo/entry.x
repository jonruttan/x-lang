; entry.x -- the Logo ENTRY reader: the dialect's own grouping layer,
; driving the C tokenizer on the LIVE stream (#157).
;
; Architecture: the shared REPL protocol is only "read one unit", with
; three outcomes -- a token list, the clean-EOF marker, or a raise
; (truncation / STOP).  Everything Logo-specific about WHAT a unit is
; (lines, indentation, blank-line termination, the arity hold) lives
; HERE, in the dialect, never in shared machinery.
;
; All BLOCKING reads run inside %logo-base via the Base-eval door, so
; the type alist that tokenizes is Logo's, and the #90 EOF latch, the
; line counter, and EINTR effects land on %logo-base's OWN cells --
; the session base's stream state is never touched.  This module itself
; is plain x running on the session base (NOT inside x_token_read), so
; it is free of the reader-callback constraints.
;
; The byte scanner owns exactly the depth-0 INTER-TOKEN bytes: line
; starts (blank lines, indent runs, ; comments) and the spaces/tabs and
; newline between tokens.  No Logo token type consumes its trailing
; newline (types.x audit), so after every token the terminator byte is
; already buffered and the scanner classifies it without blocking.
; Tokens themselves always come from the real tokenizer -- the scanner
; never parses content.
(import logo/types)

; Fetch the plumbing prims from the catalog.
(def %entry-str-make (prim-ref 'str 'make))
(def %entry-buf-make (prim-ref 'buf 'make))
(def %entry-buf-reset-prim (prim-ref 'buf 'reset))
(def %entry-last-char (prim-ref 'buf 'last-char))
(def %entry-type? (prim-ref 'type '?))
(def %entry-obj-same? (prim-ref 'obj 'same?))

; ------------------------------------------------------------
; The stream buffer
; ------------------------------------------------------------
; Constructed here rather than reusing (Base make)'s 256-byte buffer:
; x_type_buffer_append is bounds-UNCHECKED, and the buffer size caps one
; token's unconsumed run.  The module-top def roots the backing string
; for the buffer view's lifetime (a buffer is a non-owning view).
(def %entry-buf-store (%entry-str-make 4096))
(def %entry-buf (%entry-buf-make %entry-buf-store))

; ------------------------------------------------------------
; Doors into %logo-base
; ------------------------------------------------------------
; The prim OBJECTS are bound into %logo-base's env and invoked there via
; Base eval, so the C functions run with p_base = %logo-base (the
; tokenizing type alist is selected by the C p_base argument alone; the
; read-args rest slot is vestigial).  Precedent:
; tests/x/specs/meta/printer.spec.md.
(Base bind %logo-base '%entry-door-tok (prim-ref 'tok 'read))
(Base bind %logo-base '%entry-door-byte (prim-ref 'buf 'read))
(Base bind %logo-base '%entry-door-buf %entry-buf)
; make-instance resolves the TYPE against the calling base's alist, so
; a session-side call with a logo type silently answers nil (the
; convert-silent-nil shape) -- instance SYNTHESIS goes through the door
; too.  Cross-base forms may reference ONLY symbols bound here: symbol
; interning is per-base, so a stock name like `lit` in a session-built
; form would not resolve inside %logo-base.
(Base bind %logo-base '%entry-door-mi (prim-ref 'type 'make-instance))
(Base bind %logo-base '%entry-door-indent %logo-indent)
(Base bind %logo-base '%entry-door-pair pair)

(def %entry-tok-form (list '%entry-door-tok '%entry-door-buf))
(def %entry-byte-form (list '%entry-door-byte '%entry-door-buf))

; Synthesize the LOGO-INDENT instance (k . word) inside %logo-base.
; k and word self-evaluate, so the built form needs no quoting.
(def %entry-synth-indent
  (fn (_ k word)
    (Base eval %logo-base
      (list '%entry-door-mi '%entry-door-indent
        (list '%entry-door-pair k word)))))

; One token from the live stream, tokenized by Logo's types.  nil means
; the stream ended (EOF, or an interrupted read via the EINTR latch).
(def %entry-read-tok (fn (_) (Base eval %logo-base %entry-tok-form)))

; One byte appended to the buffer (blocking); nil at stream end.  The
; byte value is then (buf last-char) -- a session-side cursor read.
(def %entry-read-byte
  (fn (_)
    (if (null? (Base eval %logo-base %entry-byte-form))
      ()
      (%entry-last-char %entry-buf))))

; ------------------------------------------------------------
; Cancel support for the REPL loop (provided)
; ------------------------------------------------------------
; %logo-base's OWN filein cell: the #90 latch a ctrl-c'd read poisons.
; Resolved per call -- filein is a chain with a cell per include.
(def %logo-filein-cell
  (fn (_) (%reflect-step %logo-base (%reflect-path (lit filein) %base-paths))))

; Drop everything unconsumed (a cancelled entry's partial line).
(def %logo-entry-flush (fn (_) (%entry-buf-reset-prim %entry-buf)))

; Clean-EOF marker: fresh pair, identity-compared with same? (never
; eq?, which compares value words).
(def %logo-eof (pair () ()))
(def %logo-entry-same? (fn (_ a b) (%entry-obj-same? a b)))

; ------------------------------------------------------------
; The arity hold (%entry-wants-block?)
; ------------------------------------------------------------
; After a column-0 line, hold the entry open for an indented body when
; the line CANNOT be complete: TO or REPEAT with no block token yet, a
; dangling THEN/ELSE, or IF with no THEN.  Conservative on purpose -- a
; wrong hold is escaped by the blank line, a wrong release would
; execute half an entry.
(def %entry-has-block?
  (fn (self toks)
    (match
      ((null? toks) #f)
      ((%is-block? (first toks)) #t)
      (#t (self (rest toks))))))

(def %entry-has-word?
  (fn (self toks kw)
    (match
      ((null? toks) #f)
      ((%logo-word=? (first toks) kw) #t)
      (#t (self (rest toks) kw)))))

(def %entry-last-tok
  (fn (self toks)
    (match
      ((null? toks) ())
      ((null? (rest toks)) (first toks))
      (#t (self (rest toks))))))

(def %entry-wants-block?
  (fn (_ toks)
    (match
      ((null? toks) #f)
      ((and (or (%entry-has-word? toks "TO")
                (%entry-has-word? toks "REPEAT"))
            (not (%entry-has-block? toks))) #t)
      ((%logo-word=? (%entry-last-tok toks) "THEN") #t)
      ((%logo-word=? (%entry-last-tok toks) "ELSE") #t)
      ((and (%entry-has-word? toks "IF")
            (not (%entry-has-word? toks "THEN"))) #t)
      (#t #f))))

; ------------------------------------------------------------
; The entry reader
; ------------------------------------------------------------
; Byte codes: 9 tab, 10 newline, 32 space, 59 semicolon.

; Consume bytes through the end of line.  #t = newline consumed,
; nil = the stream ended first.
(def %entry-skip-line
  (fn (self)
    (def b (%entry-read-byte))
    (match
      ((null? b) ())
      ((= b 10) #t)
      (#t (self)))))

; Scan a line start.  Returns (lit eof) | (lit blank) | (lit comment) |
; (pair k ()) with the first content byte UNREAD (k = indent count).
(def %entry-line-start
  (fn (self k)
    (def b (%entry-read-byte))
    (match
      ((null? b) (lit eof))
      ((= b 10) (lit blank))
      ((or (= b 32) (= b 9)) (self (+ k 1)))
      ((= b 59) (if (null? (%entry-skip-line)) (lit eof) (lit comment)))
      (#t (do (%buffer-unread %entry-buf) (pair k ()))))))

; The rest of a line's tokens after its first: consume inter-token
; spaces/tabs; a newline or a mid-line comment ends the line.  Blocking
; gaps here are bytes the user has already typed (tty line buffering
; delivers whole lines).  Raises on truncation: input that ends inside
; a line never executes.
(def %entry-line-toks
  (fn (self acc)
    (def b (%entry-read-byte))
    (match
      ((null? b) (error "Unterminated input"))
      ((= b 10) acc)
      ((or (= b 32) (= b 9)) (self acc))
      ((= b 59) (if (null? (%entry-skip-line)) (error "Unterminated input") acc))
      (#t
        (do
          (%buffer-unread %entry-buf)
          (def tok (%entry-read-tok))
          (if (if (null? tok) #t (eq? tok %logo-truncated))
            (error "Unterminated input")
            (self (pair tok acc))))))))

; One full line, given its indent k (first content byte pending).  The
; first token of a word-led line is re-shaped into the LOGO-INDENT
; instance the batch tokenizer would have produced -- (k . word), the
; fused token every dispatch consumer already understands -- because
; the scanner consumed the newline and indent bytes the analyser would
; have fused from.  Non-word-led lines carry no line marker, exactly
; like the batch path (%indent-after-nl rejects them).
(def %entry-read-line
  (fn (_ k)
    (def tok (%entry-read-tok))
    (if (if (null? tok) #t (eq? tok %logo-truncated))
      (error "Unterminated input")
      (do
        (def head
          (if (%entry-type? tok %logo)
            (%entry-synth-indent k (first tok))
            tok))
        (List reverse (%entry-line-toks (list head)))))))

(def %entry-prepend-rev
  (fn (self items acc)
    (match
      ((null? items) acc)
      (#t (self (rest items) (pair (first items) acc))))))

; The grammar (Logo's own, minus the dead execute-oracle):
;   blank line, nothing pending      -> keep waiting
;   blank line, entry open           -> entry ends (the escape hatch
;                                       if the arity hold is wrong)
;   comment line                     -> invisible
;   indented line                    -> joins the entry, stays open
;   column-0 line, nothing pending   -> the entry, ending AT ITS OWN
;     newline -- unless %entry-wants-block? holds it open
;   column-0 line, entry open        -> joins the entry, entry ends
;   stream end at a line start       -> %logo-eof if nothing pending,
;     else "Unterminated input"
(def %logo-read-entry
  (fn ()
    (def %loop
      (fn (self acc)
        (def start (%entry-line-start 0))
        (match
          ((eq? start (lit eof))
            (if (null? acc) %logo-eof (error "Unterminated input")))
          ((eq? start (lit blank))
            (if (null? acc) (self ()) (List reverse acc)))
          ((eq? start (lit comment)) (self acc))
          (#t
            (do
              (def k (first start))
              (def line (%entry-read-line k))
              (def acc2 (%entry-prepend-rev line acc))
              (match
                ((null? acc)
                  (if (if (> k 0) #t (%entry-wants-block? line))
                    (self acc2)
                    (List reverse acc2)))
                ((> k 0) (self acc2))
                (#t (List reverse acc2))))))))
    (%loop ())))

(provide logo/entry
  %logo-read-entry %logo-eof %logo-entry-same?
  %logo-filein-cell %logo-entry-flush)
