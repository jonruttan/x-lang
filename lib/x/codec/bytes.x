; bytes.x -- Bytes: binary buffers that carry their length.
;
; A string has no length of its own past its first NUL: byte-len, Str8
; length, Hex decode and Str8 append all stop there.  Protocol bytes --
; TLS records, SSH packets, digests -- have NULs anywhere, so their code
; keeps every length beside its buffer.  This class is that bookkeeping
; once.  A REGION is (BUF START LEN): LEN bytes of BUF from START, BUF any
; string; it is what the codecs take (Hmac, Hkdf) and what this class
; answers.  A WRITER grows a buffer as bytes are put; a READER walks a
; region and raises when a field runs past its end, since a short message
; is an error, never a zero.  Integers are big-endian, the network's
; order.
(module x/codec/bytes)

(import x/type/vector)
(import x/codec/hex)
(import x/sys/file)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

(def %r-buf (fn (_ r) (first r)))
(def %r-start (fn (_ r) (first (rest r))))
(def %r-len (fn (_ r) (first (rest (rest r)))))

; A fresh buffer of n bytes; one byte at least, since an empty region
; still names a buffer.
(def %fresh (fn (_ n) (%make-str (if (> n 0) n 1))))

; dst[at..] = the region's bytes.
(def %copy-into!
  (fn (_ p at r)
    (def s (%r-buf r))
    (def start (%r-start r))
    (def len (%r-len r))
    ((fn (self i)
       (unless (= i len)
         (do (%pset1 p (%add at i) (%byte s (%add start i)) 1) (self (%add i 1))))) 0)))

; --- writers: a vector of (BUF LEN CAP) ------------------------------

(def %room!
  (fn (self w n)
    (when (> (%add (%oref w 2) n) (%oref w 3))
      (do (def cap (* (%oref w 3) 2))
          (def buf (%make-str cap))
          (%copy-into! (%str->ptr buf) 0 (list (%oref w 1) 0 (%oref w 2)))
          (%oset! w 1 buf)
          (%oset! w 3 cap)
          (self w n)))))

(def %put-byte!
  (fn (_ w b)
    (%room! w 1)
    (%pset1 (%str->ptr (%oref w 1)) (%oref w 2) (& b 255) 1)
    (%oset! w 2 (%add (%oref w 2) 1))))

; n's low k bytes, most significant first.
(def %put-int!
  (fn (self w n k)
    (unless (= k 0)
      (do (%put-byte! w (>> n (<< (%sub k 1) 3)))
          (self w n (%sub k 1))))))

(def %put-region!
  (fn (_ w r)
    (%room! w (%r-len r))
    (%copy-into! (%str->ptr (%oref w 1)) (%oref w 2) r)
    (%oset! w 2 (%add (%oref w 2) (%r-len r)))))

; --- readers: a vector of (BUF POS END) ------------------------------

(def %need
  (fn (_ rd n)
    (when (> (%add (%oref rd 2) n) (%oref rd 3))
      (Err raise (lit value) "Bytes: a field runs past the end of its message" n))))

(def %get-int
  (fn (_ rd k)
    (%need rd k)
    (def s (%oref rd 1))
    (def pos (%oref rd 2))
    (%oset! rd 2 (%add pos k))
    ((fn (self i acc) (if (= i k) acc (self (%add i 1) (| (<< acc 8) (%byte s (%add pos i)))))) 0 0)))

(def %as-region
  (fn (_ x) (if (str? x) (list x 0 (Str8 length x)) x)))

(def-class Bytes ()
  (static
    ; --- regions
    (method region (self (param s STRING "A buffer")
                         (param start INTEGER "The first byte")
                         (param len INTEGER "How many bytes"))
      (doc "The region (BUF START LEN): len bytes of s from start. No copy is made."
        (returns LIST "(BUF START LEN)")
        (example "(Bytes hex (Bytes region \"abcdef\" 2 2))" "\"6364\""))
      (list s start len))
    (method of (self (param x ANY "A region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "x as a region: a region as it is, a STRING as its bytes up to its first NUL. What a function taking either calls first."
        (returns LIST "(BUF START LEN)")
        (example "(Bytes length (Bytes of \"abc\"))" "3"))
      (%as-region x))
    (method length (self (param r LIST "A region (BUF START LEN)"))
      (doc "How many bytes the region holds."
        (returns INTEGER "LEN")
        (example "(Bytes length (Bytes of-hex \"00ff00\"))" "3"))
      (%r-len r))
    (method ref (self (param r LIST "A region (BUF START LEN)")
                      (param i INTEGER "An index into the region, from 0"))
      (doc "The region's byte at i, 0-255. The index is not checked against the region."
        (returns INTEGER "A byte")
        (example "(Bytes ref (Bytes of-hex \"00ff00\") 1)" "255"))
      (%byte (%r-buf r) (%add (%r-start r) i)))
    (method copy (self (param r ANY "A region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "A fresh buffer holding the region's bytes, as a region of its own starting at 0."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes hex (Bytes copy (Bytes region \"abcdef\" 1 3)))" "\"626364\""))
      (def rr (%as-region r))
      (def out (%fresh (%r-len rr)))
      (%copy-into! (%str->ptr out) 0 rr)
      (list out 0 (%r-len rr)))
    (method sub (self (param r LIST "A region (BUF START LEN)")
                      (param start INTEGER "Where the part starts, from the region's start")
                      (param len INTEGER "How many bytes"))
      (doc "Part of a region, as a region of the same buffer. No copy is made, and the bounds are checked."
        (returns LIST "(BUF START+start len)")
        (example "(Bytes hex (Bytes sub (Bytes of-hex \"00112233\") 1 2))" "\"1122\""))
      (when (> (%add start len) (%r-len r))
        (Err raise (lit value) "Bytes sub: past the end of the region" (list start len)))
      (list (%r-buf r) (%add (%r-start r) start) len))
    (method join (self . (param parts LIST "Regions (BUF START LEN), or STRINGs up to their first NUL"))
      (doc "The parts' bytes end to end, in a fresh buffer."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes hex (Bytes join (Bytes of-hex \"00\") \"ab\" (Bytes of-hex \"ff\")))" "\"006162ff\""))
      (def rs (List map %as-region parts))
      (def total ((fn (self l n) (if (null? l) n (self (rest l) (%add n (%r-len (first l)))))) rs 0))
      (def out (%fresh total))
      (def p (%str->ptr out))
      ((fn (self l at) (unless (null? l) (do (%copy-into! p at (first l)) (self (rest l) (%add at (%r-len (first l))))))) rs 0)
      (list out 0 total))
    (method same? (self (param a LIST "A region") (param b LIST "A region"))
      (doc "#t when the regions hold the same bytes. Every byte is compared whatever the first difference, so the time taken does not tell an attacker how much of a tag was right."
        (returns BOOL "#t when equal")
        (example "(Bytes same? (Bytes of-hex \"0102\") (Bytes sub (Bytes of-hex \"000102\") 1 2))" "#t"))
      (if (= (%r-len a) (%r-len b))
        (= 0 ((fn (self i acc)
                (if (= i (%r-len a)) acc
                  (self (%add i 1) (| acc (^ (%byte (%r-buf a) (%add (%r-start a) i))
                                             (%byte (%r-buf b) (%add (%r-start b) i)))))))
              0 0))
        #f))
    (method hex (self (param r LIST "A region"))
      (doc "The region's bytes as lowercase hex, two characters a byte, NULs included."
        (returns STRING "Hex text")
        (example "(Bytes hex (Bytes of-hex \"00Ab\"))" "\"00ab\""))
      (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (%sub i 1) (pair (Bytes ref r i) acc))))
                         (%sub (%r-len r) 1) ())))
    (method of-hex (self (param text STRING "Hex text, either case"))
      (doc "The bytes the hex text spells, NULs included, in a fresh buffer. Odd length or a non-hex character raises, as Hex decode-bytes does."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes length (Bytes of-hex \"000000\"))" "3"))
      (Bytes of-list (Hex decode-bytes text)))
    (method of-list (self (param bs LIST "Byte values, 0-255"))
      (doc "The bytes of a list, in a fresh buffer."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes hex (Bytes of-list (list 0 1 255)))" "\"0001ff\""))
      (def n (List length bs))
      (def out (%fresh n))
      (def p (%str->ptr out))
      ((fn (self i l) (unless (null? l) (do (%pset1 p i (& (first l) 255) 1) (self (%add i 1) (rest l))))) 0 bs)
      (list out 0 n))
    (method random (self (param n INTEGER "How many bytes"))
      (doc "n bytes from the kernel's CSPRNG, /dev/urandom, in a fresh buffer. Raises a label 'io when the device cannot be read in full."
        (returns LIST "(BUF 0 n)")
        (sample "(Bytes random 32)" "32 random bytes"))
      (def fd (File open "/dev/urandom" (lit rdonly)))
      (when (< fd 0) (Err raise (lit io) "Bytes random: no /dev/urandom" ()))
      (def buf (%fresh n))
      (def got (File read fd buf n))
      (File close fd)
      (unless (= got n) (Err raise (lit io) "Bytes random: /dev/urandom came up short" got))
      (list buf 0 n))

    ; --- writers
    (method writer (self)
      (doc "A fresh writer: an empty buffer that grows as bytes are put."
        (returns OBJECT "A writer")
        (example "(Bytes hex (Bytes written (Bytes writer)))" "\"\""))
      (def w (Vector make 3 0))
      (%oset! w 1 (%make-str 256))
      (%oset! w 2 0)
      (%oset! w 3 256)
      w)
    (method put-u8 (self (param w OBJECT "A writer") (param n INTEGER "The byte, 0-255"))
      (doc "Put one byte."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u8 w 7) (Bytes hex (Bytes written w))) (Bytes writer))" "\"07\""))
      (%put-byte! w n))
    (method put-u16 (self (param w OBJECT "A writer") (param n INTEGER "The value, below 2^16"))
      (doc "Put a 16-bit big-endian integer."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u16 w 772) (Bytes hex (Bytes written w))) (Bytes writer))" "\"0304\""))
      (%put-int! w n 2))
    (method put-u24 (self (param w OBJECT "A writer") (param n INTEGER "The value, below 2^24"))
      (doc "Put a 24-bit big-endian integer."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u24 w 65536) (Bytes hex (Bytes written w))) (Bytes writer))" "\"010000\""))
      (%put-int! w n 3))
    (method put-u32 (self (param w OBJECT "A writer") (param n INTEGER "The value, below 2^32"))
      (doc "Put a 32-bit big-endian integer."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u32 w 258) (Bytes hex (Bytes written w))) (Bytes writer))" "\"00000102\""))
      (%put-int! w n 4))
    (method put (self (param w OBJECT "A writer") (param r ANY "A region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "Put a region's bytes."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put w \"ab\") (Bytes put w (Bytes of-hex \"00\")) (Bytes hex (Bytes written w))) (Bytes writer))" "\"616200\""))
      (%put-region! w (%as-region r)))
    (method written (self (param w OBJECT "A writer"))
      (doc "What has been put so far, as a region of the writer's buffer. Putting more may move the buffer; take the region again after."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes length (Bytes written (Bytes writer)))" "0"))
      (list (%oref w 1) 0 (%oref w 2)))
    (method size (self (param w OBJECT "A writer"))
      (doc "How many bytes have been put."
        (returns INTEGER "The count")
        (example "(Bytes size (Bytes writer))" "0"))
      (%oref w 2))
    (method patch-u16 (self (param w OBJECT "A writer") (param at INTEGER "Where, a byte already put") (param n INTEGER "The value, below 2^16"))
      (doc "Overwrite two bytes already put with n, big-endian: how a length is filled in once what it measures has been written."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u16 w 0) (Bytes put w \"abc\") (Bytes patch-u16 w 0 3) (Bytes hex (Bytes written w))) (Bytes writer))" "\"0003616263\""))
      (when (> (%add at 2) (%oref w 2)) (Err raise (lit value) "Bytes patch: past what was written" at))
      (def p (%str->ptr (%oref w 1)))
      (%pset1 p at (& (>> n 8) 255) 1)
      (%pset1 p (%add at 1) (& n 255) 1))
    (method patch-u24 (self (param w OBJECT "A writer") (param at INTEGER "Where, a byte already put") (param n INTEGER "The value, below 2^24"))
      (doc "Overwrite three bytes already put with n, big-endian."
        (returns ANY "nil")
        (example "((fn (_ w) (Bytes put-u24 w 0) (Bytes patch-u24 w 0 258) (Bytes hex (Bytes written w))) (Bytes writer))" "\"000102\""))
      (when (> (%add at 3) (%oref w 2)) (Err raise (lit value) "Bytes patch: past what was written" at))
      (def p (%str->ptr (%oref w 1)))
      (%pset1 p at (& (>> n 16) 255) 1)
      (%pset1 p (%add at 1) (& (>> n 8) 255) 1)
      (%pset1 p (%add at 2) (& n 255) 1))

    ; --- readers
    (method reader (self (param r ANY "A region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "A reader over the region, at its first byte."
        (returns OBJECT "A reader")
        (example "(Bytes get-u16 (Bytes reader (Bytes of-hex \"0304\")))" "772"))
      (def rr (%as-region r))
      (def rd (Vector make 3 0))
      (%oset! rd 1 (%r-buf rr))
      (%oset! rd 2 (%r-start rr))
      (%oset! rd 3 (%add (%r-start rr) (%r-len rr)))
      rd)
    (method get-u8 (self (param rd OBJECT "A reader"))
      (doc "Read one byte. Raises a label 'value past the end."
        (returns INTEGER "0-255")
        (example "(Bytes get-u8 (Bytes reader (Bytes of-hex \"ff\")))" "255"))
      (%get-int rd 1))
    (method get-u16 (self (param rd OBJECT "A reader"))
      (doc "Read a 16-bit big-endian integer."
        (returns INTEGER "The value")
        (example "(Bytes get-u16 (Bytes reader (Bytes of-hex \"0100\")))" "256"))
      (%get-int rd 2))
    (method get-u24 (self (param rd OBJECT "A reader"))
      (doc "Read a 24-bit big-endian integer."
        (returns INTEGER "The value")
        (example "(Bytes get-u24 (Bytes reader (Bytes of-hex \"010000\")))" "65536"))
      (%get-int rd 3))
    (method get-u32 (self (param rd OBJECT "A reader"))
      (doc "Read a 32-bit big-endian integer."
        (returns INTEGER "The value")
        (example "(Bytes get-u32 (Bytes reader (Bytes of-hex \"00000102\")))" "258"))
      (%get-int rd 4))
    (method get (self (param rd OBJECT "A reader") (param n INTEGER "How many bytes"))
      (doc "The next n bytes as a region of the reader's buffer, no copy. Raises a label 'value when fewer are left."
        (returns LIST "(BUF POS n)")
        (example "(Bytes hex (Bytes get (Bytes reader (Bytes of-hex \"00112233\")) 3))" "\"001122\""))
      (%need rd n)
      (def pos (%oref rd 2))
      (%oset! rd 2 (%add pos n))
      (list (%oref rd 1) pos n))
    (method left (self (param rd OBJECT "A reader"))
      (doc "How many bytes are left to read."
        (returns INTEGER "The count")
        (example "(Bytes left (Bytes reader (Bytes of-hex \"0011\")))" "2"))
      (%sub (%oref rd 3) (%oref rd 2)))
    (method rest (self (param rd OBJECT "A reader"))
      (doc "What is left to read, as a region; the reader is then at its end."
        (returns LIST "(BUF POS LEFT)")
        (example "((fn (_ rd) (Bytes get-u8 rd) (Bytes hex (Bytes rest rd))) (Bytes reader (Bytes of-hex \"001122\")))" "\"1122\""))
      (Bytes get rd (Bytes left rd)))))

(doc (provide x/codec/bytes Bytes)
  "Binary buffers that carry their length: regions (BUF START LEN), a growable writer, and a bounds-checked reader, for protocol bytes with NULs anywhere.")
