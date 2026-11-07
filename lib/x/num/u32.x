; u32.x -- the unsigned 32-bit value of a word's low 32 bits, and back.
;
; A checksum is 32 bits, unsigned: 0 to 4294967295.  An 8-byte word holds
; every one of those; a 4-byte word holds the same bits, but from 2^31 up
; they read negative, the value it cannot hold.  A module computes in the
; word's bits and converts here at its boundary: u32 gives the value, a
; bigint from 2^31 up on a 4-byte word, and u32-bits takes a value back to
; the word's bits.  bigint loads only where a 4-byte word needs it.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/u32)
(import x/core/doors int& int- int< int<< int>> type-of)

(when (int< %word-size 8) (import x/num/bigint))

; 2^32, which only a 4-byte word needs, and there a bigint
(def %wide (int< 4 %word-size))
(def %span (if %wide () (* 65536 65536)))
(def %int-t (type-of 0))

(doc (def u32
  (fn (_ v)
    (match
      (%wide (int& v 0xFFFFFFFF))
      ((if (eq? (type-of v) %int-t) (int< v 0) #f) (+ v %span))
      (#t v))))
  (param v INTEGER "A word whose low 32 bits are the value, or the value itself")
  (returns INTEGER "The value, 0 to 4294967295: a bigint from 2^31 up on a 4-byte word")
  (example "(u32 -1)" "4294967295")
  "The unsigned value of a word's low 32 bits.")

(doc (def u32-bits
  (fn (_ v)
    (match
      (%wide (int& v 0xFFFFFFFF))
      ((eq? (type-of v) %int-t) v)
      (#t (- v %span)))))
  (param v INTEGER "A value, 0 to 4294967295")
  (returns INTEGER "The value's 32 bits as the word holds them: negative from 2^31 up on a 4-byte word")
  (example "(u32 (u32-bits 4294967295))" "4294967295")
  "The word holding a 32-bit value's bits, the form a computation in the word's bits takes.")

; An 8-byte word holds the bits non-negative, so its arithmetic shift is
; already logical and is the door itself; on a 4-byte word the top bit is
; the sign, which the shift copies down and the mask clears.
(doc (def u32-srl
  (if %wide int>>
    (fn (_ x n) (int& (int>> x n) (int- (int<< 1 (int- 32 n)) 1)))))
  (param x INTEGER "32 bits as u32-bits holds them")
  (param n INTEGER "The shift, 1 to 31")
  (returns INTEGER "x shifted right n places, zeros in from the top, as u32-bits holds it")
  (example "(u32 (u32-srl (u32-bits 4294967295) 4))" "268435455")
  "The logical right shift of 32 bits held in a word.")

(doc (provide x/num/u32 u32 u32-bits u32-srl)
  (example "(u32 (u32-srl (u32-bits 4294967295) 28))" "15")
  "32-bit unsigned values on any word: u32 reads a word's low 32 bits as the value, u32-bits takes the value back to the word's bits, and u32-srl shifts those bits right logically.")
