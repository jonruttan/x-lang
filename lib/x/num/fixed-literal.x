; fixed-literal.x -- a reader literal for x/num/fixed's values: 0.75q16.
;
; [+-]DIGITS[.DIGITS]qK reads as the decimal number times 2^K, rounded to
; the nearest, a half going away from zero: 0.75q16 is the integer 49152.
; The reader does the arithmetic, so the program holds an integer.  K is 0
; to 32 and the value must fit 32 bits signed; a literal that does not is
; an error where it is read.
;
; The literal is this module's to load and not x/num/fixed's, because a
; reader's analyser sees every token read after it is registered: a
; program that only calls the arithmetic does not pay for a literal it
; never writes.
;
; The magnitude is built negative, so that 2^31 fits the word it is built
; in, and the fraction's bits come off its decimal digits one doubling at a
; time: no step needs more than the word, and a 4-byte word reads what an
; 8-byte word reads.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/fixed-literal)
(import x/core/doors buf-tok char->int int% int* int+ int- int/ int< int= int<< str-byte-len str-byte-ref type-make)

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
; The two states below see every token the reader meets, so each asks the
; doors directly and in the order that lets most characters go soonest:
; past the digits first, where every name begins.
(def %lit-int ())
(set! %lit-int
  (fn (_ buffer score chr)
    (if (int< 57 chr)
      (if (int= chr 113) %lit-first-k ())
      (if (int< 47 chr) %lit-int (if (int= chr 46) %lit-first-frac ())))))
; a lone sign must see a digit next, so - and + stay operators
(def %lit-sign (fn (_ buffer score chr) (if (%digit? chr) %lit-int ())))

; The type exists to carry the reader: what it reads is an INTEGER.
(def %fixed-literal
  (type-make "FIXED"
    (list
      (pair (lit analyse)
        (fn (_ buffer score chr)
          (if (int< 57 chr) ()
            (if (int< chr 43) ()
              (if (int< 47 chr) %lit-int
                (if (int= chr 44) () (if (int< chr 46) %lit-sign ())))))))
      (pair (lit read) (fn (_ . args) (%lit-read (buf-tok (first args))))))))

(doc (provide x/num/fixed-literal)
  (example "(do (import x/num/fixed-literal) (Tok read-str (%base) \"0.75q16 -1.5q8 \"))" "(49152 -384)")
  "The reader literal for fixed-point values, DIGITS[.DIGITS]qK: once this module is loaded, 0.75q16 reads as the integer 49152, the number times 2^16, rounded to the nearest and held to 32 bits signed. A form is read whole before it runs, so the import stands in a form before the first literal.")
