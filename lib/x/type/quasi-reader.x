; quasi-reader.x -- Reader syntax for quasiquote, unquote, unquote-splicing
;
; Registers two tokenizer types via make-type:
;   QUASI-READ   -- matches ` (backtick), reads next expr, wraps in (quasi expr)
;   UNQUOTE-READ -- matches , or ,@ reads next expr, wraps in (unquote expr)
;                   or (unquote-splicing expr)
;
; Both types register delimit hooks so backtick and comma terminate
; adjacent tokens (e.g. foo`bar reads as foo then `bar).
;
; Requires: quasi.x, intrinsics.x (buffer-len, buffer-unread, score-set),
;           token-read, buffer-last-char primitives (from C)

; --- Analyser states ---
; Single-char accept: unread the lookahead char, score, accept.
; Used by backtick (always single-char) after the entry matches.

(def %quasi-accept
  (fn (_ buffer score chr)
    (%seq (buffer-unread buffer) (score-set score 1 buffer))))

; After comma, check for @ (splice) or accept as plain unquote.

(def %unquote-after-comma
  (fn (_ buffer score chr)
    (if (= chr 64)
      (score-set score 1 buffer)
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

; --- Register QUASI-READ type (backtick) ---

(def %quasi-read-atom
(make-type
  "QUASI-READ"
  (list
    (pair (lit first-chars) "`")
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 96) %quasi-accept ())))
    (pair
      (lit delimit)
      (fn (_ buffer . rest)
        (if (= (buffer-last-char buffer) 96)
          (%seq (buffer-unread buffer) buffer)
          ())))
    (pair
      (lit read)
      (fn (_ . args)
        (pair (lit quasi)
          (pair (token-read (first args)) ())))))))

; --- Register UNQUOTE-READ type (comma, comma-at) ---

(def %unquote-read-atom
(make-type
  "UNQUOTE-READ"
  (list
    (pair (lit first-chars) ",")
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 44)
          %unquote-after-comma
          ())))
    (pair
      (lit delimit)
      (fn (_ buffer . rest)
        (if (= (buffer-last-char buffer) 44)
          (%seq (buffer-unread buffer) buffer)
          ())))
    (pair
      (lit read)
      (fn (_ . args)
        (if (= (buffer-len (first args)) 1)
          (pair (lit unquote)
            (pair (token-read (first args)) ()))
          (pair (lit unquote-splicing)
            (pair (token-read (first args)) ()))))))))

(doc (provide x/type/quasi-reader
  %quasi-read-atom %unquote-read-atom
  %quasi-accept %unquote-after-comma)
  "Reader syntax for quasiquote: backtick, comma and comma-at expand to quasi/unquote forms.")
