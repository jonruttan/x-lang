; bcrypt-jit.x -- the compiled bcrypt_hash engine behind (Bcrypt jit!).
;
; Loaded lazily by x/codec/bcrypt, as x/codec/chacha20-jit is by its
; codec: this module pulls the JIT toolchain, and the codec must stay
; loadable and correct on a host with no JIT.  The pure-x hash in
; bcrypt.x is the reference and the fallback; this engine is adopted
; only after it ANSWERS Go's bcrypt_hash vector -- any disagreement is a
; raise, and the caller's guard turns a raise into "stay pure-x".
;
; Three compiled functions over one buffer, each a tail loop (a tail
; self-call compiles as a jump, so a loop allocates nothing a turn):
;
;   reset   the 1042 state words copied in from the buffer's initial copy
;   expand  one key schedule, 521 blocks in a chain: m 0 is expand0state
;           with the salt's key words, m 1 with the passphrase's, m 2
;           expandstate with the passphrase's and the salt's data words
;   final   the eight magic words, each pair encrypted 64 times
;
; Blowfish's sixteen rounds are straight-line in each, the block's halves
; in buffer words.  The driver here, in x, runs a hash's 131 calls.
(module x/codec/bcrypt-jit)

(import x/tool/jit-group jit-group)

(def %bj-make-str (prim-ref (lit str) (lit make)))
(def %bj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %bj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %bj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %bj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %bj-pset1 (prim-ref (lit ptr) (lit set!)))
(def %bj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %bj-char->int (prim-ref (lit char) (lit ->int)))
(def %bj-M 4294967295)

; the buffer, in words:
;   0..17 P | 18..1041 S0 S1 S2 S3 | 1042..1059 the salt's key words |
;   1060..1077 the passphrase's | 1078..1093 the salt's data words |
;   1094 L | 1095 R | 1096 T | 1100..1107 the magic words |
;   1108..2149 the initial state
(def %bj-KS 1042)
(def %bj-KP 1060)
(def %bj-DS 1078)
(def %bj-L 1094)
(def %bj-R 1095)
(def %bj-T 1096)
(def %bj-C 1100)
(def %bj-INIT 1108)
(def %bj-words 2150)

; --- expression builders (generation time) ---
(def %bj-W (fn (_ i) (list '%mem-ref 'a i)))
(def %bj-setW (fn (_ i v) (list '%mem-set! 'a i v)))
(def %bj-at (fn (_ e) (list '%mem-ref-at 'a e)))
(def %bj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))

; F on the word in buffer word x: S0[a] + S1[b], XOR S2[c], + S3[d].
(def %bj-f
  (fn (_ x)
    (def X (%bj-W x))
    (list '& (list '+ (list '^ (list '& (list '+ (%bj-at (list '+ 18 (list '>> X 24)))
                                                 (%bj-at (list '+ 274 (list '& (list '>> X 16) 255))))
                                         %bj-M)
                                (%bj-at (list '+ 530 (list '& (list '>> X 8) 255))))
                     (%bj-at (list '+ 786 (list '& X 255))))
          %bj-M)))

; One block (blf_enc) on L and R in place.
(def %bj-encrypt
  (list 'do
    (%bj-setW %bj-L (list '^ (%bj-W %bj-L) (%bj-W 0)))
    (%bj-seq 16
      (fn (_ k)
        (def n (+ k 1))
        (if (= (& n 1) 1)
          (%bj-setW %bj-R (list '^ (%bj-W %bj-R) (list '^ (%bj-f %bj-L) (%bj-W n))))
          (%bj-setW %bj-L (list '^ (%bj-W %bj-L) (list '^ (%bj-f %bj-R) (%bj-W n)))))))
    (%bj-setW %bj-T (list '^ (%bj-W %bj-R) (%bj-W 17)))
    (%bj-setW %bj-R (%bj-W %bj-L))
    (%bj-setW %bj-L (%bj-W %bj-T))))

(def %bj-reset-expr
  (list 'fn '(self a i)
    (list 'if (list '< 'i 1042)
      (list 'do (list '%mem-set-at! 'a 'i (%bj-at (list '+ %bj-INIT 'i)))
                (list 'self 'a (list '+ 'i 1)))
      0)))

; The key words into P: the salt's under m 0, the passphrase's otherwise.
(def %bj-key-in
  (%bj-seq 18
    (fn (_ k)
      (%bj-setW k (list '^ (%bj-W k)
                         (%bj-at (list '+ (list 'if (list '= 'm 0) %bj-KS %bj-KP) k)))))))

(def %bj-expand-expr
  (list 'fn '(self a m i)
    (list 'if (list '< 'i 0)
      (list 'do %bj-key-in (%bj-setW %bj-L 0) (%bj-setW %bj-R 0) (list 'self 'a 'm 0))
      (list 'if (list '< 'i 521)
        (list 'do
          (list 'if (list '= 'm 2)
            (list 'do
              (%bj-setW %bj-L (list '^ (%bj-W %bj-L) (%bj-at (list '+ %bj-DS (list '& (list '<< 'i 1) 15)))))
              (%bj-setW %bj-R (list '^ (%bj-W %bj-R) (%bj-at (list '+ %bj-DS (list '& (list '+ (list '<< 'i 1) 1) 15))))))
            0)
          %bj-encrypt
          (list '%mem-set-at! 'a (list '<< 'i 1) (%bj-W %bj-L))
          (list '%mem-set-at! 'a (list '+ (list '<< 'i 1) 1) (%bj-W %bj-R))
          (list 'self 'a 'm (list '+ 'i 1)))
        0))))

; The magic words' four pairs, each encrypted 64 times: turn i is pair i>>6.
(def %bj-final-expr
  ((fn (_ at)
     (list 'fn '(self a i)
       (list 'if (list '< 'i 256)
         (list 'do
           (%bj-setW %bj-L (%bj-at at))
           (%bj-setW %bj-R (%bj-at (list '+ at 1)))
           %bj-encrypt
           (list '%mem-set-at! 'a at (%bj-W %bj-L))
           (list '%mem-set-at! 'a (list '+ at 1) (%bj-W %bj-R))
           (list 'self 'a (list '+ 'i 1)))
         0)))
   (list '+ %bj-C (list '<< (list '>> 'i 6) 1))))

; --- build: compile, wire a driver, and PROVE it against the vector ---
;
; ref: the pure-x hash, (fn (_ pass salt) -> 32 bytes); init: Blowfish's
; 1042 initial words.  Returns a function of the same shape driving the
; compiled functions, or raises -- on a host whose architecture has no
; assembler backend, on any toolchain error, or on a wrong answer.
(def bcrypt-jit-make
  (fn (_ ref init)
    (jit-group "bcrypt-jit" (fn (_) (list %bj-reset-expr %bj-expand-expr %bj-final-expr))
      (fn (_ fns replayed?) (%bj-wire init (first fns) (List ref 1 fns) (List ref 2 fns) replayed?)))))

(def %bj-wire
  (fn (_ init %reset %expand %final replayed?)
    (unless replayed? (Heap collect))
    (def %buf (%bj-make-str (+ (* %bj-words 8) 8)))
    (def %ptr (%bj-str->ptr %buf))
    (def %addr (%bj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%bj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%bj-pref %ptr (* i 8))))
    ((fn (self i ws) (unless (null? ws) (do (%poke i (first ws)) (self (+ i 1) (rest ws))))) %bj-INIT init)
    (def %byte (fn (_ s i) (%bj-char->int (%bj-byte-ref s i))))
    ; big-endian word k of a 64-byte digest, k counted around its 16
    (def %be
      (fn (_ s k)
        (def j (* (if (< k 16) k (- k 16)) 4))
        (| (<< (%byte s j) 24) (| (<< (%byte s (+ j 1)) 16) (| (<< (%byte s (+ j 2)) 8) (%byte s (+ j 3)))))))
    (def %magic (list 1333295459 1752330093 1635019107 1114402679 1718186856 1400332660 1148808801 1835627621))
    (def %engine
      (fn (_ pass salt)
        ((fn (self k) (unless (= k 18) (do (%poke (+ %bj-KS k) (%be salt k)) (%poke (+ %bj-KP k) (%be pass k)) (self (+ k 1))))) 0)
        ((fn (self k) (unless (= k 16) (do (%poke (+ %bj-DS k) (%be salt k)) (self (+ k 1))))) 0)
        ((fn (self i ws) (unless (null? ws) (do (%poke i (first ws)) (self (+ i 1) (rest ws))))) %bj-C %magic)
        (%reset %addr 0)
        (%expand %addr 2 -1)
        ((fn (self n) (unless (= n 0) (do (%expand %addr 0 -1) (%expand %addr 1 -1) (self (- n 1))))) 64)
        (%final %addr 0)
        (def out (%bj-make-str 33))
        (def p (%bj-str->ptr out))
        ((fn (self k)
           (unless (= k 8)
             (do (def w (%peek (+ %bj-C k)))
                 (%bj-pset1 p (* k 4) (& w 255) 1)
                 (%bj-pset1 p (+ (* k 4) 1) (& (>> w 8) 255) 1)
                 (%bj-pset1 p (+ (* k 4) 2) (& (>> w 16) 255) 1)
                 (%bj-pset1 p (+ (* k 4) 3) (& (>> w 24) 255) 1)
                 (self (+ k 1)))))
         0)
        out))
    ; the check: Go's bcrypt_hash vector, the passphrase digest bytes 0..63
    ; and the salt's 64..127
    (def %ramp
      (fn (_ from)
        (def r (%bj-make-str 65))
        (def p (%bj-str->ptr r))
        ((fn (self i) (unless (= i 64) (do (%bj-pset1 p i (+ from i) 1) (self (+ i 1))))) 0)
        r))
    (def %want (list 135 144 72 112 238 249 222 221 248 231 97 26 20 1 6 230
                     170 241 163 99 217 162 197 4 219 53 100 67 114 30 181 85))
    (unless replayed?
      ((fn (_ got)
         ((fn (self i ws)
            (unless (null? ws)
              (do (unless (= (%byte got i) (first ws))
                    (Err raise 'state "bcrypt-jit: the engine does not answer Go's bcrypt_hash vector" ()))
                  (self (+ i 1) (rest ws)))))
          0 %want))
       (%engine (%ramp 0) (%ramp 64))))
    %engine))

; The codec reaches the maker through the catalogue, as chacha20's does.
(prim-reg! (lit bcrypt) (lit jit-make) bcrypt-jit-make)

(doc (provide x/codec/bcrypt-jit bcrypt-jit-make)
  "The compiled bcrypt_hash engine (JIT, ARM64 and x86-64 backends); built and adopted by x/codec/bcrypt after it answers Go's bcrypt_hash vector.")
