; lit-reader.x -- Reader syntax for quote: 'expr reads as (lit expr)
;
; Registers one tokenizer type via make-type:
;   LIT-READ -- matches ' (apostrophe), reads next expr, wraps in (lit expr)
;
; Mirrors quasi-reader.x. The analyse handler is kept JIT-compatible -- only
; integer char compares and nested `if`, no cond/convert/eq?-on-heap -- so the
; x/and and x/or dialects can compile it to native code (see lib/x-and.x,
; lib/x-or.x). Interpreted, it runs on every char while tokenizing and slows
; parsing; compiled, that cost disappears.
;
; The delimit hook makes ' terminate an adjacent token, so foo'bar reads as
; foo then 'bar (' is a terminating macro char, as in standard Lisp).
;
; Requires: intrinsics.x (buffer-unread, score-set), token-read,
;           buffer-last-char primitives (from C). `lit` is a core special form.

; Single-char accept: unread the lookahead char, score, accept.
(def %lit-accept
  (fn (_ buffer score _)
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))

; --- Register LIT-READ type (single quote) ---

(def %lit-read-atom
(make-type
  "LIT-READ"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 39) %lit-accept ())))
    (pair
      (lit delimit)
      (fn (_ buffer . rest)
        (if (= (buffer-last-char buffer) 39)
          (%seq (buffer-unread buffer) buffer)
          ())))
    (pair
      (lit read)
      (fn (_ . args)
        (pair (lit lit)
          (pair (token-read (first args)) ())))))))

(doc (provide x/type/lit-reader
  %lit-read-atom %lit-accept)
  (note "'sym is a symbol, '(a b) a literal list, ''x nests. ' also terminates an")
  (note "adjacent token: foo'bar reads as foo then 'bar. The x/and and x/or dialects")
  (note "JIT-compile the reader so it does not slow tokenizing.")
  (example "'(1 2 3)" "(1 2 3)")
  "Quote reader: 'expr is reader shorthand for (lit expr).")
