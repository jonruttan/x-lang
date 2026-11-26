; gzip.x -- Gzip: a gzip member written a piece at a time.
;
; A gzip member (RFC 1952) is a ten-byte header, a raw DEFLATE stream, and
; eight bytes after it: the CRC-32 of what was compressed and its length
; modulo 2^32, both little-endian.  This class keeps the three in step
; over a stream fed in pieces, so a file is never held whole, and answers
; the member's bytes as regions (x/codec/bytes).  It does no I/O.
;
; The header names no file and no time, and its OS byte is 3 (Unix), so
; the same input gives the same member on any machine.  Compression is
; x/codec/deflate's and the sum x/codec/crc32's: no libz is reached.
;
; The reader is x/codec/inflate, whose stream leaves a member's trailer in
; (Inflate rest).
(module x/codec/gzip)

(import x/type/vector)
(import x/codec/bytes)
(import x/codec/deflate)
(import x/codec/crc32)
(import x/num/u32 u32-bits u32-srl)
(import x/core/doors int& int+ int>> obj-ref obj-set!)

; A stream is a vector: the Deflate stream, the CRC so far, the length so
; far as its low and high 16 bits, and whether the header has gone out.
; Two halves, because a 4-byte word holds no 32-bit count.
(def %Z 1)
(def %CRC 2)
(def %LO 3)
(def %HI 4)
(def %OPEN 5)

; 32 bits, as u32-bits holds them, put to w low byte first.
(def %put-le32!
  (fn (_ w bits)
    (do (Bytes put-u8 w (int& bits 255))
        (Bytes put-u8 w (int& (u32-srl bits 8) 255))
        (Bytes put-u8 w (int& (u32-srl bits 16) 255))
        (Bytes put-u8 w (int& (u32-srl bits 24) 255)))))

(def-class Gzip ()
  (doc "A gzip member (RFC 1952) written a piece at a time: its header, the compressed pieces and its CRC and length, as regions. No I/O is done and no libz is reached."
    (example "(Bytes hex (Bytes sub (Gzip feed (Gzip stream) \"\" 0 0 #t) 0 4))" "\"1f8b0800\"")
    (see stream) (see feed))
  (static
    (method stream (self)
      (doc "A fresh member, nothing written: what (Gzip feed) is given with each piece."
        (returns VECTOR "The stream")
        (example "(Bytes length (Gzip feed (Gzip stream) \"\" 0 0 #t))" "20"))
      (def g (Vector make 5 0))
      (obj-set! g %Z (Deflate stream))
      (obj-set! g %OPEN #f)
      g)

    (method feed (self (param g VECTOR "A (Gzip stream)")
                       (param s STRING "Bytes holding the next piece")
                       (param start INTEGER "Where the piece starts in s")
                       (param n INTEGER "How many bytes it is")
                       (param final BOOL "Is this the last piece? The member is then ended with its CRC and length"))
      (doc "Compress n more bytes into the member. Answers the bytes of the member they made: before the first piece's, the header; after the last piece's (final), the CRC-32 and the length. A member of no bytes is one final piece of none."
        (returns LIST "A region (BUF 0 LEN)")
        (example "(Bytes hex (Bytes sub (Gzip feed (Gzip stream) \"abc\" 0 3 #t) 0 10))" "\"1f8b0800000000000003\"")
        (example "((fn (_ r) (Bytes hex (Bytes sub r (- (Bytes length r) 8) 8))) (Gzip feed (Gzip stream) \"abc\" 0 3 #t))" "\"c241243503000000\""))
      (def w (Bytes writer))
      (unless (obj-ref g %OPEN)
        (do (Bytes put w (Bytes of-list (list 31 139 8 0 0 0 0 0 0 3)))
            (obj-set! g %OPEN #t)))
      (obj-set! g %CRC (Crc32 update (obj-ref g %CRC) s start n))
      (def low (int+ (obj-ref g %LO) n))
      (obj-set! g %LO (int& low 65535))
      (obj-set! g %HI (int& (int+ (obj-ref g %HI) (int>> low 16)) 65535))
      (def out (Deflate feed (obj-ref g %Z) s start n final))
      (Bytes put w (list (first out) 0 (first (rest out))))
      (when final
        (do (%put-le32! w (u32-bits (obj-ref g %CRC)))
            (Bytes put-u8 w (int& (obj-ref g %LO) 255))
            (Bytes put-u8 w (int>> (obj-ref g %LO) 8))
            (Bytes put-u8 w (int& (obj-ref g %HI) 255))
            (Bytes put-u8 w (int>> (obj-ref g %HI) 8))))
      (Bytes written w))))

(doc (provide x/codec/gzip Gzip)
  (example "(Bytes length (Gzip feed (Gzip stream) \"\" 0 0 #t))" "20")
  "A gzip member written a piece at a time, as regions: the header, the compressed pieces, the CRC-32 and the length. Compression is x/codec/deflate's; the reader is x/codec/inflate.")
