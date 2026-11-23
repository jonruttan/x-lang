; transformer.x -- Transformer: a language model's forward pass, in GPT-2's layout.
;
; A transformer reads a list of ids, each an item of its vocabulary, and
; answers for every position a score for each item that might come next:
; the logits.  The item scored highest after the last id is the model's
; prediction, and generating is predicting again and again, each id joining
; the list the next is predicted from.
;
;   (Transformer from-file path heads)  -> a model, from a safetensors file
;   (m logits ids)                      -> a Matrix: a row for each id, a column for each item
;   (m predict ids)                     -> the id scored highest after the ids
;   (m generate ids n)                  -> the ids and n more, each the prediction
;                                          from those before it
;   (m release)                         -> the GPU buffers holding the weights given back
;
; The layout is the one GPT-2 is published in.  An id's row of the table
; wte and its position's row of wpe are added.  Each block h.N then adds
; two things to that: its attention, and its perceptron.  Last, the layer
; norm ln_f is taken, and a position's logits are its product with every
; row of wte.
;
;   attention    the layer norm ln_1; c_attn, a weight and a bias, makes a
;                query, a key and a value for each head, side by side; a
;                head's scores are its queries times its keys, over the
;                root of the head's width, masked so that no position sees
;                a later one, and softmaxed along each row; the scores
;                times the head's values are its answer, and the heads'
;                answers side by side go through c_proj
;   perceptron   the layer norm ln_2; c_fc; gelu in its tanh form; c_proj
;
; A weight here has a row for each input and a column for each output, so
; a layer is the input times the weight, plus the bias.
;
; Everything between c_attn and c_proj is one kernel, f32-attention, a
; word form registered with Tensor and run on its lanes.  A tensor
; operation costs its dispatch whatever its size, and a block's attention
; as products, slices and softmaxes is about ten of them for each head:
; in one kernel a block's attention is one.  For a position and a head it
; takes the scores of the positions up to it, keeping the greatest; then
; each score's exponential less that, and their sum; then each column of
; the answer, the values weighed by those and over the sum.
;
; A file does not say how many heads its attention has, so from-file is
; told.  Everything else is read from the tensors' extents.  Tensors are
; kept in f32, whatever the file holds them in.
;
; The products run on the GPU where there is one (x/num/gpu) and through
; Matrix's kernels otherwise.  On the GPU the weights are held there from
; the start, so a product reads them where they lie; only release gives
; their buffers back, and a model is not to be kept in a state image.  The GPU sums in single precision and Matrix
; in double, so logits differ in their last places from one host to
; another, as they do from one framework to another.  Matrix's product
; makes an f64 copy of each operand, wte among them: on a host with no GPU
; a large model costs that copy at every call.
;
; Each block keeps a cache: a row of queries, keys and values for each
; position worked out.  A pass writes its positions' rows there and
; attends to every row up to each, so generate works out the prompt once
; and then one position for each new id.  The pure-x steps between the
; kernels leave garbage, and nothing collects it during a call, so the
; heap is collected every %tf-collect-every blocks.
;
; A tensor operation's cost is mostly its making: a result, a scratch, a
; product's buffers and dimensions.  Where the weights are held, generate
; makes those once for its one-position predictions (%tf-work): a held
; row for the hidden row, a plan for each product (Gpu %plan) whose
; result is the next step's operand, and a scratch for each kernel.  A
; prediction then runs the plans and drives the kernels, and makes no
; tensor.  The kernels and the products are the same ones, so the ids
; are the same.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/transformer)
(import x/type/class)
(import x/type/list)
(import x/codec/safetensors)
(import x/num/float float-of fsqrt f-div f-lt)
(import x/num/random)
(import x/num/tensor)
(import x/num/matrix)
(import x/num/neural)
(import x/num/gpu)
(import x/sys/gc)
(import x/tool/word-form word-form-pure)
(import x/core/doors int* int+ int- int/ int% int->ptr int< int= mem-cmp mem-copy mem-set obj-ref ptr->int ptr-ref-word ptr-set-word!
  str->ptr str-make type-of type?)

; --- the place of the greatest element ------------------------------------------
; A kernel of Tensor's lane convention over one contiguous run of singles:
; the run's address in word 0, its length in word 6, the element reached
; in word 7 and the budget in word 8.  The greatest element so far is the
; double 16 and its place word 13; of equal elements the first is kept.
(def %tf-greatest-at-form
  (let ((x (lit (f32-ref (%mem-ref s 0) (%mem-ref s 7)))))
    (list (lit fn) (lit (self s))
      (list (lit match)
        (lit ((= (%mem-ref s 8) 0) 0))
        (list (lit (< (%mem-ref s 7) (%mem-ref s 6)))
          (list (lit do)
            (list (lit if) (lit (= (%mem-ref s 7) 0))
              (list (lit do) (list (lit f-set!) (lit s) 16 x) (lit (%mem-set! s 13 0)))
              (list (lit if) (list (lit f<) (lit (f-ref s 16)) x)
                (list (lit do) (list (lit f-set!) (lit s) 16 x) (lit (%mem-set! s 13 (%mem-ref s 7))))
                0))
            (lit (%mem-set! s 7 (+ (%mem-ref s 7) 1)))
            (lit (%mem-set! s 8 (- (%mem-ref s 8) 1)))
            (lit (self s))))
        (lit (#t 1))))))

(def %tf-word! (fn (_ s k v) (ptr-set-word! (str->ptr s) (int* k %word-size) v)))
(def %tf-word (fn (_ s k) (ptr-ref-word (str->ptr s) (int* k %word-size))))

; The scratch after a kernel function has run over eight check singles.
(def %tf-check-run
  (fn (_ kern)
    (let ((in (Tensor %check-input (lit f32) (list 3 -2 7 0 -5 9 1 9))) (s (str-make 256)))
      (%tf-word! s 0 (rest in)) (%tf-word! s 6 8) (%tf-word! s 7 0) (%tf-word! s 8 1073741823) (%tf-word! s 13 0)
      (kern (ptr->int (str->ptr s)))
      ; in is held to here, so its address stayed good
      (do in s))))

; Whether the compiled kernel finds the place and the element the pure one does.
(def %tf-agrees?
  (fn (_ compiled)
    (let ((a (%tf-check-run (word-form-pure %tf-greatest-at-form))) (b (%tf-check-run compiled)))
      ; word 13, and the double 16, 128 bytes in
      (if (int= (%tf-word a 13) (%tf-word b 13))
        (int= (mem-cmp (int->ptr (int+ (ptr->int (str->ptr a)) 128))
                       (int->ptr (int+ (ptr->int (str->ptr b)) 128)) 8) 0)
        #f))))

(Tensor %register! (lit f32-greatest-at) %tf-greatest-at-form %tf-agrees?)

; The place of the greatest of COUNT singles at ADDR.
(def %tf-greatest-at
  (fn (_ addr count)
    (let ((s (str-make 256)))
      (%tf-word! s 0 addr) (%tf-word! s 6 count) (%tf-word! s 7 0) (%tf-word! s 13 0)
      ((obj-ref (Tensor %fast) 14) (lit f32-greatest-at) s)
      (%tf-word s 13))))

; --- a place drawn at random ----------------------------------------------------
; A kernel of the lane convention over one contiguous run of singles, the
; scores: each score's share is the exponential of its difference from the
; greatest, over the temperature, and a place is drawn with a chance in
; proportion to its share.  Scratch words: 0 the run's address, 6 its
; length, 7 the element reached, 8 the budget, 9 the phase, 10 the passes
; made, 11 the passes left, 12 whether the draw is limited to the
; greatest, 13 the place, 14 whether this pass has a candidate.  Doubles:
; 16 the greatest score, 17 a sum, 18 the floor, 19 a number from 0 to 1
; and then the sum it reaches, 20 the temperature, 21 a pass's candidate.
;
; Phase 0 is a pass for each of the greatest asked for, 1 where there is
; no limit: the first finds the greatest score, and each one after it the
; greatest below the last, which is then the floor.  Equal scores are one
; pass, so scores equal to the floor are all kept.  Phase 1 sums the
; shares of the scores not below the floor.  Phase 2 sums them again and
; stops at the first place where the sum passes word 19's part of the
; whole; the last place kept is the answer if rounding leaves none.
(def %tf-variate-form
  (let ((w (fn (_ k) (list (lit %mem-ref) (lit s) k)))
        (w! (fn (_ k v) (list (lit %mem-set!) (lit s) k v)))
        (d (fn (_ k) (list (lit f-ref) (lit s) k)))
        (d! (fn (_ k v) (list (lit f-set!) (lit s) k v))))
    (let ((x (list (lit f32-ref) (w 0) (w 7))) (zero (lit (i->f 0))))
      (let ((share (list (lit f-exp) (list (lit f/) (list (lit f-) x (d 16)) (d 20))))
            (take (list (lit do) (d! 21 x) (w! 14 1)))
            (kept (fn (_ then) (list (lit if) (list (lit =) (w 12) 0) then (list (lit if) (list (lit f<) x (d 18)) 0 then)))))
        (let ((consider (list (lit if) (list (lit =) (w 14) 0) take (list (lit if) (list (lit f<) (d 21) x) take 0))))
          (list (lit fn) (lit (self s))
            (list (lit match)
              (list (list (lit =) (w 8) 0) 0)
              (list (list (lit <) (w 7) (w 6))
                (list (lit do)
                  (list (lit if) (list (lit =) (w 9) 0)
                    (list (lit if) (list (lit =) (w 10) 0) consider (list (lit if) (list (lit f<) x (d 18)) consider 0))
                    (list (lit if) (list (lit =) (w 9) 1)
                      (kept (d! 17 (list (lit f+) (d 17) share)))
                      (kept (list (lit do)
                              (d! 17 (list (lit f+) (d 17) share))
                              (w! 13 (w 7))
                              (list (lit if) (list (lit f<) (d 19) (d 17)) (w! 7 (list (lit -) (w 6) 1)) 0)))))
                  (w! 7 (list (lit +) (w 7) 1))
                  (w! 8 (list (lit -) (w 8) 1))
                  (lit (self s))))
              (list (list (lit =) (w 9) 0)
                (list (lit do)
                  (list (lit if) (list (lit =) (w 14) 0) (w! 11 1)
                    (list (lit do) (list (lit if) (list (lit =) (w 10) 0) (d! 16 (d 21)) 0) (d! 18 (d 21))))
                  (w! 14 0) (w! 10 (list (lit +) (w 10) 1)) (w! 11 (list (lit -) (w 11) 1)) (w! 7 0)
                  (list (lit if) (list (lit <) (w 11) 1) (list (lit do) (w! 9 1) (d! 17 zero)) 0)
                  (lit (self s))))
              (list (list (lit =) (w 9) 1)
                (list (lit do) (d! 19 (list (lit f*) (d 19) (d 17))) (d! 17 zero) (w! 9 2) (w! 7 0) (lit (self s))))
              (lit (#t 1)))))))))

; A double stored at double I of address A: made the first time it is
; wanted and kept, since making it walks the form.
(def %tf-fset-cell (pair () ()))
(def %tf-fset
  (fn (_ a i v)
    (if (null? (first %tf-fset-cell))
      (%set-first! %tf-fset-cell (word-form-pure (lit (fn (_ a i v) (f-set! a i v)))))
      ())
    ((first %tf-fset-cell) a i v)))

; A scratch for the kernel: COUNT singles at ADDR, U a Float from 0 to 1,
; TEMPERATURE a Float, GREATEST how many of the greatest are kept, or nil.
(def %tf-variate-scratch
  (fn (_ addr count u temperature greatest)
    (let ((s (str-make 256)))
      (mem-set (str->ptr s) 0 256)
      (%tf-word! s 0 addr) (%tf-word! s 6 count)
      (%tf-word! s 11 (if (null? greatest) 1 greatest)) (%tf-word! s 12 (if (null? greatest) 0 1))
      (%tf-fset (ptr->int (str->ptr s)) 19 (first u))
      (%tf-fset (ptr->int (str->ptr s)) 20 (first temperature))
      s)))

; The scratch after a kernel function has drawn among the three greatest
; of eight check singles, at a temperature of 2 and three fifths of the way.
(def %tf-variate-check-run
  (fn (_ kern)
    (let ((in (Tensor %check-input (lit f32) (list 3 -2 7 0 -5 9 1 9))))
      (let ((s (%tf-variate-scratch (rest in) 8 (f-div (float-of 3) (float-of 5)) (float-of 2) 3)))
        (%tf-word! s 8 1073741823)
        (kern (ptr->int (str->ptr s)))
        ; in is held to here, so its address stayed good
        (do in s)))))

; Whether the compiled kernel draws the place the pure one does, with the same sum.
(def %tf-variate-agrees?
  (fn (_ compiled)
    (let ((a (%tf-variate-check-run (word-form-pure %tf-variate-form))) (b (%tf-variate-check-run compiled)))
      ; word 13, and the double 17, 136 bytes in
      (if (int= (%tf-word a 13) (%tf-word b 13))
        (int= (mem-cmp (int->ptr (int+ (ptr->int (str->ptr a)) 136))
                       (int->ptr (int+ (ptr->int (str->ptr b)) 136)) 8) 0)
        #f))))

(Tensor %register! (lit f32-variate-at) %tf-variate-form %tf-variate-agrees?)

; A place drawn from COUNT singles at ADDR.
(def %tf-variate-at
  (fn (_ addr count u temperature greatest)
    (let ((s (%tf-variate-scratch addr count u temperature greatest)))
      ((obj-ref (Tensor %fast) 14) (lit f32-variate-at) s)
      (%tf-word s 13))))

; The function that picks an id from scores, (fn (_ ADDR COUNT)): the
; greatest with no RANDOM and no OPTIONS, else a draw from RANDOM with
; OPTIONS, an optional temperature and greatest.
(def %tf-picking
  (fn (_ random options)
    (if (if (null? random) (null? options) #f) %tf-greatest-at (%tf-drawing random options))))

(def %tf-drawing
  (fn (_ random options)
    (let ((temperature (if (null? options) 1 (first options)))
          (greatest (if (if (null? options) #t (null? (rest options))) () (first (rest options)))))
      (if (if (object? random) (instance-of? random Random) #f) ()
        (Err raise (lit type) "Transformer: not a Random" random))
      (if (if (null? greatest) #t (if (type? greatest (type-of 0)) (int< 0 greatest) #f)) ()
        (Err raise (lit value) "Transformer: greatest is an integer above 0" greatest))
      (let ((t (guard (_ ()) (float-of temperature))))
        (if (if (null? t) #f (f-lt (float-of 0) t)) ()
          (Err raise (lit value) "Transformer: the temperature is a number above 0" temperature))
        (fn (_ addr count) (%tf-variate-at addr count (random float) t greatest))))))

; --- the pieces ---------------------------------------------------------------------
; a times b: on the GPU where there is one, else by Matrix's kernels, cast
; back to f32.  a has two axes; b has two, or one and is a column.
(def %tf-product
  (fn (_ a b)
    (if (Gpu available?) (Gpu product a b)
      (((Matrix %make (a %st)) product b) as (lit f32)))))

; A held product's buffer given back: a product of a held weight is held,
; and nothing else gives its buffer back.
(def %tf-done (fn (_ p) (if (Gpu held? p) (Gpu release p) ())))

; A layer: x times the weight, plus the bias along each row.  The sum is a
; fresh tensor, so the product is done with once it is made.
(def %tf-layer
  (fn (_ x layer)
    (let ((p (%tf-product x (first layer))))
      (let ((r (p add (rest layer))))
        (%tf-done p)
        r))))

; A tensor as f32.
(def %tf-f32 (fn (_ t) (if (eq? (t encoding) (lit f32)) t (t as (lit f32)))))

; --- attention ----------------------------------------------------------------------
; A kernel of Tensor's lane convention.  Scratch words: 0 the address of
; the queries, keys and values, a row for each position, the three side
; by side and each a head after another; 1 the address of a row of
; doubles, a score for each position; 2 the address of the answer, a row
; for each position worked out; 3 the positions; 4 the width; 5 a head's
; width; 8 the budget; 9 the phase; 10 the position; 11 the head; 12 the
; position attended to; 13 the column within the head; 14 the heads; 15
; the first position worked out, whose answer is the answer's row 0: the
; positions before it are attended to and not worked out.  Doubles: 16
; the sum being made, 17 the greatest score, 18 the exponentials' sum, 19
; the root of a head's width.
;
; Phase 0 makes a score for each position up to this one, a column of
; the head at a step, and keeps the greatest.  Phase 1 turns each score
; into its exponential less the greatest, and sums them.  Phase 2 makes
; each column of the answer, a position attended to at a step.  A step is
; one visit, and takes one from the budget.
(def %tf-attention-form
  (let ((w (fn (_ k) (list (lit %mem-ref) (lit s) k)))
        (w! (fn (_ k v) (list (lit %mem-set!) (lit s) k v)))
        (d (fn (_ k) (list (lit f-ref) (lit s) k)))
        (d! (fn (_ k v) (list (lit f-set!) (lit s) k v))))
    (let ((add (fn (_ a b) (list (lit +) a b))) (mul (fn (_ a b) (list (lit *) a b))))
      ; element (ROW, PART, the head's column) of the queries, keys and values
      (let ((qkv (fn (_ row part)
                   (list (lit f32-ref) (w 0)
                     (add (add (mul row (mul 3 (w 4))) (mul part (w 4))) (add (mul (w 11) (w 5)) (w 13))))))
            (score (fn (_) (list (lit f-ref) (w 1) (w 12))))
            (score! (fn (_ v) (list (lit f-set!) (w 1) (w 12) v)))
            (zero (lit (i->f 0)))
            (next (fn (_ k) (w! k (add (w k) 1))))
            (upto? (list (lit <) (w 12) (add (w 10) 1))))
        (list (lit fn) (lit (self s))
          (list (lit match)
            (list (list (lit =) (w 8) 0) 0)
            (list (list (lit =) (w 10) (w 3)) 1)
            (list (lit #t)
              (list (lit do)
                (list (lit if) (list (lit =) (w 9) 0)
                  (list (lit if) (list (lit <) (w 13) (w 5))
                    (list (lit do)
                      (d! 16 (list (lit f+) (d 16) (list (lit f*) (qkv (w 10) 0) (qkv (w 12) 1))))
                      (next 13))
                    (list (lit do)
                      (d! 16 (list (lit f/) (d 16) (d 19)))
                      (score! (d 16))
                      (list (lit if) (list (lit =) (w 12) 0) (d! 17 (d 16))
                        (list (lit if) (list (lit f<) (d 17) (d 16)) (d! 17 (d 16)) 0))
                      (d! 16 zero) (w! 13 0) (next 12)
                      (list (lit if) upto? 0
                        (list (lit do) (w! 9 1) (w! 12 0) (d! 18 zero)))))
                  (list (lit if) (list (lit =) (w 9) 1)
                    (list (lit if) upto?
                      (list (lit do)
                        (score! (list (lit f-exp) (list (lit f-) (score) (d 17))))
                        (d! 18 (list (lit f+) (d 18) (score)))
                        (next 12))
                      (list (lit do) (w! 9 2) (w! 12 0) (w! 13 0) (d! 16 zero)))
                    (list (lit if) (list (lit <) (w 13) (w 5))
                      (list (lit if) upto?
                        (list (lit do)
                          (d! 16 (list (lit f+) (d 16) (list (lit f*) (score) (qkv (w 12) 2))))
                          (next 12))
                        (list (lit do)
                          (list (lit f32-set!) (w 2)
                            (add (mul (list (lit -) (w 10) (w 15)) (w 4)) (add (mul (w 11) (w 5)) (w 13)))
                            (list (lit f/) (d 16) (d 18)))
                          (d! 16 zero) (w! 12 0) (next 13)))
                      (list (lit do)
                        (w! 9 0) (w! 12 0) (w! 13 0) (d! 16 zero) (next 11)
                        (list (lit if) (list (lit =) (w 11) (w 14))
                          (list (lit do) (w! 11 0) (next 10))
                          0)))))
                (w! 8 (list (lit -) (w 8) 1))
                (lit (self s))))))))))

; A scratch for the attention kernel: the queries, keys and values at
; address made, the answer at address out, for count positions, of which
; those from from on are worked out.  The row of scores is held in the
; scratch's pair, which the caller keeps.
(def %tf-attention-scratch
  (fn (_ made out count width heads from)
    (let ((s (str-make 256)) (scores (str-make (int* 8 (if (int< count 1) 1 count))))
          (fset (word-form-pure (lit (fn (_ a i v) (f-set! a i v))))))
      (mem-set (str->ptr s) 0 256)
      (%tf-word! s 0 made) (%tf-word! s 1 (ptr->int (str->ptr scores))) (%tf-word! s 2 out)
      (%tf-word! s 3 count) (%tf-word! s 4 width) (%tf-word! s 5 (int/ width heads)) (%tf-word! s 14 heads)
      (%tf-word! s 10 from) (%tf-word! s 15 from)
      (fset (ptr->int (str->ptr s)) 16 (first (float-of 0)))
      (fset (ptr->int (str->ptr s)) 19 (first (fsqrt (float-of (int/ width heads)))))
      (pair s scores))))

; The answer's bytes after a kernel function has run over the check
; problem: 3 positions, a width of 4 and 2 heads, the elements quarters.
(def %tf-attention-check-run
  (fn (_ kern)
    (let ((f (Tensor %fast)))
      (let ((made ((obj-ref f 4) (lit f32) (list 3 12))) (out ((obj-ref f 4) (lit f32) (list 3 4)))
            (put ((obj-ref f 6) (lit f32))))
        ((fn (go i)
           (if (int< i 36)
             (do (put ((obj-ref f 13) made) i (f-div (float-of (int- (int% (int+ 3 (int* 7 i)) 11) 5)) (float-of 4)))
                 (go (int+ i 1)))
             ()))
          0)
        (let ((sc (%tf-attention-scratch ((obj-ref f 13) made) ((obj-ref f 13) out) 3 4 2 0)))
          (%tf-word! (first sc) 8 1073741823)
          (kern (ptr->int (str->ptr (first sc))))
          ; made and the scratch are held to here, so their addresses stayed good
          (do made sc (List ref 4 out)))))))

(def %tf-attention-agrees?
  (fn (_ compiled)
    (int= (mem-cmp (str->ptr (%tf-attention-check-run (word-form-pure %tf-attention-form)))
                   (str->ptr (%tf-attention-check-run compiled)) 48)
          0)))

(Tensor %register! (lit f32-attention) %tf-attention-form %tf-attention-agrees?)

; One block's attention of x, whose rows are the positions from from on:
; attend, a (WEIGHT . BIAS), makes their queries, keys and values, which
; are written into the block's cache at those positions' rows; the kernel
; makes the heads' answers side by side for those positions, attending to
; every position the cache holds up to each; and project, another, takes
; them through c_proj.
(def %tf-attention
  (fn (_ x attend project heads cache from)
    (let ((f (Tensor %fast)) (made (%tf-f32 (%tf-layer x attend))))
      (let ((st (if ((obj-ref f 3) (made %st)) (made %st) ((obj-ref f 10) (made %st) (lit f32)))))
        (let ((count (first (List ref 1 st))) (across (first (rest (List ref 1 st)))))
          (let ((width (int/ across 3)) (row (int* 4 across)))
            (mem-copy (int->ptr (int+ ((obj-ref f 13) cache) (int* from row)))
                      (int->ptr ((obj-ref f 13) st)) (int* count row))
            (let ((out ((obj-ref f 4) (lit f32) (list count width))))
              (let ((sc (%tf-attention-scratch ((obj-ref f 13) cache) ((obj-ref f 13) out)
                          (int+ from count) width heads from)))
                ((obj-ref f 14) (lit f32-attention) (first sc))
                ; st, the cache and the scratch are held to here, so their addresses stayed good
                (do st cache sc (%tf-layer (Matrix %make out) project))))))))))

; A cache for each block: room for the queries, keys and values of rows
; positions, a row of them for each.
(def %tf-caches
  (fn (_ m rows)
    (let ((f (Tensor %fast)) (across (int* 3 (m %width))))
      (List map (fn (_ b) ((obj-ref f 4) (lit f32) (list rows across))) (m %blocks)))))

; The blocks between collections.  A block's operations leave about
; 700,000 objects behind on GPT-2, and Tensor's own window is 4,400,000.
(def %tf-collect-every 4)

; The model's last hidden rows, after ln_f, for ids at the positions from
; from on, one row for each; caches holds a cache for each block, with
; room for those positions, and the positions before them already in it.
(def %tf-hidden
  (fn (_ m ids from caches)
    (let ((count (List length ids)) (heads (m %heads)))
      (if (int= count 0) (Err raise (lit value) "Transformer: there are no ids" ()) ())
      (if (int< (m %context) (int+ from count))
        (Err raise (lit value) "Transformer: more ids than the model has positions" (list (int+ from count) (m %context))) ())
      ((fn (go blocks cs x n)
         (if (null? blocks)
           (Neural layer-norm x (first (m %norm)) (rest (m %norm)))
           (let ((b (first blocks)))
             (let ((x (x add (%tf-attention (Neural layer-norm x (first (List ref 0 b)) (rest (List ref 0 b)))
                                (List ref 1 b) (List ref 2 b) heads (first cs) from))))
               (let ((x (x add (%tf-layer
                                 (Neural gelu (%tf-layer (Neural layer-norm x (first (List ref 3 b)) (rest (List ref 3 b)))
                                                (List ref 4 b))
                                   (lit tanh))
                                 (List ref 5 b)))))
                 (if (int= (int% n %tf-collect-every) 0) (Heap collect) ())
                 (go (rest blocks) (rest cs) x (int+ n 1)))))))
        (m %blocks)
        caches
        ((Neural embed (m %items) ids) add (Neural embed (m %positions) (List range from (int+ from count))))
        1))))

; The id PICK takes from the scores after the last of the hidden rows h:
; PICK is (fn (_ ADDR COUNT)) over the scores as singles.
(def %tf-next
  (fn (_ m h pick)
    (let ((f (Tensor %fast)) (count (first (h extent))))
      (let ((scores (%tf-product (m %items) ((h slice 0 (int- count 1) count) reshape (list (m %width))))))
        (let ((st ((%tf-f32 scores) %st)))
          (let ((at (pick ((obj-ref f 13) st) ((obj-ref f 1) (List ref 1 st)))))
            (%tf-done scores)
            ; st is held to here, so its address stayed good
            (do st at)))))))

; --- one new position, with nothing made --------------------------------------------
; generate's predictions after the first each work out one position.  On a
; host with a GPU the work for that is made once: a held row for the
; position's hidden row and two more to work in, a plan for each product
; (Gpu %plan) whose result is the next step's operand, and a scratch for
; each kernel with its addresses in it.  A prediction then runs the plans
; and drives the kernels, and makes no tensor.
;
; The work is (STEP . RELEASE): STEP takes an id and its position and
; answers the id PICK takes from the scores after it; RELEASE gives the
; buffers back.

; The address of a tensor's elements as contiguous f32, and the state
; that keeps them alive.
(def %tf-flat
  (fn (_ t)
    (let ((f (Tensor %fast)) (st ((%tf-f32 t) %st)))
      (let ((c (if ((obj-ref f 3) st) st ((obj-ref f 10) st (lit f32)))))
        (pair ((obj-ref f 13) c) c)))))

(def %tf-zero! (fn (go s ks) (if (null? ks) () (do (%tf-word! s (first ks) 0) (go s (rest ks))))))

; A kernel driven over a scratch whose addresses are in it: the words KS
; are set to zero first, since the last run left them where it ended.
(def %tf-driven
  (fn (_ name s ks)
    (let ((drive (obj-ref (Tensor %fast) 14)))
      (fn (_) (%tf-zero! s ks) (drive name s)))))

; O[k] = A[k] + B[k] over N singles at those addresses.
(def %tf-add-scratch
  (fn (_ a b o n)
    (let ((s (str-make 256)))
      (mem-set (str->ptr s) 0 256)
      (%tf-word! s 0 a) (%tf-word! s 1 b) (%tf-word! s 2 o)
      (%tf-word! s 3 1) (%tf-word! s 4 1) (%tf-word! s 5 1) (%tf-word! s 6 n)
      s)))
(def %tf-adding (fn (_ a b o n) (%tf-driven (lit f32-add) (%tf-add-scratch a b o n) (list 7))))

; The N singles at IN normalized into OUT with a gain and a bias.
(def %tf-norming
  (fn (_ in gain bias out n)
    (let ((s (Neural %scratch)))
      (%tf-word! s 0 in) (%tf-word! s 1 gain) (%tf-word! s 2 out) (%tf-word! s 6 n) (%tf-word! s 10 bias)
      ; the doubles 16 and 17, the two sums, are words on a host with a GPU
      (%tf-driven (lit f32-layer-norm) s (list 7 9 16 17)))))

; gelu, the tanh form, in place over N singles.
(def %tf-gelu-ing
  (fn (_ a n)
    (let ((s (Neural %scratch)))
      (%tf-word! s 0 a) (%tf-word! s 2 a) (%tf-word! s 6 n)
      (%tf-driven (lit f32-gelu-tanh) s (list 7 9)))))

; Attention for the one position AT, whose queries, keys and values are
; the row at MADE: they are copied into the cache, and the answer is
; written at OUT.  AT is read from the cell at the time of each run.
(def %tf-attending
  (fn (_ made cache out rows width heads at)
    (let ((f (Tensor %fast)) (row (int* 12 width)))
      (let ((sc (%tf-attention-scratch ((obj-ref f 13) cache) out rows width heads 0))
            (drive (obj-ref f 14)))
        (fn (_)
          (let ((from (first at)) (s (first sc)))
            (mem-copy (int->ptr (int+ ((obj-ref f 13) cache) (int* from row))) (int->ptr made) row)
            (%tf-word! s 3 (int+ from 1)) (%tf-word! s 10 from) (%tf-word! s 15 from)
            (%tf-zero! s (list 9 11 12 13 16))
            (drive (lit f32-attention) s)
            ; the cache and the scratch are held to here, so their addresses stayed good
            (do cache sc ())))))))

(def %tf-each (fn (go l) (if (null? l) () (do ((first l)) (go (rest l))))))

(def %tf-work
  (fn (_ m caches pick)
    (let ((f (Tensor %fast)) (width (m %width)) (heads (m %heads)) (at (pair 0 ())) (kept (pair () ())) (plans (pair () ())))
      (let ((row (fn (_) (Gpu hold (Matrix %make ((obj-ref f 4) (lit f32) (list 1 width))))))
            (addr (fn (_ t) ((obj-ref f 13) (t %st))))
            (flat (fn (_ t) (let ((a (%tf-flat t))) (%set-first! kept (pair (rest a) (first kept))) (first a)))))
        (let ((x (row)) (n (row)) (t (row)))
          ; a times the layer's weight, plus its bias: the plan, its result
          ; and the two steps that work it out
          (let ((layer
                  (fn (_ a l)
                    (let ((plan (Gpu %plan a (first l))))
                      (%set-first! plans (pair plan (first plans)))
                      (let ((out (Gpu %plan-out plan)))
                        (let ((o (addr out)) (count ((obj-ref f 1) (List ref 1 (out %st)))))
                          (list out
                                (fn (_) (Gpu %plan-run plan))
                                (%tf-adding o (flat (rest l)) o count)))))))
                (norming (fn (_ g) (%tf-norming (addr x) (flat (first g)) (flat (rest g)) (addr n) width)))
                (rows (first (List ref 1 (first caches)))))
            (let ((steps
                    (List flat-map
                      (fn (_ bc)
                        (let ((b (first bc)) (cache (rest bc)))
                          (let ((attend (layer n (List ref 1 b))) (project (layer t (List ref 2 b)))
                                (wide (layer n (List ref 4 b))))
                            (let ((narrow (layer (first wide) (List ref 5 b))))
                              (list (norming (List ref 0 b))
                                    (List ref 1 attend) (List ref 2 attend)
                                    (%tf-attending (addr (first attend)) cache (addr t) rows width heads at)
                                    (List ref 1 project) (List ref 2 project)
                                    (%tf-adding (addr x) (addr (first project)) (addr x) width)
                                    (norming (List ref 3 b))
                                    (List ref 1 wide) (List ref 2 wide)
                                    (%tf-gelu-ing (addr (first wide)) ((obj-ref f 1) (List ref 1 ((first wide) %st))))
                                    (List ref 1 narrow) (List ref 2 narrow)
                                    (%tf-adding (addr x) (addr (first narrow)) (addr x) width))))))
                      (List zip (m %blocks) caches)))
                  (finish (norming (m %norm)))
                  ; the scores: the items times the last row as a column
                  (column (Tensor %make ((obj-ref f 11) (n %st) (list width) (list 1) 0))))
              (let ((scoring (Gpu %plan (m %items) column)))
                (%set-first! plans (pair scoring (first plans)))
                (let ((scores (Gpu %plan-out scoring)) (items (flat (m %items))) (places (flat (m %positions)))
                      (bytes (int* 4 width)) (drive (obj-ref f 14)))
                  (let ((embed (%tf-add-scratch 0 0 (addr x) width)) (at-scores (addr scores)) (many (first (scores extent))))
                    (pair
                      (fn (_ id from)
                        (%set-first! at from)
                        (%tf-word! embed 0 (int+ items (int* id bytes)))
                        (%tf-word! embed 1 (int+ places (int* from bytes)))
                        (%tf-word! embed 7 0)
                        (drive (lit f32-add) embed)
                        (%tf-each steps)
                        (finish)
                        (Gpu %plan-run scoring)
                        (let ((id (pick at-scores many)))
                          ; the rows, the states and the scratch are held to here, so their addresses stayed good
                          (do x n t kept scores embed id)))
                      (fn (_)
                        (List for-each (fn (_ p) (Gpu %plan-done p #f)) (first plans))
                        (%set-first! plans ())
                        (List for-each (fn (_ r) (Gpu release r)) (list x n t))
                        ()))))))))))))

; IDS and N more, each one PICK takes from the scores after those before
; it; EACH is called with each as it is made.
(def %tf-generate
  (fn (_ m ids n pick each)
    (if (int< n 1) ids
      (let ((count (List length ids)))
        (if (int< (m %context) (int- (int+ count n) 1))
          (Err raise (lit value) "Transformer: more ids than the model has positions"
            (list (int- (int+ count n) 1) (m %context)))
          ())
        (let ((caches (%tf-caches m (int- (int+ count n) 1))))
          ; the first prediction works out every position of ids
          (let ((first-id (%tf-next m (%tf-hidden m ids 0 caches) pick)))
            (each first-id)
            (if (int= n 1) (List append ids (list first-id))
              ; each one after it works out one position: by the work made
              ; once where the weights are held, else as the first did.
              ; made, the ids generated so far, last first; from, the
              ; position of the last of them
              (let ((work (if (m %held) (%tf-work m caches pick) ())))
                (let ((step (if (null? work)
                              (fn (_ id from) (%tf-next m (%tf-hidden m (list id) from caches) pick))
                              (first work))))
                  (let ((made
                          (guard (e (do (if (null? work) () ((rest work))) (error e)))
                            ((fn (go made from k)
                               (if (int= k 0) made
                                 (let ((id (step (first made) from)))
                                   (each id)
                                   (go (pair id made) (int+ from 1) (int- k 1)))))
                              (list first-id) count (int- n 1)))))
                    (if (null? work) () ((rest work)))
                    (List append ids (List reverse made))))))))))))

(def-class Transformer ()
  (doc "A language model's forward pass, in the layout GPT-2 is published in: from a list of ids, a score for every vocabulary item at every position, and the ids predicted to follow."
    (note "from-file reads a safetensors file with GPT-2's tensor names. The file does not say how many heads the attention has, so the caller does.")
    (note "The products run on the GPU where there is one and through Matrix's kernels otherwise, so logits differ in their last places from one host to another.")
    (note "generate keeps each block's queries, keys and values from one prediction to the next, and works out one new position for each id.")
    (note "On a host with a GPU, generate's predictions after the first run products planned once over buffers made once, and make no tensor.")
    (note "On a host with a GPU the weights are held there; (m release) gives the buffers back.")
    (sample "((Transformer from-file \"model.safetensors\" 12) generate (list 15496 11 995 0) 8)" "the four ids and the eight GPT-2 predicts after them")
    (known-as "GPT" "decoder-only transformer")
    (see from-file) (see logits) (see predict) (see variate) (see generate) (see release))

  heads       ; how many heads each block's attention has
  width       ; the length of a position's hidden row
  context     ; how many positions the model has
  items       ; wte: a row for each vocabulary item
  positions   ; wpe: a row for each position
  blocks      ; each block: ((GAIN . BIAS) (WEIGHT . BIAS) ...) for ln_1,
              ; attn.c_attn, attn.c_proj, ln_2, mlp.c_fc and mlp.c_proj
  norm        ; ln_f: (GAIN . BIAS)
  held        ; #t when the weights are held on the GPU, to be given back by release

  (static
    (method from-file (self (param path STRING "A safetensors file with GPT-2's tensor names")
                            (param heads INTEGER "How many heads each block's attention has: 12 for GPT-2"))
      (doc "A model from a safetensors file. The tensors are read into f32; the blocks are counted, and the width, the positions and the vocabulary are taken from the tensors' extents. A file that lacks a tensor, or a width the heads do not divide, raises a label 'value."
        (returns Transformer "The model")
        (sample "(Transformer from-file \"model.safetensors\" 12)" "GPT-2, from its published weights"))
      (let ((f (Safetensors open path)))
        (guard (e (do (f close) (error e)))
          (let ((tensor
                  (fn (_ name)
                    (let ((t (f ref name)))
                      (if (null? t) (Err raise (lit value) "Transformer: the file lacks a tensor" name) (%tf-f32 t)))))
                (matrix (fn (_ t) (Matrix %make (t %st))))
                (held (Gpu available?)))
            ; A weight on the GPU is read where it lies by every product
            ; that uses it; an ordinary one is copied in for each.
            (def weight (fn (_ t) (if held (Gpu hold t) t)))
            (let ((pair-of (fn (_ stem) (pair (tensor (Str8 append stem ".weight")) (tensor (Str8 append stem ".bias")))))
                  (layer (fn (_ stem) (pair (weight (matrix (tensor (Str8 append stem ".weight")))) (tensor (Str8 append stem ".bias"))))))
              (let ((items (weight (matrix (tensor "wte.weight")))) (positions (matrix (tensor "wpe.weight"))))
                (let ((width (List ref 1 (items extent))))
                  (if (if (type? heads (type-of 0)) (if (int< 0 heads) (int= (int% width heads) 0) #f) #f) ()
                    (Err raise (lit value) "Transformer: the heads do not divide the width" (list heads width)))
                  (let ((blocks
                          ((fn (go n)
                             (let ((stem (Str8 append "h." (Str8 str n))))
                               (if (null? (f extent (Str8 append stem ".ln_1.weight"))) ()
                                 (let ((b (list (pair-of (Str8 append stem ".ln_1"))
                                                (layer (Str8 append stem ".attn.c_attn"))
                                                (layer (Str8 append stem ".attn.c_proj"))
                                                (pair-of (Str8 append stem ".ln_2"))
                                                (layer (Str8 append stem ".mlp.c_fc"))
                                                (layer (Str8 append stem ".mlp.c_proj")))))
                                   (pair b (go (int+ n 1)))))))
                            0))
                        (norm (pair-of "ln_f")))
                    (f close)
                    (new-from self
                      (list (lit heads) heads (lit width) width (lit context) (first (positions extent))
                            (lit items) items (lit positions) positions (lit blocks) blocks (lit norm) norm
                            (lit held) held)))))))))))

  (method %heads (self) (field (lit heads)))
  (method %width (self) (field (lit width)))
  (method %context (self) (field (lit context)))
  (method %items (self) (field (lit items)))
  (method %positions (self) (field (lit positions)))
  (method %blocks (self) (field (lit blocks)))
  (method %norm (self) (field (lit norm)))
  (method %held (self) (field (lit held)))

  (method logits (self (param ids LIST "Ids, at least one and no more than the model has positions"))
    (doc "Every position's score for every vocabulary item: row i is the model's scores for the item after ids 0 to i. No ids, more than the model has positions, or an id it has no item for raises a label 'value."
      (returns Matrix "A fresh f32 Matrix, a row for each id and a column for each item")
      (sample "((m logits (list 15496 11 995 0)) extent)" "(4 50257)"))
    ; items times the hidden rows as columns is a column of scores for each
    ; position; its transpose is a row for each
    (let ((p (%tf-product (field (lit items))
               ((%tf-hidden self ids 0 (%tf-caches self (List length ids))) transpose))))
      (let ((r ((p transpose) copy)))
        (%tf-done p)
        r)))

  (method predict (self (param ids LIST "Ids, at least one and no more than the model has positions"))
    (doc "The id the model scores highest after the ids; of equal scores, the least id."
      (returns INTEGER "An id")
      (sample "(m predict (list 15496 11 995 0))" "the id of the item most likely to follow"))
    (%tf-next self (%tf-hidden self ids 0 (%tf-caches self (List length ids))) %tf-greatest-at))

  (method generate (self (param ids LIST "Ids to begin from, at least one")
                         (param n INTEGER "How many ids to add"))
    (doc "The ids and n more, each the prediction from all those before it. Each block keeps its queries, keys and values from one prediction to the next, so a prediction works out the one new position. The ids and the n less one fed back must be no more than the model has positions, or a label 'value is raised."
      (returns LIST "The ids, n longer")
      (sample "(m generate (list 15496 11 995 0) 8)" "the four ids and eight that follow"))
    (%tf-generate self ids n %tf-greatest-at (fn (_ id) ())))

  (method variate (self (param ids LIST "Ids, at least one and no more than the model has positions")
                        (param random Random "The source of the randomness, as (Random sw 7) or (Random hw)")
                        . (param options NUMBER "Optional (TEMPERATURE GREATEST): 1 and no limit by default"))
    (doc "An id drawn at random after the ids: each item's chance is in proportion to the exponential of its score over the temperature. A temperature below 1 favours the items scored highest and one above 1 evens the chances. With greatest, the draw is among that many of the highest scores, and every item scored equal to the last of them. A temperature not above 0, or a greatest that is not an integer above 0, raises a label 'value."
      (returns INTEGER "An id")
      (sample "(m variate (list 15496 11 995 0) (Random sw 7) 0.8 40)" "an id among the 40 scored highest")
      (known-as "sample" "temperature sampling" "top-k sampling")
      (see predict))
    ; the options are refused before any position is worked out
    (let ((pick (%tf-drawing random options)))
      (%tf-next self (%tf-hidden self ids 0 (%tf-caches self (List length ids))) pick)))

  (method %picking (self random options) (%tf-picking random options))
  (method %generate (self ids n pick each) (%tf-generate self ids n pick each))

  (method release (self)
    (doc "Give back the GPU buffers that hold the model's weights. The model is finished: using it afterwards raises a label 'state. A model whose weights are not held, on a host with no GPU, has nothing to give back; releasing twice does nothing."
      (returns ANY "nil")
      (sample "(m release)" "the weights' buffers given back"))
    (if (field (lit held))
      (do (Gpu release (field (lit items)))
          (List for-each
            (fn (_ b) (List for-each (fn (_ k) (Gpu release (first (List ref k b)))) (list 1 2 4 5)))
            (field (lit blocks))))
      ())
    ()))

(doc (provide x/num/transformer Transformer)
  (sample "((Transformer from-file \"model.safetensors\" 12) predict (list 15496 11 995 0))" "the id GPT-2 scores highest after the four")
  "Transformer: a language model's forward pass in GPT-2's layout, from a safetensors file: logits for every position, the id predicted next, and the ids generated from a beginning.")
