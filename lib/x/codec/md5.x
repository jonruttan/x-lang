; md5.x -- Md5: the MD5 digest (RFC 1321) in pure x-lang.
;
; MD5 is broken for collision resistance and is here for what still names
; things by it: md5sum's files, and crypt(3)'s $1$ password hash, which
; Crypt md5 builds on.  The shape is sha1.x's: pure INT on the C bit ops,
; every addition through the cached int '+ prim and masked to 32 bits, and
; the padded message addressed virtually, with no padded copy built.  MD5
; reads its words and writes its length little-endian, where SHA-1 is
; big-endian.
(module x/codec/md5)

(import x/type/vector)
(import x/sys/gc)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %mul (prim-ref 'int '*))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %cvt (prim-ref (lit convert) (lit to)))
(def %string-type (Type named STRING))
(def %mask 4294967295)

; 67452301 efcdab89 98badcfe 10325476 (3.3)
(def %ih (list 1732584193 4023233417 2562383102 271733878))

; T[i] = floor(2^32 * |sin(i + 1)|) (3.4), in decimal
(def %k (Vector from-list (lit (
  3614090360 3905402710 606105819 3250441966 4118548399 1200080426 2821735955 4249261313
  1770035416 2336552879 4294925233 2304563134 1804603682 4254626195 2792965006 1236535329
  4129170786 3225465664 643717713 3921069994 3593408605 38016083 3634488961 3889429448
  568446438 3275163606 4107603335 1163531501 2850285829 4243563512 1735328473 2368359562
  4294588738 2272392833 1839030562 4259657740 2763975236 1272893353 4139469664 3200236656
  681279174 3936430074 3572445317 76029189 3654602809 3873151461 530742520 3299628645
  4096336452 1126891415 2878612391 4237533241 1700485571 2399980690 4293915773 2240044497
  1873313359 4264355552 2734768916 1309151649 4149444226 3174756917 718787259 3951481745))))

; the shift each step rotates by (3.4), four to a round
(def %r (Vector from-list (lit (7 12 17 22 5 9 14 20 4 11 16 23 6 10 15 21))))

(def %rotl (fn (_ x n) (& (| (<< x n) (>> x (%sub 32 n))) %mask)))

; Byte i of the padded message: the message; then 0x80; then zeros; then
; the bit length, little-endian in the last 8 bytes.
(def %byte
  (fn (_ s len total i)
    (match
      ((< i len) (%char->int (%byte-ref s i)))
      ((= i len) 128)
      ((< i (%sub total 8)) 0)
      (#t (& (>> (%mul len 8) (<< (%sub i (%sub total 8)) 3)) 255)))))

; word j of the block at BASE, little-endian
(def %word
  (fn (_ s len total base)
    (| (%byte s len total base)
       (| (<< (%byte s len total (%add base 1)) 8)
          (| (<< (%byte s len total (%add base 2)) 16)
             (<< (%byte s len total (%add base 3)) 24))))))

; X[j] in slot j+1 of a 16-slot vector (the length rides slot 0)
(def %fill!
  (fn (self s len total base x j)
    (unless (= j 16)
      (do (%oset! x (%add j 1) (%word s len total (%add base (<< j 2))))
          (self s len total base x (%add j 1))))))

; step i's function of b c d, and the word it reads (3.4)
(def %f
  (fn (_ i b c d)
    (match
      ((< i 16) (| (& b c) (& (& (~ b) %mask) d)))
      ((< i 32) (| (& b d) (& c (& (~ d) %mask))))
      ((< i 48) (^ b (^ c d)))
      (#t (^ c (| b (& (~ d) %mask)))))))

(def %g
  (fn (_ i)
    (match
      ((< i 16) i)
      ((< i 32) (& (%add (%mul 5 i) 1) 15))
      ((< i 48) (& (%add (%mul 3 i) 5) 15))
      (#t (& (%mul 7 i) 15)))))

(def %rounds
  (fn (self x i a b c d)
    (if (= i 64) (list a b c d)
      (let ((sum (& (%add (%add a (%f i b c d))
                          (%add (%oref %k (%add i 1)) (%oref x (%add (%g i) 1))))
                    %mask)))
        (self x (%add i 1) d
              (& (%add b (%rotl sum (%oref %r (%add (<< (>> i 4) 2) (%add (& i 3) 1))))) %mask)
              b c)))))

(def %sum
  (fn (self hs rs)
    (if (null? hs) ()
      (pair (& (%add (first hs) (first rs)) %mask) (self (rest hs) (rest rs))))))

(def %blocks
  (fn (self s len total base x hs)
    (match
      ((= base total) (do (Heap collect) hs))
      (#t
        (do (when (and (> base 0) (= (& (>> base 6) 7) 0)) (Heap collect))
            (%fill! s len total base x 0)
            (self s len total (%add base 64) x
              (%sum hs (%rounds x 0 (first hs) (first (rest hs)) (first (rest (rest hs)))
                                (first (rest (rest (rest hs))))))))))))

; bytes -> the four state words; the optional length is the caller's claim
(def %digest-words
  (fn (_ s . n)
    (def len (match ((null? n) (Str8 length s)) (#t (first n))))
    (%blocks s len (<< (%add (>> (%add len 8) 6) 1) 6) 0 (Vector make 16 0) %ih)))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As sha1.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x digest above, and built only for an
; input of %jit-threshold bytes or more or on (Md5 jit!).  The digests
; built on MD5 -- crypt's $1$, a thousand of them a hash -- ask for it.
(def %entry ())
(def %jit-threshold 8192)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit md5) %digest-words
          (fn (_)
            (import x/codec/sha-jit)
            ((prim-ref (lit md5) (lit jit-make)) %k %r %ih %digest-words))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; the state words of S's first N bytes (its length where N is not given),
; or, given OUT after N, the digest's bytes written there and OUT answered:
; the compiled engine writes them itself, pure-x through %bytes
(def %words
  (fn (_ s . more)
    (def len (match ((null? more) (Str8 length s)) (#t (first more))))
    (def out (match ((null? more) ()) ((null? (rest more)) ()) (#t (first (rest more)))))
    (when (and (>= len %jit-threshold)
               ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
                %entry))
      (%jit-try!))
    ; one send: an entry's compiled version is nil unless it is compiled
    ((fn (_ c)
       (match
         ((null? c) (if (null? out) (%digest-words s len) (%bytes (%digest-words s len) out)))
         ((null? out) (c s len))
         (#t (c s len out))))
     ((fn (_ entry) (if (null? entry) () (entry compiled))) %entry))))

; a state word's four bytes, low first, as hex
(def %hex-word
  (fn (_ wd)
    (Str8 join ""
      (List map (fn (_ k) (Str pad-left 2 #\0 (%cvt (& (>> wd (<< k 3)) 255) %string-type 16)))
                (list 0 1 2 3)))))

(def %hex (fn (_ hs) (Str8 join "" (List map %hex-word hs))))

(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

; the state words as the digest's sixteen bytes, low byte of each word
; first, written into OUT
(def %bytes
  (fn (_ hs out)
    (def p (%str->ptr out))
    (def put
      (fn (self ws i)
        (unless (null? ws)
          (do (%pset1 p i (& (first ws) 255) 1)
              (%pset1 p (%add i 1) (& (>> (first ws) 8) 255) 1)
              (%pset1 p (%add i 2) (& (>> (first ws) 16) 255) 1)
              (%pset1 p (%add i 3) (& (>> (first ws) 24) 255) 1)
              (self (rest ws) (%add i 4))))))
    (do (put hs 0) out)))

(def-class Md5 ()
  (static
    (method hex (self (param s STRING "Bytes to digest (a byte string)"))
      (doc "MD5 digest of s, as a 32-character lowercase hex string (RFC 1321). For what still names things by MD5 -- md5sum's files and crypt(3)'s $1$ hash; MD5 is broken for collision resistance, so use Sha256 to trust."
        (returns STRING "32 hex characters")
        (example "(Md5 hex \"\")" "\"d41d8cd98f00b204e9800998ecf8427e\"")
        (example "(Md5 hex \"abc\")" "\"900150983cd24fb0d6963f7d28e17f72\""))
      (%hex (%words s)))
    (method hex-n (self (param s STRING "Byte region to digest")
                        (param n INTEGER "How many bytes of s to digest"))
      (doc "MD5 of the FIRST n BYTES of s, for binary input hex cannot measure (Str8 length stops at the first NUL). THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED: n past the region's allocation reads past the allocation."
        (returns STRING "32 hex characters")
        (example "(Md5 hex-n \"abc\" 3)" "\"900150983cd24fb0d6963f7d28e17f72\"")
        (example "(Md5 hex-n \"abc\" 0)" "\"d41d8cd98f00b204e9800998ecf8427e\""))
      (%hex (%words s n)))
    (method bytes-n (self (param s STRING "Byte region to digest")
                          (param n INTEGER "How many bytes of s to digest"))
      (doc "MD5 of the FIRST n BYTES of s, as a fresh buffer of the digest's 16 bytes -- binary, so read it by count, not as a string: a NUL among the bytes ends its string length. THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED, as hex-n's is."
        (returns STRING "A 16-byte buffer"))
      (%words s n (%make-str 17)))
    (method bytes-into (self (param s STRING "Byte region to digest")
                             (param n INTEGER "How many bytes of s to digest")
                             (param out STRING "A buffer of 16 bytes or more, written from its start"))
      (doc "MD5 of the FIRST n BYTES of s, its 16 bytes written into out, which is returned: bytes-n into a buffer you own, so a loop of digests makes none. The compiled engine writes the bytes itself, with no list between. THE LENGTHS ARE YOUR CLAIM AND ARE NOT CHECKED: out shorter than 16 bytes is written past."
        (returns STRING "out"))
      (%words s n out))
    (method bytes-writer (self)
      (doc "A function (s n out) doing what bytes-into does, for a loop of digests: the compiled engine itself once it is adopted, so each call pays no dispatch, or bytes-into's own path while it is not. It does not build the engine; call jit! first. Ask again after a state image loads: one held across it is the engine of the session that wrote it."
        (returns CALLABLE "(fn (_ s n out)) answering out"))
      ((fn (_ c) (if (null? c) (fn (_ s n out) (%words s n out)) c))
       (if (null? %entry) () ((fn (_ entry) (entry compiled)) %entry))))
    (method jit! (self)
      (doc "Build and adopt the compiled digest engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x digest. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hex also builds it on its own for any single input of 8KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/md5 Md5)
  "MD5 (RFC 1321): (Md5 hex s) digests a byte string, (Md5 hex-n s n) and (Md5 bytes-n s n) its first n bytes. Pure x-lang, with an optional differentially-verified JIT engine ((Md5 jit!), or built on its own for an input of 8KB or more).")
