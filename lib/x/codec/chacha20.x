; chacha20.x -- ChaCha20: the stream cipher (RFC 8439) in pure x-lang.
;
; An SSH written in x needs the cipher where no C library is present:
; chacha20-poly1305@openssh.com is what the client and server agree on
; first.  The cipher is the keystream generator; the AEAD construction
; around it (Poly1305 over the ciphertext, the packet-length cipher) is
; the transport's business and lives beside it.
;
; The shape is sha1.x's: pure INT on the C bit ops, every addition
; through the cached int '+ prim and masked to 32 bits, so the cipher is
; tower-proof; a 16-word state built once from the key and the IV; and a
; compiled engine in x/codec/chacha20-jit, adopted only after it agrees
; with this cipher.  The IV is the sixteen bytes of state words 12..15,
; which is how both nonce shapes are one cipher: RFC 8439 puts a 32-bit
; counter then a 96-bit nonce there, the original cipher -- and the
; openssh AEAD -- a 64-bit counter then a 64-bit nonce.  The block counter
; is word 12, carried into word 13 when it wraps, as OpenSSL's does.
(module x/codec/chacha20)

(import x/type/vector)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(import x/core/doors char->int int& int+ int- int< int<< int= int>> int| obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).  Every operand is an int.
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))

(def %mask 4294967295)

; "expand 32-byte k", as four little-endian words (2.3):
; 61707865 3320646e 79622d32 6b206574
(def %sigma (list 1634760805 857760878 2036477234 1797285236))

(def %rotl (fn (_ x n) (int& (int| (int<< x n) (int>> x (int- 32 n))) %mask)))

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

; The little-endian word at byte i of s.
(def %word
  (fn (_ s i)
    (int| (%byte s i)
         (int| (int<< (%byte s (int+ i 1)) 8)
              (int| (int<< (%byte s (int+ i 2)) 16)
                   (int<< (%byte s (int+ i 3)) 24))))))

; n little-endian words from byte i of s, consed onto tail.
(def %words
  (fn (self s i n tail)
    (if (int= n 0) tail (pair (%word s i) (self s (int+ i 4) (int- n 1) tail)))))

; The sixteen state words (2.3): the constants, the key's eight words,
; then the IV's four -- counter and nonce, however the caller lays them.
(def %state
  (fn (_ key iv)
    (def tail (%words key 0 8 (%words iv 0 4 ())))
    (pair 1634760805 (pair 857760878 (pair 2036477234 (pair 1797285236 tail))))))

; Vectors carry word k in slot k+1 (the length rides slot 0), as sha1.x's
; message schedule does.
(def %fill!
  (fn (self v i ws)
    (unless (null? ws)
      (do (obj-set! v i (first ws)) (self v (int+ i 1) (rest ws))))))

(def %copy!
  (fn (self w v i)
    (unless (int= i 17)
      (do (obj-set! w i (obj-ref v i)) (self w v (int+ i 1))))))

; The quarter round (2.1) on slots a b c d of w.
(def %qr!
  (fn (_ w a b c d)
    (obj-set! w a (int& (int+ (obj-ref w a) (obj-ref w b)) %mask))
    (obj-set! w d (%rotl (%xor (obj-ref w d) (obj-ref w a)) 16))
    (obj-set! w c (int& (int+ (obj-ref w c) (obj-ref w d)) %mask))
    (obj-set! w b (%rotl (%xor (obj-ref w b) (obj-ref w c)) 12))
    (obj-set! w a (int& (int+ (obj-ref w a) (obj-ref w b)) %mask))
    (obj-set! w d (%rotl (%xor (obj-ref w d) (obj-ref w a)) 8))
    (obj-set! w c (int& (int+ (obj-ref w c) (obj-ref w d)) %mask))
    (obj-set! w b (%rotl (%xor (obj-ref w b) (obj-ref w c)) 7))))

; A column round then a diagonal round (2.3), in slots.
(def %double-round!
  (fn (_ w)
    (%qr! w 1 5 9 13) (%qr! w 2 6 10 14) (%qr! w 3 7 11 15) (%qr! w 4 8 12 16)
    (%qr! w 1 6 11 16) (%qr! w 2 7 12 13) (%qr! w 3 8 9 14) (%qr! w 4 5 10 15)))

(def %rounds!
  (fn (self w n)
    (unless (int= n 0) (do (%double-round! w) (self w (int- n 1))))))

(def %sum!
  (fn (self w v i)
    (unless (int= i 17)
      (do (obj-set! w i (int& (int+ (obj-ref w i) (obj-ref v i)) %mask))
          (self w v (int+ i 1))))))

; One block (2.3): the state's twenty rounds summed into the state, left
; in w as the sixteen keystream words.
(def %block!
  (fn (_ v w)
    (%copy! w v 1)
    (%rounds! w 10)
    (%sum! w v 1)))

; The counter: word 12, carried into word 13.
(def %bump!
  (fn (_ v)
    (obj-set! v 13 (int& (int+ (obj-ref v 13) 1) %mask))
    (when (int= (obj-ref v 13) 0)
      (obj-set! v 14 (int& (int+ (obj-ref v 14) 1) %mask)))))

; Keystream byte i (0..63) of the block in w, serialized little-endian.
(def %key-byte
  (fn (_ w i) (int& (int>> (obj-ref w (int+ (int>> i 2) 1)) (int<< (int& i 3) 3)) 255)))

; Bytes pos.. of the region, up to the block's end or the region's, each
; XORed with its keystream byte into out.
(def %emit!
  (fn (self w s start len out p pos i)
    (unless (if (int= i 64) #t (int= pos len))
      (do (ptr-set! p pos (%xor (%byte s (int+ start pos)) (%key-byte w i)) 1)
          (self w s start len out p (int+ pos 1) (int+ i 1))))))

(def %blocks!
  (fn (self v w s start len out p pos)
    (when (int< pos len)
      (do (%block! v w)
          (%emit! w s start len out p pos 0)
          (%bump! v)
          (self v w s start len out p (int+ pos 64))))))

; The pure-x cipher: the state words, a byte region -> a fresh string of
; len bytes, each XORed with the keystream.  The compiled engine answers
; the same string, so it is a drop-in for this function.
(def %xor-bytes
  (fn (_ st s start len)
    (def v (Vector make 16 0))
    (def w (Vector make 16 0))
    (def out (str-make len))
    (%fill! v 1 st)
    (%blocks! v w s start len out (str->ptr out) 0)
    out))

; n zero bytes, so a block is the keystream itself: four at a write, and
; the odd ones singly.
(def %zeros
  (fn (_ n)
    (def s (str-make n))
    (def p (str->ptr s))
    ((fn (self i)
       (if (int< (int+ i 3) n) (do (ptr-set! p i 0 4) (self (int+ i 4)))
         (unless (int= i n) (do (ptr-set! p i 0 1) (self (int+ i 1))))))
     0)
    s))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As sha1.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x cipher above, and built only for a
; region of %jit-threshold bytes or more or on (ChaCha20 jit!).
;
; THE BAR IS THE MEASURED BREAKEVEN, 2026-10-08, arm64, asm cache warm:
; pure-x runs at 3.6KB/s (4000 bytes in 1.1s), the build is 2.3s (6.9s on
; a cold cache), and the engine 1.3MB/s (64KB in 49ms), so the two cost
; the same at ~8KB.
(def %entry ())
(def %jit-threshold 8192)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit chacha20) %xor-bytes
          (fn (_)
            (import x/codec/chacha20-jit)
            ((prim-ref (lit chacha20) (lit jit-make)) %xor-bytes))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ st s start len)
    (when (if (int< len %jit-threshold) #f
            ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
             %entry))
      (%jit-try!))
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) st s start len)
         (%xor-bytes st s start len)))
     %entry)))

; The optional region: all of s, measured to its first NUL, when absent.
(def %region
  (fn (_ s r)
    (match ((null? r) (list 0 (Str8 length s)))
           (#t (list (first r) (first (rest r)))))))

(def-class ChaCha20 ()
  (static
    (method xor (self (param key STRING "The 256-bit key: 32 bytes are read")
                      (param iv STRING "Block counter and nonce: 16 bytes are read, state words 12..15 little-endian")
                      (param s STRING "The bytes to encrypt or decrypt")
                      . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The ChaCha20 stream cipher (RFC 8439): every byte of the region XORed with the keystream for key and iv, answered as a fresh string of LEN bytes. One operation encrypts and decrypts. The iv is the sixteen bytes of state words 12..15: RFC 8439's 32-bit counter then 96-bit nonce, or the original cipher's 64-bit counter then 64-bit nonce -- the counter is word 12, carried into word 13. GIVE THE REGION FOR BINARY INPUT: s's own length is measured to its first NUL, and the answer's is LEN, which only the caller knows. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "LEN bytes")
        (example "(ChaCha20 xor (Str8 pad-right 32 #\\k \"\") (Str8 pad-right 16 #\\i \"\") (ChaCha20 xor (Str8 pad-right 32 #\\k \"\") (Str8 pad-right 16 #\\i \"\") \"abc\") 0 3)" "\"abc\""))
      (def r (%region s span))
      (%run (%state key iv) s (first r) (first (rest r))))
    (method block (self (param key STRING "The 256-bit key: 32 bytes are read")
                        (param iv STRING "Block counter and nonce: 16 bytes are read"))
      (doc "The 64-byte keystream block for key and iv (RFC 8439 2.3): the cipher over sixty-four zero bytes. The first 32 bytes of block 0 are what the Poly1305 one-time key is taken from."
        (returns STRING "64 bytes"))
      (%run (%state key iv) (%zeros 64) 0 64))
    (method jit! (self)
      (doc "Build and adopt the compiled cipher engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x cipher. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. xor also builds it on its own for any single region of 8KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/chacha20 ChaCha20)
  "ChaCha20 (RFC 8439): (ChaCha20 xor key iv s [start len]) encrypts or decrypts a byte region, (ChaCha20 block key iv) is a keystream block. Pure x-lang, with an optional differentially-verified JIT engine ((ChaCha20 jit!), or built on its own for a region of 8KB or more).")
