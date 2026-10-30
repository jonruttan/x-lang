; der.x -- Der: reading DER, the encoding X.509 certificates are written in.
;
; DER (X.690) is tag, length, contents, nested: a SEQUENCE's contents are
; more of the same.  This reads it over regions (BUF START LEN), as
; x/codec/bytes has them: an element is (TAG CONTENTS WHOLE), the contents
; and the whole element regions of the input, so a certificate's signed
; part is its own bytes and nothing is copied.  Lengths are DER's: short,
; or long in at most four bytes, never indefinite; anything else raises a
; label 'value, since a certificate that does not parse is refused.
(module x/codec/der)

(import x/codec/bytes)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(import x/core/doors char->int int& int- int/ int<< int>> int| ptr-set! str->ptr str-byte-ref str-make)
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))


; Integer division on the int prim: under the numeric tower / is exact, and
; 7/2 is a ratio there.

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Der: " what) ())))

; Bytes read through the prims: a certificate is read a byte at a time,
; and a class call a byte is hundreds of objects where a prim is one.
(def %at (fn (_ r i) (char->int (str-byte-ref (first r) (+ (first (rest r)) i)))))
(def %len (fn (_ r) (first (rest (rest r)))))


; n's decimal digits written at p + at: answers the offset past them.
(def %put-dec
  (fn (_ p at n)
    (def len ((fn (self m k) (if (< m 10) k (self (int/ m 10) (+ k 1)))) n 1))
    ((fn (self i m)
       (unless (< i 0)
         (do (ptr-set! p (+ at i) (+ 48 (- m (* 10 (int/ m 10)))) 1)
             (self (- i 1) (int/ m 10)))))
     (- len 1) n)
    (+ at len)))

; A cursor over a region: (BUF POS END), POS moving.
(def %rd (fn (_ r) (list (first r) (first (rest r)) (+ (first (rest r)) (%len r)))))
(def %rd-pos (fn (_ rd) (first (rest rd))))
(def %rd-left (fn (_ rd) (- (first (rest (rest rd))) (first (rest rd)))))
(def %rd-u8
  (fn (_ rd)
    (def p (first (rest rd)))
    (when (>= p (first (rest (rest rd)))) (%fail "an element cut short"))
    (%set-first! (rest rd) (+ p 1))
    (char->int (str-byte-ref (first rd) p))))
(def %rd-take
  (fn (_ rd n)
    (def p (first (rest rd)))
    (%set-first! (rest rd) (+ p n))
    (list (first rd) p n)))

(def %length
  (fn (_ rd)
    (def b (%rd-u8 rd))
    (match
      ((< b 128) b)
      ((= b 128) (%fail "an indefinite length"))
      ((> b 132) (%fail "a length of more than four bytes"))
      (#t ((fn (self k acc) (if (= k 0) acc (self (- k 1) (int| (int<< acc 8) (%rd-u8 rd))))) (- b 128) 0)))))

; The next element at a cursor, as (TAG CONTENTS WHOLE).
(def %next
  (fn (_ rd)
    (def start (%rd-pos rd))
    (def tag (%rd-u8 rd))
    (when (= (int& tag 31) 31) (%fail "a multi-byte tag"))
    (def len (%length rd))
    (when (> len (%rd-left rd)) (%fail "an element longer than what holds it"))
    (def contents (%rd-take rd len))
    (list tag contents (list (first rd) start (- (%rd-pos rd) start)))))

; Days since 1970-01-01 of a civil date (Hinnant's days_from_civil).
(def %days
  (fn (_ y m d)
    (def y2 (if (<= m 2) (- y 1) y))
    (def era (if (>= y2 0) (int/ y2 400) (int/ (- y2 399) 400)))
    (def yoe (- y2 (* era 400)))
    (def doy (+ (int/ (+ (* 153 (+ m (if (> m 2) -3 9))) 2) 5) (- d 1)))
    (def doe (+ (* yoe 365) (int/ yoe 4) (- 0 (int/ yoe 100)) doy))
    (+ (* era 146097) doe -719468)))

(def %digits
  (fn (_ r at n)
    ((fn (self i acc)
       (if (= i n) acc
         (do (def c (%at r (+ at i)))
             (unless (and (>= c 48) (<= c 57)) (%fail "a time with a non-digit"))
             (self (+ i 1) (+ (* acc 10) (- c 48))))))
     0 0)))

(def-class Der ()
  (static
    (method read (self (param r ANY "A region holding one DER element, or a STRING up to its first NUL"))
      (doc "The one element a region holds, as (TAG CONTENTS WHOLE): CONTENTS and WHOLE are regions of the input. Raises a label 'value when the region holds anything more or less."
        (returns LIST "(TAG CONTENTS WHOLE)")
        (example "(first (Der read (Bytes of-hex \"020101\")))" "2"))
      (def rd (%rd (Bytes of r)))
      (def e (%next rd))
      (unless (= (%rd-left rd) 0) (%fail "bytes after the element"))
      e)
    (method items (self (param contents LIST "A constructed element's contents, a region"))
      (doc "The elements a SEQUENCE's or SET's contents hold, in order, each (TAG CONTENTS WHOLE)."
        (returns LIST "A list of elements")
        (example "(List length (Der items (first (rest (Der read (Bytes of-hex \"3006020101020102\"))))))" "2"))
      (def rd (%rd contents))
      ((fn (self acc) (if (= (%rd-left rd) 0) (List reverse acc) (self (pair (%next rd) acc)))) ()))
    (method oid (self (param contents LIST "An OBJECT IDENTIFIER's contents, a region"))
      (doc "The OID in dotted form."
        (returns STRING "Its dotted form")
        (example "(Der oid (first (rest (Der read (Bytes of-hex \"06082a8648ce3d040302\")))))" "\"1.2.840.10045.4.3.2\""))
      (def n (%len contents))
      (when (= n 0) (%fail "an empty OID"))
      (def b0 (%at contents 0))
      ; the dotted text written into a buffer as the arcs are read: at most
      ; twenty digits and a dot an arc, and an arc a byte at most
      (def out (str-make (+ 1 (* 21 (+ n 2)))))
      (def p (str->ptr out))
      (def at1 (%put-dec p 0 (if (< b0 80) (int/ b0 40) 2)))
      (ptr-set! p at1 46 1)
      (def at (%put-dec p (+ at1 1) (if (< b0 80) (- b0 (* 40 (int/ b0 40))) (- b0 80))))
      ((fn (self i at v)
         (if (= i n)
           (if (= v 0) (do (ptr-set! p at 0 1) out) (%fail "an OID cut short"))
           (do (def b (%at contents i))
               (def v2 (int| (int<< v 7) (int& b 127)))
               (if (>= b 128) (self (+ i 1) at v2)
                 (do (ptr-set! p at 46 1) (self (+ i 1) (%put-dec p (+ at 1) v2) 0))))))
       1 at 0))
    (method time (self (param tag INTEGER "23 for UTCTime, 24 for GeneralizedTime")
                       (param contents LIST "The time's contents, a region"))
      (doc "A UTCTime (YYMMDDHHMMSSZ, years 1950-2049 as RFC 5280 says) or GeneralizedTime (YYYYMMDDHHMMSSZ) as seconds since the Unix epoch."
        (returns INTEGER "Seconds since 1970-01-01T00:00:00Z")
        (example "(Der time 23 (Bytes of \"700101000000Z\"))" "0"))
      (def long (= tag 24))
      (def n (%len contents))
      (unless (and (= n (if long 15 13)) (= (%at contents (- n 1)) 90)) (%fail "a time not in DER's form"))
      (def yy (if long (%digits contents 0 4) (%digits contents 0 2)))
      (def y (if long yy (if (< yy 50) (+ 2000 yy) (+ 1900 yy))))
      (def at (if long 4 2))
      (+ (* 86400 (%days y (%digits contents at 2) (%digits contents (+ at 2) 2)))
         (* 3600 (%digits contents (+ at 4) 2))
         (* 60 (%digits contents (+ at 6) 2))
         (%digits contents (+ at 8) 2)))
    (method bits (self (param contents LIST "A BIT STRING's contents, a region"))
      (doc "A BIT STRING's bytes, its unused-bits count checked to be zero, as keys and signatures are."
        (returns LIST "A region of the bits")
        (example "(Bytes hex (Der bits (first (rest (Der read (Bytes of-hex \"030300abcd\"))))))" "\"abcd\""))
      (when (or (= (%len contents) 0) (not (= (%at contents 0) 0))) (%fail "a BIT STRING with unused bits"))
      (list (first contents) (+ (first (rest contents)) 1) (- (%len contents) 1)))
    (method small (self (param contents LIST "An INTEGER's contents, a region, small and non-negative"))
      (doc "A small non-negative INTEGER's value, as a version or a path length is."
        (returns INTEGER "The value")
        (example "(Der small (first (rest (Der read (Bytes of-hex \"020102\")))))" "2"))
      (when (or (= (%len contents) 0) (> (%len contents) 4) (>= (%at contents 0) 128)) (%fail "not a small INTEGER"))
      ((fn (self i acc) (if (= i (%len contents)) acc (self (+ i 1) (int| (int<< acc 8) (%at contents i))))) 0 0))))

(doc (provide x/codec/der Der)
  "DER (X.690) over regions: (Der read r) answers an element (TAG CONTENTS WHOLE); items, oid, time, bits and small read what is inside one.")
