; poly1305.x -- Poly1305: the one-time authenticator (RFC 8439 2.5) in pure x-lang.
;
; The MAC half of chacha20-poly1305@openssh.com, which an SSH written in
; x needs where no C library is present: a tag over a packet, keyed by
; the first 32 keystream bytes of a ChaCha20 block.  This is the plain
; authenticator over a byte region; the AEAD framings around it (RFC
; 8439 2.8's padded lengths, openssh's none) are their users' business.
;
; The arithmetic is mod 2^130 - 5 on 26-bit limbs, five to a number, as
; poly1305-donna's 32-bit variant lays it out: a limb times a limb (or
; five times one) is under 2^56, a row of five under 2^59, so every
; product and sum fits the engine's 64-bit int and the cipher is
; tower-proof on the int prims.  A compiled engine in x/codec/poly1305-jit
; takes the block loop -- the hot part -- and is adopted only after it
; agrees with the one here; the key clamp, the padded last block and the
; final reduction stay in x on both paths.
(module x/codec/poly1305)

(import x/type/vector)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(import x/core/doors char->int int& int* int+ int- int< int<< int>> int| obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)
(def %M 67108863)
(def %M32 4294967295)

; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

; The little-endian 32-bit word at byte i of s.
(def %le32
  (fn (_ s i)
    (int| (%byte s i)
       (int| (int<< (%byte s (int+ i 1)) 8)
          (int| (int<< (%byte s (int+ i 2)) 16)
             (int<< (%byte s (int+ i 3)) 24))))))

; Vectors carry limb k in slot k+1 (the length rides slot 0).  h is the
; accumulator's five limbs; rv holds r's five limbs then 5*r1..5*r4,
; the multiples the reduction folds the high limbs back with.
(def %r-vector
  (fn (_ key)
    (def rv (Vector make 9 0))
    ; r clamped (2.5): the top four bits of each of its 32-bit words and
    ; the low two of the upper three are zero, which the limb masks apply
    (obj-set! rv 1 (int& (%le32 key 0) 67108863))
    (obj-set! rv 2 (int& (int>> (%le32 key 3) 2) 67108611))
    (obj-set! rv 3 (int& (int>> (%le32 key 6) 4) 67092735))
    (obj-set! rv 4 (int& (int>> (%le32 key 9) 6) 66076671))
    (obj-set! rv 5 (int& (int>> (%le32 key 12) 8) 1048575))
    (obj-set! rv 6 (int* (obj-ref rv 2) 5))
    (obj-set! rv 7 (int* (obj-ref rv 3) 5))
    (obj-set! rv 8 (int* (obj-ref rv 4) 5))
    (obj-set! rv 9 (int* (obj-ref rv 5) 5))
    rv))

; One block: the sixteen bytes at i of s, plus the 2^128 bit (hibit is
; 1<<24 at limb 4, or 0 for a padded last block), added to h and the
; sum multiplied by r mod 2^130 - 5.
(def %block!
  (fn (_ h rv s i hibit)
    (def h0 (int+ (obj-ref h 1) (int& (%le32 s i) %M)))
    (def h1 (int+ (obj-ref h 2) (int& (int>> (%le32 s (int+ i 3)) 2) %M)))
    (def h2 (int+ (obj-ref h 3) (int& (int>> (%le32 s (int+ i 6)) 4) %M)))
    (def h3 (int+ (obj-ref h 4) (int& (int>> (%le32 s (int+ i 9)) 6) %M)))
    (def h4 (int+ (obj-ref h 5) (int| (int>> (%le32 s (int+ i 12)) 8) hibit)))
    (def r0 (obj-ref rv 1)) (def r1 (obj-ref rv 2)) (def r2 (obj-ref rv 3))
    (def r3 (obj-ref rv 4)) (def r4 (obj-ref rv 5))
    (def s1 (obj-ref rv 6)) (def s2 (obj-ref rv 7)) (def s3 (obj-ref rv 8)) (def s4 (obj-ref rv 9))
    (def d0 (int+ (int+ (int* h0 r0) (int* h1 s4)) (int+ (int+ (int* h2 s3) (int* h3 s2)) (int* h4 s1))))
    (def d1 (int+ (int+ (int* h0 r1) (int* h1 r0)) (int+ (int+ (int* h2 s4) (int* h3 s3)) (int* h4 s2))))
    (def d2 (int+ (int+ (int* h0 r2) (int* h1 r1)) (int+ (int+ (int* h2 r0) (int* h3 s4)) (int* h4 s3))))
    (def d3 (int+ (int+ (int* h0 r3) (int* h1 r2)) (int+ (int+ (int* h2 r1) (int* h3 r0)) (int* h4 s4))))
    (def d4 (int+ (int+ (int* h0 r4) (int* h1 r3)) (int+ (int+ (int* h2 r2) (int* h3 r1)) (int* h4 r0))))
    ; the carries, each limb back under 26 bits, the top one's fold being
    ; times five (2^130 = 5 mod p)
    (def e1 (int+ d1 (int>> d0 26)))
    (def e2 (int+ d2 (int>> e1 26)))
    (def e3 (int+ d3 (int>> e2 26)))
    (def e4 (int+ d4 (int>> e3 26)))
    (def f0 (int+ (int& d0 %M) (int* (int>> e4 26) 5)))
    (obj-set! h 1 (int& f0 %M))
    (obj-set! h 2 (int+ (int& e1 %M) (int>> f0 26)))
    (obj-set! h 3 (int& e2 %M))
    (obj-set! h 4 (int& e3 %M))
    (obj-set! h 5 (int& e4 %M))))

; The block loop, pure x: blocks from byte i up to end of s, end - i a
; multiple of sixteen.  The compiled engine takes the same arguments and
; leaves the same h, so it is a drop-in for this function.
(def %blocks!
  (fn (self h rv s i end hibit)
    (when (int< i end)
      (do (%block! h rv s i hibit)
          (self h rv s (int+ i 16) end hibit)))))

; A short last block padded as 2.5 says: the bytes, then 0x01, then
; zeros to sixteen.
(def %tail
  (fn (_ s i n)
    (def t (str-make 16))
    (def p (str->ptr t))
    ((fn (self k)
       (unless (= k 16)
         (do (ptr-set! p k (match ((< k n) (%byte s (int+ i k))) ((= k n) 1) (#t 0)) 1)
             (self (int+ k 1))))) 0)
    t))

; The tag (2.5): h fully carried, reduced mod p by adding 5 and keeping
; the sum only when it overflows 2^130, then plus s mod 2^128, as sixteen
; little-endian bytes.
(def %finish
  (fn (_ h key)
    (def c1 (obj-ref h 2))
    (def c2 (int+ (obj-ref h 3) (int>> c1 26)))
    (def c3 (int+ (obj-ref h 4) (int>> c2 26)))
    (def c4 (int+ (obj-ref h 5) (int>> c3 26)))
    (def c0 (int+ (obj-ref h 1) (int* (int>> c4 26) 5)))
    (def h0 (int& c0 %M))
    (def h1 (int+ (int& c1 %M) (int>> c0 26)))
    (def h2 (int& c2 %M))
    (def h3 (int& c3 %M))
    (def h4 (int& c4 %M))
    (def g0 (int+ h0 5))
    (def g1 (int+ h1 (int>> g0 26)))
    (def g2 (int+ h2 (int>> g1 26)))
    (def g3 (int+ h3 (int>> g2 26)))
    (def g4 (int- (int+ h4 (int>> g3 26)) 67108864))
    (def take-g (not (int< g4 0)))
    (def k0 (if take-g (int& g0 %M) h0))
    (def k1 (if take-g (int& g1 %M) h1))
    (def k2 (if take-g (int& g2 %M) h2))
    (def k3 (if take-g (int& g3 %M) h3))
    (def k4 (if take-g (int& g4 %M) h4))
    ; four 32-bit words from the five limbs, then s added with carries
    (def w0 (int+ (int& (int| k0 (int<< k1 26)) %M32) (%le32 key 16)))
    (def w1 (int+ (int+ (int& (int| (int>> k1 6) (int<< k2 20)) %M32) (%le32 key 20)) (int>> w0 32)))
    (def w2 (int+ (int+ (int& (int| (int>> k2 12) (int<< k3 14)) %M32) (%le32 key 24)) (int>> w1 32)))
    (def w3 (int+ (int+ (int& (int| (int>> k3 18) (int<< k4 8)) %M32) (%le32 key 28)) (int>> w2 32)))
    (def tag (str-make 16))
    (def p (str->ptr tag))
    ((fn (self k ws)
       (unless (null? ws)
         (do (ptr-set! p k (int& (first ws) 255) 1)
             (ptr-set! p (int+ k 1) (int& (int>> (first ws) 8) 255) 1)
             (ptr-set! p (int+ k 2) (int& (int>> (first ws) 16) 255) 1)
             (ptr-set! p (int+ k 3) (int& (int>> (first ws) 24) 255) 1)
             (self (int+ k 4) (rest ws)))))
     0 (list w0 w1 w2 w3))
    tag))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As chacha20.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by %blocks! above, and built only for a region
; of %jit-threshold bytes or more or on (Poly1305 jit!).
;
; THE BAR IS THE MEASURED BREAKEVEN, 2026-10-08, arm64, asm cache warm:
; pure-x tags at 24us a byte (1000 bytes in 24ms), the build is 1.1s
; (2.3s on a cold cache), and the engine 5.4MB/s (64KB in 12ms), so the
; two cost the same at ~46KB.
(def %entry ())
(def %jit-threshold 49152)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit poly1305) %blocks!
          (fn (_)
            (import x/codec/poly1305-jit)
            ((prim-ref (lit poly1305) (lit jit-make)) %blocks!
              (%r-vector (Str8 pad-right 32 #\k ""))))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run!
  (fn (_ h rv s i end hibit)
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) h rv s i end hibit)
         (%blocks! h rv s i end hibit)))
     %entry)))

; The authenticator: the whole blocks, then the padded tail if the
; region does not end on one, then the final reduction.
(def %mac
  (fn (_ key s start len)
    (when (if (int< len %jit-threshold) #f
               ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
                %entry))
      (%jit-try!))
    (def h (Vector make 5 0))
    (def rv (%r-vector key))
    (def whole (int<< (int>> len 4) 4))
    (%run! h rv s start (int+ start whole) 16777216)
    (unless (= whole len)
      (%run! h rv (%tail s (int+ start whole) (int- len whole)) 0 16 0))
    (%finish h key)))

(def %region
  (fn (_ s r)
    (match ((null? r) (list 0 (Str8 length s)))
           (#t (list (first r) (first (rest r)))))))

(def-class Poly1305 ()
  (static
    (method mac (self (param key STRING "The one-time key: 32 bytes are read, r then s")
                      (param s STRING "The bytes to authenticate")
                      . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The Poly1305 tag (RFC 8439 2.5) of a byte region under a one-time key, as sixteen bytes. The key is used ONCE: a second message under the same key gives the key away. GIVE THE REGION FOR BINARY INPUT: s's own length is measured to its first NUL. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "16 bytes")
        (example "(Poly1305 mac (Str8 pad-right 32 #\\k \"\") \"\")" "\"kkkkkkkkkkkkkkkk\""))
      (def r (%region s span))
      (%mac key s (first r) (first (rest r))))
    (method jit! (self)
      (doc "Build and adopt the compiled block engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x block loop. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. mac also builds it on its own for any single region of 48KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/poly1305 Poly1305)
  "Poly1305 (RFC 8439 2.5): (Poly1305 mac key s [start len]) is the 16-byte tag of a byte region under a one-time key. Pure x-lang, with an optional differentially-verified JIT engine ((Poly1305 jit!), or built on its own for a region of 48KB or more).")
