; char-io.x -- UTF-8-aware CHARACTER write/display handlers (x-lang)
;
; A CHARACTER holds a Unicode code point. The C type ships a minimal byte-level
; write/display at the bottom of the type's IO stacks (correct for ASCII only).
; Here we push handlers that own the full behaviour, so UTF-8 lives in x-lang,
; not C:
;   display  -> the code point's UTF-8 bytes (via x/codec/utf8 + bytes->str)
;   write    -> #\ prefix, then a named char (#\newline, ...) or the glyph
;
; Loaded right after the codec and string layer at boot; the pushed handlers
; shadow the C fallback before any non-ASCII character is printed.

(import x/codec/utf8)
; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-write (prim-ref (lit type) (lit push-write)))
(def %type-push-display (prim-ref (lit type) (lit push-display)))


; The code point's UTF-8 byte string -- a CHARACTER is a 1-code-point string.
; list->str (x/type/str-utf8) already encodes a code-point char to its bytes.
(def %char->str (fn (_ ch) (list->str (list ch))))

; --- display: raw glyph bytes ---

(def %char-display
  (fn (_ ch) (display (%char->str ch))))

; --- write: #\ prefix + named char or glyph ---

; Named characters, by code point. Mirrors the C type's data alist so
; (write #\newline) stays "#\newline", not a literal newline.
(def %char-names
  (lit
    ((0 . "null") (7 . "alarm") (8 . "backspace") (9 . "tab")
     (10 . "newline") (13 . "return") (27 . "escape") (32 . "space")
     (127 . "delete"))))

(def %char-name
  (fn (_ cp)
    (let loop ((al %char-names))
      (if (null? al) ()
        (if (= (first (first al)) cp)
          (rest (first al))
          (loop (rest al)))))))

(def %char-write
  (fn (_ ch)
    (display "#\\")
    (let ((name (%char-name (char->integer ch))))
      (if (null? name)
        (display (%char->str ch))   ; glyph: the char's UTF-8 bytes
        (display name)))))          ; named: #\newline etc.

; --- install (push over the C fallback) ---

(let ((ct (%type-by-atom (type-of (integer->char 0)))))
  (%type-push-display ct %char-display)
  (%type-push-write   ct %char-write))

(doc (provide x/type/char-io)
  "UTF-8-aware write/display handlers for CHARACTER values, so a code point renders as its glyph.")
