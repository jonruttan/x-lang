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

; The five operations compiled, each (fn (_ a ...)) over the scratch
; address a and word offsets: (mul h f g) (add h f g) (sub h f g)
; (mul121666 h f) (cswap f g b).
(def fe-jit-compile
  (fn (_)
    (list (compile-asm %fj-mul-expr) (compile-asm %fj-add-expr) (compile-asm %fj-sub-expr)
          (compile-asm %fj-m121666-expr) (compile-asm %fj-cswap-expr))))

(doc (provide x/codec/fe25519-jit fe-jit-compile fe-jit-rows fe-jit-swap)
  "The GF(2^255 - 19) operations as compiled functions over a scratch of limbs (JIT, ARM64 and x86-64 backends): (fe-jit-compile) builds multiply, add, subtract, times-121666 and swap for X25519's and Ed25519's engines.")
