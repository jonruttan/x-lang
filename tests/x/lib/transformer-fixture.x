; transformer-fixture.x -- a small model in GPT-2's layout, for the Transformer specs.
;
; (transformer-fixture path) writes a safetensors file of a model with 11
; items, 8 positions, a width of 8 and 2 blocks, to be read with 2 heads.
; Element i of each tensor is (((seed + 37 i) mod 23) - 11) / 32, and 1 more
; for a layer norm's weight; a tensor's seed is 3 + 11 k, k its place among
; the names in order.  Every value is exact in f32.  The logits the specs
; expect are those a reference implementation of GPT-2 answers for a model
; made by the same formula.
;
; (transformer-fixture-model) answers that model, read with 2 heads.  It is
; made once for the process and kept: a spec file's cases share one
; interpreter, and making the model costs about what a forward pass does,
; which on a host whose kernels all run pure is seconds.
;
; (transformer-near? got want) answers whether two lists of rows agree,
; element by element, within a ten-thousandth.
(def transformer-fixture
  (fn (_ path)
    (import x/codec/safetensors)
    (let ((mod (prim-ref (lit int) (lit %))) (v 11) (c 8) (d 8) (tensors (Dict make)))
      (def block
        (fn (_ l)
          (let ((p (Str8 append "h." (Str8 str l) ".")))
            (list (list (Str8 append p "ln_1.weight") (list d) #t)
                  (list (Str8 append p "ln_1.bias") (list d) #f)
                  (list (Str8 append p "ln_2.weight") (list d) #t)
                  (list (Str8 append p "ln_2.bias") (list d) #f)
                  (list (Str8 append p "attn.c_attn.weight") (list d (* 3 d)) #f)
                  (list (Str8 append p "attn.c_attn.bias") (list (* 3 d)) #f)
                  (list (Str8 append p "attn.c_proj.weight") (list d d) #f)
                  (list (Str8 append p "attn.c_proj.bias") (list d) #f)
                  (list (Str8 append p "mlp.c_fc.weight") (list d (* 4 d)) #f)
                  (list (Str8 append p "mlp.c_fc.bias") (list (* 4 d)) #f)
                  (list (Str8 append p "mlp.c_proj.weight") (list (* 4 d) d) #f)
                  (list (Str8 append p "mlp.c_proj.bias") (list d) #f)))))
      (def rows
        (List sort (fn (_ a b) (Str8 <? (first a) (first b)))
          (List append
            (list (list "wte.weight" (list v d) #f) (list "wpe.weight" (list c d) #f)
                  (list "ln_f.weight" (list d) #t) (list "ln_f.bias" (list d) #f))
            (List append (block 0) (block 1)))))
      ((fn (go l k)
         (if (null? l) ()
           (let ((name (first (first l))) (ext (first (rest (first l)))) (norm? (first (rest (rest (first l)))))
                 (seed (+ 3 (* 11 k))))
             (let ((n (List fold (fn (_ acc x) (* acc x)) 1 ext)))
               (let ((t ((Tensor from
                           ((fn (each i) (if (< i n) (pair (- (mod (+ seed (* 37 i)) 23) 11) (each (+ i 1))) ())) 0)
                           (lit f32))
                         div 32)))
                 (tensors set! name ((if norm? (t add 1) t) reshape ext))
                 (go (rest l) (+ k 1)))))))
        rows 0)
      (Safetensors write path tensors))))

(def transformer-near?
  (fn (go got want)
    (match
      ((null? got) (null? want))
      ((null? want) #f)
      ((pair? (first got)) (if (go (first got) (first want)) (go (rest got) (rest want)) #f))
      (#t (let ((d (- (first got) (first want))))
            (if (< (* d d) 1.0e-08) (go (rest got) (rest want)) #f))))))

; The kept model, nil until the first case asks for it.  The file is
; included by every case, so the binding is kept when there is one.
(def transformer-fixture-kept (guard (e ()) transformer-fixture-kept))

(def transformer-fixture-model
  (fn (_)
    (if (null? transformer-fixture-kept)
      (let ((tmp (File temp "/tmp/x-transformer-fixture-")))
        (File close (first tmp))
        (transformer-fixture (rest tmp))
        (set! transformer-fixture-kept (Transformer from-file (rest tmp) 2))
        (File unlink (rest tmp)))
      ())
    transformer-fixture-kept))
