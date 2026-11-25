; neural.x -- Neural: the operations a transformer is made of, on tensors.
;
;   (Neural softmax t)                  -> each run of the last axis as shares of 1
;   (Neural gelu t)                     -> each element x as x times the normal's cumulative at x
;   (Neural gelu t 'tanh)               -> the same by its tanh approximation
;   (Neural layer-norm t gain bias)     -> each run of the last axis brought to mean 0 and
;                                          deviation 1, then scaled by gain and moved by bias
;   (Neural embed table indexes)        -> the table's rows the indexes pick, in their order
;   (Neural causal-mask t)              -> t with every element above the diagonal of its last
;                                          two axes negative infinity
;   (Neural jit!)                       -> the kernels compiled now, and the names of those that are
;
; Each answers a fresh tensor and leaves its operands as they were.  The
; result is f32 for an f32 operand and f64 for any other real one; embed
; and causal-mask keep the operand's encoding.
;
; softmax, gelu and layer-norm are kernels, word forms registered with
; Tensor and run on its lanes: pure at first, compiled once warm, and
; adopted where the compiled kernel writes what the pure one does.  A
; kernel works in place over one contiguous run, the operand's fresh
; copy, element K at word 7 of the scratch.  One with phases keeps the
; phase in word 9: when a pass ends, the form between the phases runs,
; the phase rises and K returns to 0.
;
; An f32 kernel reads a single as a double and rounds a result as it is
; stored, as Tensor's do.  softmax stores each exponential and then
; divides the stored value by their sum, so an f32 share is rounded twice.
;
; gelu is x/2 (1 + erf(x / sqrt 2)); its tanh form, which some published
; models were trained with, is x/2 (1 + tanh(sqrt(2/pi) (x + 0.044715 x^3))).
; layer-norm's variance divides by the count, and epsilon, 1/100000 unless
; given, is added to it under the root.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/neural)
(import x/type/class)
(import x/type/list)
(import x/num/float float-of f-div)
(import x/num/tensor)
(import x/tool/word-form word-form-pure)
(import x/core/doors int* int+ int- int->ptr int< int= mem-cmp mem-copy mem-set obj-ref ptr->int ptr-set-word!
  str->ptr str->sym str-make type-of type?)

; --- the kernels ---------------------------------------------------------------
; Scratch words: 0 the run's address, 1 the gain's, 2 the output's, 6 the
; run's length, 7 the element reached, 8 the budget, 9 the phase, 10 the
; bias's address.  Doubles: 16 and 17 a kernel's two accumulators, 18
; epsilon, 19 a kernel's working value, 20 a half, 21 sqrt(2/pi), 22
; 0.044715 and 23 1/sqrt 2.
(def %nn-w (fn (_ k) (list (lit %mem-ref) (lit s) k)))
(def %nn-w! (fn (_ k v) (list (lit %mem-set!) (lit s) k v)))
(def %nn-d (fn (_ k) (list (lit f-ref) (lit s) k)))
(def %nn-d! (fn (_ k v) (list (lit f-set!) (lit s) k v)))
(def %nn-ref
  (fn (_ enc a) (list (if (eq? enc (lit f32)) (lit f32-ref) (lit f-ref)) (%nn-w a) (%nn-w 7))))
(def %nn-set
  (fn (_ enc a v) (list (if (eq? enc (lit f32)) (lit f32-set!) (lit f-set!)) (%nn-w a) (%nn-w 7) v)))

; A kernel of the lane's convention from STEPS, one form a phase, and
; BETWEEN, the form run when each phase but the last ends.  It answers 1
; when the last phase is done and 0 when the budget is spent.
(def %nn-kernel
  (fn (_ steps between)
    (let ((pick
            (fn (go k forms)
              (if (null? (rest forms)) (first forms)
                (list (lit if) (list (lit =) (%nn-w 9) k) (first forms) (go (int+ k 1) (rest forms)))))))
      (list (lit fn) (lit (self s))
        (list (lit match)
          (list (list (lit =) (%nn-w 8) 0) 0)
          (list (list (lit <) (%nn-w 7) (%nn-w 6))
            (list (lit do) (pick 0 steps)
              (%nn-w! 7 (list (lit +) (%nn-w 7) 1))
              (%nn-w! 8 (list (lit -) (%nn-w 8) 1))
              (lit (self s))))
          (list (list (lit <) (%nn-w 9) (int- (List length steps) 1))
            (list (lit do) (if (null? between) 0 (pick 0 between))
              (%nn-w! 9 (list (lit +) (%nn-w 9) 1))
              (%nn-w! 7 0)
              (lit (self s))))
          (lit (#t 1)))))))

; softmax: the greatest element into 16; each element's exponential less
; that stored and summed into 17; each stored value over the sum.
(def %nn-softmax-form
  (fn (_ enc)
    (let ((x (%nn-ref enc 0)))
      (%nn-kernel
        (list
          (list (lit if) (list (lit =) (%nn-w 7) 0) (%nn-d! 16 x)
            (list (lit if) (list (lit f<) (%nn-d 16) x) (%nn-d! 16 x) 0))
          (list (lit do)
            (%nn-d! 19 (list (lit f-exp) (list (lit f-) x (%nn-d 16))))
            (%nn-set enc 2 (%nn-d 19))
            (%nn-d! 17 (list (lit f+) (%nn-d 17) (%nn-d 19))))
          (%nn-set enc 2 (list (lit f/) (%nn-ref enc 2) (%nn-d 17))))
        (list (%nn-d! 17 (list (lit i->f) 0)) 0)))))

(def %nn-gelu-form
  (fn (_ enc)
    (let ((x (%nn-ref enc 0)))
      (%nn-kernel
        (list
          (%nn-set enc 2
            (list (lit f*) (list (lit f*) (%nn-d 20) x)
              (list (lit f+) (list (lit i->f) 1) (list (lit f-erf) (list (lit f*) x (%nn-d 23)))))))
        ()))))

(def %nn-gelu-tanh-form
  (fn (_ enc)
    (let ((x (%nn-ref enc 0)))
      (%nn-kernel
        (list
          (%nn-set enc 2
            (list (lit f*) (list (lit f*) (%nn-d 20) x)
              (list (lit f+) (list (lit i->f) 1)
                (list (lit f-tanh)
                  (list (lit f*) (%nn-d 21)
                    (list (lit f+) x (list (lit f*) (%nn-d 22) (list (lit f*) x (list (lit f*) x x))))))))))
        ()))))

; layer-norm: the sum into 16, then the mean; the squared differences
; into 17, then the root of their mean and epsilon; each element's
; difference over that, times its gain, plus its bias.
(def %nn-layer-norm-form
  (fn (_ enc)
    (let ((x (%nn-ref enc 0)) (count (list (lit i->f) (%nn-w 6))))
      (%nn-kernel
        (list
          (%nn-d! 16 (list (lit f+) (%nn-d 16) x))
          (list (lit do)
            (%nn-d! 19 (list (lit f-) x (%nn-d 16)))
            (%nn-d! 17 (list (lit f+) (%nn-d 17) (list (lit f*) (%nn-d 19) (%nn-d 19)))))
          (%nn-set enc 2
            (list (lit f+)
              (list (lit f*) (list (lit f/) (list (lit f-) x (%nn-d 16)) (%nn-d 17)) (%nn-ref enc 1))
              (%nn-ref enc 10))))
        (list
          (list (lit do) (%nn-d! 16 (list (lit f/) (%nn-d 16) count)) (%nn-d! 17 (list (lit i->f) 0)))
          (%nn-d! 17 (list (lit f-sqrt) (list (lit f+) (list (lit f/) (%nn-d 17) count) (%nn-d 18)))))))))

; Each kernel: (NAME FORM ENC).
(def %nn-kernels
  (List flat-map
    (fn (_ enc)
      (let ((name (fn (_ which) (str->sym (Str8 append (symbol->str enc) "-" which)))))
        (list (list (name "softmax") (%nn-softmax-form enc) enc)
              (list (name "gelu") (%nn-gelu-form enc) enc)
              (list (name "gelu-tanh") (%nn-gelu-tanh-form enc) enc)
              (list (name "layer-norm") (%nn-layer-norm-form enc) enc))))
    (list (lit f64) (lit f32))))

; The default epsilon and zero, each a Float made once.
(def %nn-kept (fn (_ cell make) (if (null? (first cell)) (%set-first! cell (make)) ()) (first cell)))
(def %nn-epsilon-cell (pair () ()))
(def %nn-epsilon (fn (_) (%nn-kept %nn-epsilon-cell (fn (_) (f-div (float-of 1) (float-of 100000))))))
(def %nn-zero-cell (pair () ()))
(def %nn-zero (fn (_) (%nn-kept %nn-zero-cell (fn (_) (float-of 0)))))

; A double stored at double I of address A: made the first time it is
; wanted and kept, since making it walks the form.
(def %nn-fset-cell (pair () ()))
(def %nn-fset
  (fn (_ a i v)
    (if (null? (first %nn-fset-cell))
      (%set-first! %nn-fset-cell (word-form-pure (lit (fn (_ a i v) (f-set! a i v)))))
      ())
    ((first %nn-fset-cell) a i v)))

; The constants every kernel finds in its doubles, in a scratch made once
; and copied for each use.
(def %nn-constants-cell (pair () ()))
(def %nn-constants
  (fn (_)
    (if (null? (first %nn-constants-cell))
      (let ((s (str-make 256)))
        (let ((put (fn (_ k x) (%nn-fset (ptr->int (str->ptr s)) k (first x)))))
          (mem-set (str->ptr s) 0 256)
          (put 20 (f-div (float-of 1) (float-of 2)))
          (put 21 (float-of "0.7978845608028654"))
          (put 22 (float-of "0.044715"))
          (put 23 (float-of "0.7071067811865476"))
          (%set-first! %nn-constants-cell s)))
      ())
    (first %nn-constants-cell)))

; A scratch with those constants, the doubles 16, 17 and 19 zero, and
; EPSILON, a Float, in 18.
(def %nn-scratch
  (fn (_ epsilon)
    (let ((s (str-make 256)))
      (mem-copy (str->ptr s) (str->ptr (%nn-constants)) 256)
      (%nn-fset (ptr->int (str->ptr s)) 18 (first epsilon))
      s)))

(def %nn-word! (fn (_ s k v) (ptr-set-word! (str->ptr s) (int* k %word-size) v)))

; The check problem: eight quarters in place, with a gain and a bias, and
; an epsilon of a quarter.  Answers the output's bytes.
(def %nn-check-run
  (fn (_ kern enc)
    (let ((o (Tensor %check-input enc (list 3 -2 7 0 -5 9 1 4)))
          (g (Tensor %check-input enc (list 2 8 -1 5 3 -4 6 2)))
          (b (Tensor %check-input enc (list 1 0 -3 2 6 -1 4 5)))
          (s (%nn-scratch (f-div (float-of 1) (float-of 4)))))
      (%nn-word! s 0 (rest o)) (%nn-word! s 1 (rest g)) (%nn-word! s 2 (rest o)) (%nn-word! s 10 (rest b))
      (%nn-word! s 6 8) (%nn-word! s 7 0) (%nn-word! s 8 1073741823) (%nn-word! s 9 0)
      (kern (ptr->int (str->ptr s)))
      (list (List ref 4 (first o)) g b))))

(def %nn-agrees?
  (fn (_ form enc compiled)
    (let ((r1 (%nn-check-run (word-form-pure form) enc)) (r2 (%nn-check-run compiled enc)))
      (int= (mem-cmp (str->ptr (first r1)) (str->ptr (first r2)) (if (eq? enc (lit f32)) 32 64)) 0))))

(List for-each
  (fn (_ k)
    (Tensor %register! (first k) (List ref 1 k)
      (fn (_ compiled) (%nn-agrees? (List ref 1 k) (List ref 2 k) compiled))))
  %nn-kernels)

(def %nn-size (fn (go ext) (if (null? ext) 1 (int* (first ext) (go (rest ext))))))
(def %nn-last (fn (go ext) (if (null? (rest ext)) (first ext) (go (rest ext)))))

; The encoding a kernel's result takes: f32 for f32, else f64.
(def %nn-enc (fn (_ st) (if (eq? (first st) (lit f32)) (lit f32) (lit f64))))

; A fresh contiguous copy of a tensor's state in the result's encoding.
(def %nn-copy (fn (_ t) ((obj-ref (Tensor %fast) 10) (t %st) (%nn-enc (t %st)))))

; Drive kernel WHICH in place over OUT, a fresh contiguous state, a run of
; LENGTH elements at a time.  WORDS, ((K . V) ...), are written for every
; run, with the two accumulators cleared.
(def %nn-run!
  (fn (_ which out length epsilon words)
    (let ((f (Tensor %fast)) (enc (first out)) (count (%nn-size (List ref 1 out))))
      (if (if (int= count 0) #t (int= length 0)) out
        (let ((s (%nn-scratch epsilon)) (base ((obj-ref f 13) out)) (width (if (eq? enc (lit f32)) 4 8))
              (name (str->sym (Str8 append (symbol->str enc) "-" which)))
              (zero (first (%nn-zero))))
          (List for-each (fn (_ w) (%nn-word! s (first w) (rest w))) words)
          ((fn (go at)
             (if (int< at count)
               (let ((a (int+ base (int* width at))))
                 (%nn-word! s 0 a) (%nn-word! s 2 a) (%nn-word! s 6 length) (%nn-word! s 7 0) (%nn-word! s 9 0)
                 (%nn-fset (ptr->int (str->ptr s)) 16 zero)
                 (%nn-fset (ptr->int (str->ptr s)) 17 zero)
                 ((obj-ref f 14) name s)
                 (go (int+ at length)))
               ()))
            0)
          out)))))

(def %nn-tensor!
  (fn (_ who t)
    (if (if (object? t) (instance-of? t Tensor) #f)
      (if (eq? (first (t %st)) (lit c128)) (Err raise (lit value) (Str8 append "Neural " who ": a c128 tensor has no order") ()) ())
      (Err raise (lit type) (Str8 append "Neural " who ": not a tensor") t))))

(def-class Neural ()
  (doc "The operations a transformer is made of, on tensors: softmax, gelu and layer-norm along the last axis, the rows of an embedding table, and the causal mask."
    (note "Each answers a fresh tensor. softmax, gelu and layer-norm answer f32 for an f32 operand and f64 for any other; embed and causal-mask keep the operand's encoding.")
    (note "softmax, gelu and layer-norm run as kernels on Tensor's lanes, compiled where a JIT backend is.")
    (example "((Neural softmax (Tensor from '(0 0))) ->list)" "(0.5 0.5)")
    (see softmax) (see gelu) (see layer-norm) (see embed) (see causal-mask) (see jit!))
  (static
    (method jit! (self)
      (doc "Build the compiled version of every Neural kernel now (JIT; ARM64 and x86-64), adopting each one that writes what its pure version does on the check problem. Answers the names of the Neural kernels running compiled; the results are the same either way."
        (returns LIST "Kernel names, () where none can be built")
        (sample "(Neural jit!)" "every Neural kernel's name where a JIT backend is, () elsewhere"))
      (List for-each (fn (_ k) (Tensor %jit (first k))) %nn-kernels)
      (let ((mine (List map first %nn-kernels)))
        (List filter (fn (_ name) (List includes? name mine)) (Tensor compiled))))

    (method softmax (self (param t Tensor "A real tensor of rank 1 or more"))
      (doc "Each run of the last axis as shares that sum to 1: every element's exponential over the sum of the run's. The run's greatest element is taken from each first, so a large element does not overflow."
        (returns Tensor "A fresh tensor of t's extent")
        (example "((Neural softmax (Tensor from '((0 0) (0 0)))) ->list)" "((0.5 0.5) (0.5 0.5))"))
      (%nn-tensor! "softmax" t)
      (let ((out (%nn-copy t)))
        (if (null? (List ref 1 out)) (Err raise (lit value) "Neural softmax: a tensor of rank 0 has no axis" ()) ())
        (t %wrap (%nn-run! "softmax" out (%nn-last (List ref 1 out)) (%nn-epsilon) ()))))

    (method gelu (self (param t Tensor "A real tensor")
                       . (param form SYMBOL "Optional: tanh, for the tanh approximation"))
      (doc "Each element x as x times the standard normal's cumulative at x, x/2 (1 + erf(x / sqrt 2)); with tanh, x/2 (1 + tanh(sqrt(2/pi) (x + 0.044715 x^3))), the approximation some published models were trained with."
        (known-as "Gaussian error linear unit")
        (returns Tensor "A fresh tensor of t's extent")
        (example "((Neural gelu (Tensor from '(0 0))) ->list)" "(0.0 0.0)"))
      (%nn-tensor! "gelu" t)
      (let ((which (match ((null? form) "gelu") ((eq? (first form) (lit tanh)) "gelu-tanh")
                          (#t (Err raise (lit value) "Neural gelu: no such form" (first form)))))
            (out (%nn-copy t)))
        (t %wrap (%nn-run! which out (%nn-size (List ref 1 out)) (%nn-epsilon) ()))))

    (method layer-norm (self (param t Tensor "A real tensor of rank 1 or more")
                             (param gain Tensor "A rank-1 tensor as long as t's last axis")
                             (param bias Tensor "A rank-1 tensor as long as t's last axis")
                             . (param epsilon FLOAT "Optional, added to the variance: 1/100000 by default"))
      (doc "Each run of the last axis less its mean and over its deviation, then times gain and plus bias, element by element. The variance divides by the count, and epsilon is added to it under the root."
        (returns Tensor "A fresh tensor of t's extent")
        (example "((Neural layer-norm (Tensor from '(1 1 1)) (Tensor from '(2 2 2)) (Tensor from '(5 6 7))) ->list)" "(5.0 6.0 7.0)"))
      (%nn-tensor! "layer-norm" t) (%nn-tensor! "layer-norm" gain) (%nn-tensor! "layer-norm" bias)
      (let ((out (%nn-copy t)) (f (Tensor %fast)))
        (if (null? (List ref 1 out)) (Err raise (lit value) "Neural layer-norm: a tensor of rank 0 has no axis" ()) ())
        (let ((length (%nn-last (List ref 1 out)))
              (g ((obj-ref f 10) (gain %st) (first out))) (b ((obj-ref f 10) (bias %st) (first out))))
          (if (if (equal? (List ref 1 g) (list length)) (equal? (List ref 1 b) (list length)) #f) ()
            (Err raise (lit value) "Neural layer-norm: gain and bias are rank 1 and as long as the last axis"
              (list (List ref 1 out) (List ref 1 g) (List ref 1 b))))
          (%nn-run! "layer-norm" out length (if (null? epsilon) (%nn-epsilon) (float-of (first epsilon)))
            (list (pair 1 ((obj-ref f 13) g)) (pair 10 ((obj-ref f 13) b))))
          ; g and b are held to here, so their addresses stayed good
          (do g b (t %wrap out)))))

    (method embed (self (param table Tensor "A rank-2 tensor, a row for each index")
                        (param indexes LIST "Row indexes; a negative one counts from the end"))
      (doc "The table's rows the indexes pick, in the indexes' order, a row of the result for each."
        (returns Tensor "A fresh tensor of as many rows as indexes, in table's encoding")
        (example "((Neural embed (Tensor from '((1 2) (3 4) (5 6)) 'f64) '(2 0 2)) ->list)" "((5.0 6.0) (1.0 2.0) (5.0 6.0))"))
      (if (if (object? table) (instance-of? table Tensor) #f) ()
        (Err raise (lit type) "Neural embed: not a tensor" table))
      (let ((f (Tensor %fast)) (st (table %st)))
        (if (int= (List length (List ref 1 st)) 2) ()
          (Err raise (lit value) "Neural embed: the table has two axes" (List ref 1 st)))
        (let ((src (if ((obj-ref f 3) st) st ((obj-ref f 10) st (first st))))
              (rows (first (List ref 1 st))) (cols (first (rest (List ref 1 st)))))
          (let ((out ((obj-ref f 4) (first st) (list (List length indexes) cols)))
                (bytes (int* cols (match ((eq? (first st) (lit c128)) 16) ((eq? (first st) (lit f32)) 4) (#t 8)))))
            (let ((from ((obj-ref f 13) src)) (to ((obj-ref f 13) out)))
              ((fn (go l k)
                 (if (null? l) ()
                   (let ((i (first l)))
                     (if (type? i (type-of 0)) () (Err raise (lit type) "Neural embed: an index is an integer" i))
                     (let ((r (if (int< i 0) (int+ rows i) i)))
                       (if (if (int< r 0) #t (not (int< r rows)))
                         (Err raise (lit value) "Neural embed: no such row" i) ())
                       (if (int< 0 bytes)
                         (mem-copy (int->ptr (int+ to (int* k bytes))) (int->ptr (int+ from (int* r bytes))) bytes)
                         ())
                       (go (rest l) (int+ k 1))))))
                indexes 0)
              ; src is held to here, so its address stayed good
              (do src (Tensor %make out)))))))

    (method causal-mask (self (param t Tensor "A real tensor of rank 2 or more"))
      (doc "t with every element above the diagonal of its last two axes negative infinity, so that a softmax along the last axis gives a row's later columns no share."
        (returns Tensor "A fresh tensor of t's extent and encoding")
        (example "((Neural softmax (Neural causal-mask (Tensor from '((0 0) (0 0)) 'f64))) ->list)" "((1.0 0.0) (0.5 0.5))"))
      (%nn-tensor! "causal-mask" t)
      (let ((f (Tensor %fast)) (st (t %st)))
        (if (if (int< (List length (List ref 1 st)) 2) #t (eq? (first st) (lit i64)))
          (Err raise (lit value) "Neural causal-mask: a tensor of f64 or f32 with two axes or more" (List ref 1 st)) ())
        (let ((out ((obj-ref f 10) st (first st))))
          (let ((ext (List ref 1 out)))
            (let ((cols (%nn-last ext)) (rows (List ref (int- (List length ext) 2) ext))
                  (low (f-div (float-of -1) (float-of 0))))
              (let ((block (int* rows cols)) (count (%nn-size ext)))
                ((fn (go at)
                   (if (int< at count)
                     (do ((fn (row i)
                            (if (if (int< i rows) (int< (int+ i 1) cols) #f)
                              (do ((obj-ref f 9)
                                    ((obj-ref f 11) out (list (int- cols (int+ i 1))) (list 1)
                                      (int+ at (int+ (int* i cols) (int+ i 1))))
                                    low)
                                  (row (int+ i 1)))
                              ()))
                          0)
                         (go (int+ at block)))
                     ()))
                  0)
                (t %wrap out)))))))))

(doc (provide x/num/neural Neural)
  (example "((Neural softmax (Tensor from '(0 0))) ->list)" "(0.5 0.5)")
  "Neural: the operations a transformer is made of, on tensors: softmax, gelu and layer-norm along the last axis, an embedding table's rows, and the causal mask.")
