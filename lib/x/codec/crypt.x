; crypt.x -- Crypt: crypt(3)'s traditional DES password hash, in pure x-lang.
;
; The hash an /etc/passwd or /etc/shadow line has carried since V7, and the
; default of busybox's cryptpw: the password's first eight bytes, each
; shifted left one, are a DES key (FIPS 46); the salt's two characters, read
; in crypt's base-64, swap twelve pairs of the E box's outputs; a block of
; zeros is encrypted twenty-five times, and its 64 bits are written after the
; salt, six at a time, in eleven characters.
;
; The block's halves are 32-bit ints on the C bit ops, every sum through the
; cached int prims, so the hash is tower-proof as sha256.x's is.  The E box
; is shifts of the right half doubled, its eight 6-bit groups each a window;
; the salt's swaps are one xor-mask between E's two 24-bit halves; the S
; boxes and P are folded at load into eight 64-entry tables, each giving the
; permuted 32 bits a box's six input bits make.  Twenty-five encryptions
; between one IP and one FP: an FP and the next encryption's IP cancel.
(module x/codec/crypt)

(import x/type/vector)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %mul (prim-ref 'int '*))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %m32 4294967295)

; vector slot I of V (slot 0 of a Vector's object holds its length)
(def %v (fn (_ v i) (%oref v (%add i 1))))

; the tables (FIPS 46), positions counted from 1, bit 1 the most significant
(def %ip (Vector from-list (lit (58 50 42 34 26 18 10 2 60 52 44 36 28 20 12 4 62 54 46 38 30 22 14 6
  64 56 48 40 32 24 16 8 57 49 41 33 25 17 9 1 59 51 43 35 27 19 11 3 61 53 45 37 29 21 13 5 63 55 47 39 31 23 15 7))))
(def %fp (Vector from-list (lit (40 8 48 16 56 24 64 32 39 7 47 15 55 23 63 31 38 6 46 14 54 22 62 30
  37 5 45 13 53 21 61 29 36 4 44 12 52 20 60 28 35 3 43 11 51 19 59 27 34 2 42 10 50 18 58 26 33 1 41 9 49 17 57 25))))
(def %p (Vector from-list (lit (16 7 20 21 29 12 28 17 1 15 23 26 5 18 31 10 2 8 24 14 32 27 3 9 19 13 30 6 22 11 4 25))))
(def %pc1 (Vector from-list (lit (57 49 41 33 25 17 9 1 58 50 42 34 26 18 10 2 59 51 43 35 27 19 11 3 60 52 44 36
  63 55 47 39 31 23 15 7 62 54 46 38 30 22 14 6 61 53 45 37 29 21 13 5 28 20 12 4))))
(def %pc2 (Vector from-list (lit (14 17 11 24 1 5 3 28 15 6 21 10 23 19 12 4 26 8 16 7 27 20 13 2
  41 52 31 37 47 55 30 40 51 45 33 48 44 49 39 56 34 53 46 42 50 36 29 32))))
(def %shifts (lit (1 1 2 2 2 2 2 2 1 2 2 2 2 2 2 1)))
(def %s (Vector from-list (lit (
  14 4 13 1 2 15 11 8 3 10 6 12 5 9 0 7 0 15 7 4 14 2 13 1 10 6 12 11 9 5 3 8
  4 1 14 8 13 6 2 11 15 12 9 7 3 10 5 0 15 12 8 2 4 9 1 7 5 11 3 14 10 0 6 13
  15 1 8 14 6 11 3 4 9 7 2 13 12 0 5 10 3 13 4 7 15 2 8 14 12 0 1 10 6 9 11 5
  0 14 7 11 10 4 13 1 5 8 12 6 9 3 2 15 13 8 10 1 3 15 4 2 11 6 7 12 0 5 14 9
  10 0 9 14 6 3 15 5 1 13 12 7 11 4 2 8 13 7 0 9 3 4 6 10 2 8 5 14 12 11 15 1
  13 6 4 9 8 15 3 0 11 1 2 12 5 10 14 7 1 10 13 0 6 9 8 7 4 15 14 3 11 5 2 12
  7 13 14 3 0 6 9 10 1 2 8 5 11 12 4 15 13 8 11 5 6 15 0 3 4 7 2 12 1 10 14 9
  10 6 9 0 12 11 7 13 15 1 3 14 5 2 8 4 3 15 0 6 10 1 13 8 9 4 5 11 12 7 2 14
  2 12 4 1 7 10 11 6 8 5 3 15 13 0 14 9 14 11 2 12 4 7 13 1 5 0 15 10 3 9 8 6
  4 2 1 11 10 13 7 8 15 9 12 5 6 3 0 14 11 8 12 7 1 14 2 13 6 15 0 9 10 4 5 3
  12 1 10 15 9 2 6 8 0 13 3 4 14 7 5 11 10 15 4 2 7 12 9 5 6 1 13 14 0 11 3 8
  9 14 15 5 2 8 12 3 7 0 4 10 1 13 11 6 4 3 2 12 9 5 15 10 11 14 1 7 6 0 8 13
  4 11 2 14 15 0 8 13 3 12 9 7 5 10 6 1 13 0 11 7 4 9 1 10 14 3 5 12 2 15 8 6
  1 4 11 13 12 3 7 14 10 15 6 8 0 5 9 2 6 11 13 8 1 4 10 7 9 5 0 15 14 2 3 12
  13 2 8 4 6 15 11 1 10 9 3 14 5 0 12 7 1 15 13 8 10 3 7 4 12 5 6 11 0 14 9 2
  7 11 4 1 9 12 14 2 0 6 10 13 15 3 5 8 2 1 14 7 4 10 8 13 15 12 9 0 3 5 6 11))))

; bit I (from 1, the most significant) of the W-bit word X
(def %bit (fn (_ x w i) (& (>> x (%sub w i)) 1)))

; the W-bit word X permuted by TABLE (positions in X), N bits out
(def %perm
  (fn (_ x w table n)
    ((fn (self i acc)
       (if (= i n) acc
         (self (%add i 1) (| (<< acc 1) (%bit x w (%v table i))))))
     0 0)))

; P applied to box B's output VAL, the four bits at the box's own place
(def %sp-entry
  (fn (_ b v)
    (def row (| (<< (& (>> v 5) 1) 1) (& v 1)))
    (def col (& (>> v 1) 15))
    (def val (%v %s (%add (%mul b 64) (%add (%mul row 16) col))))
    (%perm (<< val (%sub 28 (%mul b 4))) 32 %p 32)))

; the eight boxes' tables, box B's at 64B
(def %sp
  (Vector from-list
    ((fn (self k)
       (if (= k 512) () (pair (%sp-entry (>> k 6) (& k 63)) (self (%add k 1))))) 0)))

; the sixteen round keys from the 64-bit key as (HI . LO), each key's 48
; bits as two 24-bit halves (LEFT . RIGHT), the E box's halves' order
(def %subkeys
  (fn (_ hi lo)
    (def key (| (<< hi 32) lo))
    (def cd (%perm key 64 %pc1 56))
    (def rot28 (fn (_ x n) (& (| (<< x n) (>> x (%sub 28 n))) 268435455)))
    ((fn (self ss c d acc)
       (if (null? ss) (Vector from-list (List reverse acc))
         (let ((c2 (rot28 c (first ss))) (d2 (rot28 d (first ss))))
           (let ((k (%perm (| (<< c2 28) d2) 56 %pc2 48)))
             (self (rest ss) c2 d2 (pair (pair (>> k 24) (& k 16777215)) acc))))))
     %shifts (>> cd 28) (& cd 268435455) ())))

; f(R, K) with the salt's mask: E's eight groups from R doubled, salted,
; keyed, through the S and P tables
(def %f
  (fn (_ r k salt)
    (def rr (| (>> r 1) (<< (& r 1) 31)))
    (def dd (| (<< rr 32) rr))
    (def group (fn (_ b) (& (>> dd (%sub 58 (%mul 4 b))) 63)))
    (def el (| (<< (group 0) 18) (| (<< (group 1) 12) (| (<< (group 2) 6) (group 3)))))
    (def er (| (<< (group 4) 18) (| (<< (group 5) 12) (| (<< (group 6) 6) (group 7)))))
    (def sw (& (^ el er) salt))
    (def xl (^ (^ el sw) (first k)))
    (def xr (^ (^ er sw) (rest k)))
    (^ (^ (^ (%v %sp (& (>> xl 18) 63)) (%v %sp (%add 64 (& (>> xl 12) 63))))
          (^ (%v %sp (%add 128 (& (>> xl 6) 63))) (%v %sp (%add 192 (& xl 63)))))
       (^ (^ (%v %sp (%add 256 (& (>> xr 18) 63))) (%v %sp (%add 320 (& (>> xr 12) 63))))
          (^ (%v %sp (%add 384 (& (>> xr 6) 63))) (%v %sp (%add 448 (& xr 63))))))))

; a salt character's value in crypt's base-64, as busybox's ascii_to_bin
; reads one: . / 0-9 A-Z a-z are 0 to 63, any other 0
(def %a64
  (fn (_ c)
    (match
      ((> c 122) 0) ((>= c 97) (%sub c 59))
      ((> c 90) 0) ((>= c 65) (%sub c 53))
      ((> c 57) 0) ((>= c 46) (%sub c 46))
      (#t 0))))

(def %crypt64 "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

; the salt's twelve bits as E's swap mask: bit I of the salt (the first
; character's six low, the second's six high) swaps E bits I and I+24,
; which in a 24-bit half is the bit 23-I from the bottom
(def %salt-mask
  (fn (_ s0 s1)
    (def bits (| (%a64 s0) (<< (%a64 s1) 6)))
    ((fn (self i acc)
       (if (= i 12) acc
         (self (%add i 1) (if (= (& (>> bits i) 1) 1) (| acc (<< 1 (%sub 23 i))) acc))))
     0 0)))

(def %des
  (fn (_ key s0 s1)
    (def kb (fn (_ i) (if (< i (Str8 length key)) (& (<< (%char->int (%byte-ref key i)) 1) 255) 0)))
    (def hi (| (<< (kb 0) 24) (| (<< (kb 1) 16) (| (<< (kb 2) 8) (kb 3)))))
    (def lo (| (<< (kb 4) 24) (| (<< (kb 5) 16) (| (<< (kb 6) 8) (kb 7)))))
    (def ks (%subkeys hi lo))
    (def salt (%salt-mask s0 s1))
    ; the sixteen rounds, then the halves swapped; twenty-five times
    (def rounds
      (fn (self i l r)
        (if (= i 16) (pair r l)
          (self (%add i 1) r (& (^ l (%f r (%v ks i) salt)) %m32)))))
    (def lr
      ((fn (self n h)
         (if (= n 25) h (self (%add n 1) (rounds 0 (first h) (rest h)))))
       0 (pair 0 0)))
    (def block (%perm (| (<< (first lr) 32) (rest lr)) 64 %fp 64))
    (def char (fn (_ v) (Str8 sub v 1 %crypt64)))
    ; eleven characters, six bits each from the top, two zero bits after
    (Str8 join ""
      (List map (fn (_ g)
                  (char (if (= g 10) (<< (& block 15) 2) (& (>> block (%sub 58 (%mul 6 g))) 63))))
                (List range 0 11)))))

(def-class Crypt ()
  (static
    (method des (self (param key STRING "The password; its first eight bytes are used")
                      (param salt STRING "The salt; its first two characters are used"))
      (doc "crypt(3)'s traditional DES hash of KEY with SALT: the salt's two characters, then eleven of crypt's base-64 -- thirteen in all, as /etc/passwd has long held them. A salt of fewer than two characters raises a label 'value, as busybox's pw_encrypt refuses one."
        (returns STRING "13 characters")
        (example "(Crypt des \"pw\" \"ab\")" "\"abzlUXK5ed5rs\""))
      (when (< (Str8 length salt) 2)
        (Err raise 'value "Crypt des: the salt is two characters" salt))
      (Str8 append (Str8 sub 0 2 salt)
        (%des key (%char->int (%byte-ref salt 0)) (%char->int (%byte-ref salt 1)))))))

(doc (provide x/codec/crypt Crypt)
  "crypt(3)'s password hashes: (Crypt des key salt), the traditional DES one. Pure x-lang.")
