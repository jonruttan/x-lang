; fe25519-jit.x -- the field's operations compiled, for X25519 and Ed25519.
;
; Loaded lazily by the engines (x25519-jit, ed25519-jit): this module
; pulls the JIT toolchain.  Each operation is one compiled function over
; a scratch of 64-bit words, a field element ten words at an offset the
; call names, so one build serves every layout: (fe-jit-compile) answers
; the five, mul add sub mul121666 and cswap, in that order.  The multiply
; is ref10's fe_mul straight-line: row k collects the products f_i g_j
; with i + j = k, and those with i + j = k + 10 folded by 19, an odd-odd
; pair doubled; the rows land in a row area at fe-jit-rows and the
; rounding carries run there, so the result may alias an operand.  The
; carries' shifts are arithmetic, which is what signed limbs need and
; what the lane emits.  A caller lays its elements out around the row
; area and the swap temporary, which are the scratch's slots 120..130.
(module x/codec/fe25519-jit)

(import x/tool/compile compile-asm)
(import x/codec/fe25519 fe-zero fe-limbs fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-sq-n fe-mul121666)

(def fe-jit-rows 120)
(def fe-jit-swap 130)
(def %ROWS fe-jit-rows)
(def %SWAP fe-jit-swap)

; --- expression builders (generation time) ---
; An operand's limb i: the offset is a parameter, so it is a runtime add.
(def %fj-at (fn (_ off i) (list '%mem-ref-at 'a (list '+ off i))))
(def %fj-set (fn (_ off i v) (list '%mem-set-at! 'a (list '+ off i) v)))
(def %fj-row (fn (_ i) (list '%mem-ref 'a (+ %ROWS i))))
(def %fj-row-set (fn (_ i v) (list '%mem-set! 'a (+ %ROWS i) v)))
(def %fj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))
(def %fj-width (fn (_ i) (if (= (& i 1) 0) 26 25)))

; The rounding carry from row i into row i+1 (row 9's into row 0, times
; 19): c = (h_i + 2^(w-1)) >> w; h_i -= c << w; h_next += c.  The carry
; is spelled twice rather than kept, the lane having no locals.
(def %fj-carry
  (fn (_ i)
    (def w (%fj-width i))
    (def c (list '>> (list '+ (%fj-row i) (<< 1 (- w 1))) w))
    (def next (if (= i 9) 0 (+ i 1)))
    (list 'do
      (%fj-row-set next (list '+ (%fj-row next) (if (= i 9) (list '* c 19) c)))
      (%fj-row-set i (list '- (%fj-row i) (list '<< c w))))))

(def %fj-mul-order (list 0 4 1 5 2 6 3 7 4 8 9 0))
(def %fj-load-order (list 9 1 3 5 7 0 2 4 6 8))

(def %fj-carries
  (fn (_ order) (pair 'do (List map %fj-carry order))))

; Row k of the product: every f_i g_j with i + j = k, or = k + 10 folded
; by 19; odd-odd pairs doubled.
(def %fj-mul-row
  (fn (_ k)
    (def term
      (fn (_ i j)
        (list '* (list '* (%fj-at 'f i) (%fj-at 'g j))
              (* (if (= (& (& i j) 1) 1) 2 1) (if (>= (+ i j) 10) 19 1)))))
    ; one pair an i: j = k - i, or k - i + 10 for the fold
    (def terms
      ((fn (self i acc)
         (if (< i 0) acc
           (self (- i 1) (pair (term i (if (>= (- k i) 0) (- k i) (+ (- k i) 10))) acc))))
       9 ()))
    (%fj-row-set k
      ((fn (self ts) (if (null? (rest ts)) (first ts) (list '+ (first ts) (self (rest ts))))) terms))))

(def %fj-copy-rows
  (fn (_ off) (%fj-seq 10 (fn (_ i) (%fj-set off i (%fj-row i))))))

; h = f * g
(def %fj-mul-expr
  (list 'fn '(_ a h f g)
    (list 'do (%fj-seq 10 %fj-mul-row) (%fj-carries %fj-mul-order) (%fj-copy-rows 'h))))

; h = f + g, h = f - g: limb by limb, no carry (the multiply's absorb it)
(def %fj-add-expr
  (list 'fn '(_ a h f g)
    (%fj-seq 10 (fn (_ i) (%fj-set 'h i (list '+ (%fj-at 'f i) (%fj-at 'g i)))))))
(def %fj-sub-expr
  (list 'fn '(_ a h f g)
    (%fj-seq 10 (fn (_ i) (%fj-set 'h i (list '- (%fj-at 'f i) (%fj-at 'g i)))))))

; h = f * 121666, the ladder's constant
(def %fj-m121666-expr
  (list 'fn '(_ a h f)
    (list 'do (%fj-seq 10 (fn (_ i) (%fj-row-set i (list '* (%fj-at 'f i) 121666))))
              (%fj-carries %fj-load-order)
              (%fj-copy-rows 'h))))

; f and g exchanged when b is 1
(def %fj-cswap-expr
  (list 'fn '(_ a f g b)
    (list 'if (list '= 'b 1)
      (%fj-seq 10 (fn (_ i)
                    (list 'do (list '%mem-set! 'a %SWAP (%fj-at 'f i))
                              (%fj-set 'f i (%fj-at 'g i))
                              (%fj-set 'g i (list '%mem-ref 'a %SWAP)))))
      0)))

; --- the build, once a process, proven against the pure-x field ---------

(def %fj-make-str (prim-ref (lit str) (lit make)))
(def %fj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %fj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %fj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %fj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %fj-oref (prim-ref (lit obj) (lit ref)))
(def %fj-oset! (prim-ref (lit obj) (lit set!)))
(def %fj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %fj-char->int (prim-ref (lit char) (lit ->int)))

; A scratch of n words: (BUF PTR ADDR), the string kept so its address
; stays live.
(def %fj-scratch
  (fn (_ n)
    (def buf (%fj-make-str (* n 8)))
    (def ptr (%fj-str->ptr buf))
    (list buf ptr (%fj-ptr->int ptr))))

(def %fj-load!
  (fn (_ ptr off v)
    ((fn (self i) (unless (= i 10) (do (%fj-pset ptr (* (+ off i) 8) (%fj-oref v (+ i 1))) (self (+ i 1))))) 0)))

(def %fj-store
  (fn (_ ptr off)
    (def v (fe-zero))
    ((fn (self i) (unless (= i 10) (do (%fj-oset! v (+ i 1) (%fj-pref ptr (* (+ off i) 8))) (self (+ i 1))))) 0)
    v))

(def %fj-same-limbs?
  (fn (_ x y)
    ((fn (self i) (if (= i 11) #t (if (= (%fj-oref x i) (%fj-oref y i)) (self (+ i 1)) #f))) 1)))

(def %fj-built ())

; The differential check: each operation against the pure-x field's, limb
; for limb (the two are the same algorithm, ref10's, carried in the same
; order), on two elements with every limb in use.  A field operation costs
; the pure-x side a couple of milliseconds, so the check is cheap.
(def %fj-check
  (fn (_ ops)
    (def s (%fj-scratch 136))
    (def ptr (first (rest s)))
    (def a (first (rest (rest s))))
    (def f (fe-frombytes "x25519 and ed25519 share a field"))
    (def g (fe-frombytes "the field is GF(2^255 - 19), ok?"))
    (def %run
      (fn (_ call)
        (%fj-load! ptr 0 f) (%fj-load! ptr 10 g)
        (call)
        (%fj-store ptr 20)))
    (def %expect
      (fn (_ got want what)
        (unless (%fj-same-limbs? got want)
          (Err raise 'state (Str8 append "fe25519-jit: " what " disagrees with the pure-x field") ()))))
    (%expect (%run (fn (_) ((List ref 0 ops) a 20 0 10))) (fe-mul f g) "mul")
    (%expect (%run (fn (_) ((List ref 1 ops) a 20 0 10))) (fe-add f g) "add")
    (%expect (%run (fn (_) ((List ref 2 ops) a 20 0 10))) (fe-sub f g) "sub")
    (%expect (%run (fn (_) ((List ref 3 ops) a 20 0))) (fe-mul121666 f) "mul121666")
    (%fj-load! ptr 0 f) (%fj-load! ptr 10 g)
    ((List ref 4 ops) a 0 10 1)
    (%expect (%fj-store ptr 0) g "cswap")
    (%expect (%fj-store ptr 10) f "cswap")
    ((List ref 4 ops) a 0 10 0)
    (%expect (%fj-store ptr 0) g "cswap")))

; The five operations compiled, each (fn (_ a ...)) over the scratch
; address a and word offsets: (mul h f g) (add h f g) (sub h f g)
; (mul121666 h f) (cswap f g b).  Built and checked the first time it is
; asked for; both curves' engines share the one build.
(def fe-jit-compile
  (fn (_)
    (when (null? %fj-built)
      (do (def ops (list (compile-asm %fj-mul-expr) (compile-asm %fj-add-expr) (compile-asm %fj-sub-expr)
                         (compile-asm %fj-m121666-expr) (compile-asm %fj-cswap-expr)))
          (%fj-check ops)
          (set! %fj-built ops)))
    %fj-built))

; --- the inverse and the square root's power, on field vectors -----------
;
; ref10's two chains, the same as x/codec/fe25519's fe-invert and
; fe-pow22523, run on the compiled multiply over a scratch of their own:
; an element in, an element out, a few hundred native multiplies where the
; pure-x chain is a few hundred interpreted ones.  Each is checked once,
; algebraically, against the pure-x field: z times its inverse is one, and
; the power to the eighth times z to the fourth is one.

(def %fj-chains ())

(def %fj-make-chains
  (fn (_ ops)
    (def s (%fj-scratch 136))
    (def ptr (first (rest s)))
    (def a (first (rest (rest s))))
    (def mul (List ref 0 ops))
    (def %Z 0) (def %A 10) (def %B 20) (def %C 30) (def %D 40) (def %O 50)
    (def %copy (fn (_ to from) ((fn (self i) (unless (= i 10) (do (%fj-pset ptr (* (+ to i) 8) (%fj-pref ptr (* (+ from i) 8))) (self (+ i 1))))) 0)))
    (def %sq (fn (_ h f) (mul a h f f)))
    ; h = f^(2^n), h and f distinct or the same
    (def %sqn (fn (_ h f n) (%copy h f) ((fn (self i) (unless (= i 0) (do (%sq h h) (self (- i 1))))) n)))
    (def %m (fn (_ h f g) (mul a h f g)))
    (def invert
      (fn (_ z)
        (%fj-load! ptr %Z z)
        (%sq %A %Z)
        (%sqn %D %A 2) (%m %B %Z %D)
        (%m %A %A %B)
        (%sq %D %A) (%m %B %B %D)
        (%sqn %D %B 5) (%m %B %D %B)
        (%sqn %D %B 10) (%m %C %D %B)
        (%sqn %D %C 20) (%m %C %D %C)
        (%sqn %D %C 10) (%m %B %D %B)
        (%sqn %D %B 50) (%m %C %D %B)
        (%sqn %D %C 100) (%m %C %D %C)
        (%sqn %D %C 50) (%m %D %D %B)
        (%sqn %D %D 5) (%m %O %D %A)
        (%fj-store ptr %O)))
    (def pow22523
      (fn (_ z)
        (%fj-load! ptr %Z z)
        (%sq %A %Z)
        (%sqn %D %A 2) (%m %B %Z %D)
        (%m %D %A %B) (%sq %D %D) (%m %A %B %D)
        (%sqn %D %A 5) (%m %A %D %A)
        (%sqn %D %A 10) (%m %B %D %A)
        (%sqn %D %B 20) (%m %B %D %B)
        (%sqn %D %B 10) (%m %A %D %A)
        (%sqn %D %A 50) (%m %B %D %A)
        (%sqn %D %B 100) (%m %B %D %B)
        (%sqn %D %B 50) (%m %A %D %A)
        (%sqn %D %A 2) (%m %O %D %Z)
        (%fj-store ptr %O)))
    (def z (fe-frombytes "x25519 and ed25519 share a field"))
    (def one (fe-tobytes (fe-limbs (list 1))))
    (def %is-one?
      (fn (_ v)
        (def b (fe-tobytes v))
        ((fn (self i) (if (= i 32) #t (if (= (%fj-char->int (%fj-byte-ref b i)) (%fj-char->int (%fj-byte-ref one i))) (self (+ i 1)) #f))) 0)))
    (unless (%is-one? (fe-mul z (invert z)))
      (Err raise 'state "fe25519-jit: the inverse chain disagrees with the pure-x field" ()))
    (unless (%is-one? (fe-mul (fe-sq-n (pow22523 z) 3) (fe-sq (fe-sq z))))
      (Err raise 'state "fe25519-jit: the square root's power disagrees with the pure-x field" ()))
    (list invert pow22523)))

; (invert pow22523), each (fn (_ z) -> element), built the first time.
(def fe-jit-chains
  (fn (_)
    (when (null? %fj-chains) (set! %fj-chains (%fj-make-chains (fe-jit-compile))))
    %fj-chains))

(doc (provide x/codec/fe25519-jit fe-jit-compile fe-jit-chains fe-jit-rows fe-jit-swap)
  "The GF(2^255 - 19) operations as compiled functions over a scratch of limbs (JIT, ARM64 and x86-64 backends): (fe-jit-compile) builds multiply, add, subtract, times-121666 and swap once a process, each checked against the pure-x field; (fe-jit-chains) the inverse and the square root's power on field elements over them.")
