; bigint.x -- Arbitrary-precision integer type
;
; Bigint values stored as (sign . limb-list) where:
;   sign = 1 or -1
;   limb-list = list of integers [0..base-1], least-significant first
;   Base chosen at load time so (base-1)^2 fits in native integer
;
; Promotion chain: integer -> bigint -> rational -> float -> complex
(import x/core/list)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-push-analyse (prim-ref 'type 'push-analyse))
(def %type-push-op (prim-ref 'type 'push-op))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref 'type 'make-instance))
(def %make-type (prim-ref 'type 'make))
(def %type-of (prim-ref 'type 'of))
(def %type? (prim-ref 'type '?))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref 'char '->int))




; --- Platform constants ---

; Max signed integer, computed from word size via bit-shifting
(def %long-max
  (do
    (def %bm
      (fn (self bits acc)
        (if (%int= bits 0) acc
          (self (%int- bits 1) (%int+ (%int* acc 2) 1)))))
    (%bm (%int- (%int* %word-size 8) 1) 0)))

; Safe max decimal digits for native integer (conservative: 2 per byte)
(def %int-max-digits (%int* %word-size 2))

; Find largest power of 10 whose square fits in native integer
; This gives us the bigint base and digits-per-limb
; Find largest d where (10^d - 1)^2 fits in long
; i.e. largest d where 10^d <= sqrt(LONG_MAX)
; Test: can we go one more? If LONG_MAX / (b*10) < (b*10), stop at d
(def %bigint-digits-per-limb
  (do
    (def %fb
      (fn (self d b)
        (def next (%int* b 10))
        ; Safe check: LONG_MAX / next >= next means next^2 fits
        (if (%int< (%int/ %long-max next) next)
          d
          (self (%int+ d 1) next))))
    (%fb 1 10)))

(def %bigint-base
  (do
    (def %pb
      (fn (self d acc)
        (if (%int= d 0) acc
          (self (%int- d 1) (%int* acc 10)))))
    (%pb %bigint-digits-per-limb 1)))

; --- Limb list utilities ---

; Strip trailing zero limbs (MSB end), keep at least one limb
(def %bigint-normalize
  (fn (_ limbs)
    (def %rev (%reverse limbs))
    (def %strip
      (fn (self lst)
        (if (null? (rest lst)) lst
          (if (%int= (first lst) 0)
            (self (rest lst))
            lst))))
    (%reverse (%strip %rev))))

; Compare magnitudes: return -1, 0, or 1
(def %limb-cmp
  (fn (_ a b)
    (def la (%length a))
    (def lb (%length b))
    (if (%int< la lb) -1
      (if (%int< lb la) 1
        ; Same length: compare from MSB
        (let ()  ; scoped: def in tail position would leak to global
          (def %cmp-rev
            (fn (self ra rb)
              (if (null? ra) 0
                (if (%int< (first ra) (first rb)) -1
                  (if (%int< (first rb) (first ra)) 1
                    (self (rest ra) (rest rb)))))))
          (%cmp-rev (%reverse a) (%reverse b)))))))

; --- Limb arithmetic ---

; Add two limb lists with carry
(def %limb-add
  (fn (self a b carry)
    (if (if (null? a) (if (null? b) (%int= carry 0) #f) #f)
      ()
      (let ()
        (def s (%int+ (%int+ (if (null? a) 0 (first a))
                              (if (null? b) 0 (first b)))
                       carry))
        (pair (%int% s %bigint-base)
              (self (if (null? a) () (rest a))
                         (if (null? b) () (rest b))
                         (%int/ s %bigint-base)))))))

; Subtract b from a (assumes a >= b), with borrow
(def %limb-sub
  (fn (self a b borrow)
    (if (null? a) ()
      (let ()
        (def d (%int- (%int- (first a) (if (null? b) 0 (first b))) borrow))
        (if (%int< d 0)
          (pair (%int+ d %bigint-base)
                (self (rest a) (if (null? b) () (rest b)) 1))
          (pair d
                (self (rest a) (if (null? b) () (rest b)) 0)))))))

; Multiply limb list by a single limb, with carry
(def %limb-mul1
  (fn (self b limb carry)
    (if (null? b)
      (if (%int= carry 0) () (list carry))
      (let ()
        (def p (%int+ (%int* (first b) limb) carry))
        (pair (%int% p %bigint-base)
              (self (rest b) limb (%int/ p %bigint-base)))))))

; Schoolbook multiply: a * b
(def %limb-mul
  (fn (_ a b)
    (def %mul-go
      (fn (self as shift acc)
        (if (null? as) acc
          (self (rest as) (pair 0 shift)
            (%limb-add acc (%append shift (%limb-mul1 b (first as) 0)) 0)))))
    (%mul-go a () (list 0))))

; Divide limb list by single limb, return (quotient-limbs . remainder).
; The walk is MSB-first (over (%reverse a)), so prepending each quotient digit
; leaves qacc LSB-first -- ALREADY the limb storage order. Do not reverse it:
; a reverse here flips multi-limb quotients (latent for ages -- single-limb
; quotients, the only spec'd case, are order-immune).
(def %limb-divmod1
  (fn (_ a divisor)
    (def %div-go
      (fn (self ra rem qacc)
        (if (null? ra) (pair qacc rem)
          (let ()
            (def cur (%int+ (%int* rem %bigint-base) (first ra)))
            (self (rest ra) (%int% cur divisor)
                     (pair (%int/ cur divisor) qacc))))))
    (%div-go (%reverse a) 0 ())))

; General division: a / b, return (quotient-limbs . remainder-limbs)
; Uses trial division at the limb level
(def %limb-divmod
  (fn (_ a b)
    ; Single-limb divisor: fast path
    (if (null? (rest b))
      (let ()
        (def r (%limb-divmod1 a (first b)))
        (pair (first r) (list (rest r))))
      ; Multi-limb: positional schoolbook long division (#401).  The old
      ; arm subtracted q-est*b UNSHIFTED and stacked each iteration's
      ; count as if it were a positional digit: wrong quotients once the
      ; dividend outgrew the divisor by more than one limb, and an
      ; iteration count that scaled with the quotient's VALUE (the
      ; OOM-kill).  Here the dividend's limbs stream in MSB-first, one
      ; quotient digit per position.  Invariant: rem < b after every
      ; position, so the prepend below keeps rem < base*b and the digit
      ; loop is bounded -- termination by construction.
      (let ()
        (def blen (%length b))
        (def rb (%reverse b))
        (def btop (first rb))
        ; MSB-first compare of equal-length limb lists; %cmp-len decides
        ; from precomputed lengths + MSB views.  One reverse + one
        ; length walk per digit-loop pass, instead of %limb-cmp's two of
        ; each per CALL (the #341 lesson, kept through the #401 rewrite).
        (def %cmp-msb
          (fn (self ra rb2)
            (if (null? ra) 0
              (if (%int< (first ra) (first rb2)) -1
                (if (%int< (first rb2) (first ra)) 1
                  (self (rest ra) (rest rb2)))))))
        (def %cmp-len
          (fn (_ la ra lb2 rb2)
            (if (%int< la lb2) -1
              (if (%int< lb2 la) 1
                (%cmp-msb ra rb2)))))
        ; One quotient digit: accumulate d until rem < b.  The estimate
        ; keys on rem's length: at rlen == blen ONE top limb over
        ; (btop + 1), at rlen == blen + 1 (the invariant's ceiling) the
        ; two-limb form.  Either never overestimates (rem >= its top
        ; limbs scaled, b < (btop + 1) scaled), so d only climbs; the
        ; defensive decrement guards the floor-truncation edge anyway.
        (def %digit-loop
          (fn (self rem rrem rlen d)
            (if (%int< (%cmp-len rlen rrem blen rb) 0) (pair d rem)
              (let ()
                (def rtop (first rrem))
                (def est
                  (if (%int= rlen blen) (%int/ rtop (%int+ btop 1))
                    (%int/ (%int+ (%int* rtop %bigint-base)
                                  (first (rest rrem)))
                           (%int+ btop 1))))
                (if (%int= est 0) (set! est 1) ())
                (def product (%limb-mul1 b est 0))
                (if (%int< (%cmp-len rlen rrem
                                     (%length product) (%reverse product))
                           0)
                  (do
                    (set! est (%int- est 1))
                    (set! product (%limb-mul1 b est 0))
                    ())
                  ())
                (def new-rem (%bigint-normalize (%limb-sub rem product 0)))
                (self new-rem (%reverse new-rem) (%length new-rem)
                      (%int+ d est))))))
        ; A zero rem threads as () between positions: prepending onto
        ; the normalized-zero (0) would leave a HIGH zero limb, and
        ; %limb-cmp compares lengths first.
        (def %rem-thread
          (fn (_ r)
            (if (null? (rest r)) (if (%int= (first r) 0) () r) r)))
        ; Walk dividend limbs MSB-first; LSB-first rem means
        ; rem*base + limb is ONE prepend.  Digits prepend to qacc, so
        ; qacc ends LSB-first -- already the storage order.
        (def %pos-loop
          (fn (self ra rem qacc)
            (if (null? ra) (pair (%bigint-normalize qacc)
                                 (if (null? rem) (list 0)
                                   (%bigint-normalize rem)))
              (let ((r2 (pair (first ra) rem)))
                (let ((dr (%digit-loop r2 (%reverse r2) (%length r2) 0)))
                  (self (rest ra) (%rem-thread (rest dr))
                        (pair (first dr) qacc)))))))
        ; MSB-first prefix of n limbs as an LSB list, plus the rest:
        ; prepend-accumulate reverses the prefix, which IS the LSB order.
        (def %take-rev
          (fn (self n xs acc)
            (if (%int= n 0) (pair acc xs)
              (self (%int- n 1) (rest xs) (pair (first xs) acc)))))
        ; Seed rem with the dividend's top blen limbs in ONE step (their
        ; value is < base^blen <= base*b, so the digit bound holds) and
        ; walk only the remaining alen - blen positions: the quotient
        ; has alen - blen + 1 digits, and an equal-length divide is one
        ; digit-loop pass -- not a walk over every dividend limb.
        (def alen (%length a))
        (if (%int< alen blen) (pair (list 0) a)
          (let ((sr (%take-rev blen (%reverse a) ())))
            (let ((dr0 (%digit-loop (first sr) (%reverse (first sr))
                                    blen 0)))
              (%pos-loop (rest sr) (%rem-thread (rest dr0))
                         (list (first dr0))))))))))

; --- String conversion ---

; Pad a number string to n digits with leading zeros
(def %bigint-pad
  (fn (self s n)
    (if (not (%int< (%str-length s) n)) s
      (self (%str-append "0" s) n))))

; Limb list to decimal string
(def %bigint-to-string
  (fn (_ sign limbs)
    (def %rev (%reverse limbs))
    (def prefix (if (%int= sign -1) "-" ""))
    (def head-str (%number->str (first %rev)))
    (def %tail
      (fn (self lst)
        (if (null? lst) ""
          (%str-append
            (%bigint-pad (%number->str (first lst)) %bigint-digits-per-limb)
            (self (rest lst))))))
    (%str-append prefix (%str-append head-str (%tail (rest %rev))))))

; Parse decimal string to (sign . normalized-limb-list)
(def %bigint-parse-digits
  (fn (_ s)
    (def len (%str-length s))
    (def neg (if (%int< 0 len)
               (if (%int= (%char->integer (%str-ref s 0)) 45) #t #f) #f))
    (def start (if neg 1
                 (if (if (%int< 0 len)
                       (%int= (%char->integer (%str-ref s 0)) 43) #f) 1 0)))
    (def sign (if neg -1 1))
    (def digit-str (if (%int= start 0) s (%substring s start len)))
    (def dlen (%str-length digit-str))
    (def %go
      (fn (self pos acc)
        (if (not (%int< 0 pos))
          acc
          (let ()
            (def cs (if (%int< (%int- pos %bigint-digits-per-limb) 0)
                      0 (%int- pos %bigint-digits-per-limb)))
            (def lm (%str->number (%substring digit-str cs pos)))
            (self cs (pair lm acc))))))
    (pair sign (%bigint-normalize (%reverse (%go dlen ()))))))

; Decimal string to bigint instance.  Through %make-bigint, NOT a direct
; %make-instance: the capped int analyser hands over anything past 16
; digits, but 17-19 digit values can still fit the native int -- a direct
; instance there is a stealth bigint (prints like an int, fails eq? and
; raw slot ops).  %make-bigint demotes exactly the ones that round-trip.
(def %bigint-from-string
  (fn (_ s)
    (def parsed (%bigint-parse-digits s))
    (%make-bigint (first parsed) (rest parsed))))

; --- Constructor with auto-demotion ---

(def %bigint-to-int
  (fn (_ sign limbs)
    (def %go
      (fn (self lst mult acc)
        (if (null? lst) acc
          (self (rest lst) (%int* mult %bigint-base)
               (%int+ acc (%int* (first lst) mult))))))
    (%int* sign (%go limbs 1 0))))

(def %bigint-from-int
  (fn (_ n)
    (def sign (if (%int< n 0) -1 1))
    (def mag (if (%int< n 0) (%int- 0 n) n))
    (def %go
      (fn (self m acc)
        (if (%int= m 0) (if (null? acc) (list 0) acc)
          (self (%int/ m %bigint-base)
               (pair (%int% m %bigint-base) acc)))))
    (pair sign (%reverse (%go mag ())))))

; Forward declare %bigint and reader
(def %bigint ())
(def %bigint-read ())

(def %make-bigint
  (fn (_ sign limbs)
    (def nl (%bigint-normalize limbs))
    ; Zero check
    (if (if (null? (rest nl)) (%int= (first nl) 0) #f)
      0
      ; If few enough limbs to possibly fit in native int, try demotion.
      ; The window is every length whose value COULD fit -- one limb past
      ; the safe digit budget (a 3-limb 19-digit value can still be under
      ; MAX); the round-trip verify below rejects the ones that wrapped.
      ; The old guard (length*digits <= budget) only ever demoted single
      ; limbs, so any result >= the limb base stayed bigint forever --
      ; printing like an int but failing eq? and raw slot ops.
      (if (not (%int< (%int* %word-size 2) (%int* (%int- (%length nl) 2) %bigint-digits-per-limb)))
        (let ()
          (def val (%bigint-to-int sign nl))
          ; Verify it round-trips (didn't overflow)
          (def rt (%bigint-from-int val))
          (if (if (%int= sign (first rt))
                (%int= 0 (%limb-cmp nl (rest rt))) #f)
            val
            (%make-instance %bigint (pair sign nl))))
        (%make-instance %bigint (pair sign nl))))))

; --- Signed operations ---

(note "Predicates")

; Private predicate; the public API is (Bigint bigint? x).
(def %bigint? (fn (_ x) (%type? x %bigint)))

(def %big-sign (fn (_ x) (first (first x))))
(def %big-limbs (fn (_ x) (rest (first x))))

(def %ensure-big
  (fn (_ x)
    (if (%bigint? x) x
      (let ()
        (def r (%bigint-from-int x))
        (%make-instance %bigint r)))))

(note "Arithmetic")

(def %big-add
  (fn (_ a b)
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def la (%big-limbs a))
    (def lb (%big-limbs b))
    (if (%int= sa sb)
      ; Same sign: add magnitudes
      (%make-bigint sa (%limb-add la lb 0))
      ; Different signs: subtract smaller from larger
      (let ()
        (def c (%limb-cmp la lb))
        (if (%int= c 0) 0
          (if (%int< 0 c)
            (%make-bigint sa (%limb-sub la lb 0))
            (%make-bigint sb (%limb-sub lb la 0))))))))

(def %big-sub
  (fn (_ a b)
    ; Negate b's sign and add
    (def sb (%int* -1 (%big-sign b)))
    (def nb (%make-instance %bigint (pair sb (%big-limbs b))))
    (%big-add a nb)))

(def %big-mul
  (fn (_ a b)
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def sign (%int* sa sb))
    (%make-bigint sign (%limb-mul (%big-limbs a) (%big-limbs b)))))

(def %big-div
  (fn (_ a b)
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (def sign (%int* sa sb))
    (def r (%limb-divmod (%big-limbs a) (%big-limbs b)))
    (%make-bigint sign (first r))))

(def %big-mod
  (fn (_ a b)
    (def r (%limb-divmod (%big-limbs a) (%big-limbs b)))
    (%make-bigint (%big-sign a) (rest r))))

(note "Comparison")

(def %big-lt
  (fn (_ a b)
    (def sa (%big-sign a))
    (def sb (%big-sign b))
    (if (%int< sa sb) #t
      (if (%int< sb sa) #f
        ; Same sign
        (let ()
          (def c (%limb-cmp (%big-limbs a) (%big-limbs b)))
          (if (%int= sa 1)
            (%int< c 0)
            (%int< 0 c)))))))

(def %big-eq
  (fn (_ a b)
    (if (not (%int= (%big-sign a) (%big-sign b))) #f
      (%int= 0 (%limb-cmp (%big-limbs a) (%big-limbs b))))))

; --- Overflow detection for integer operations ---

(def %int-abs (fn (_ n) (if (%int< n 0) (%int- 0 n) n)))

; a+b overflows iff (b>0 and a > MAX-b) or (b<0 and a < MIN-b).  Both
; thresholds are computed on the side that cannot wrap: MAX-b for b>0 and
; MIN-b for b<0 stay in range (MIN itself is spelled -LONG_MAX - 1, both
; steps representable).  (The old form built MIN-b as (MIN+2)+b,
; which itself wrapped for b < -2 -- every (- x digit) with x negative
; spuriously promoted to bigint, and 2-limb results then never demoted,
; leaving bigints that print like ints but fail eq? and raw slot ops.)
(def %would-overflow-add?
  (fn (_ a b)
    (if (%int< 0 b)
      (%int< (%int- %long-max b) a)
      (if (%int< b 0)
        (%int< a (%int- (%int- (%int- 0 %long-max) 1) b))
        #f))))

; a-b overflows iff (b<0 and a > MAX+b) or (b>0 and a < MIN+b).  A direct
; predicate, not add?-of-negation: (%int- 0 b) wraps for b = MIN, and this
; form also answers that edge exactly (MAX+MIN = -1, so a >= 0 promotes).
(def %would-overflow-sub?
  (fn (_ a b)
    (if (%int< b 0)
      (%int< (%int+ %long-max b) a)
      (if (%int< 0 b)
        (%int< a (%int+ (%int- (%int- 0 %long-max) 1) b))
        #f))))

(def %would-overflow-mul?
  (fn (_ a b)
    (if (%int= a 0) #f
      (if (%int= b 0) #f
        (%int< (%int/ %long-max (%int-abs a)) (%int-abs b))))))

(note "Operator Overrides")

; ONE variadic layer per dialect, folded over the DISPATCHING C binaries
; (%int+ etc. are x_prim_sum & co., whose typed-operand path routes bigint --
; and later float/complex -- through the type ops registered below). The only
; semantics the binary dispatch cannot see is INT OVERFLOW PROMOTION: both
; operands are plain ints, so these folds check %would-overflow-* and promote.
; Binary % < = need no wrapper at all: the C prims dispatch directly.
;
; One more blind spot (#584): the C arbitration (x_type_op_try) PUNTS on
; a typed pair where BOTH types register the operator and NEITHER side's
; cvt from-alist declares the other, and the raw fallback then reads
; payload words as integers -- address garbage, caught by the
; cross-engine fuzzer as a divergence (the C answer moves with ASLR, the
; rust answer sits on the pinned arena).  The folds ask %big-mixed-check
; first: exactly that pair raises the lattice's teaching error at the
; operator door.  Every other shape keeps the raw path -- same-type,
; declared, and single-handler pairs are op dispatch's to run, and the
; raw nil raise stays the error the specs pin.  The from/ops alists are
; read through the type catalog: one lattice, one authority (the same
; cells x_type_op_try walks).

(def %type-from-cell (prim-ref 'type 'from-cell))
(def %type-ops-cell (prim-ref 'type 'ops-cell))

(def %big-mixed-check
  (fn (_ op a b)
    (if (null? a) ()
      (if (null? b) ()
        (if (%int-number? a) ()
          (if (%int-number? b) ()
            (do
              (def ha (%type-of a))
              (def hb (%type-of b))
              (def %hit
                (fn (self alist key)
                  (if (null? alist) #f
                    (if (same? (first (first alist)) key) #t
                      (self (rest alist) key)))))
              (if (same? ha hb) ()
                (do
                  (def ta (%type-by-atom ha))
                  (def tb (%type-by-atom hb))
                  (if (%hit (first (%type-from-cell ta)) hb) ()
                    (if (%hit (first (%type-from-cell tb)) ha) ()
                      (if (%hit (first (%type-ops-cell ta)) op)
                        (if (%hit (first (%type-ops-cell tb)) op)
                          (error (%str-append "int op: no declared promotion ("
                            (%str-append ((prim-ref 'type 'name) ha)
                              (%str-append " x "
                                (%str-append ((prim-ref 'type 'name) hb)
                                  ") -- declare the cvt relation (#584)")))))
                          ())
                        ()))))))))))))

; The per-pair binaries, NAMED so the 2-arg fast path below calls them
; directly -- (op a b) is the overwhelming shape and the fold entry
; costs ~1,100 objects per call (the measured allocation disease).
(def %big-add2
  (fn (_ acc x)
    (if (if (%int-number? acc) (%int-number? x) #f)
      (if (%would-overflow-add? acc x)
        (%big-add (%ensure-big acc) (%ensure-big x))
        (%int+ acc x))
      (do (%big-mixed-check (lit +) acc x)
        (%int+ acc x)))))
(def %big-sub2
  (fn (_ acc x)
    (if (if (%int-number? acc) (%int-number? x) #f)
      (if (%would-overflow-sub? acc x)
        (%big-sub (%ensure-big acc) (%ensure-big x))
        (%int- acc x))
      (do (%big-mixed-check (lit -) acc x)
        (%int- acc x)))))
(def %big-mul2
  (fn (_ acc x)
    (if (if (%int-number? acc) (%int-number? x) #f)
      (if (%would-overflow-mul? acc x)
        (%big-mul (%ensure-big acc) (%ensure-big x))
        (%int* acc x))
      (do (%big-mixed-check (lit *) acc x)
        (%int* acc x)))))

(doc + "Add numbers, promoting to bigint on overflow."
  (param args INT|BIGINT "Numbers to add")
  (returns INT|BIGINT "Sum"))
(set! +
  (fn (_ . args)
    (if (eq? args ()) 0
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%big-add2 (first args) (first (rest args)))
          (%fold %big-add2 (first args) (rest args)))))))

(doc - "Subtract numbers, promoting to bigint on overflow. Unary form negates."
  (param args INT|BIGINT "Numbers to subtract")
  (returns INT|BIGINT "Difference"))
(set! -
  (fn (_ . args)
    (if (eq? args ()) 0
      (if (eq? (rest args) ())
        ; Unary negation: plain ints negate directly; typed values (bigint,
        ; rational, float, ...) negate via the dispatching binary (- 0 x),
        ; which routes to the type's own - handler.
        (if (%int-number? (first args))
          (%int- (first args))
          (%int- 0 (first args)))
        (if (eq? (rest (rest args)) ())
          (%big-sub2 (first args) (first (rest args)))
          (%fold %big-sub2 (first args) (rest args)))))))

(doc * "Multiply numbers, promoting to bigint on overflow."
  (param args INT|BIGINT "Numbers to multiply")
  (returns INT|BIGINT "Product"))
(set! *
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%big-mul2 (first args) (first (rest args)))
          (%fold %big-mul2 (first args) (rest args)))))))

(doc / "Divide numbers; bigint operands dispatch through the type ops."
  (param args INT|BIGINT "Numbers to divide")
  (returns INT|BIGINT "Quotient"))
(set! /
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int/ (first args) (first (rest args)))
          (%fold (fn (_ acc x) (%int/ acc x))
            (first args) (rest args)))))))

; --- Type registration ---

; Analyser: consumes [+-]?[0-9]+ but only scores when too many digits for int
(def %big-digits ())
(set! %big-digits
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      (do (%buffer-unread buffer)
          ; Only score if digit count exceeds native integer range
          (if (%int< %int-max-digits (%buffer-len buffer))
            (%score-set score 1 buffer)
            ())))))

(def %big-sign-state
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      ())))

(def %big-analyse
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %big-digits
      (if (if (= chr 45) #t (= chr 43))
        %big-sign-state
        ()))))

(set! %bigint
  (%make-type "BIGINT"
    (list
      (pair 'write
        (fn (_ self) (display (%bigint-to-string (first (first self)) (rest (first self))))))
      (pair 'analyse %big-analyse)
      (pair 'read (fn (_ . args) (%bigint-read (first args))))
      (pair 'from
        (list
          (pair (%type-of 42)
            (fn (_ value)
              (def r (%bigint-from-int value))
              (%make-instance %bigint r)))
          (pair (%type-of "")
            (fn (_ value) (%bigint-from-string value)))))
      (pair 'to
        (list
          (pair (%type-of 42)
            (fn (_ self) (%bigint-to-int (first (first self)) (rest (first self)))))
          (pair (%type-of "")
            (fn (_ self) (%bigint-to-string (first (first self)) (rest (first self))))))))))

; --- Reader (set after make-type so closure captures the real %bigint) ---
; Through %make-bigint for the same reason as %bigint-from-string: the
; capped analyser triggers on digit COUNT, and a 17-19 digit literal that
; fits the native int must come out native, not as a stealth bigint.
(set! %bigint-read
  (fn (_ . args)
    (let ((parsed (%bigint-parse-digits (%buffer-token (first args)))))
      (%make-bigint (first parsed) (rest parsed)))))

; --- Cap the integer analyser ---
; Push a capped analyser onto the integer type's analyse stack
; that rejects numbers with too many digits for native int

; Type struct navigation via type.x (available from x-core.x boot)
(def %int-type (%type-by-atom (%type-of 0)))

(def %int-capped-digits ())
(set! %int-capped-digits
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      %int-capped-digits
      (do (%buffer-unread buffer)
          (if (not (%int< %int-max-digits (%buffer-len buffer)))
            (%score-set score 1 buffer)
            ())))))

; Hex literals (#507): a leading 0 may open 0x/0X, and the engine's own
; xdigits machine is shadowed by this push, so the cap must read hex too.
; "0x" plus 16 hex digits fills the 64-bit word, so the cap is 18 bytes;
; a bare "0x" declines (no digit was consumed).  Character constants
; throughout: chr arrives as the character CODE and eq?/< compare
; operand words (engine law 1), so #\x and 120 are the same test.
(def %int-capped-xdigits ())
(set! %int-capped-xdigits
  (fn (_ buffer score chr)
    (if (if (if (>= chr #\0) (<= chr #\9) #f) #t
          (if (if (>= chr #\a) (<= chr #\f) #f) #t
            (if (>= chr #\A) (<= chr #\F) #f)))
      %int-capped-xdigits
      (do (%buffer-unread buffer)
          (if (not (%int< 18 (%buffer-len buffer)))
            (%score-set score 1 buffer)
            ())))))

(def %int-capped-xfirst
  (fn (_ buffer score chr)
    (if (if (if (>= chr #\0) (<= chr #\9) #f) #t
          (if (if (>= chr #\a) (<= chr #\f) #f) #t
            (if (>= chr #\A) (<= chr #\F) #f)))
      %int-capped-xdigits
      ())))

(def %int-capped-base
  (fn (_ buffer score chr)
    (if (if (= chr #\x) #t (= chr #\X))
      %int-capped-xfirst
      (%int-capped-digits buffer score chr))))

(def %int-capped-sign
  (fn (_ buffer score chr)
    (if (= chr #\0)
      %int-capped-base
      (if (if (>= chr #\1) (<= chr #\9) #f)
        %int-capped-digits
        ()))))

(def %int-capped-analyse
  (fn (_ buffer score chr)
    (if (= chr #\0)
      %int-capped-base
      (if (if (>= chr #\1) (<= chr #\9) #f)
        %int-capped-digits
        (if (if (= chr #\-) #t (= chr #\+))
          %int-capped-sign
          ())))))

(%type-push-analyse %int-type %int-capped-analyse)

; --- Type ops: the generic operators dispatch here for bigint operands ---
; Handlers receive raw operands; the non-bigint side is always an int (a wider
; type would have absorbed the bigint via its from-declaration), so %ensure-big
; covers the coercion.

(def %bigint-type (%type-by-atom %bigint))
(%type-push-op %bigint-type '+ (fn (_ a b) (%big-add (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '- (fn (_ a b) (%big-sub (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '* (fn (_ a b) (%big-mul (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '/ (fn (_ a b) (%big-div (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '% (fn (_ a b) (%big-mod (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '< (fn (_ a b) (%big-lt (%ensure-big a) (%ensure-big b))))
(%type-push-op %bigint-type '= (fn (_ a b) (%big-eq (%ensure-big a) (%ensure-big b))))

(import x/type/class)

(def-class Bigint ()
  (static
    (method bigint? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an arbitrary-precision integer."
        (returns BOOL "True if x is a bigint"))
      (%bigint? x))
    (method + (self (param a INT|BIGINT "First operand") (param b INT|BIGINT "Second operand"))
      (doc "Add two bigints (ints coerce)." (returns INT|BIGINT "Sum, demoted to integer if it fits"))
      (%big-add (%ensure-big a) (%ensure-big b)))
    (method - (self (param a INT|BIGINT "First operand") (param b INT|BIGINT "Second operand"))
      (doc "Subtract two bigints (ints coerce)." (returns INT|BIGINT "Difference, demoted to integer if it fits"))
      (%big-sub (%ensure-big a) (%ensure-big b)))
    (method * (self (param a INT|BIGINT "First operand") (param b INT|BIGINT "Second operand"))
      (doc "Multiply two bigints (ints coerce)." (returns INT|BIGINT "Product, demoted to integer if it fits"))
      (%big-mul (%ensure-big a) (%ensure-big b)))
    (method / (self (param a INT|BIGINT "Dividend") (param b INT|BIGINT "Divisor"))
      (doc "Divide two bigints (truncating; ints coerce)." (returns INT|BIGINT "Quotient, demoted to integer if it fits"))
      (%big-div (%ensure-big a) (%ensure-big b)))
    (method % (self (param a INT|BIGINT "Dividend") (param b INT|BIGINT "Divisor"))
      (doc "Remainder of bigint division (ints coerce)." (returns INT|BIGINT "Remainder, demoted to integer if it fits"))
      (%big-mod (%ensure-big a) (%ensure-big b)))
    (method < (self (param a INT|BIGINT "Left operand") (param b INT|BIGINT "Right operand"))
      (doc "Test whether a is less than b (ints coerce)." (returns BOOL "True if a < b"))
      (%big-lt (%ensure-big a) (%ensure-big b)))
    (method = (self (param a INT|BIGINT "Left operand") (param b INT|BIGINT "Right operand"))
      (doc "Test whether a equals b (ints coerce)." (returns BOOL "True if a equals b"))
      (%big-eq (%ensure-big a) (%ensure-big b)))
    (method would-overflow-add? (self (param a INT "First operand") (param b INT "Second operand"))
      (doc "Test whether addition of two native integers would overflow."
        (returns BOOL "True if a + b would overflow native integer"))
      (%would-overflow-add? a b))
    (method would-overflow-mul? (self (param a INT "First operand") (param b INT "Second operand"))
      (doc "Test whether multiplication of two native integers would overflow."
        (returns BOOL "True if a * b would overflow native integer"))
      (%would-overflow-mul? a b))))

; Value dispatch (subject-last): (big bigint?) -> (Bigint bigint? big).
(def %type-push-call (prim-ref 'type 'push-call))
(%type-push-call (%type-by-atom %bigint) (%class-call-handler Bigint))

; Join the pact last, once the module is fully usable: this fires any
; pairwise registration waiting on bigint (e.g. float's bigint->float
; conversion) regardless of which module loaded first.
(import x/sys/pact)
(Pact join 'bigint %bigint)

(doc (provide x/num/bigint Bigint)
  (note "Auto-promotes when integers exceed native range; the generic operators")
  (note "dispatch bigint operands through the type ops. API: (Bigint + a b), ...")
  "Arbitrary-precision integers, homed on the Bigint class.")
