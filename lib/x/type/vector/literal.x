; vector/literal.x -- the vector literal: #(1 2 3)
;
; Importing this module installs the literal on the base that imports it.
; x/type/vector is the library and installs no reader syntax.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/type/vector/literal)
(import x/core/doors char->int type-by-atom type-of type-push-analyse)
(import x/type/vector Vector)

(def %read (prim-ref (lit io) (lit read)))

; After #, a ( opens the vector.  The ( is given back: the read handler
; reads the list it opens.  A module-level def, so reading a # makes no
; closure.
(def %vector-after-hash
  (fn (_ buffer score chr)
    (if (= chr (char->int #\())
      (do (%buffer-unread buffer) (%score-set score 1 buffer))
      ())))

(def %vector-literal-analyse
  (fn (_ buffer score chr)
    (if (= chr (char->int #\#)) %vector-after-hash ())))

; The read primitive answers the EOF sentinel at end of input; a vector
; literal cut off there reads as an empty vector.
; The library's door from a list is fetched once: a tokenizer callback does
; not dispatch on a class (lib/x/type/io.x).
(def %vector-from-list (class-static-ref Vector (lit from-list)))
(def %vector-literal-read
  (fn (_ . args)
    (let ((v (%read)))
      (%vector-from-list Vector (if (same? v %token-eof) () v)))))

(def %vector-type (type-by-atom (type-of (Vector of))))
(type-push-analyse %vector-type %vector-literal-analyse)
((prim-ref (lit type) (lit push-read)) %vector-type %vector-literal-read)

(doc (provide x/type/vector/literal)
  (sample "(import x/type/vector/literal)" "#(1 2 3) now reads as a vector on this base")
  "The vector literal #(1 2 3), installed on the importing base's VECTOR type.")
