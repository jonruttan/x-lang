; sha3-jit.x -- the compiled Keccak engine behind (Sha3 jit!).
;
; Loaded lazily by x/codec/sha3, as x/codec/sha512-jit is by sha512.x: this
; module pulls the JIT toolchain, and the codec must stay loadable -- and
; correct -- on a host with no JIT.  The pure-x digest in sha3.x is the
; reference and the fallback; this engine is an accelerator only, adopted
; only after it AGREES with that digest on the standard's widths, padding
; boundaries and binary input.
;
; The lanes live in a scratch buffer as 64-bit words.  Four compiled
; functions do the work: absorb xors a block of the padded message into the
; lanes, a lane a step, with SHA-3's padding compiled arithmetic on the
; length and the total; theta, rho-pi and chi-iota are a round's three
; steps, each unrolled over the twenty-five lanes.  The x driver calls them
; per block and per round -- one function a step keeps each inside what the
; assembler's buffer takes.  As in sha512-jit, the lane's right shift is
; arithmetic, so every logical shift is masked after.
(module x/codec/sha3-jit)

(import x/tool/compile compile-asm)
(import x/type/vector)

(def %k3-make-str (prim-ref (lit str) (lit make)))
(def %k3-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %k3-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %k3-pset (prim-ref (lit ptr) (lit set!)))
(def %k3-pref (prim-ref (lit ptr) (lit ref)))
(def %k3-oref (prim-ref (lit obj) (lit ref)))

; scratch layout, one 1024-byte buffer of 64-bit words:
;   0..24 A (the lanes) | 25..49 B | 50..54 C | 55 base 56 len 57 total
;   58 lanes a block | 64..87 the round constants
(def %k3-B 25)
(def %k3-C 50)
(def %k3-RC 64)

(def %k3-rot (lit (0 1 62 28 27 36 44 6 55 20 3 10 43 25 39 41 45 15 21 8 18 2 61 56 14)))
(def %k3-pi (lit (0 10 20 5 15 16 1 11 21 6 7 17 2 12 22 23 8 18 3 13 14 24 9 19 4)))

; --- expression builders (generation time) ---
(def %k3-at (fn (_ i) (list '%mem-ref 'a i)))
(def %k3-set (fn (_ i v) (list '%mem-set! 'a i v)))
(def %k3-lmask (fn (_ n) (if (= n 1) 9223372036854775807 (- (<< 1 (- 64 n)) 1))))
(def %k3-rotl
  (fn (_ x n)
    (if (= n 0) x
      (list '| (list '<< x n) (list '& (list '>> x (- 64 n)) (%k3-lmask (- 64 n)))))))
(def %k3-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))
(def %k3-nth (fn (self n l) (if (= n 0) (first l) (self (- n 1) (rest l)))))

; theta: C[x] the column parities, then each lane xored with its neighbours'
(def %k3-theta-expr
  (list 'fn '(self a)
    (list 'do
      (%k3-seq 5 (fn (_ x)
        (%k3-set (+ %k3-C x)
          (list '^ (%k3-at x) (list '^ (%k3-at (+ x 5)) (list '^ (%k3-at (+ x 10))
            (list '^ (%k3-at (+ x 15)) (%k3-at (+ x 20)))))))))
      (%k3-seq 25 (fn (_ i)
        (let ((x (% i 5)))
          (%k3-set i (list '^ (%k3-at i)
                       (list '^ (%k3-at (+ %k3-C (% (+ x 4) 5)))
                                (%k3-rotl (%k3-at (+ %k3-C (% (+ x 1) 5))) 1))))))))))

; rho and pi: each lane rotated into its place in B
(def %k3-rhopi-expr
  (list 'fn '(self a)
    (%k3-seq 25 (fn (_ i)
      (%k3-set (+ %k3-B (%k3-nth i %k3-pi)) (%k3-rotl (%k3-at i) (%k3-nth i %k3-rot)))))))

; chi from B back into A, then iota with round R's constant
(def %k3-chi-expr
  (list 'fn '(self a r)
    (list 'do
      (%k3-seq 25 (fn (_ i)
        (let ((x (% i 5)) (row (- i (% i 5))))
          (%k3-set i (list '^ (%k3-at (+ %k3-B i))
                       (list '& (list '~ (%k3-at (+ %k3-B row (% (+ x 1) 5))))
                                (%k3-at (+ %k3-B row (% (+ x 2) 5)))))))))
      (%k3-set 0 (list '^ (%k3-at 0) (list '%mem-ref-at 'a (list '+ %k3-RC 'r)))))))

; byte K of the padded message, K an expression: the message, 0x06, zeros,
; 0x80 on the last byte of the last block, 0x86 where the two meet
(def %k3-pad-byte
  (fn (_ k)
    (def L (%k3-at 56))
    (def T (%k3-at 57))
    (list 'if (list '< k L)
      (list '%mem-byte-ref-at 'm k)
      (list 'if (list '= k L)
        (list 'if (list '= k (list '- T 1)) 134 6)
        (list 'if (list '= k (list '- T 1)) 128 0)))))

; lane T of the block at base: eight padded bytes, little-endian
(def %k3-lane
  ((fn (self j acc)
     (if (< j 0) acc
       (self (- j 1)
         (list '| (list '<< (%k3-pad-byte (list '+ (list '+ (%k3-at 55) (list '<< 't 3)) j)) (* 8 j)) acc))))
   6 (list (lit <<) (%k3-pad-byte (list (lit +) (list (lit +) (%k3-at 55) (list (lit <<) (lit t) 3)) 7)) 56)))

(def %k3-absorb-expr
  (list 'fn '(self a m t)
    (list 'if (list '= 't (%k3-at 58)) 0
      (list 'do
        (list '%mem-set-at! 'a 't (list '^ (list '%mem-ref-at 'a 't) %k3-lane))
        (list 'self 'a 'm (list '+ 't 1))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; rc:  the codec's round-constant vector, twenty-four lanes.
; ref: the pure-x digest, (fn (_ width s n) -> a Vector of the 25 lanes).
;
; Returns (fn (_ width s n) -> a Vector of the 25 lanes) driving the
; compiled functions, or raises -- on a host with no assembler backend, on
; any toolchain error, or on DISAGREEMENT with the reference.  The caller
; guards; a raise means "stay pure-x", never a wrong digest.
(def sha3-jit-make
  (fn (_ rc ref)
    (def %theta (compile-asm %k3-theta-expr))
    (def %rhopi (compile-asm %k3-rhopi-expr))
    (def %chi (compile-asm %k3-chi-expr))
    (def %absorb (compile-asm %k3-absorb-expr))
    (Heap collect)
    (def %buf (%k3-make-str 1024))
    (def %ptr (%k3-str->ptr %buf))
    (def %addr (%k3-ptr->int %ptr))
    (def %poke (fn (_ i v) (%k3-pset %ptr (* i 8) v 8)))
    (def %peek (fn (_ i) (%k3-pref %ptr (* i 8) 8)))
    ((fn (self r)
       (unless (= r 24)
         (do (%poke (+ %k3-RC r) (%k3-oref rc (+ r 1))) (self (+ r 1))))) 0)
    (def %digest
      (fn (_ width s n)
        (def rate (- 200 (>> width 2)))
        (def total (* (+ (/ (- n (% n rate)) rate) 1) rate))
        (def maddr (%k3-ptr->int (%k3-str->ptr s)))
        ((fn (self i) (unless (= i 25) (do (%poke i 0) (self (+ i 1))))) 0)
        (%poke 56 n)
        (%poke 57 total)
        (%poke 58 (>> rate 3))
        ((fn (self b)
           (unless (= b total)
             (do (%poke 55 b)
                 (%absorb %addr maddr 0)
                 ((fn (self r)
                    (unless (= r 24)
                      (do (%theta %addr) (%rhopi %addr) (%chi %addr r) (self (+ r 1))))) 0)
                 (self (+ b rate))))) 0)
        (Vector from-list ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%peek i) acc)))) 24 ()))))
    (def %disagrees "sha3-jit: engine disagrees with the pure-x digest")
    (def %same
      (fn (_ x y)
        ((fn (self i) (if (= i 25) #t (if (= (Vector ref i x) (Vector ref i y)) (self (+ i 1)) #f))) 0)))
    (def %check
      (fn (_ width s n)
        (unless (%same (%digest width s n) (ref width s n))
          (Err raise 'state %disagrees width))))
    (%check 256 "" 0)
    (%check 224 "abc" 3)
    (%check 384 "abc" 3)
    (%check 512 "abc" 3)
    ; the padding alone in a block, two blocks, and 0x06 and 0x80 meeting
    (%check 256 (Str8 pad-right 136 #\y "x") 136)
    (%check 256 (Str8 pad-right 200 #\a "") 200)
    (%check 256 (Str8 pad-right 135 #\z "") 135)
    ; binary bytes across a block boundary, NULs included
    (def %k3-bin
      (let ((r (%k3-make-str 300)))
        (let ((p (%k3-str->ptr r)))
          (do ((fn (self i) (unless (= i 300) (do (%k3-pset p i (& i 255) 1) (self (+ i 1))))) 0)
              r))))
    (%check 512 %k3-bin 300)
    %digest))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit sha3) (lit jit-make) sha3-jit-make)

(doc (provide x/codec/sha3-jit sha3-jit-make)
  "The compiled Keccak engine for SHA-3 (JIT, ARM64 and x86-64 backends); built and adopted only via (Sha3 jit!) after proving agreement with the pure-x digest.")
