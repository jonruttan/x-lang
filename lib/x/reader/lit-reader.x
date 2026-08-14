; lit-reader.x -- quote (') reader macro, plus the wiring that places the
; quote family (lit / quasi / unquote) onto the symbol type.
;
;   'expr -> (lit expr)
;
; Loading last, this file assembles the symbol type's reader slots:
;   analyse: a list (lit quasi unquote <C symbol analyse>) the tokenizer
;            scores in turn -- the C symbol analyse is the catch-all tail.
;   read:    a list (lit quasi unquote <C symbol read>); each macro read
;            self-selects on its leading char and declines otherwise.
;   delimit: one combined handler so ' ` , terminate an adjacent token
;            (foo'bar reads as foo then 'bar).
;
; Requires: quasi-reader.x, intrinsics.x, str.x, char.x, x/type/struct.

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-last-char (prim-ref (lit buf) (lit last-char)))
(def %token-read (prim-ref (lit tok) (lit read)))

(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-analyse-cell (prim-ref (lit type) (lit analyse-cell)))
(def %type-push-analyse (prim-ref (lit type) (lit push-analyse)))
(def %type-read-cell (prim-ref (lit type) (lit read-cell)))
(def %type-push-delimit (prim-ref (lit type) (lit push-delimit)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))

(def %type-push-read (prim-ref (lit type) (lit push-read)))

(def %lit-accept
  (fn (_ buffer score _)
    (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))

(def %lit-analyse
  (fn (_ buffer score chr) (if (= chr #\') %lit-accept ())))

(def %lit-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) #\')
      (pair (lit lit) (pair (%token-read buffer) ()))
      ())))

; ' ` , each terminate an adjacent token.  Nested if (no cond/or) and no
; binding keep it allocation-free on the per-char delimiter path.
(def %macro-delimit
  (fn (_ buffer . rest)
    (if (if (= (%buffer-last-char buffer) #\') #t
          (if (= (%buffer-last-char buffer) #\`) #t
            (= (%buffer-last-char buffer) #\,)))
      (%seq (%buffer-unread buffer) buffer)
      ())))

; --- $"...{expr}..." string interpolation --------------------------------
; $"a{x}b" parses at READ time into the call (Str8 str "a" x "b"): the analyser
; scores the whole literal as one token and %interp-read splits it, emitting the
; call directly.  Each hole is thus a plain sub-expression that evaluates in
; place, in whatever env the literal sits in -- no eval-time wrapper, no
; operative needed for the caller's scope.
;
; The analyser is a state machine because a hole holds arbitrary code, and code
; contains characters that would otherwise end the token: a string inside a hole
; ($"{(join " " xs)}"), a nested literal ($"{$"{c}"}"), a #\" or #\} character
; literal.  Each state is a closure carrying the state to RESUME when the
; construct it opened closes, so nesting needs neither a depth counter nor any
; shared mutable state -- which matters because %interp-read re-enters the
; tokenizer for the holes, and shared analyser state would have to survive that.
; Allocating a state per construct is the protocol's supported path:
; x_token_analyse roots whatever handler a state returns ("Replace Analyser").
; Callback discipline holds inside every state body: primitive `if` only, never
; an op (docs/syntax.md, "reader-callback code").
;
; Parsing was once DEFERRED to eval time: the literal read as (%interp-str X), an
; op that re-tokenized the holes on every evaluation, to keep token-read-string
; out of the GC-sensitive tokenizer loop.  That rationale is now obsolete -- GC is
; explicit-only (pure allocators never collect), so re-entering the tokenizer from
; a reader handler is safe -- %interp-read does it for every hole and every
; literal chunk.  Do NOT move parsing back to eval time: besides re-parsing on every
; eval, token-read-string's tokenizer re-entry leaves the base's env register
; dirty, and an if-tail (TCO) position inherits that dirty env -- stranding a
; later interpolation's variable as Unbound.  Parsing at read time sidesteps it
; entirely (the env is never touched mid-evaluation).
; (display/str themselves live in boot/string.x and the Str8 class respectively.)
(def %str-append        (prim-ref (lit str)  (lit append)))
(def %token-read-string (prim-ref (lit tok)  (lit read-str)))
(def %buffer-token      (prim-ref (lit buf)  (lit tok)))

; The analyser, in two pieces like the rest of the quote family: the per-char
; entry test is its own def so the tower can compile it (boot/tower-compiled.x
; captures this state as a free variable), and the state machine it hands off to
; stays interpreted -- it only runs INSIDE a literal, never on the hot path of
; ordinary characters.
;
; %interp-after-dollar: a $ has been seen.  A " opens the literal and the scan
; runs to the quote that closes it; anything else declines, leaving a bare $ (or
; $foo) an ordinary symbol.
(def %interp-after-dollar
  (let ((mk-text ()) (mk-open ()) (mk-hole ()) (mk-str ()))
    ; Literal text.  `k` is the state to resume when this literal's closing
    ; quote arrives; nil for the outermost literal, which scores the token
    ; instead (returning the score object is the protocol's "done").
    (set! mk-text
      (fn (_ k)
        (let ((body ()) (esc ()))
          (set! body
            (fn (self buffer score chr)
              (match
                ((= chr #\\) esc)
                ((= chr #\") (if k k (%score-set score 1 buffer)))
                ((= chr #\{) (mk-open body))
                (#t self))))
          (set! esc (fn (_ _ _ _) body))
          body)))
    ; Just past a { in text: doubled ({{) is a literal brace and text resumes,
    ; otherwise a hole opens and this character is its first.
    (set! mk-open
      (fn (_ back)
        (fn (_ buffer score chr)
          (if (= chr #\{) back
            ((mk-hole back) buffer score chr)))))
    ; Inside {...}: expression context.  " opens a plain string, $" a nested
    ; literal, #\ a character literal (so #\" and #\} cannot derail the scan),
    ; #/ a regex literal (whose {2,3} quantifiers otherwise read as braces),
    ; } closes the hole and resumes `back`.
    (set! mk-hole
      (fn (_ back)
        (let ((body ()) (dol ()) (hash ()) (charlit ()) (rex ()) (rex-esc ()))
          (set! body
            (fn (self buffer score chr)
              (match
                ((= chr #\") (mk-str self))
                ((= chr #\}) back)
                ((= chr #\$) dol)
                ((= chr #\#) hash)
                (#t self))))
          (set! dol
            (fn (_ buffer score chr)
              (if (= chr #\") (mk-text body) (body buffer score chr))))
          (set! hash
            (fn (_ buffer score chr)
              (match
                ((= chr #\\) charlit)
                ((= chr #\/) rex)
                (#t (body buffer score chr)))))
          (set! charlit (fn (_ _ _ _) body))
          (set! rex
            (fn (self buffer score chr)
              (match
                ((= chr #\\) rex-esc)
                ((= chr #\/) body)
                (#t self))))
          (set! rex-esc (fn (_ _ _ _) rex))
          body)))
    ; A "..." string inside a hole: only \ and the closing " matter.
    (set! mk-str
      (fn (_ back)
        (let ((body ()) (esc ()))
          (set! body
            (fn (self buffer score chr)
              (match
                ((= chr #\\) esc)
                ((= chr #\") back)
                (#t self))))
          (set! esc (fn (_ _ _ _) body))
          body)))
    (fn (_ buffer score chr) (if (= chr #\") (mk-text ()) ()))))

(def %interp-analyse
  (fn (_ buffer score chr) (if (= chr #\$) %interp-after-dollar ())))

; Interpolated text -> argument list for (Str8 str ...): literal chunks
; interleaved with parsed hole expressions.  A single { opens a hole; {{ and }}
; are literal braces, as is a lone }; \ escapes the next character, so \{ is a
; literal brace too.  The hole scanners mirror the analyser's states -- the two
; must agree on where a hole ends, so change them together.
(def %interp-forms
  (let ((next? ()) (brace ()) (hole-end ()) (str-end ()) (rex-end ())
        (text-end ()) (chunk ()) (walk ()))
    ; Is the character after i this one?  False at the end of the text.
    (set! next?
      (fn (_ s i len c)
        (if (< (+ i 1) len) (= (%str-ref s (+ i 1)) c) #f)))
    ; Next unescaped brace at/after i, else len.
    (set! brace
      (fn (self s i len)
        (match
          ((>= i len) len)
          ((= (%str-ref s i) #\\) (self s (+ i 2) len))
          ((= (%str-ref s i) #\{) i)
          ((= (%str-ref s i) #\}) i)
          (#t (self s (+ i 1) len)))))
    ; Index of the } closing a hole whose body starts at i.
    (set! hole-end
      (fn (self s i len)
        (match
          ((>= i len) len)
          ((= (%str-ref s i) #\}) i)
          ((= (%str-ref s i) #\") (self s (str-end s (+ i 1) len) len))
          ((and (= (%str-ref s i) #\#) (next? s i len #\\))
            (self s (+ i 3) len))                                ; #\X
          ((and (= (%str-ref s i) #\#) (next? s i len #\/))
            (self s (rex-end s (+ i 2) len) len))                ; #/.../
          ((and (= (%str-ref s i) #\$) (next? s i len #\"))
            (self s (text-end s (+ i 2) len) len))               ; nested $"..."
          (#t (self s (+ i 1) len)))))
    ; Index just past the " closing a string whose body starts at i.
    (set! str-end
      (fn (self s i len)
        (match
          ((>= i len) len)
          ((= (%str-ref s i) #\\) (self s (+ i 2) len))
          ((= (%str-ref s i) #\") (+ i 1))
          (#t (self s (+ i 1) len)))))
    ; Index just past the / closing a regex whose pattern starts at i.
    (set! rex-end
      (fn (self s i len)
        (match
          ((>= i len) len)
          ((= (%str-ref s i) #\\) (self s (+ i 2) len))
          ((= (%str-ref s i) #\/) (+ i 1))
          (#t (self s (+ i 1) len)))))
    ; Index just past the " closing a nested literal whose text starts at i.
    (set! text-end
      (fn (self s i len)
        (match
          ((>= i len) len)
          ((= (%str-ref s i) #\\) (self s (+ i 2) len))
          ((= (%str-ref s i) #\") (+ i 1))
          ((and (= (%str-ref s i) #\{) (next? s i len #\{))
            (self s (+ i 2) len))                                ; {{
          ((= (%str-ref s i) #\{)
            (self s (+ (hole-end s (+ i 1) len) 1) len))         ; nested hole
          (#t (self s (+ i 1) len)))))
    ; A chunk is RAW text: hand it back to the string reader so \n and friends
    ; mean exactly what they mean in an ordinary "..." -- one escape table, and
    ; it stays in C.  The chunk cannot contain a bare " (that would have closed
    ; the literal), so re-quoting it is safe.
    (set! chunk
      (fn (_ text)
        (first (%token-read-string (%base)
          (%str-append "\"" (%str-append text "\" "))))))
    (set! walk
      (fn (self s i len)
        (if (>= i len) ()
          (let ((p (brace s i len)))
            (match
              ((>= p len) (list (chunk (%substring s i len))))   ; trailing text
              ; {{ and }} are one literal brace each: emit through the brace,
              ; resume past its twin.
              ((and (= (%str-ref s p) #\{) (next? s p len #\{))
                (pair (chunk (%substring s i (+ p 1))) (self s (+ p 2) len)))
              ((and (= (%str-ref s p) #\}) (next? s p len #\}))
                (pair (chunk (%substring s i (+ p 1))) (self s (+ p 2) len)))
              ((= (%str-ref s p) #\})                            ; lone }
                (pair (chunk (%substring s i (+ p 1))) (self s (+ p 1) len)))
              (#t                                                ; hole: { expr }
                (let ((close (hole-end s (+ p 1) len)))
                  (pair (chunk (%substring s i p))               ; text before {
                    ; pad with a trailing space so a bare-symbol hole ({x})
                    ; terminates its token at end-of-buffer (token-read-string
                    ; drops an unterminated tail).
                    (pair (first (%token-read-string (%base)
                            (%str-append (%substring s (+ p 1) close) " ")))
                      (self s (+ close 1) len))))))))))
    walk))

; The winning token is the whole literal: strip $" and the closing ", split what
; is left.  The last-character test is the cheap guard -- no ordinary symbol ends
; in a quote -- so the token text is only materialized for a real candidate.
(def %interp-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) #\")
      (let ((tok (%buffer-token buffer)))
        (if (and (> (%str-length tok) 2) (= (%str-ref tok 0) #\$))
          (let ((s (%substring tok 2 (- (%str-length tok) 1))))
            (pair (lit Str8)
              (pair (lit str) (%interp-forms s 0 (%str-length s)))))
          ()))
      ())))

; --- Place the readers on the symbol type ---
; Each slot becomes a list: the macro handlers followed by the type's
; existing C handler (captured as the list tail), which the tokenizer's
; analyse/read loops iterate.

(def %sym-type (%type-by-atom (%type-of "x")))

(%type-push-analyse %sym-type
  (list %interp-analyse %lit-analyse %quasi-analyse %unquote-analyse
        (first (first (%type-analyse-cell %sym-type)))))

(%type-push-read %sym-type
  (list %interp-read %lit-read %quasi-read %unquote-read
        (first (first (%type-read-cell %sym-type)))))

(%type-push-delimit %sym-type %macro-delimit)

(doc (provide x/reader/lit-reader
  %lit-analyse %lit-read %lit-accept %macro-delimit)
  (note "'sym is a symbol, '(a b) a literal list, ''x nests; ' also terminates")
  (note "an adjacent token: foo'bar reads as foo then 'bar.")
  (example "'(1 2 3)" "(1 2 3)")
  "Quote reader ('expr -> (lit expr)) plus the wiring that puts the quote family
of readers on the symbol type.")
