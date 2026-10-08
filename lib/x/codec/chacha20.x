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

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))
(def %mask 4294967295)

; "expand 32-byte k", as four little-endian words (2.3):
; 61707865 3320646e 79622d32 6b206574
(def %sigma (list 1634760805 857760878 2036477234 1797285236))

(def %rotl (fn (_ x n) (& (| (<< x n) (>> x (%sub 32 n))) %mask)))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

; The little-endian word at byte i of s.
(def %word
  (fn (_ s i)
    (| (%byte s i)
       (| (<< (%byte s (%add i 1)) 8)
          (| (<< (%byte s (%add i 2)) 16)
             (<< (%byte s (%add i 3)) 24))))))

; n little-endian words from byte i of s, as a list.
(def %words
  (fn (self s i n)
    (if (= n 0) () (pair (%word s i) (self s (%add i 4) (%sub n 1))))))

; The sixteen state words (2.3): the constants, the key's eight words,
; then the IV's four -- counter and nonce, however the caller lays them.
(def %state
  (fn (_ key iv)
    (List append %sigma (%words key 0 8) (%words iv 0 4))))

; Vectors carry word k in slot k+1 (the length rides slot 0), as sha1.x's
; message schedule does.
(def %fill!
  (fn (self v i ws)
    (unless (null? ws)
      (do (%oset! v i (first ws)) (self v (%add i 1) (rest ws))))))

(def %copy!
  (fn (self w v i)
    (unless (= i 17)
      (do (%oset! w i (%oref v i)) (self w v (%add i 1))))))

; The quarter round (2.1) on slots a b c d of w.
(def %qr!
  (fn (_ w a b c d)
    (%oset! w a (& (%add (%oref w a) (%oref w b)) %mask))
    (%oset! w d (%rotl (^ (%oref w d) (%oref w a)) 16))
    (%oset! w c (& (%add (%oref w c) (%oref w d)) %mask))
    (%oset! w b (%rotl (^ (%oref w b) (%oref w c)) 12))
    (%oset! w a (& (%add (%oref w a) (%oref w b)) %mask))
    (%oset! w d (%rotl (^ (%oref w d) (%oref w a)) 8))
    (%oset! w c (& (%add (%oref w c) (%oref w d)) %mask))
    (%oset! w b (%rotl (^ (%oref w b) (%oref w c)) 7))))

; A column round then a diagonal round (2.3), in slots.
(def %double-round!
  (fn (_ w)
    (%qr! w 1 5 9 13) (%qr! w 2 6 10 14) (%qr! w 3 7 11 15) (%qr! w 4 8 12 16)
    (%qr! w 1 6 11 16) (%qr! w 2 7 12 13) (%qr! w 3 8 9 14) (%qr! w 4 5 10 15)))

(def %rounds!
  (fn (self w n)
    (unless (= n 0) (do (%double-round! w) (self w (%sub n 1))))))

(def %sum!
  (fn (self w v i)
    (unless (= i 17)
      (do (%oset! w i (& (%add (%oref w i) (%oref v i)) %mask))
          (self w v (%add i 1))))))

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
    (%oset! v 13 (& (%add (%oref v 13) 1) %mask))
    (when (= (%oref v 13) 0)
      (%oset! v 14 (& (%add (%oref v 14) 1) %mask)))))

; Keystream byte i (0..63) of the block in w, serialized little-endian.
(def %key-byte
  (fn (_ w i) (& (>> (%oref w (%add (>> i 2) 1)) (<< (& i 3) 3)) 255)))

; Bytes pos.. of the region, up to the block's end or the region's, each
; XORed with its keystream byte into out.
(def %emit!
  (fn (self w s start len out p pos i)
    (unless (or (= i 64) (= pos len))
      (do (%pset1 p pos (^ (%byte s (%add start pos)) (%key-byte w i)) 1)
          (self w s start len out p (%add pos 1) (%add i 1))))))

(def %blocks!
  (fn (self v w s start len out p pos)
    (unless (>= pos len)
      (do (%block! v w)
          (%emit! w s start len out p pos 0)
          (%bump! v)
          (self v w s start len out p (%add pos 64))))))

; The pure-x cipher: the state words, a byte region -> a fresh string of
; len bytes, each XORed with the keystream.  The compiled engine answers
; the same string, so it is a drop-in for this function.
(def %xor-bytes
  (fn (_ st s start len)
    (def v (Vector make 16 0))
    (def w (Vector make 16 0))
    (def out (%make-str len))
    (%fill! v 1 st)
    (%blocks! v w s start len out (%str->ptr out) 0)
    out))

; Sixty-four zero bytes, so a block is the keystream itself.
(def %zeros
  (fn (_ n)
    (def s (%make-str n))
    (def p (%str->ptr s))
    ((fn (self i) (unless (= i n) (do (%pset1 p i 0 1) (self (%add i 1))))) 0)
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
    (when (and (>= len %jit-threshold)
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
