; aes.x -- AES: the block cipher (FIPS 197) and its counter mode.
;
; What an SSH written in x opens a passphrase-protected key file with:
; OpenSSH seals the private section in aes256-ctr under a key bcrypt-pbkdf
; derives, and what its aes-ctr transport runs.  The pure-x cipher is the
; plain byte-wise one -- SubBytes and ShiftRows together through the
; S-box, MixColumns by xtime -- the reference; counter mode over a
; connection's traffic is x/codec/aes-jit's compiled engine, adopted once
; it agrees with it.  Key sizes 16, 24 and 32 bytes give AES-128, -192
; and -256.
;
; Counter mode (SP 800-38A 6.5) runs the block cipher over a 16-byte
; counter block, incremented as one big-endian 128-bit integer, and XORs
; each output block into the data: OpenSSH's aes-ctr and OpenSSL's
; -aes-256-ctr count so.  One operation encrypts and decrypts.
;
; GCM (SP 800-38D) is counter mode from the block after J0, the 96-bit IV
; then 1, and a tag: GHASH of the additional data and the ciphertext,
; XORed with the cipher of J0 -- OpenSSH's aes128-gcm@openssh.com and
; aes256-gcm@openssh.com (RFC 5647).  Counting the whole block where GCM
; counts its last word alone is the same while a message is under 2^32
; blocks less one, as any one is.
(module x/codec/aes)

(import x/type/vector)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)
(import x/codec/ghash)

(def %add (prim-ref (lit int) (lit +)))
(def %sub (prim-ref (lit int) (lit -)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))
; The bit operations through the int doors, as chacha20.x's: there is no
; int xor, so a ^ b is (a | b) - (a & b).
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shl (prim-ref (lit int) (lit <<)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %eq (prim-ref (lit int) (lit =)))
(def %lt (prim-ref (lit int) (lit <)))
(def %xor (fn (_ a b) (%sub (%or a b) (%and a b))))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

; The S-box (FIPS 197 5.1.1), byte k in slot k+1.
(def %sbox
  ((fn (_ bs)
     (def v (Vector make 256 0))
     ((fn (self i bs) (unless (null? bs) (do (%oset! v i (first bs)) (self (%add i 1) (rest bs))))) 1 bs)
     v)
   (list
     99 124 119 123 242 107 111 197 48 1 103 43 254 215 171 118
     202 130 201 125 250 89 71 240 173 212 162 175 156 164 114 192
     183 253 147 38 54 63 247 204 52 165 229 241 113 216 49 21
     4 199 35 195 24 150 5 154 7 18 128 226 235 39 178 117
     9 131 44 26 27 110 90 160 82 59 214 179 41 227 47 132
     83 209 0 237 32 252 177 91 106 203 190 57 74 76 88 207
     208 239 170 251 67 77 51 133 69 249 2 127 80 60 159 168
     81 163 64 143 146 157 56 245 188 182 218 33 16 255 243 210
     205 12 19 236 95 151 68 23 196 167 126 61 100 93 25 115
     96 129 79 220 34 42 144 136 70 238 184 20 222 94 11 219
     224 50 58 10 73 6 36 92 194 211 172 98 145 149 228 121
     231 200 55 109 141 213 78 169 108 86 244 234 101 122 174 8
     186 120 37 46 28 166 180 198 232 221 116 31 75 189 139 138
     112 62 181 102 72 3 246 14 97 53 87 185 134 193 29 158
     225 248 152 17 105 217 142 148 155 30 135 233 206 85 40 223
     140 161 137 13 191 230 66 104 65 153 45 15 176 84 187 22)))

(def %sub-byte (fn (_ b) (%oref %sbox (%add b 1))))

; Multiplication by x in GF(2^8), the field's polynomial 0x11b.
(def %xtime (fn (_ a) (%xor (%and (%shl a 1) 255) (if (%eq (%and a 128) 0) 0 27))))

; The key schedule (5.2) as round-key bytes: 16 a round, Nr+1 rounds, byte
; k in slot k+1.  Nk is the key's words, 4, 6 or 8; Nr is Nk+6.  Word i
; is bytes 4i..4i+3, and k is i's place among each Nk words.
(def %schedule
  (fn (_ key size)
    (def nk (if (%eq size 16) 4 (if (%eq size 24) 6 8)))
    (def total (%shl (%add nk 7) 4))
    (def w (Vector make total 0))
    ((fn (self i) (unless (%eq i size) (do (%oset! w (%add i 1) (%byte key i)) (self (%add i 1))))) 0)
    ; temp's four bytes for word i: word i-1, rotated, substituted and
    ; given Rcon at the start of each Nk words, substituted alone at the
    ; fourth word of an AES-256 key's eight
    ((fn (self i k rcon)
       (unless (%eq (%shl i 2) total)
         (do (def at (fn (_ j) (%oref w (%add (%shl (%sub i 1) 2) (%add j 1)))))
             (def t
               (match
                 ((%eq k 0) (list (%xor (%sub-byte (at 1)) rcon) (%sub-byte (at 2)) (%sub-byte (at 3)) (%sub-byte (at 0))))
                 ((if (%eq nk 8) (%eq k 4) #f) (list (%sub-byte (at 0)) (%sub-byte (at 1)) (%sub-byte (at 2)) (%sub-byte (at 3))))
                 (#t (list (at 0) (at 1) (at 2) (at 3)))))
             ((fn (self j t)
                (unless (null? t)
                  (do (%oset! w (%add (%shl i 2) (%add j 1))
                        (%xor (%oref w (%add (%shl (%sub i nk) 2) (%add j 1))) (first t)))
                      (self (%add j 1) (rest t)))))
              0 t)
             (self (%add i 1) (if (%eq (%add k 1) nk) 0 (%add k 1)) (if (%eq k 0) (%xtime rcon) rcon)))))
     nk 0 1)
    (pair w (%add nk 6))))

; One block (5.1): the 16 bytes at s[start..] encrypted under the schedule
; into slots 1..16 of st, column-major as the input lays them.
(def %encrypt!
  (fn (_ ks st t s start)
    (def w (first ks))
    (def nr (rest ks))
    (def add-key!
      (fn (self round i)
        (unless (%eq i 16)
          (do (%oset! st (%add i 1) (%xor (%oref st (%add i 1)) (%oref w (%add (%shl round 4) (%add i 1)))))
              (self round (%add i 1))))))
    ; SubBytes and ShiftRows: row r of column c from column c+r
    (def sub-shift!
      (fn (self i)
        (if (%eq i 16)
          ((fn (self i) (unless (%eq i 17) (do (%oset! st i (%oref t i)) (self (%add i 1))))) 1)
          (do (def r (%and i 3))
              (def c (%and (%add (%shr i 2) r) 3))
              (%oset! t (%add i 1) (%sub-byte (%oref st (%add r (%add (%shl c 2) 1)))))
              (self (%add i 1))))))
    (def mix!
      (fn (self c)
        (unless (%eq c 4)
          (do (def at (%add (%shl c 2) 1))
              (def a0 (%oref st at)) (def a1 (%oref st (%add at 1)))
              (def a2 (%oref st (%add at 2))) (def a3 (%oref st (%add at 3)))
              (def all (%xor (%xor a0 a1) (%xor a2 a3)))
              ; b_i = a_i ^ all ^ xtime(a_i ^ a_(i+1))
              (%oset! st at (%xor (%xor a0 all) (%xtime (%xor a0 a1))))
              (%oset! st (%add at 1) (%xor (%xor a1 all) (%xtime (%xor a1 a2))))
              (%oset! st (%add at 2) (%xor (%xor a2 all) (%xtime (%xor a2 a3))))
              (%oset! st (%add at 3) (%xor (%xor a3 all) (%xtime (%xor a3 a0))))
              (self (%add c 1))))))
    ((fn (self i) (unless (%eq i 16) (do (%oset! st (%add i 1) (%byte s (%add start i))) (self (%add i 1))))) 0)
    (add-key! 0 0)
    ((fn (self round)
       (if (%eq round nr)
         (do (sub-shift! 0) (add-key! round 0))
         (do (sub-shift! 0) (mix! 0) (add-key! round 0) (self (%add round 1)))))
     1)))

; The 16 slots as a fresh string.
(def %block-string
  (fn (_ st)
    (def out (%make-str 16))
    (def p (%str->ptr out))
    ((fn (self i) (unless (%eq i 16) (do (%pset1 p i (%oref st (%add i 1)) 1) (self (%add i 1))))) 0)
    out))

; The counter block plus one, big-endian across all 16 bytes, in place.
(def %bump!
  (fn (_ ctr p)
    ((fn (self i)
       (unless (%lt i 0)
         (do (def b (%and (%add (%byte ctr i) 1) 255))
             (%pset1 p i b 1)
             (when (%eq b 0) (self (%sub i 1))))))
     15)))

(def %check-size
  (fn (_ size)
    (unless (if (%eq size 16) #t (if (%eq size 24) #t (%eq size 32)))
      (Err raise 'value "Aes: the key must be 16, 24 or 32 bytes" size))))

; The optional region: all of s, measured to its first NUL, when absent.
(def %region
  (fn (_ s r)
    (if (null? r) (list 0 (Str8 length s)) (list (first r) (first (rest r))))))

; The pure-x counter mode: a schedule, the initial counter block and a
; byte region -> a fresh string of len bytes, each XORed with the
; keystream.  The compiled engine answers the same string, so it is a
; drop-in for this function.
(def %ctr-bytes
  (fn (_ ks iv s start len)
    (def st (Vector make 16 0))
    (def t (Vector make 16 0))
    (def ctr (%make-str 16))
    (def cp (%str->ptr ctr))
    ((fn (self i) (unless (%eq i 16) (do (%pset1 cp i (%byte iv i) 1) (self (%add i 1))))) 0)
    (def out (%make-str len))
    (def p (%str->ptr out))
    ((fn (self pos)
       (when (%lt pos len)
         (do (%encrypt! ks st t ctr 0)
             ((fn (self i)
                (unless (if (%eq i 16) #t (%eq (%add pos i) len))
                  (do (%pset1 p (%add pos i) (%xor (%byte s (%add start (%add pos i))) (%oref st (%add i 1))) 1)
                      (self (%add i 1)))))
              0)
             (%bump! ctr cp)
             (self (%add pos 16)))))
     0)
    out))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As chacha20.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x cipher above, and built only for a
; region of %jit-threshold bytes or more or on (Aes jit!).
(def %entry ())
(def %jit-threshold 1024)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit aes) %ctr-bytes
          (fn (_)
            (import x/codec/aes-jit)
            ((prim-ref (lit aes) (lit jit-make)) %ctr-bytes %schedule %sub-byte))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ ks iv s start len)
    (when (if (%lt len %jit-threshold) #f
            ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
             %entry))
      (%jit-try!))
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) ks iv s start len)
         (%ctr-bytes ks iv s start len)))
     %entry)))

; The schedule for the last key asked, kept: slots 1 the key's bytes, 2
; its size, 3 the schedule.  A connection's every packet is under one key.
(def %kept (Vector make 3 ()))

(def %same?
  (fn (_ x y n)
    ((fn (self i) (if (%eq i n) #t (if (%eq (%byte x i) (%byte y i)) (self (%add i 1)) #f))) 0)))

(def %copy
  (fn (_ s n)
    (def out (%make-str n))
    (def p (%str->ptr out))
    ((fn (self i) (unless (%eq i n) (do (%pset1 p i (%byte s i) 1) (self (%add i 1))))) 0)
    out))

(def %schedule-of
  (fn (_ key size)
    (if (if (null? (%oref %kept 1)) #f (if (%eq (%oref %kept 2) size) (%same? key (%oref %kept 1) size) #f))
      (%oref %kept 3)
      (do (def ks (%schedule key size))
          (%oset! %kept 1 (%copy key size)) (%oset! %kept 2 size) (%oset! %kept 3 ks)
          ks))))

; n zero bytes.
(def %zeros
  (fn (_ n)
    (def out (%make-str n))
    (def p (%str->ptr out))
    ((fn (self i) (unless (%eq i n) (do (%pset1 p i 0 1) (self (%add i 1))))) 0)
    out))

; The counter block for a 96-bit IV and a 32-bit count.
(def %gcm-block
  (fn (_ iv n)
    (def out (%zeros 16))
    (def p (%str->ptr out))
    ((fn (self i) (unless (%eq i 12) (do (%pset1 p i (%byte iv i) 1) (self (%add i 1))))) 0)
    (%pset1 p 15 n 1)
    out))

; GCM's parts for a key, an IV, and the ciphertext's region of s: the tag
; (16 bytes) of the additional data a-start..a-len and the ciphertext.
(def %gcm-tag
  (fn (_ ks iv s a-start a-len c c-start c-len)
    (def zero (%zeros 16))
    (def h (%run ks zero zero 0 16))
    (def s0 (%run ks (%gcm-block iv 1) zero 0 16))
    (def g (Ghash hash h s a-start a-len c c-start c-len))
    ((fn (_ out)
       (def p (%str->ptr out))
       ((fn (self i) (unless (%eq i 16) (do (%pset1 p i (%xor (%byte g i) (%byte s0 i)) 1) (self (%add i 1))))) 0)
       out)
     (%make-str 16))))

(def-class Aes ()
  (static
    (method encrypt-block (self (param key STRING "The key: size bytes are read")
                                (param size INTEGER "The key's length in bytes: 16, 24 or 32, for AES-128, -192 or -256")
                                (param block STRING "The 16 bytes to encrypt"))
      (doc "One block of the AES cipher (FIPS 197): 16 bytes encrypted under a 128-, 192- or 256-bit key, answered as a fresh 16-byte string -- binary, so read it by count. The key is read by size, not by its string length, so a key holding NUL bytes is whole."
        (returns STRING "16 bytes"))
      (%check-size size)
      (def st (Vector make 16 0))
      (%encrypt! (%schedule key size) st (Vector make 16 0) block 0)
      (%block-string st))
    (method ctr (self (param key STRING "The key: size bytes are read")
                      (param size INTEGER "The key's length in bytes: 16, 24 or 32")
                      (param iv STRING "The initial counter block: 16 bytes are read")
                      (param s STRING "The bytes to encrypt or decrypt")
                      . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "AES in counter mode (SP 800-38A 6.5): every byte of the region XORed with the cipher of the counter block, the counter incremented as one big-endian 128-bit integer each 16 bytes -- OpenSSH's aes128-ctr, aes192-ctr and aes256-ctr, and OpenSSL's. One operation encrypts and decrypts; a region ending inside a block uses that block's leading bytes. GIVE THE REGION FOR BINARY INPUT: s's own length is measured to its first NUL, and the answer's is LEN, which only the caller knows."
        (returns STRING "LEN bytes")
        (example "(Aes ctr (Str8 pad-right 32 #\\k \"\") 32 (Str8 pad-right 16 #\\i \"\") (Aes ctr (Str8 pad-right 32 #\\k \"\") 32 (Str8 pad-right 16 #\\i \"\") \"abc\") 0 3)" "\"abc\""))
      (%check-size size)
      (def r (%region s span))
      (%run (%schedule-of key size) iv s (first r) (first (rest r))))
    (method gcm-seal (self (param key STRING "The key: size bytes are read")
                           (param size INTEGER "The key's length in bytes: 16 or 32 for OpenSSH's, 24 too")
                           (param iv STRING "The 96-bit IV: 12 bytes are read")
                           (param s STRING "The bytes: the additional data and the plaintext")
                           (param a-start INTEGER "Where the additional data starts")
                           (param a-len INTEGER "Its length")
                           (param start INTEGER "Where the plaintext starts")
                           (param len INTEGER "Its length"))
      (doc "AES-GCM encryption (NIST SP 800-38D): the plaintext region in counter mode from the block after J0, and the 16-byte tag over the additional data and the ciphertext -- OpenSSH's aes128-gcm@openssh.com and aes256-gcm@openssh.com (RFC 5647), where the additional data is the packet length. Answered as (CIPHERTEXT . TAG), fresh strings of len and 16 bytes."
        (returns PAIR "(CIPHERTEXT . TAG)"))
      (%check-size size)
      (def ks (%schedule-of key size))
      (def c (%run ks (%gcm-block iv 2) s start len))
      (pair c (%gcm-tag ks iv s a-start a-len c 0 len)))
    (method gcm-open (self (param key STRING "The key: size bytes are read")
                           (param size INTEGER "The key's length in bytes")
                           (param iv STRING "The 96-bit IV: 12 bytes are read")
                           (param s STRING "The bytes: the additional data and the ciphertext")
                           (param a-start INTEGER "Where the additional data starts")
                           (param a-len INTEGER "Its length")
                           (param start INTEGER "Where the ciphertext starts")
                           (param len INTEGER "Its length")
                           (param tag STRING "The 16-byte tag that came with it"))
      (doc "AES-GCM decryption (NIST SP 800-38D): the tag over the additional data and the ciphertext checked, every byte of it, and only then the ciphertext deciphered. Answers the plaintext, a fresh string of len bytes, or nil when the tag does not match."
        (returns ANY "The plaintext, or nil"))
      (%check-size size)
      (def ks (%schedule-of key size))
      (def want (%gcm-tag ks iv s a-start a-len s start len))
      ; every byte compared, so how far a forgery matched is not timed
      (def diff ((fn (self i acc) (if (%eq i 16) acc (self (%add i 1) (%or acc (%xor (%byte want i) (%byte tag i)))))) 0 0))
      (if (%eq diff 0) (%run ks (%gcm-block iv 2) s start len) ()))
    (method jit! (self)
      (doc "Build and adopt the compiled counter-mode engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x cipher. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. ctr also builds it on its own for any single region of 1KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/aes Aes)
  "AES (FIPS 197): (Aes encrypt-block key size block) is one block, (Aes ctr key size iv s [start len]) counter mode (SP 800-38A), OpenSSH's aes-ctr; (Aes gcm-seal ...) and (Aes gcm-open ...) Galois/counter mode (SP 800-38D), OpenSSH's aes-gcm. Key sizes 16, 24 and 32 bytes. Pure x-lang, with an optional differentially-verified JIT engine for counter mode ((Aes jit!), or built on its own for a region of 1KB or more).")
