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
; Requires: quasi-reader.x, intrinsics.x, str.x, char.x, x/sys/type.

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-analyse-cell (prim-ref (lit type) (lit analyse-cell)))
(def %type-push-analyse (prim-ref (lit type) (lit push-analyse)))
(def %type-read-cell (prim-ref (lit type) (lit read-cell)))
(def %type-push-delimit (prim-ref (lit type) (lit push-delimit)))
(def %type-push-read (prim-ref (lit type) (lit push-read)))

(def %lit-accept
  (fn (_ buffer score _)
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))

(def %lit-analyse
  (fn (_ buffer score chr) (if (= chr 39) %lit-accept ())))

(def %lit-read
  (fn (_ buffer . rest)
    (if (= (buffer-last-char buffer) 39)
      (pair (lit lit) (pair (token-read buffer) ()))
      ())))

; ' ` , each terminate an adjacent token.  Nested if (no cond/or) and no
; binding keep it allocation-free on the per-char delimiter path.
(def %macro-delimit
  (fn (_ buffer . rest)
    (if (if (= (buffer-last-char buffer) 39) #t
          (if (= (buffer-last-char buffer) 96) #t
            (= (buffer-last-char buffer) 44)))
      (%seq (buffer-unread buffer) buffer)
      ())))

; --- Place the readers on the symbol type ---
; Each slot becomes a list: the macro handlers followed by the type's
; existing C handler (captured as the list tail), which the tokenizer's
; analyse/read loops iterate.

(def %sym-type (%type-by-atom (type-of "x")))

(%type-push-analyse %sym-type
  (list %lit-analyse %quasi-analyse %unquote-analyse
        (first (first (%type-analyse-cell %sym-type)))))

(%type-push-read %sym-type
  (list %lit-read %quasi-read %unquote-read
        (first (first (%type-read-cell %sym-type)))))

(%type-push-delimit %sym-type %macro-delimit)

(doc (provide x/type/lit-reader
  %lit-analyse %lit-read %lit-accept %macro-delimit)
  (note "'sym is a symbol, '(a b) a literal list, ''x nests; ' also terminates")
  (note "an adjacent token: foo'bar reads as foo then 'bar.")
  (example "'(1 2 3)" "(1 2 3)")
  "Quote reader ('expr -> (lit expr)) plus the wiring that puts the quote family
of readers on the symbol type.")
