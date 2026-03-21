; bignum.x -- Arbitrary-precision integer type
;
; Bignum values stored as (sign . limb-list) where:
;   sign = 1 or -1
;   limb-list = list of integers [0..base-1], least-significant first
;   Base chosen at load time so (base-1)^2 fits in native integer
;
; Promotion chain: integer -> bignum -> rational -> float -> complex
(import x/list)

; --- Platform constants ---

; Max signed integer, computed from word size via bit-shifting
(def %long-max
  (do
    (def %bm
      (fn (bits acc)
        (if (%int= bits 0) acc
          (%bm (%int- bits 1) (%int+ (%int* acc 2) 1)))))
    (%bm (%int- (%int* %word-size 8) 1) 0)))

; Safe max decimal digits for native integer (conservative: 2 per byte)
(def %int-max-digits (%int* %word-size 2))

; Find largest power of 10 whose square fits in native integer
; This gives us the bignum base and digits-per-limb
; Find largest d where (10^d - 1)^2 fits in long
; i.e. largest d where 10^d <= sqrt(LONG_MAX)
; Test: can we go one more? If LONG_MAX / (b*10) < (b*10), stop at d
(def %bignum-digits-per-limb
  (do
    (def %fb
      (fn (d b)
        (def next (%int* b 10))
        ; Safe check: LONG_MAX / next >= next means next^2 fits
        (if (%int< (%int/ %long-max next) next)
          d
          (%fb (%int+ d 1) next))))
    (%fb 1 10)))

(def %bignum-base
  (do
    (def %pb
      (fn (d acc)
        (if (%int= d 0) acc
          (%pb (%int- d 1) (%int* acc 10)))))
    (%pb %bignum-digits-per-limb 1)))

; --- Limb list utilities ---

; Strip trailing zero limbs (MSB end), keep at least one limb
(def %bignum-normalize
  (fn (limbs)
    (def %rev (reverse limbs))
    (def %strip
      (fn (lst)
        (if (null? (rest lst)) lst
          (if (%int= (first lst) 0)
            (%strip (rest lst))
            lst))))
    (reverse (%strip %rev))))

; Compare magnitudes: return -1, 0, or 1
(def %limb-cmp
  (fn (a b)
    (def la (length a))
    (def lb (length b))
    (if (%int< la lb) -1
      (if (%int< lb la) 1
        ; Same length: compare from MSB
        (do
          (def %cmp-rev
            (fn (ra rb)
              (if (null? ra) 0
                (if (%int< (first ra) (first rb)) -1
                  (if (%int< (first rb) (first ra)) 1
                    (%cmp-rev (rest ra) (rest rb)))))))
          (%cmp-rev (reverse a) (reverse b)))))))

; --- Limb arithmetic ---

; Add two limb lists with carry
(def %limb-add
  (fn (a b carry)
    (if (if (null? a) (if (null? b) (%int= carry 0) #f) #f)
      ()
      (do
        (def s (%int+ (%int+ (if (null? a) 0 (first a))
                              (if (null? b) 0 (first b)))
                       carry))
        (pair (modulo-int s %bignum-base)
              (%limb-add (if (null? a) () (rest a))
                         (if (null? b) () (rest b))
                         (%int/ s %bignum-base)))))))

; Subtract b from a (assumes a >= b), with borrow
(def %limb-sub
  (fn (a b borrow)
    (if (null? a) ()
      (do
        (def d (%int- (%int- (first a) (if (null? b) 0 (first b))) borrow))
        (if (%int< d 0)
          (pair (%int+ d %bignum-base)
                (%limb-sub (rest a) (if (null? b) () (rest b)) 1))
          (pair d
                (%limb-sub (rest a) (if (null? b) () (rest b)) 0)))))))

; Multiply limb list by a single limb, with carry
(def %limb-mul1
  (fn (b limb carry)
    (if (null? b)
      (if (%int= carry 0) () (list carry))
      (do
        (def p (%int+ (%int* (first b) limb) carry))
        (pair (modulo-int p %bignum-base)
              (%limb-mul1 (rest b) limb (%int/ p %bignum-base)))))))

; Schoolbook multiply: a * b
(def %limb-mul
  (fn (a b)
    (def %mul-go
      (fn (a shift acc)
        (if (null? a) acc
          (%mul-go (rest a) (pair 0 shift)
            (%limb-add acc (append shift (%limb-mul1 b (first a) 0)) 0)))))
    (%mul-go a () (list 0))))

; Divide limb list by single limb, return (quotient-limbs . remainder)
(def %limb-divmod1
  (fn (a divisor)
    (def %div-go
      (fn (ra rem qacc)
        (if (null? ra) (pair (reverse qacc) rem)
          (do
            (def cur (%int+ (%int* rem %bignum-base) (first ra)))
            (%div-go (rest ra) (modulo-int cur divisor)
                     (pair (%int/ cur divisor) qacc))))))
    (%div-go (reverse a) 0 ())))

; General division: a / b, return (quotient-limbs . remainder-limbs)
; Uses trial division at the limb level
(def %limb-divmod
  (fn (a b)
    ; Single-limb divisor: fast path
    (if (null? (rest b))
      (do
        (def r (%limb-divmod1 a (first b)))
        (pair (first r) (list (rest r))))
      ; Multi-limb: repeated subtraction with estimate
      ; Process from MSB, estimate quotient digit, subtract
      (do
        (def %top-limb
          (fn (lst) (first (reverse lst))))
        (def blen (length b))
        (def btop (%top-limb b))
        ; Shift a into position and extract quotient digits
        (def %div-loop
          (fn (rem qdigits)
            (def c (%limb-cmp rem b))
            (if (%int< c 0)
              (pair (if (null? qdigits) (list 0) (reverse qdigits)) rem)
              (if (%int= c 0)
                (pair (reverse (pair 1 qdigits)) (list 0))
                ; Estimate: use top limbs
                (do
                  (def rlen (length rem))
                  (def rtop (%top-limb rem))
                  ; Estimate quotient as rtop / (btop + 1) to be safe
                  (def q-est
                    (if (%int< rlen blen) 0
                      (if (%int= rlen blen)
                        (%int/ rtop (%int+ btop 1))
                        ; rem has more limbs than b
                        (do
                          (def rtop2 (first (rest (reverse rem))))
                          (%int/ (%int+ (%int* rtop %bignum-base) rtop2)
                                 (%int+ btop 1))))))
                  (if (%int= q-est 0) (set! q-est 1) ())
                  ; Subtract q-est * b from rem
                  (def product (%limb-mul1 b q-est 0))
                  (if (%int< (%limb-cmp rem product) 0)
                    ; Over-estimated, reduce by 1
                    (do
                      (set! q-est (%int- q-est 1))
                      (set! product (%limb-mul1 b q-est 0))
                      ())
                    ())
                  (def new-rem (%bignum-normalize (%limb-sub rem product 0)))
                  (%div-loop new-rem (pair q-est qdigits)))))))
        (%div-loop a ())))))

; --- String conversion ---

; Pad a number string to n digits with leading zeros
(def %bignum-pad
  (fn (s n)
    (if (not (%int< (string-length s) n)) s
      (%bignum-pad (string-append "0" s) n))))

; Limb list to decimal string
(def %bignum-to-string
  (fn (sign limbs)
    (def %rev (reverse limbs))
    (def prefix (if (%int= sign -1) "-" ""))
    (def head-str (number->string (first %rev)))
    (def %tail
      (fn (lst)
        (if (null? lst) ""
          (string-append
            (%bignum-pad (number->string (first lst)) %bignum-digits-per-limb)
            (%tail (rest lst))))))
    (string-append prefix (string-append head-str (%tail (rest %rev))))))

; Decimal string to (sign . limb-list)
(def %bignum-from-string
  (fn (s)
    (def len (string-length s))
    (def neg (if (%int< 0 len)
               (if (%int= (char->integer (s 0)) 45) #t #f) #f))
    (def start (if neg 1
                 (if (if (%int< 0 len)
                       (%int= (char->integer (s 0)) 43) #f) 1 0)))
    (def sign (if neg -1 1))
    (def digit-str (if (%int= start 0) s (substring s start len)))
    (def dlen (string-length digit-str))
    ; Process right-to-left in chunks of %bignum-digits-per-limb
    (def %parse-limbs
      (fn (pos acc)
        (if (not (%int< 0 pos))
          acc
          (do
            (def chunk-start (if (%int< (%int- pos %bignum-digits-per-limb) 0)
                               0
                               (%int- pos %bignum-digits-per-limb)))
            (def chunk (substring digit-str chunk-start pos))
            (def limb (string->number chunk))
            (%parse-limbs chunk-start (pair limb acc))))))
    (def limbs (reverse (%parse-limbs dlen ())))
    (def nlimbs (%bignum-normalize limbs))
    (make-instance %bignum (pair sign nlimbs))))

; --- Constructor with auto-demotion ---

(def %bignum-to-int
  (fn (sign limbs)
    (def %go
      (fn (lst mult acc)
        (if (null? lst) acc
          (%go (rest lst) (%int* mult %bignum-base)
               (%int+ acc (%int* (first lst) mult))))))
    (%int* sign (%go limbs 1 0))))

(def %bignum-from-int
  (fn (n)
    (def sign (if (%int< n 0) -1 1))
    (def mag (if (%int< n 0) (%int- 0 n) n))
    (def %go
      (fn (m acc)
        (if (%int= m 0) (if (null? acc) (list 0) acc)
          (%go (%int/ m %bignum-base)
               (pair (modulo-int m %bignum-base) acc)))))
    (pair sign (reverse (%go mag ())))))

; Forward declare %bignum and reader
(def %bignum ())
(def %bignum-read ())

(def %make-bignum
  (fn (sign limbs)
    (def nl (%bignum-normalize limbs))
    ; Zero check
    (if (if (null? (rest nl)) (%int= (first nl) 0) #f)
      0
      ; If few enough limbs to possibly fit in native int, try demotion
      (if (not (%int< (%int* %word-size 2) (%int* (length nl) %bignum-digits-per-limb)))
        (do
          (def val (%bignum-to-int sign nl))
          ; Verify it round-trips (didn't overflow)
          (def rt (%bignum-from-int val))
          (if (if (%int= sign (first rt))
                (%int= 0 (%limb-cmp nl (rest rt))) #f)
            val
            (make-instance %bignum (pair sign nl))))
        (make-instance %bignum (pair sign nl))))))

; --- Signed operations ---

(note "Predicates")

(doc (def bignum? (fn ((param x ANY "Value to test")) (type? x %bignum)))
  (returns BOOLEAN "True if x is a bignum")
  "Test whether a value is an arbitrary-precision integer.")

(def %big-sign (fn (x) (first (first x))))
(def %big-limbs (fn (x) (rest (first x))))

(def %ensure-big
  (fn (x)
    (if (bignum? x) x
      (do
        (def r (%bignum-from-int x))
        (make-instance %bignum r)))))

(note "Arithmetic")

(doc (def big+
  (fn ((param a BIGNUM "First operand")
       (param b BIGNUM "Second operand"))
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def la (%big-limbs a))
    (def lb (%big-limbs b))
    (if (%int= sa sb)
      ; Same sign: add magnitudes
      (%make-bignum sa (%limb-add la lb 0))
      ; Different signs: subtract smaller from larger
      (do
        (def c (%limb-cmp la lb))
        (if (%int= c 0) 0
          (if (%int< 0 c)
            (%make-bignum sa (%limb-sub la lb 0))
            (%make-bignum sb (%limb-sub lb la 0))))))))
  (returns INTEGER|BIGNUM "Sum, demoted to integer if it fits")
  "Add two bignums.")

(doc (def big-
  (fn ((param a BIGNUM "First operand")
       (param b BIGNUM "Second operand"))
    ; Negate b's sign and add
    (def sb (%int* -1 (%big-sign b)))
    (def nb (make-instance %bignum (pair sb (%big-limbs b))))
    (big+ a nb)))
  (returns INTEGER|BIGNUM "Difference, demoted to integer if it fits")
  "Subtract two bignums.")

(doc (def big*
  (fn ((param a BIGNUM "First operand")
       (param b BIGNUM "Second operand"))
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def sign (%int* sa sb))
    (%make-bignum sign (%limb-mul (%big-limbs a) (%big-limbs b)))))
  (returns INTEGER|BIGNUM "Product, demoted to integer if it fits")
  "Multiply two bignums.")

(doc (def big/
  (fn ((param a BIGNUM "Dividend")
       (param b BIGNUM "Divisor"))
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def sign (%int* sa sb))
    (def r (%limb-divmod (%big-limbs a) (%big-limbs b)))
    (%make-bignum sign (first r))))
  (returns INTEGER|BIGNUM "Quotient (truncated), demoted to integer if it fits")
  "Divide two bignums (truncating division).")

(doc (def big%
  (fn ((param a BIGNUM "Dividend")
       (param b BIGNUM "Divisor"))
    (def r (%limb-divmod (%big-limbs a) (%big-limbs b)))
    (%make-bignum (%big-sign a) (rest r))))
  (returns INTEGER|BIGNUM "Remainder, demoted to integer if it fits")
  "Compute the remainder of bignum division.")

(note "Comparison")

(doc (def big<
  (fn ((param a BIGNUM "Left operand")
       (param b BIGNUM "Right operand"))
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (if (%int< sa sb) #t
      (if (%int< sb sa) #f
        ; Same sign
        (do
          (def c (%limb-cmp (%big-limbs a) (%big-limbs b)))
          (if (%int= sa 1)
            (%int< c 0)
            (%int< 0 c)))))))
  (returns BOOLEAN "True if a < b")
  "Test whether bignum a is less than bignum b.")

(doc (def big=
  (fn ((param a BIGNUM "Left operand")
       (param b BIGNUM "Right operand"))
    (if (not (%int= (%big-sign a) (%big-sign b))) #f
      (%int= 0 (%limb-cmp (%big-limbs a) (%big-limbs b))))))
  (returns BOOLEAN "True if a equals b")
  "Test whether two bignums are equal.")

; --- Overflow detection for integer operations ---

(def %int-abs (fn (n) (if (%int< n 0) (%int- 0 n) n)))

(def %would-overflow-add?
  (fn (a b)
    (if (%int< 0 a)
      (if (%int< 0 b) (%int< (%int- %long-max a) b) #f)
      (if (%int< b 0)
        (%int< a (%int- (%int+ (%int- 0 %long-max) 1) (%int- 0 b)))
        #f))))

(def %would-overflow-mul?
  (fn (a b)
    (if (%int= a 0) #f
      (if (%int= b 0) #f
        (%int< (%int/ %long-max (%int-abs a)) (%int-abs b))))))

(note "Operator Overrides")

(doc + "Add numbers, promoting to bignum on overflow."
  (param args INTEGER|BIGNUM "Numbers to add")
  (returns INTEGER|BIGNUM "Sum"))
(set! +
  (fn args
    (if (null? args) 0
      (fold
        (fn (acc x)
          (if (bignum? acc) (big+ acc (%ensure-big x))
            (if (bignum? x) (big+ (%ensure-big acc) x)
              (if (%would-overflow-add? acc x)
                (big+ (%ensure-big acc) (%ensure-big x))
                (%int+ acc x)))))
        (first args) (rest args)))))

(doc - "Subtract numbers, promoting to bignum on overflow. Unary form negates."
  (param args INTEGER|BIGNUM "Numbers to subtract")
  (returns INTEGER|BIGNUM "Difference"))
(set! -
  (fn args
    (if (null? args) 0
      (if (null? (rest args))
        ; Unary negation
        (if (bignum? (first args))
          (%make-bignum (%int* -1 (%big-sign (first args)))
                        (%big-limbs (first args)))
          (%int- (first args)))
        (fold
          (fn (acc x)
            (if (bignum? acc) (big- acc (%ensure-big x))
              (if (bignum? x) (big- (%ensure-big acc) x)
                (if (%would-overflow-add? acc (%int- 0 x))
                  (big- (%ensure-big acc) (%ensure-big x))
                  (%int- acc x)))))
          (first args) (rest args))))))

(doc * "Multiply numbers, promoting to bignum on overflow."
  (param args INTEGER|BIGNUM "Numbers to multiply")
  (returns INTEGER|BIGNUM "Product"))
(set! *
  (fn args
    (if (null? args) 1
      (fold
        (fn (acc x)
          (if (bignum? acc) (big* acc (%ensure-big x))
            (if (bignum? x) (big* (%ensure-big acc) x)
              (if (%would-overflow-mul? acc x)
                (big* (%ensure-big acc) (%ensure-big x))
                (%int* acc x)))))
        (first args) (rest args)))))

(doc / "Divide numbers, promoting to bignum when needed."
  (param args INTEGER|BIGNUM "Numbers to divide")
  (returns INTEGER|BIGNUM "Quotient"))
(set! /
  (fn args
    (if (null? args) 1
      (fold
        (fn (acc x)
          (if (bignum? acc) (big/ acc (%ensure-big x))
            (if (bignum? x) (big/ (%ensure-big acc) x)
              (%int/ acc x))))
        (first args) (rest args)))))

(doc % "Compute remainder, promoting to bignum when needed."
  (param a INTEGER|BIGNUM "Dividend")
  (param b INTEGER|BIGNUM "Divisor")
  (returns INTEGER|BIGNUM "Remainder"))
(set! %
  (fn (a b)
    (if (bignum? a) (big% a (%ensure-big b))
      (if (bignum? b) (big% (%ensure-big a) b)
        (modulo-int a b)))))

(doc < "Compare numbers, promoting to bignum when needed."
  (param a INTEGER|BIGNUM "Left operand")
  (param b INTEGER|BIGNUM "Right operand")
  (returns BOOLEAN "True if a < b"))
(set! <
  (fn (a b)
    (if (bignum? a) (big< a (%ensure-big b))
      (if (bignum? b) (big< (%ensure-big a) b)
        (%int< a b)))))

(doc = "Test equality, promoting to bignum when needed."
  (param a INTEGER|BIGNUM "Left operand")
  (param b INTEGER|BIGNUM "Right operand")
  (returns BOOLEAN "True if a equals b"))
(set! =
  (fn (a b)
    (if (bignum? a) (big= a (%ensure-big b))
      (if (bignum? b) (big= (%ensure-big a) b)
        (%int= a b)))))

; --- Type registration ---

; Analyser: consumes [+-]?[0-9]+ but only scores when too many digits for int
(def %big-digits ())
(set! %big-digits
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      (do (buffer-unread buffer)
          ; Only score if digit count exceeds native integer range
          (if (%int< %int-max-digits (buffer-len buffer))
            (score-set score 1 buffer)
            ())))))

(def %big-sign-state
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      ())))

(def %big-analyse
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      (if (if (= chr 45) #t (= chr 43))
        %big-sign-state
        ()))))

(set! %bignum
  (make-type "BIGNUM"
    (list
      (pair (lit write)
        (fn (self) (display (%bignum-to-string (first (first self)) (rest (first self))))))
      (pair (lit first-chars) "0123456789-+")
      (pair (lit analyse) %big-analyse)
      (pair (lit read) (fn args (%bignum-read (first args))))
      (pair (lit from)
        (list
          (pair (type-of 42)
            (fn (value)
              (def r (%bignum-from-int value))
              (make-instance %bignum r)))
          (pair (type-of "")
            (fn (value) (%bignum-from-string value)))))
      (pair (lit to)
        (list
          (pair (type-of 42)
            (fn (self) (%bignum-to-int (first (first self)) (rest (first self)))))
          (pair (type-of "")
            (fn (self) (%bignum-to-string (first (first self)) (rest (first self))))))))))

; --- Reader (set after make-type so closure captures the real %bignum) ---
(set! %bignum-read
  (fn args
    (def tok (buffer-token (first args)))
    (def len (string-length tok))
    (def neg (if (%int< 0 len)
               (if (%int= (char->integer (tok 0)) 45) #t #f) #f))
    (def start (if neg 1
                 (if (if (%int< 0 len)
                       (%int= (char->integer (tok 0)) 43) #f) 1 0)))
    (def sign (if neg -1 1))
    (def digit-str (if (%int= start 0) tok (substring tok start len)))
    (def dlen (string-length digit-str))
    (def %pl
      (fn (pos acc)
        (if (not (%int< 0 pos)) acc
          (do
            (def cs (if (%int< (%int- pos %bignum-digits-per-limb) 0)
                      0 (%int- pos %bignum-digits-per-limb)))
            (def lm (string->number (substring digit-str cs pos)))
            (%pl cs (pair lm acc))))))
    (def limbs (reverse (%pl dlen ())))
    (def nlimbs (%bignum-normalize limbs))
    (make-instance %bignum (pair sign nlimbs))))

; --- Cap the integer analyser ---
; Push a capped analyser onto the integer type's analyse stack
; that rejects numbers with too many digits for native int

; Type struct navigation via type.x (available from x-core.x boot)
(def %int-type (type-by-atom (type-of 0)))

(def %int-capped-digits ())
(set! %int-capped-digits
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %int-capped-digits
      (do (buffer-unread buffer)
          (if (not (%int< %int-max-digits (buffer-len buffer)))
            (score-set score 1 buffer)
            ())))))

(def %int-capped-sign
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %int-capped-digits
      ())))

(def %int-capped-analyse
  (fn (buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %int-capped-digits
      (if (if (= chr 45) #t (= chr 43))
        %int-capped-sign
        ()))))

(type-push-analyse %int-type %int-capped-analyse)

(doc (provide x/bignum bignum? big+ big- big* big/ big% big< big=)
  (note "Auto-promotes when integers exceed native range. Extends +,-,*,/,%,<,=.")
  "Arbitrary-precision integers.")
