; cksum.x -- Cksum: the CRC of POSIX cksum in pure x-lang.
;
; The polynomial 0x04C11DB7 taken MSB first, the register started at zero,
; the input's length folded in after its bytes, low octet first, and the
; register inverted at the end.  Not x/codec/crc32's sum: that one is the
; reflected polynomial of ISO 3309, started at all ones.
;
; Pure INT on the C bit ops through the int doors; the exclusive or, which
; has no door, is (a | b) - (a & b) on the non-negative words here.  The
; byte loop is one top-level function calling itself in tail position.
(module x/codec/cksum)

(import x/type/vector)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(import x/core/doors int& int+ int- int->ptr int< int<< int= int>> int| obj-ref obj-set! ptr->int ptr-ref str->ptr str-byte-len)

(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))

(def %m32 4294967295)

; Slot i+1 holds byte i's entry: i in the register's top octet, eight
; shifts, the polynomial folded in when the top bit is set.
(def %table (Vector make 256 0))
((fn (self i)
   (if (int< i 256)
     (do (obj-set! %table (int+ i 1)
           ((fn (fold k c)
              (if (int= k 0) c
                (fold (int- k 1)
                  (int& (if (int= (int& c 2147483648) 0) (int<< c 1) (%xor (int<< c 1) 79764919)) %m32))))
            8 (int<< i 24)))
         (self (int+ i 1)))
     ()))
 0)

; The register after the bytes from i below n at p, the exclusive ors
; written out as crc32.x's are: a call of %xor a byte costs a frame.
(def %fold
  (fn (self p i n c)
    (if (int< i n)
      (do (def b (int& (ptr-ref p i 1) 255))
          (def h (int>> c 24))
          (def t (obj-ref %table (int+ (int- (int| h b) (int& h b)) 1)))
          (def s (int& (int<< c 8) %m32))
          (self p (int+ i 1) n (int- (int| t s) (int& t s))))
      c)))

; The register after the length's octets, low first, until none are left.
(def %fold-length
  (fn (self n c)
    (if (int= n 0) c
      (do (def h (%xor (int>> c 24) (int& n 255)))
          (self (int>> n 8) (%xor (obj-ref %table (int+ h 1)) (int& (int<< c 8) %m32)))))))

; START and LENGTH from an optional span, defaulting to the whole string.
(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/cksum-jit compiles the byte loop, as x/codec/crc32-jit does
; crc32's: an entry of Compiled's made on demand, built for an input of
; %jit-threshold bytes or more or on (Cksum jit!), and adopted only after
; it sums the check inputs below as %fold does.

(def %fold-x (fn (_ p n c) (%fold p 0 n c)))

; Check inputs: the standard one, and 3000 bytes of every value in turn,
; from a register of zero and from one mid-sum.
(def %agrees?
  (fn (_ eng)
    (def r ((prim-ref (lit str) (lit make)) 3000))
    (def p (str->ptr r))
    ((fn (self i) (when (int< i 3000) (do ((prim-ref (lit ptr) (lit set!)) p i (int& (int+ (int+ i 1) (int>> i 3)) 255) 1) (self (int+ i 1))))) 0)
    (and (= (%fold-x (str->ptr "123456789") 9 0) (eng (str->ptr "123456789") 9 0))
         (= (%fold-x p 3000 0) (eng p 3000 0))
         (= (%fold-x p 3000 123456789) (eng p 3000 123456789)))))

(def %jit-threshold 4096)
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit cksum) %fold-x
          (fn (_)
            (import x/codec/cksum-jit)
            ((prim-ref (lit cksum) (lit jit-make)) %table %agrees?))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; The fold for n bytes: the engine's when it is built, or when n is past the
; bar and a build succeeds; else the pure one.
(def %fold-for
  (fn (_ n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
          (%jit-try!))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             %fold-x))
         %entry))))

(def-class Cksum ()
  (doc "The CRC of POSIX cksum in pure x-lang.")
  (static
    (method of (self (param s STRING "Bytes")
                     . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The CRC cksum prints for the bytes, their length folded in. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Cksum of \"123456789\")" "930766865")
        (example "(Cksum of \"\")" "4294967295"))
      (def sp (%span s span))
      (def n (first (rest sp)))
      (%xor (%fold-length n ((%fold-for n) (%at (str->ptr s) (first sp)) n 0)) %m32))
    (method jit! (self)
      (doc "Build and adopt the compiled byte loop (JIT; ARM64 and x86-64 backends) now, if it sums the check inputs exactly as the pure-x fold does. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x fold carries on, with the same sums. of builds it on its own for 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/cksum Cksum)
  "The CRC of POSIX cksum in pure x-lang: (Cksum of s), the polynomial 0x04C11DB7 MSB first with the length folded in.")
