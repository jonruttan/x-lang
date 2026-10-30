; aes.x -- AES: the block cipher (FIPS 197) and its counter mode, pure x-lang.
;
; What an SSH written in x opens a passphrase-protected key file with:
; OpenSSH seals the private section in aes256-ctr under a key bcrypt-pbkdf
; derives.  A key file is a few hundred bytes, so the cipher is the plain
; byte-wise one -- SubBytes and ShiftRows together through the S-box,
; MixColumns by xtime -- with no tables but the S-box and no compiled
; engine.  Key sizes 16, 24 and 32 bytes give AES-128, -192 and -256.
;
; Counter mode (SP 800-38A 6.5) runs the block cipher over a 16-byte
; counter block, incremented as one big-endian 128-bit integer, and XORs
; each output block into the data: OpenSSH's aes-ctr and OpenSSL's
; -aes-256-ctr count so.  One operation encrypts and decrypts.
(module x/codec/aes)

(import x/type/vector)

(import x/core/doors char->int int& int+ int- int< int<< int= int>> int| obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)
; The bit operations through the int doors, as chacha20.x's: there is no
; int xor, so a ^ b is (a | b) - (a & b).
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

; The S-box (FIPS 197 5.1.1), byte k in slot k+1.
(def %sbox
  ((fn (_ bs)
     (def v (Vector make 256 0))
     ((fn (self i bs) (unless (null? bs) (do (obj-set! v i (first bs)) (self (int+ i 1) (rest bs))))) 1 bs)
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

(def %sub-byte (fn (_ b) (obj-ref %sbox (int+ b 1))))

; Multiplication by x in GF(2^8), the field's polynomial 0x11b.
(def %xtime (fn (_ a) (%xor (int& (int<< a 1) 255) (if (int= (int& a 128) 0) 0 27))))

; The key schedule (5.2) as round-key bytes: 16 a round, Nr+1 rounds, byte
; k in slot k+1.  Nk is the key's words, 4, 6 or 8; Nr is Nk+6.  Word i
; is bytes 4i..4i+3, and k is i's place among each Nk words.
(def %schedule
  (fn (_ key size)
    (def nk (if (int= size 16) 4 (if (int= size 24) 6 8)))
    (def total (int<< (int+ nk 7) 4))
    (def w (Vector make total 0))
    ((fn (self i) (unless (int= i size) (do (obj-set! w (int+ i 1) (%byte key i)) (self (int+ i 1))))) 0)
    ; temp's four bytes for word i: word i-1, rotated, substituted and
    ; given Rcon at the start of each Nk words, substituted alone at the
    ; fourth word of an AES-256 key's eight
    ((fn (self i k rcon)
       (unless (int= (int<< i 2) total)
         (do (def at (fn (_ j) (obj-ref w (int+ (int<< (int- i 1) 2) (int+ j 1)))))
             (def t
               (match
                 ((int= k 0) (list (%xor (%sub-byte (at 1)) rcon) (%sub-byte (at 2)) (%sub-byte (at 3)) (%sub-byte (at 0))))
                 ((if (int= nk 8) (int= k 4) #f) (list (%sub-byte (at 0)) (%sub-byte (at 1)) (%sub-byte (at 2)) (%sub-byte (at 3))))
                 (#t (list (at 0) (at 1) (at 2) (at 3)))))
             ((fn (self j t)
                (unless (null? t)
                  (do (obj-set! w (int+ (int<< i 2) (int+ j 1))
                        (%xor (obj-ref w (int+ (int<< (int- i nk) 2) (int+ j 1))) (first t)))
                      (self (int+ j 1) (rest t)))))
              0 t)
             (self (int+ i 1) (if (int= (int+ k 1) nk) 0 (int+ k 1)) (if (int= k 0) (%xtime rcon) rcon)))))
     nk 0 1)
    (pair w (int+ nk 6))))

; One block (5.1): the 16 bytes at s[start..] encrypted under the schedule
; into slots 1..16 of st, column-major as the input lays them.
(def %encrypt!
  (fn (_ ks st t s start)
    (def w (first ks))
    (def nr (rest ks))
    (def add-key!
      (fn (self round i)
        (unless (int= i 16)
          (do (obj-set! st (int+ i 1) (%xor (obj-ref st (int+ i 1)) (obj-ref w (int+ (int<< round 4) (int+ i 1)))))
              (self round (int+ i 1))))))
    ; SubBytes and ShiftRows: row r of column c from column c+r
    (def sub-shift!
      (fn (self i)
        (if (int= i 16)
          ((fn (self i) (unless (int= i 17) (do (obj-set! st i (obj-ref t i)) (self (int+ i 1))))) 1)
          (do (def r (int& i 3))
              (def c (int& (int+ (int>> i 2) r) 3))
              (obj-set! t (int+ i 1) (%sub-byte (obj-ref st (int+ r (int+ (int<< c 2) 1)))))
              (self (int+ i 1))))))
    (def mix!
      (fn (self c)
        (unless (int= c 4)
          (do (def at (int+ (int<< c 2) 1))
              (def a0 (obj-ref st at)) (def a1 (obj-ref st (int+ at 1)))
              (def a2 (obj-ref st (int+ at 2))) (def a3 (obj-ref st (int+ at 3)))
              (def all (%xor (%xor a0 a1) (%xor a2 a3)))
              ; b_i = a_i ^ all ^ xtime(a_i ^ a_(i+1))
              (obj-set! st at (%xor (%xor a0 all) (%xtime (%xor a0 a1))))
              (obj-set! st (int+ at 1) (%xor (%xor a1 all) (%xtime (%xor a1 a2))))
              (obj-set! st (int+ at 2) (%xor (%xor a2 all) (%xtime (%xor a2 a3))))
              (obj-set! st (int+ at 3) (%xor (%xor a3 all) (%xtime (%xor a3 a0))))
              (self (int+ c 1))))))
    ((fn (self i) (unless (int= i 16) (do (obj-set! st (int+ i 1) (%byte s (int+ start i))) (self (int+ i 1))))) 0)
    (add-key! 0 0)
    ((fn (self round)
       (if (int= round nr)
         (do (sub-shift! 0) (add-key! round 0))
         (do (sub-shift! 0) (mix! 0) (add-key! round 0) (self (int+ round 1)))))
     1)))

; The 16 slots as a fresh string.
(def %block-string
  (fn (_ st)
    (def out (str-make 16))
    (def p (str->ptr out))
    ((fn (self i) (unless (int= i 16) (do (ptr-set! p i (obj-ref st (int+ i 1)) 1) (self (int+ i 1))))) 0)
    out))

; The counter block plus one, big-endian across all 16 bytes, in place.
(def %bump!
  (fn (_ ctr p)
    ((fn (self i)
       (unless (int< i 0)
         (do (def b (int& (int+ (%byte ctr i) 1) 255))
             (ptr-set! p i b 1)
             (when (int= b 0) (self (int- i 1))))))
     15)))

(def %check-size
  (fn (_ size)
    (unless (if (int= size 16) #t (if (int= size 24) #t (int= size 32)))
      (Err raise 'value "Aes: the key must be 16, 24 or 32 bytes" size))))

; The optional region: all of s, measured to its first NUL, when absent.
(def %region
  (fn (_ s r)
    (if (null? r) (list 0 (Str8 length s)) (list (first r) (first (rest r))))))

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
      (def start (first r))
      (def len (first (rest r)))
      (def ks (%schedule key size))
      (def st (Vector make 16 0))
      (def t (Vector make 16 0))
      (def ctr (str-make 16))
      (def cp (str->ptr ctr))
      ((fn (self i) (unless (int= i 16) (do (ptr-set! cp i (%byte iv i) 1) (self (int+ i 1))))) 0)
      (def out (str-make len))
      (def p (str->ptr out))
      ((fn (self pos)
         (when (int< pos len)
           (do (%encrypt! ks st t ctr 0)
               ((fn (self i)
                  (unless (if (int= i 16) #t (int= (int+ pos i) len))
                    (do (ptr-set! p (int+ pos i) (%xor (%byte s (int+ start (int+ pos i))) (obj-ref st (int+ i 1))) 1)
                        (self (int+ i 1)))))
                0)
               (%bump! ctr cp)
               (self (int+ pos 16)))))
       0)
      out)))

(doc (provide x/codec/aes Aes)
  "AES (FIPS 197): (Aes encrypt-block key size block) is one block, (Aes ctr key size iv s [start len]) counter mode (SP 800-38A), OpenSSH's aes-ctr. Key sizes 16, 24 and 32 bytes. Pure x-lang.")
