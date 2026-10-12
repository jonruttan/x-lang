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

; Integer division on the int prim: under the numeric tower / is exact, and
; 7/2 is a ratio there.
(def %div (prim-ref (lit int) (lit /)))

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Der: " what) ())))

(def %length
  (fn (_ rd)
    (def b (Bytes get-u8 rd))
    (match
      ((< b 128) b)
      ((= b 128) (%fail "an indefinite length"))
      ((> b 132) (%fail "a length of more than four bytes"))
      (#t ((fn (self k acc) (if (= k 0) acc (self (- k 1) (| (<< acc 8) (Bytes get-u8 rd))))) (- b 128) 0)))))

; The next element of a reader, as (TAG CONTENTS WHOLE).
(def %next
  (fn (_ rd)
    (def start (Bytes left rd))
    (def tag (Bytes get-u8 rd))
    (when (= (& tag 31) 31) (%fail "a multi-byte tag"))
    (def len (%length rd))
    (when (> len (Bytes left rd)) (%fail "an element longer than what holds it"))
    (def contents (Bytes get rd len))
    (list tag contents
          (list (first contents) (- (first (rest contents)) (- start (+ (Bytes left rd) len))) (+ len (- start (+ (Bytes left rd) len)))))))

; Days since 1970-01-01 of a civil date (Hinnant's days_from_civil).
(def %days
  (fn (_ y m d)
    (def y2 (if (<= m 2) (- y 1) y))
    (def era (if (>= y2 0) (%div y2 400) (%div (- y2 399) 400)))
    (def yoe (- y2 (* era 400)))
    (def doy (+ (%div (+ (* 153 (+ m (if (> m 2) -3 9))) 2) 5) (- d 1)))
    (def doe (+ (* yoe 365) (%div yoe 4) (- 0 (%div yoe 100)) doy))
    (+ (* era 146097) doe -719468)))

(def %digits
  (fn (_ r at n)
    ((fn (self i acc)
       (if (= i n) acc
         (do (def c (Bytes ref r (+ at i)))
             (unless (and (>= c 48) (<= c 57)) (%fail "a time with a non-digit"))
             (self (+ i 1) (+ (* acc 10) (- c 48))))))
     0 0)))

(def-class Der ()
  (static
    (method read (self (param r ANY "A region holding one DER element, or a STRING up to its first NUL"))
      (doc "The one element a region holds, as (TAG CONTENTS WHOLE): CONTENTS and WHOLE are regions of the input. Raises a label 'value when the region holds anything more or less."
        (returns LIST "(TAG CONTENTS WHOLE)")
        (example "(first (Der read (Bytes of-hex \"020101\")))" "2"))
      (def rd (Bytes reader (Bytes of r)))
      (def e (%next rd))
      (unless (= (Bytes left rd) 0) (%fail "bytes after the element"))
      e)
    (method items (self (param contents LIST "A constructed element's contents, a region"))
      (doc "The elements a SEQUENCE's or SET's contents hold, in order, each (TAG CONTENTS WHOLE)."
        (returns LIST "A list of elements")
        (example "(List length (Der items (first (rest (Der read (Bytes of-hex \"3006020101020102\"))))))" "2"))
      (def rd (Bytes reader contents))
      ((fn (self acc) (if (= (Bytes left rd) 0) (List reverse acc) (self (pair (%next rd) acc)))) ()))
    (method oid (self (param contents LIST "An OBJECT IDENTIFIER's contents, a region"))
      (doc "The OID in dotted form."
        (returns STRING "Its dotted form")
        (example "(Der oid (first (rest (Der read (Bytes of-hex \"06082a8648ce3d040302\")))))" "\"1.2.840.10045.4.3.2\""))
      (def n (Bytes length contents))
      (when (= n 0) (%fail "an empty OID"))
      (def b0 (Bytes ref contents 0))
      (def head (if (< b0 80) (list (%div b0 40) (- b0 (* 40 (%div b0 40)))) (list 2 (- b0 80))))
      (def arcs
        ((fn (self i acc v)
           (if (= i n) (if (= v 0) (List reverse acc) (%fail "an OID cut short"))
             (do (def b (Bytes ref contents i))
                 (def v2 (| (<< v 7) (& b 127)))
                 (if (>= b 128) (self (+ i 1) acc v2) (self (+ i 1) (pair v2 acc) 0)))))
         1 () 0))
      (Str8 join "." (List map (fn (_ a) (Str8 str a)) (List append head arcs))))
    (method time (self (param tag INTEGER "23 for UTCTime, 24 for GeneralizedTime")
                       (param contents LIST "The time's contents, a region"))
      (doc "A UTCTime (YYMMDDHHMMSSZ, years 1950-2049 as RFC 5280 says) or GeneralizedTime (YYYYMMDDHHMMSSZ) as seconds since the Unix epoch."
        (returns INTEGER "Seconds since 1970-01-01T00:00:00Z")
        (example "(Der time 23 (Bytes of \"700101000000Z\"))" "0"))
      (def long (= tag 24))
      (def n (Bytes length contents))
      (unless (and (= n (if long 15 13)) (= (Bytes ref contents (- n 1)) 90)) (%fail "a time not in DER's form"))
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
      (when (or (= (Bytes length contents) 0) (not (= (Bytes ref contents 0) 0))) (%fail "a BIT STRING with unused bits"))
      (Bytes sub contents 1 (- (Bytes length contents) 1)))
    (method small (self (param contents LIST "An INTEGER's contents, a region, small and non-negative"))
      (doc "A small non-negative INTEGER's value, as a version or a path length is."
        (returns INTEGER "The value")
        (example "(Der small (first (rest (Der read (Bytes of-hex \"020102\")))))" "2"))
      (when (or (= (Bytes length contents) 0) (> (Bytes length contents) 4) (>= (Bytes ref contents 0) 128)) (%fail "not a small INTEGER"))
      ((fn (self i acc) (if (= i (Bytes length contents)) acc (self (+ i 1) (| (<< acc 8) (Bytes ref contents i))))) 0 0))))

(doc (provide x/codec/der Der)
  "DER (X.690) over regions: (Der read r) answers an element (TAG CONTENTS WHOLE); items, oid, time, bits and small read what is inside one.")
