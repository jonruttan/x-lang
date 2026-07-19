; type/buf.x -- Buf + Tok: the tokenizer buffer and token-stream API.
;
; The C primitives live in src/x-prim/type.c (catalog ns `buf` and `tok`);
; the methods fetch inline per the cold rule. Both namespaces are
; DE-REGISTERED (R5): the classes -- or catalog fetches -- are the only
; surface. READER-HOT consumers (custom readers and analyse handlers built
; via make-type: lit-reader, quasi-reader, the numeric tower's readers)
; must fetch-and-cache into module %-vars, never class-dispatch per token:
;   (def %buffer-token (prim-ref (lit buf) (lit tok)))

(import x/type/class)

; A buffer is a non-owning VIEW over storage someone else owns (a string's
; bytes, the input channel). It is never constructed here -- the tokenizer hands
; you one; these methods operate on it. (Hence no (Buf make): a buffer that
; allocated its own storage would defeat the point.)
(def-class Buf ()
  (static
    (method tok (self (param buffer ANY "A tokenizer buffer"))
      (doc "The buffer's current token as a string."
        (returns STRING "The token text"))
      ((prim-ref (lit buf) (lit tok)) buffer))
    (method last-char (self (param buffer ANY "A tokenizer buffer"))
      (doc "The last character read into the buffer, as its integer code."
        (returns INT "The character code"))
      ((prim-ref (lit buf) (lit last-char)) buffer))
    (method reset (self (param buffer ANY "A tokenizer buffer"))
      (doc "Empty a tokenizer buffer: reset its read and write cursors to the base."
        (returns ANY "The buffer"))
      ((prim-ref (lit buf) (lit reset)) buffer))
    (method retain (self (param buffer ANY "A tokenizer buffer"))
      (doc "Compact a buffer's unread data to the front, freeing consumed space."
        (returns ANY "The buffer"))
      ((prim-ref (lit buf) (lit retain)) buffer))
    (method append (self (param buffer ANY "A tokenizer buffer") (param ch CHAR "Character to write"))
      (doc "Append one character at a buffer's write cursor."
        (returns ANY "The buffer"))
      ((prim-ref (lit buf) (lit append)) buffer ch))
    (method read (self (param buffer ANY "A tokenizer buffer"))
      (doc "Read one character into a buffer, extending from the input channel if it is exhausted."
        (returns ANY "The buffer, or () at EOF"))
      ((prim-ref (lit buf) (lit read)) buffer))
    (method read-text (self (param buffer ANY "A tokenizer buffer"))
      (doc "Like (Buf read), but a NUL character counts as end-of-input."
        (returns ANY "The buffer, or () at EOF/NUL"))
      ((prim-ref (lit buf) (lit read-text)) buffer))))

(def-class Tok ()
  (static
    (method read (self (param buffer ANY "A tokenizer buffer"))
      (doc "Read one token from a buffer through the type system's analysers."
        (returns ANY "The parsed token"))
      ((prim-ref (lit tok) (lit read)) buffer))
    (method read-str (self (param base ANY "Base object with type alist") (param s STRING "Source string to tokenize"))
      (doc "Tokenize a string using a base's type system."
        (returns LIST "List of parsed tokens"))
      ((prim-ref (lit tok) (lit read-str)) base s))))

(doc (provide x/type/buf Buf Tok)
  (note "ns `buf`/`tok` are de-registered; reader-hot callers fetch-and-cache the prims, never class-dispatch per token.")
  "Tokenizer buffers (Buf) and the token stream (Tok): the low-level reader surface for custom types.")
