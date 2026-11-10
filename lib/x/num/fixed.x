; fixed.x -- fixed-point arithmetic on plain integers, the same on any word.
;
; A fixed-point value is an integer holding a number times 2^K: K is its
; fraction bits, stated by the caller at each call, so a value is a word
; and nothing is allocated for it.  Operands and answers are 32-bit signed
; values; what lies between them is exact to 64 bits.  An 8-byte word holds
; that in one word and uses the integer doors as they are.  A 4-byte word
; cannot, and works in 16-bit limbs.  Both give the same answers.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/fixed)
(import x/core/doors buf-tok char->int int% int& int* int+ int- int/ int< int= int<< int>> int| str-byte-len str-byte-ref type-make)

(def %wide (int< 4 %word-size))
; the low 32 bits: every bit of a 4-byte word
(def %m32 0xFFFFFFFF)

; 32 bits shifted right N places, 1 to 31, zeros in from the top: x/num/u32's
; u32-srl, kept here so a 4-byte word does not load bigint for it
(def %srl
  (if %wide int>>
    (fn (_ x n) (int& (int>> x n) (int- (int<< 1 (int- 32 n)) 1)))))

(def %neg? (fn (_ a) (int< a 0)))
(def %abs (fn (_ a) (if (int< a 0) (int- 0 a) a)))
(def %lo16 (fn (_ p) (int& p 65535)))
(def %hi16 (fn (_ p) (int& (int>> p 16) 65535)))
; R at least D, both 32 bits unsigned, D under 2^31
(def %ge? (fn (_ r d) (if (int< (int& r %m32) 0) #t (if (int< (int& r %m32) d) #f #t))))

; --- 64 bits as two words of 32 ------------------------------------------
;
; A magnitude up to 2^64 is HI and LO, each 32 bits as u32-bits holds them.

; HI:LO shifted right K places, 0 to 32: its low 32 bits.
(def %shr
  (fn (_ hi lo k)
    (match
      ((int= k 0) lo)
      ((int= k 32) hi)
      (#t (int& (int| (%srl lo k) (int<< hi (int- 32 k))) %m32)))))

; The magnitude HI:LO divided by D, 1 to 2^31 - 1: the quotient's low 32
; bits, one bit a turn from the top.  ROUND adds one when twice the
; remainder reaches D.
(def %div-go
  (fn (self i hi lo d rem q round)
    (if (int< i 0)
      (if (if round (%ge? (int<< rem 1) d) #f) (int& (int+ q 1) %m32) q)
      ((fn (_ r)
         (if (%ge? r d)
           (self (int- i 1) hi lo d (int& (int- r d) %m32) (int& (int| (int<< q 1) 1) %m32) round)
           (self (int- i 1) hi lo d r (int& (int<< q 1) %m32) round)))
       (int| (int<< rem 1)
             (int& (if (int< i 32) (int>> lo i) (int>> hi (int- i 32))) 1))))))
(def %div (fn (_ hi lo d round) (%div-go 63 hi lo d 0 0 round)))

; A magnitude with its sign put back.
(def %signed (fn (_ neg m) (if neg (int- 0 m) m)))

; --- The 4-byte word's arithmetic, in limbs ---------------------------------
;
; |A| times |B| is four 16-bit limbs, R0 the lowest, summed so that no sum
; passes 2^18.  A negative product is shifted as its floor: 2^K - 1 goes
; onto the magnitude first, in limbs M0 and M1.
(def %mul-shift
  (fn (_ neg r0 r1 r2 r3 k)
    (def m0 (if neg (if (int< k 16) (int- (int<< 1 k) 1) 65535) 0))
    (def m1 (if neg (if (int< 16 k) (int- (int<< 1 (int- k 16)) 1) 0) 0))
    (def s0 (int+ r0 m0))
    (def s1 (int+ (int+ r1 m1) (int>> s0 16)))
    (def s2 (int+ r2 (int>> s1 16)))
    (def s3 (int+ r3 (int>> s2 16)))
    (%signed neg
      (%shr (int| (int<< (%lo16 s3) 16) (%lo16 s2))
            (int| (int<< (%lo16 s1) 16) (%lo16 s0))
            k))))

; The limbs of |A| times |B|, handed to THEN with what follows them.
(def %mul-limbs
  (fn (_ ua ub then neg x)
    (def p0 (int* (%lo16 ua) (%lo16 ub)))
    (def p1 (int* (%lo16 ua) (%hi16 ub)))
    (def p2 (int* (%hi16 ua) (%lo16 ub)))
    (def p3 (int* (%hi16 ua) (%hi16 ub)))
    (def t1 (int+ (int+ (%hi16 p0) (%lo16 p1)) (%lo16 p2)))
    (def t2 (int+ (int+ (int+ (int>> t1 16) (%hi16 p1)) (%hi16 p2)) (%lo16 p3)))
    (then neg (%lo16 p0) (%lo16 t1) (%lo16 t2) (int+ (int>> t2 16) (%hi16 p3)) x)))

(def %narrow*
  (fn (_ a b k)
    (%mul-limbs (%abs a) (%abs b) %mul-shift (if (eq? (%neg? a) (%neg? b)) #f #t) k)))

(def %narrow/
  (fn (_ a b k)
    (def ua (%abs a))
    (%signed (if (eq? (%neg? a) (%neg? b)) #f #t)
      (%div (if (int= k 0) 0 (if (int= k 32) (int& ua %m32) (%srl (int& ua %m32) (int- 32 k))))
            (if (int= k 32) 0 (int& (int<< ua k) %m32))
            (%abs b) #f))))

(def %mul-div
  (fn (_ neg r0 r1 r2 r3 uc)
    (%signed neg
      (%div (int| (int<< r3 16) r2) (int| (int<< r1 16) r0) uc #f))))
(def %narrow*/
  (fn (_ a b c)
    (%mul-limbs (%abs a) (%abs b) %mul-div
      (if (eq? (if (eq? (%neg? a) (%neg? b)) #f #t) (%neg? c)) #f #t)
      (%abs c))))

(def %narrow-ratio
  (fn (_ n d k)
    (def un (%abs n))
    (%signed (if (eq? (%neg? n) (%neg? d)) #f #t)
      (%div (if (int= k 0) 0 (if (int= k 32) (int& un %m32) (%srl (int& un %m32) (int- 32 k))))
            (if (int= k 32) 0 (int& (int<< un k) %m32))
            (%abs d) #t))))

; --- The 8-byte word's arithmetic: the doors ---------------------------------

(def %wide* (fn (_ a b k) (int>> (int* a b) k)))
(def %wide/ (fn (_ a b k) (int/ (int<< a k) b)))
(def %wide*/ (fn (_ a b c) (int/ (int* a b) c)))
(def %wide-ratio
  (fn (_ n d k)
    (def top (int<< (%abs n) k))
    (def ud (%abs d))
    (%signed (if (eq? (%neg? n) (%neg? d)) #f #t)
      (int+ (int/ top ud) (if (int< (int<< (int% top ud) 1) ud) 0 1)))))

; --- The surface ----------------------------------------------------------

(doc (def fixed*
  (if %wide %wide* %narrow*))
  (param a INTEGER "A fixed-point value, 32 bits signed")
  (param b INTEGER "A fixed-point value, 32 bits signed")
  (param k INTEGER "Places to shift the product down, 0 to 32: the fraction bits one operand gives up")
  (returns INTEGER "a times b over 2^k, rounded down; the caller keeps it within 32 bits")
  (example "(do (import x/num/fixed fixed*) (fixed* 98304 163840 16))" "245760")
  "The product of two fixed-point values, exact through its 64 bits and shifted down.")

(doc (def fixed/
  (if %wide %wide/ %narrow/))
  (param a INTEGER "A fixed-point value, 32 bits signed")
  (param b INTEGER "The divisor, not zero")
  (param k INTEGER "Places to shift a up before dividing, 0 to 32: the fraction bits the quotient gains")
  (returns INTEGER "a times 2^k over b, rounded toward zero; the caller keeps it within 32 bits")
  (example "(do (import x/num/fixed fixed/) (fixed/ 98304 163840 16))" "39321")
  "The quotient of two fixed-point values, the dividend shifted up through 64 bits first.")

(doc (def fixed*/
  (if %wide %wide*/ %narrow*/))
  (param a INTEGER "A value, 32 bits signed")
  (param b INTEGER "A value, 32 bits signed")
  (param c INTEGER "The divisor, not zero")
  (returns INTEGER "a times b over c, rounded toward zero; the caller keeps it within 32 bits")
  (example "(do (import x/num/fixed fixed*/) (fixed*/ 1000000 44100 1000))" "44100000")
  "A value scaled by a ratio, the product exact through its 64 bits.")

(doc (def fixed-ratio
  (if %wide %wide-ratio %narrow-ratio))
  (param n INTEGER "The numerator, 32 bits signed")
  (param d INTEGER "The denominator, not zero")
  (param k INTEGER "The fraction bits, 0 to 32")
  (returns INTEGER "n over d as a fixed-point value of k fraction bits, rounded to the nearest")
  (example "(do (import x/num/fixed fixed-ratio) (fixed-ratio 3 4 16))" "49152")
  "A ratio as a fixed-point value.")

(doc (def fixed
  (fn (_ n k) (int<< n k)))
  (param n INTEGER "A whole number")
  (param k INTEGER "The fraction bits")
  (returns INTEGER "n as a fixed-point value of k fraction bits")
  (example "(do (import x/num/fixed fixed) (fixed 3 16))" "196608")
  "A whole number as a fixed-point value.")

(doc (def fixed-floor
  (fn (_ v k) (int>> v k)))
  (param v INTEGER "A fixed-point value")
  (param k INTEGER "Its fraction bits")
  (returns INTEGER "The whole number at or below v")
  (example "(do (import x/num/fixed fixed-floor) (fixed-floor -98304 16))" "-2")
  "A fixed-point value's whole part, rounded down.")

(doc (def fixed-round
  (fn (_ v k) (if (int= k 0) v (int>> (int+ v (int<< 1 (int- k 1))) k))))
  (param v INTEGER "A fixed-point value")
  (param k INTEGER "Its fraction bits")
  (returns INTEGER "The whole number nearest v, a half going up")
  (example "(do (import x/num/fixed fixed-round) (fixed-round 98304 16))" "2")
  "A fixed-point value rounded to the nearest whole number.")

(doc (def fixed-clamp
  (fn (_ v lo hi) (if (int< v lo) lo (if (int< hi v) hi v))))
  (param v INTEGER "A value")
  (param lo INTEGER "The least it may be")
  (param hi INTEGER "The most it may be")
  (returns INTEGER "v, or the bound it passed")
  (example "(do (import x/num/fixed fixed-clamp) (fixed-clamp 40000 -32768 32767))" "32767")
  "A value held within two bounds.")

; --- The literal: [+-]DIGITS[.DIGITS]qK -------------------------------------
;
; 0.75q16 reads as 49152: the decimal number times 2^K, rounded to the
; nearest, a half going away from zero.  The reader does the arithmetic,
; so the program holds an integer.  K is 0 to 32 and the value must fit 32
; bits signed; a literal that does not is an error where it is read.
;
; The magnitude is built negative, so that 2^31 fits the word it is built
; in, and the fraction's bits come off its decimal digits one doubling at a
; time: no step needs more than the word.

(def %min32 (int<< -1 31))
(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))
(def %digit? (fn (_ c) (if (int< 47 c) (int< c 58) #f)))
(def %lit-range
  (fn (_ tok) (Err raise (lit value) "fixed literal: the value does not fit 32 bits" tok)))

; The whole part from I, negative: (N . the index past it).
(def %lit-whole
  (fn (self tok i n)
    (def c (%byte tok i))
    (if (%digit? c)
      (if (if (int< n -214748364) #t (if (int= n -214748364) (int< 56 c) #f))
        (%lit-range tok)
        (self tok (int+ i 1) (int- (int* n 10) (int- c 48))))
      (pair n i))))

; The fraction's digits from I, most significant first: (DIGITS . the index
; past them).
(def %lit-frac
  (fn (self tok i)
    (def c (%byte tok i))
    (if (%digit? c)
      ((fn (_ r) (pair (pair (int- c 48) (first r)) (rest r))) (self tok (int+ i 1)))
      (pair () i))))

; K from I to the token's end.
(def %lit-places
  (fn (self tok i len k)
    (if (int= i len) k
      ((fn (_ k)
         (if (int< 32 k)
           (Err raise (lit value) "fixed literal: the fraction bits run 0 to 32" tok)
           (self tok (int+ i 1) len k)))
       (int+ (int* k 10) (int- (%byte tok i) 48))))))

; A fraction's digits doubled: (the carry out of the top . the digits).
(def %lit-double
  (fn (self ds)
    (if (null? ds) (pair 0 ())
      ((fn (_ r)
         ((fn (_ v) (pair (int/ v 10) (pair (int% v 10) (rest r))))
          (int+ (int* 2 (first ds)) (first r))))
       (self (rest ds))))))

; N doubled with BIT under it, or nil when that passes 2^31.
(def %lit-step
  (fn (_ n bit)
    (if (if (int< n (int<< -1 30)) #t (if (int= n (int<< -1 30)) (int= bit 1) #f)) ()
      (int- (int* n 2) bit))))

; The negative magnitude N with K bits of the fraction DS under it, then
; rounded by the bit after them; nil when it passes 2^31.
(def %lit-scale
  (fn (self n ds k)
    (def r (%lit-double ds))
    (if (int= k 0)
      (if (int= (first r) 0) n (if (int= n %min32) () (int- n 1)))
      ((fn (_ n) (if (null? n) () (self n (rest r) (int- k 1))))
       (%lit-step n (first r))))))

(def %lit-read
  (fn (_ tok)
    (def c0 (%byte tok 0))
    (def neg (int= c0 45))
    (def w (%lit-whole tok (if (if neg #t (int= c0 43)) 1 0) 0))
    (def f (if (int= (%byte tok (rest w)) 46) (%lit-frac tok (int+ (rest w) 1)) (pair () (rest w))))
    (def n (%lit-scale (first w) (first f) (%lit-places tok (int+ (rest f) 1) (str-byte-len tok) 0)))
    (match
      ((null? n) (%lit-range tok))
      (neg n)
      ((int= n %min32) (%lit-range tok))
      (#t (int- 0 n)))))

; The analyser's states.  Only a digit of K scores, and the score covers
; the suffix, so 0.75q16 outbids a number reader's 0.75 on the same run.
(def %lit-k ())
(set! %lit-k
  (fn (_ buffer score chr)
    (if (%digit? chr)
      (%seq (%score-set score 1 buffer) %lit-k)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(def %lit-first-k
  (fn (_ buffer score chr)
    (if (%digit? chr) (%seq (%score-set score 1 buffer) %lit-k) ())))
(def %lit-frac-digits ())
(set! %lit-frac-digits
  (fn (_ buffer score chr)
    (if (%digit? chr) %lit-frac-digits (if (int= chr 113) %lit-first-k ()))))
(def %lit-first-frac
  (fn (_ buffer score chr) (if (%digit? chr) %lit-frac-digits ())))
(def %lit-int ())
(set! %lit-int
  (fn (_ buffer score chr)
    (match
      ((%digit? chr) %lit-int)
      ((int= chr 113) %lit-first-k)
      ((int= chr 46) %lit-first-frac)
      (#t ()))))
; a lone sign must see a digit next, so - and + stay operators
(def %lit-sign (fn (_ buffer score chr) (if (%digit? chr) %lit-int ())))

; The type exists to carry the reader: what it reads is an INTEGER.
(def %fixed-literal
  (type-make "FIXED"
    (list
      (pair (lit analyse)
        (fn (_ buffer score chr)
          (if (%digit? chr) %lit-int
            (if (if (int= chr 45) #t (int= chr 43)) %lit-sign ()))))
      (pair (lit read) (fn (_ . args) (%lit-read (buf-tok (first args))))))))

(doc (provide x/num/fixed fixed fixed* fixed/ fixed*/ fixed-ratio fixed-floor fixed-round fixed-clamp)
  (example "(do (import x/num/fixed fixed-ratio fixed*) (fixed* (fixed-ratio 3 4 16) (fixed-ratio 1 2 16) 16))" "24576")
  "Fixed-point arithmetic on plain integers: a value is a number times 2^k, k stated at each call, and products and quotients are exact through 64 bits on any word. Once the module is loaded the reader takes a literal, DIGITS[.DIGITS]qK: 0.75q16 reads as the integer 49152, rounded to the nearest and held to 32 bits signed.")
