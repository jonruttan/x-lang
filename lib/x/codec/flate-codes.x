; flate-codes.x -- the DEFLATE length and distance code tables (RFC 1951 3.2.5).
;
; A length symbol 257..285 names a base length and a count of extra bits,
; a distance symbol 0..29 a base distance and its extra bits; slot k+1 of
; each vector holds symbol k's, the Vector convention.  The decoder
; (x/codec/inflate) reads them to widen a symbol into a length or a
; distance, and the encoder (x/codec/deflate) to find a length's or a
; distance's symbol and write the extra bits; one table, read from both,
; (import x/codec/flate-codes lbase lext dbase dext).
(module x/codec/flate-codes)

(import x/type/vector)

(def lbase (Vector from-list (list 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258)))
(def lext (Vector from-list (list 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)))
(def dbase (Vector from-list (list 1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577)))
(def dext (Vector from-list (list 0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

(doc (provide x/codec/flate-codes lbase lext dbase dext)
  (note "Slot k+1 of each vector is symbol k's entry: lbase and lext for the length symbols 257..285 taken from 257, dbase and dext for the distance symbols 0..29.")
  (see Inflate)
  (see Deflate)
  "The DEFLATE length and distance code tables of RFC 1951 3.2.5 -- base values and extra-bit counts -- bound once for the decoder and the encoder to import.")
