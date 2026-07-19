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
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))

(def %lit-analyse
  (fn (_ buffer score chr) (if (= chr 39) %lit-accept ())))

(def %lit-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) 39)
      (pair (lit lit) (pair (%token-read buffer) ()))
      ())))

; ' ` , each terminate an adjacent token.  Nested if (no cond/or) and no
; binding keep it allocation-free on the per-char delimiter path.
(def %macro-delimit
  (fn (_ buffer . rest)
    (if (if (= (%buffer-last-char buffer) 39) #t
          (if (= (%buffer-last-char buffer) 96) #t
            (= (%buffer-last-char buffer) 44)))
      (%seq (buffer-unread buffer) buffer)
      ())))

; --- $"...{expr}..." string interpolation --------------------------------
; $"a{x}b" parses at READ time into the call (Str8 str "a" x "b"): %interp-read
; runs the hole parser (%interp-forms) and emits the call directly.  Each hole is
; thus a plain sub-expression that evaluates in place, in whatever env the literal
; sits in -- no eval-time wrapper, no operative needed for the caller's scope.
;
; Parsing was once DEFERRED to eval time: the literal read as (%interp-str X), an
; op that re-tokenized the holes on every evaluation, to keep token-read-string
; out of the GC-sensitive tokenizer loop.  That rationale is now obsolete -- GC is
; explicit-only (pure allocators never collect), so re-entering the tokenizer from
; a reader handler is safe (%interp-read already calls token-read for the string
; itself).  Do NOT move parsing back to eval time: besides re-parsing on every
; eval, token-read-string's tokenizer re-entry leaves the base's env register
; dirty, and an if-tail (TCO) position inherits that dirty env -- stranding a
; later interpolation's variable as Unbound.  Parsing at read time sidesteps it
; entirely (the env is never touched mid-evaluation).
; (display/str themselves live in boot/string.x and the Str8 class respectively.)
(def %str-append        (prim-ref (lit str)  (lit append)))
(def %char->int         (prim-ref (lit char) (lit ->int)))
(def %token-read-string (prim-ref (lit tok)  (lit read-str)))

; Index of byte `code` in s at/after i, else len.
(def %str-index
  (fn (self s code i len)
    (if (>= i len) len
      (if (= (%char->int (str-ref s i)) code) i
        (self s code (+ i 1) len)))))

; Interpolated string -> argument list for (Str8 str ...): literal chunks
; interleaved with parsed hole expressions.  { = 123, } = 125.  A single { opens
; a hole; {{ and }} are literal braces; a lone } is a literal brace too.
(def %interp-forms
  (fn (self s i len)
    (if (>= i len) ()
      (let ((o (%str-index s 123 i len))                    ; next {
            (c (%str-index s 125 i len)))                   ; next }
        (let ((p (if (< o c) o c)))                         ; whichever brace comes first
          (if (>= p len)
            (list (substring s i len))                      ; no more braces: trailing literal
            (if (= (%char->int (str-ref s p)) 123)
              ; a {  -- either a hole or a {{ literal
              (if (and (< (+ p 1) len) (= (%char->int (str-ref s (+ p 1))) 123))
                (pair (substring s i (+ p 1)) (self s (+ p 2) len))   ; {{ -> literal {
                (let ((close (%str-index s 125 (+ p 1) len)))         ; hole: { expr }
                  (pair (substring s i p)                             ; text before {
                    ; pad with a trailing space so a bare-symbol hole ({x}) terminates its
                    ; token at end-of-buffer (token-read-string drops an unterminated tail).
                    (pair (first (%token-read-string (%base) (%str-append (substring s (+ p 1) close) " ")))
                      (self s (+ close 1) len)))))
              ; a }  -- }} or a lone }, both literal (one brace either way)
              (if (and (< (+ p 1) len) (= (%char->int (str-ref s (+ p 1))) 125))
                (pair (substring s i (+ p 1)) (self s (+ p 2) len))   ; }} -> literal }
                (pair (substring s i (+ p 1)) (self s (+ p 1) len)))))))))) ; lone } -> literal }

; $ (byte 36) reader: one-char token, then parse the following string.
(def %interp-accept
  (fn (_ buffer score _)
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))
(def %interp-analyse
  (fn (_ buffer score chr) (if (= chr 36) %interp-accept ())))
(def %interp-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) 36)
      ; %token-read consumes the following string token; %interp-forms splits its
      ; holes now, so we emit (Str8 str <chunk> <expr> ...) directly (see header).
      (let ((s (%token-read buffer)))
        (pair (lit Str8) (pair (lit str) (%interp-forms s 0 (str-length s)))))
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
