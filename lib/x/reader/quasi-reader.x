; quasi-reader.x -- quasiquote / unquote reader-macro handlers.
;
;   `expr  -> (quasi expr)
;   ,expr  -> (unquote expr)
;   ,@expr -> (unquote-splicing expr)
;
; These are NOT their own tokenizer types.  Their analyse + read handlers
; ride on the symbol type's analyse/read lists, which lit-reader.x (loaded
; last) assembles.  Each read self-selects on the token's leading char and
; returns () to decline, so the symbol reader -- the list tail -- handles
; everything else.
;
; Requires: intrinsics.x (buffer-*, score-set), %token-read, str.x, char.x.

; --- analyser accept states ---

; Single-char accept: unread the lookahead char, score one, accept.
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref (lit buf) (lit tok)))
(def %buffer-last-char (prim-ref (lit buf) (lit last-char)))
(def %token-read (prim-ref (lit tok) (lit read)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))


(def %quasi-accept
  (fn (_ buffer score _)
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))

; After a comma, an @ makes it unquote-splicing; either way score one char.
(def %unquote-after-comma
  (fn (_ buffer score chr)
    (if (= chr 64)
      (score-set score 1 buffer)
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

; --- analyse: score a leading ` or , as a one-char token ---

(def %quasi-analyse
  (fn (_ buffer score chr) (if (= chr 96) %quasi-accept ())))

(def %unquote-analyse
  (fn (_ buffer score chr) (if (= chr 44) %unquote-after-comma ())))

; --- read: confirm the token, then wrap the following expression ---
; ' ` , are delimiters, so a token ending in ` or , can only be that macro
; (a symbol never ends in one).  ,@ is the lone two-char token; it ends in
; @, so confirm a leading , (vs a symbol like x@) before splicing.

(def %quasi-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) 96)
      (pair (lit quasi) (pair (%token-read buffer) ()))
      ())))

(def %unquote-read
  (fn (_ buffer . rest)
    (if (= (%buffer-last-char buffer) 44)
      (pair (lit unquote) (pair (%token-read buffer) ()))
      (if (= (%buffer-last-char buffer) 64)
        (if (= (%char->integer (%str-ref (%buffer-token buffer) 0)) 44)
          (pair (lit unquote-splicing) (pair (%token-read buffer) ()))
          ())
        ()))))

(doc (provide x/reader/quasi-reader
  %quasi-analyse %unquote-analyse %quasi-read %unquote-read
  %quasi-accept %unquote-after-comma)
  "Quasiquote reader-macro handlers (backtick, comma, comma-at), placed on the
symbol type by lit-reader.x.")
