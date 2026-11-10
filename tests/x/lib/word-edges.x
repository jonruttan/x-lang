; The machine word's edges, for specs that state a fact at the word's
; limits: built from %word-size, so a case says the same thing on an
; 8-byte word and a 4-byte one.  Needs x/num/bigint.
;
;   %bw-bits  the word's bits less the sign bit (63 on an 8-byte word)
;   %bw-min   LONG_MIN, from the bitwise door
;   %bw-big   2^%bw-bits as a bigint: LONG_MIN's magnitude, built by expt
;   %bw-p10   the largest power of ten the word holds (10^18 on 8 bytes)
;   %bw-b     the largest power of ten whose square fits: the bigint base
;             (10^9 on 8 bytes)
(def %bw-bits (- (* 8 %word-size) 1))
(def %bw-min (<< 1 %bw-bits))
(def %bw-big (Num expt 2 %bw-bits))
(def %bw-p10 (let next ((p 1)) (if (Bigint would-overflow-mul? p 10) p (next (* p 10)))))
(def %bw-b (let next ((p 10)) (if (Bigint would-overflow-mul? (* p 10) (* p 10)) p (next (* p 10)))))
