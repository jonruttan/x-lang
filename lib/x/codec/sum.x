; sum.x -- Sum: the two checksums of sum(1) in pure x-lang.
;
; BSD's, sum's default: a 16-bit register rotated right one bit, then the
; byte added.  System V's (sum -s): the bytes added in 32 bits, the total
; folded twice into 16.
;
; Pure INT on the C bit ops through the int doors.  Each byte loop is one
; top-level function calling itself in tail position.
(module x/codec/sum)

; The compiled engines are on Compiled's list.
(import x/tool/compiled)

(import x/core/doors int& int+ int- int->ptr int< int<< int>> ptr->int ptr-ref str->ptr str-byte-len)

; BSD's register after the bytes from i below n at p.
(def %fold-bsd
  (fn (self p i n s)
    (if (int< i n)
      (self p (int+ i 1) n
        (int& (int+ (int+ (int>> s 1) (int<< (int& s 1) 15)) (int& (ptr-ref p i 1) 255)) 65535))
      s)))

; System V's total after the bytes from i below n at p.
(def %fold-sysv
  (fn (self p i n t)
    (if (int< i n)
      (self p (int+ i 1) n (int+ t (int& (ptr-ref p i 1) 255)))
      t)))

; The total cut to 32 bits, as sum's unsigned register wraps, and folded
; twice into 16.
(def %sysv-fold
  (fn (_ t)
    (def w (int& t 4294967295))
    (def r (int+ (int& w 65535) (int>> w 16)))
    (int& (int+ (int& r 65535) (int>> r 16)) 65535)))

; START and LENGTH from an optional span, defaulting to the whole string.
(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))

; --- The compiled engines (JIT), adopted only when they prove out ----
;
; x/codec/sum-jit compiles each byte loop, as x/codec/crc32-jit does
; crc32's: an entry of Compiled's made on demand, built for an input of
; %jit-threshold bytes or more or on (Sum jit!), and adopted only after it
; sums the check inputs below as the pure fold does.

(def %bsd-x (fn (_ p n s) (%fold-bsd p 0 n s)))
(def %sysv-x (fn (_ p n t) (%fold-sysv p 0 n t)))

; Check inputs: the standard one, and 3000 bytes of every value in turn,
; from a register of zero and from one mid-sum.
(def %agrees-with
  (fn (_ ref)
    (fn (_ eng)
      (def r ((prim-ref (lit str) (lit make)) 3000))
      (def p (str->ptr r))
      ((fn (self i) (when (int< i 3000) (do ((prim-ref (lit ptr) (lit set!)) p i (int& (int+ (int+ i 1) (int>> i 3)) 255) 1) (self (int+ i 1))))) 0)
      (and (= (ref (str->ptr "123456789") 9 0) (eng (str->ptr "123456789") 9 0))
           (= (ref p 3000 0) (eng p 3000 0))
           (= (ref p 3000 12345) (eng p 3000 12345))))))

(def %jit-threshold 4096)

; Each engine's Compiled entry, made on first use; WHICH is bsd or sysv.
(def %bsd-entry ())
(def %sysv-entry ())

(def %bsd? (fn (_ which) (eq? which (lit bsd))))
(def %entry (fn (_ which) (if (%bsd? which) %bsd-entry %sysv-entry)))
(def %fold-x (fn (_ which) (if (%bsd? which) %bsd-x %sysv-x)))

(def %jit-try!
  (fn (_ which)
    (when (null? (%entry which))
      ((fn (_ e) (if (%bsd? which) (set! %bsd-entry e) (set! %sysv-entry e)))
       (Compiled make-on-demand (if (%bsd? which) (lit sum-bsd) (lit sum-sysv)) (%fold-x which)
         (fn (_)
           (import x/codec/sum-jit)
           ((prim-ref (lit sum) (lit jit-make)) which (%agrees-with (%fold-x which))))
         (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     (%entry which))))

; The fold for n bytes: the engine's when it is built, or when n is past the
; bar and a build succeeds; else the pure one.
(def %fold-for
  (fn (_ which n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) (%entry which)))
          (%jit-try! which))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             (%fold-x which)))
         (%entry which)))))

(def %run
  (fn (_ which s span)
    (def sp (%span s span))
    (def n (first (rest sp)))
    ((%fold-for which n) (%at (str->ptr s) (first sp)) n 0)))

(def-class Sum ()
  (doc "The two checksums of sum(1), BSD's and System V's, in pure x-lang.")
  (static
    (method bsd (self (param s STRING "Bytes")
                      . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "BSD's checksum of the bytes, sum's default. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns INTEGER "The checksum, 0 to 65535")
        (example "(Sum bsd \"123456789\")" "53615")
        (example "(Sum bsd \"\")" "0"))
      (%run (lit bsd) s span))
    (method sysv (self (param s STRING "Bytes")
                       . (param span LIST "START, then LENGTH, as for bsd"))
      (doc "System V's checksum of the bytes, sum -s's."
        (returns INTEGER "The checksum, 0 to 65535")
        (example "(Sum sysv \"123456789\")" "477")
        (example "(Sum sysv \"\")" "0"))
      (%sysv-fold (%run (lit sysv) s span)))
    (method jit! (self)
      (doc "Build and adopt both compiled byte loops (JIT; ARM64 and x86-64 backends) now, if each sums the check inputs exactly as its pure-x fold does. Idempotent. Answers #t when both engines are active, #f otherwise -- the pure-x folds carry on, with the same sums. bsd and sysv build theirs on their own for 4KB or more."
        (returns BOOL "#t when both compiled engines are active"))
      (and (%jit-try! (lit bsd)) (%jit-try! (lit sysv))))))

(doc (provide x/codec/sum Sum)
  "The two checksums of sum(1) in pure x-lang: (Sum bsd s), BSD's rotate-and-add, and (Sum sysv s), System V's byte total folded into 16 bits.")
