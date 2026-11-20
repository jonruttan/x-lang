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
; a layer is the input times the weight, plus the bias.  The heads'
; answers are not laid side by side: their product with c_proj's weight is
; the sum of each head's product with its own rows of the weight, and that
; sum is taken.
;
; A file does not say how many heads its attention has, so from-file is
; told.  Everything else is read from the tensors' extents.  Tensors are
; kept in f32, whatever the file holds them in.
;
; The products run on the GPU where there is one (x/num/gpu) and through
; Matrix's kernels otherwise.  The GPU sums in single precision and Matrix
; in double, so logits differ in their last places from one host to
; another, as they do from one framework to another.  Matrix's product
; makes an f64 copy of each operand, wte among them: on a host with no GPU
; a large model costs that copy at every call.
;
; generate works out every position again for each new id; it keeps
; nothing from one prediction to the next.  The pure-x steps between the
; kernels leave garbage, and nothing collects it during a call, so the
; heap is collected after each block.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/transformer)
(import x/type/class)
(import x/type/list)
(import x/codec/safetensors)
(import x/num/float float-of fsqrt)
(import x/num/tensor)
(import x/num/matrix)
(import x/num/neural)
(import x/num/gpu)
(import x/sys/gc)
(import x/tool/word-form word-form-pure)
(import x/core/doors int* int+ int- int/ int% int->ptr int< int= mem-cmp obj-ref ptr->int ptr-ref-word ptr-set-word!
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

; The place of the greatest element of a contiguous f32 state.
(def %tf-greatest-at
  (fn (_ st)
    (let ((f (Tensor %fast)) (s (str-make 256)))
      (%tf-word! s 0 ((obj-ref f 13) st)) (%tf-word! s 6 ((obj-ref f 1) (List ref 1 st))) (%tf-word! s 7 0)
      (%tf-word! s 13 0)
      ((obj-ref f 14) (lit f32-greatest-at) s)
      (%tf-word s 13))))

; --- the pieces ---------------------------------------------------------------------
; a times b: on the GPU where there is one, else by Matrix's kernels, cast
; back to f32.  a has two axes; b has two, or one and is a column.
(def %tf-product
  (fn (_ a b)
    (if (Gpu available?) (Gpu product a b)
      (((Matrix %make (a %st)) product b) as (lit f32)))))

; A layer: x times the weight, plus the bias along each row.
(def %tf-layer (fn (_ x layer) ((%tf-product x (first layer)) add (rest layer))))

; A tensor as f32.
(def %tf-f32 (fn (_ t) (if (eq? (t encoding) (lit f32)) t (t as (lit f32)))))

; One block's attention of x: heads of width wide each, of a block's
; (WEIGHT . BIAS) pairs attend, the query, key and value maker, and project.
(def %tf-attention
  (fn (_ x attend project heads wide)
    (let ((made (%tf-layer x attend)) (width (int* heads wide)) (root (fsqrt (float-of wide))))
      (def head
        (fn (_ h)
          (let ((at (int* h wide)))
            (let ((q (made slice 1 at (int+ at wide)))
                  (k (made slice 1 (int+ width at) (int+ width (int+ at wide))))
                  (v (made slice 1 (int+ (int* 2 width) at) (int+ (int* 2 width) (int+ at wide)))))
              (%tf-product
                (%tf-product (Neural softmax (Neural causal-mask ((%tf-product q (k transpose)) div root))) v)
                ((first project) slice 0 at (int+ at wide)))))))
      ((fn (go h sum) (if (int< h heads) (go (int+ h 1) (sum add (head h))) (sum add (rest project))))
        1 (head 0)))))

; The model's last hidden rows for ids, one for each, after ln_f.
(def %tf-hidden
  (fn (_ m ids)
    (let ((count (List length ids)) (heads (m %heads)) (wide (int/ (m %width) (m %heads))))
      (if (int= count 0) (Err raise (lit value) "Transformer: there are no ids" ()) ())
      (if (int< (m %context) count)
        (Err raise (lit value) "Transformer: more ids than the model has positions" (list count (m %context))) ())
      ((fn (go blocks x)
         (if (null? blocks)
           (Neural layer-norm x (first (m %norm)) (rest (m %norm)))
           (let ((b (first blocks)))
             (let ((x (x add (%tf-attention (Neural layer-norm x (first (List ref 0 b)) (rest (List ref 0 b)))
                                (List ref 1 b) (List ref 2 b) heads wide))))
               (let ((x (x add (%tf-layer
                                 (Neural gelu (%tf-layer (Neural layer-norm x (first (List ref 3 b)) (rest (List ref 3 b)))
                                                (List ref 4 b))
                                   (lit tanh))
                                 (List ref 5 b)))))
                 (Heap collect)
                 (go (rest blocks) x))))))
        (m %blocks)
        ((Neural embed (m %items) ids) add (Neural embed (m %positions) (List range 0 count)))))))

(def-class Transformer ()
  (doc "A language model's forward pass, in the layout GPT-2 is published in: from a list of ids, a score for every vocabulary item at every position, and the ids predicted to follow."
    (note "from-file reads a safetensors file with GPT-2's tensor names. The file does not say how many heads the attention has, so the caller does.")
    (note "The products run on the GPU where there is one and through Matrix's kernels otherwise, so logits differ in their last places from one host to another.")
    (note "generate works out every position again for each new id.")
    (sample "((Transformer from-file \"model.safetensors\" 12) generate (list 15496 11 995 0) 8)" "the four ids and the eight GPT-2 predicts after them")
    (known-as "GPT" "decoder-only transformer")
    (see from-file) (see logits) (see predict) (see generate))

  heads       ; how many heads each block's attention has
  width       ; the length of a position's hidden row
  context     ; how many positions the model has
  items       ; wte: a row for each vocabulary item
  positions   ; wpe: a row for each position
  blocks      ; each block: ((GAIN . BIAS) (WEIGHT . BIAS) ...) for ln_1,
              ; attn.c_attn, attn.c_proj, ln_2, mlp.c_fc and mlp.c_proj
  norm        ; ln_f: (GAIN . BIAS)

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
                (matrix (fn (_ t) (Matrix %make (t %st)))))
            (let ((pair-of (fn (_ stem) (pair (tensor (Str8 append stem ".weight")) (tensor (Str8 append stem ".bias")))))
                  (layer (fn (_ stem) (pair (matrix (tensor (Str8 append stem ".weight"))) (tensor (Str8 append stem ".bias"))))))
              (let ((items (matrix (tensor "wte.weight"))) (positions (matrix (tensor "wpe.weight"))))
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
                            (lit items) items (lit positions) positions (lit blocks) blocks (lit norm) norm)))))))))))

  (method %heads (self) (field (lit heads)))
  (method %width (self) (field (lit width)))
  (method %context (self) (field (lit context)))
  (method %items (self) (field (lit items)))
  (method %positions (self) (field (lit positions)))
  (method %blocks (self) (field (lit blocks)))
  (method %norm (self) (field (lit norm)))

  (method logits (self (param ids LIST "Ids, at least one and no more than the model has positions"))
    (doc "Every position's score for every vocabulary item: row i is the model's scores for the item after ids 0 to i. No ids, more than the model has positions, or an id it has no item for raises a label 'value."
      (returns Matrix "A fresh f32 Matrix, a row for each id and a column for each item")
      (sample "((m logits (list 15496 11 995 0)) extent)" "(4 50257)"))
    ; items times the hidden rows as columns is a column of scores for each
    ; position; its transpose is a row for each
    (((%tf-product (field (lit items)) ((%tf-hidden self ids) transpose)) transpose) copy))

  (method predict (self (param ids LIST "Ids, at least one and no more than the model has positions"))
    (doc "The id the model scores highest after the ids; of equal scores, the least id."
      (returns INTEGER "An id")
      (sample "(m predict (list 15496 11 995 0))" "the id of the item most likely to follow"))
    (let ((h (%tf-hidden self ids)) (count (List length ids)))
      (let ((scores (%tf-product (field (lit items))
                      ((h slice 0 (int- count 1) count) reshape (list (field (lit width)))))))
        (%tf-greatest-at ((%tf-f32 scores) %st)))))

  (method generate (self (param ids LIST "Ids to begin from, at least one")
                         (param n INTEGER "How many ids to add"))
    (doc "The ids and n more, each the prediction from all those before it. A prediction is made from no more ids than the model has positions: one asked of more raises a label 'value."
      (returns LIST "The ids, n longer")
      (sample "(m generate (list 15496 11 995 0) 8)" "the four ids and eight that follow"))
    ((fn (go ids k) (if (int< 0 k) (go (List append ids (list (self predict ids))) (int- k 1)) ids))
      ids n)))

(doc (provide x/num/transformer Transformer)
  (sample "((Transformer from-file \"model.safetensors\" 12) predict (list 15496 11 995 0))" "the id GPT-2 scores highest after the four")
  "Transformer: a language model's forward pass in GPT-2's layout, from a safetensors file: logits for every position, the id predicted next, and the ids generated from a beginning.")
