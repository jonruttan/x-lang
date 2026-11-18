; gpu.x -- Gpu: Tensor arithmetic run on the host's GPU.
;
; Gpu is the front the numeric library sends GPU work through.  It names
; no system: it asks the backends it knows for one that is available, and
; today there is one, x/sys/darwin/metal.  A second backend answers the
; same messages as Metal -- buffer, pointer, compile, run, release -- and
; brings its own kernel source.
;
;   (Gpu available?)   -> #t when this host has a GPU a backend reaches
;   (Gpu product a b)  -> the matrix product of a and b, in f32
;
; The elements are f32: a GPU kernel's floats are 32-bit.  An operand of
; another encoding is cast as (t as 'f32) casts it.  The operands' bytes
; are copied into buffers the GPU shares, the kernel runs, and the result
; is copied out into a fresh Matrix.
;
; A GPU sums a row's products in single precision, where Tensor's kernels
; keep a double and round once, so a product here can differ in its last
; bits from the same product by Matrix's kernels cast to f32.  That is why
; this is a message a caller sends, and not a kernel a lane adopts: a lane
; adopts only what agrees to the byte.
;
; On a host with no GPU the messages that need one raise a label 'io; a
; caller asks available? first and takes Matrix's product otherwise.
;
; A compiled kernel is process state.  It is kept after its first use and
; released before a state image is written, to be compiled again when next
; wanted.

(module x/num/gpu)
(import x/type/class)
(import x/type/list)
(import x/num/tensor)
(import x/num/matrix)
(import x/sys/darwin/metal)
(import x/core/doors image-transient! int* int->ptr int= mem-copy obj-ref ptr-set!)

(def-class Gpu ()
  (doc "Tensor arithmetic run on the host's GPU, in f32, through whichever backend is available: Metal on macOS."
    (note "A GPU sums in single precision, so a result can differ in its last bits from the same operation by Tensor's kernels cast to f32.")
    (note "On a host with no GPU, product raises a label 'io: ask available? first.")
    (example "(boolean? (Gpu available?))" "#t")
    (see available?) (see product))
  (static
    ; The product's kernel in the Metal Shading Language.  dims holds the
    ; inner length m and the result's columns k; the grid is k across and
    ; the result's rows down.
    (%product-source "#include <metal_stdlib>
using namespace metal;
kernel void product(device const float* a [[buffer(0)]],
                    device const float* b [[buffer(1)]],
                    device float* c [[buffer(2)]],
                    device const uint* dims [[buffer(3)]],
                    uint2 at [[thread_position_in_grid]]) {
  uint m = dims[0], k = dims[1];
  float sum = 0.0f;
  for (uint j = 0; j < m; j++) sum += a[at.y * m + j] * b[j * k + at.x];
  c[at.y * k + at.x] = sum;
}")

    ; The compiled kernels by name, ((NAME . PIPELINE) ...).
    (%pipelines-cell (pair () ()))

    (method %backend (self)
      (doc "The backend class in use, or nil when this host has no GPU one reaches."
        (returns ANY "Metal where it is available, else nil")
        (sample "(Gpu %backend)" "Metal on an Apple silicon Mac"))
      (if (Metal available?) Metal ()))

    (method %need-backend (self)
      (doc "The backend class in use; raises a label 'io when this host has none."
        (returns ANY "The backend class")
        (sample "(Gpu %need-backend)" "Metal on an Apple silicon Mac"))
      (def backend (Gpu %backend))
      (when (null? backend)
        (Err raise (lit io) "Gpu: no GPU on this host" ()))
      backend)

    (method %pipeline (self (param backend ANY "The backend class")
                            (param name SYMBOL "The kernel's name")
                            (param source STRING "Its source"))
      (doc "The kernel compiled, kept after the first time it is asked for."
        (returns LIST "The backend's pipeline")
        (sample "(Gpu %pipeline Metal (lit product) (Gpu %product-source))" "a pipeline"))
      (def kept (Assoc entry name (first (Gpu %pipelines-cell))))
      (if (null? kept)
        (let ((made (backend compile source (symbol->str name))))
          (%set-first! (Gpu %pipelines-cell) (pair (pair name made) (first (Gpu %pipelines-cell))))
          made)
        (rest kept)))

    (method %forget! (self)
      (doc "Release every kept kernel; each is compiled again when next wanted. Sent before a state image is written."
        (returns ANY "nil")
        (sample "(Gpu %forget!)" "nil"))
      (List for-each (fn (_ e) (Metal release (rest e))) (first (Gpu %pipelines-cell)))
      (%set-first! (Gpu %pipelines-cell) ())
      ())

    (method %f32 (self (param t Tensor "A tensor of any real encoding"))
      (doc "The tensor's state as contiguous f32: its own when it is that already, else a cast copy's."
        (returns LIST "A contiguous f32 state")
        (sample "(Gpu %f32 (Tensor from '(1 2)))" "the state of an f32 copy"))
      (let ((f (Tensor %fast)) (st (t %st)))
        (if (if (eq? (first st) (lit f32)) ((obj-ref f 3) st) #f) st
          ((obj-ref f 10) st (lit f32)))))

    (method available? (self)
      (doc "Whether this host has a GPU a backend reaches."
        (returns BOOL "#t on an Apple silicon Mac")
        (sample "(Gpu available?)" "#t on an Apple silicon Mac"))
      (not (null? (Gpu %backend))))

    (method product (self (param a Tensor "A Matrix, or a Tensor of two axes")
                          (param b Tensor "A Matrix, or a rank-1 Tensor, whose rows match a's columns"))
      (doc "The matrix product of a and b computed on the GPU in f32: element (i j) is the sum over k of a's (i k) times b's (k j). A rank-1 b is a column, and the product is then a rank-1 Tensor. An operand of another encoding is cast to f32 first. Raises a label 'io on a host with no GPU, and a label 'value when the extents do not fit."
        (returns Tensor "A fresh f32 Matrix of a's rows and b's columns, or a rank-1 Tensor for a rank-1 b")
        (sample "((Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((0 1) (1 0)))) ->list)" "((2.0 1.0) (4.0 3.0)) on a host with a GPU")
        (see available?))
      (def backend (Gpu %need-backend))
      (let ((f (Tensor %fast)) (sa (Gpu %f32 a)) (sb (Gpu %f32 b)))
        (let ((ea (List ref 1 sa)) (eb (List ref 1 sb)))
          (if (int= (List length ea) 2) ()
            (Err raise (lit value) "Gpu product: a has two axes" ea))
          (if (if (int= (List length eb) 1) #t (int= (List length eb) 2)) ()
            (Err raise (lit value) "Gpu product: b has one axis or two" eb))
          (let ((r (first ea)) (m (List ref 1 ea)) (column (int= (List length eb) 1)))
            (let ((k (if column 1 (List ref 1 eb))))
              (if (int= m (first eb)) ()
                (Err raise (lit value) "Gpu product: a's columns and b's rows differ" (list m (first eb))))
              (let ((out ((obj-ref f 4) (lit f32) (if column (list r) (list r k)))))
                ; a product with no elements, or summed over none, is zeros; a
                ; fresh state's bytes are not, so they are filled
                (if (if (int= r 0) #t (if (int= m 0) #t (int= k 0))) ((obj-ref f 9) out 0)
                  (let ((ba (backend buffer (int* 4 (int* r m)))) (bb (backend buffer (int* 4 (int* m k))))
                        (bc (backend buffer (int* 4 (int* r k)))) (dims (backend buffer 8)))
                    (mem-copy (backend pointer ba) (int->ptr ((obj-ref f 13) sa)) (int* 4 (int* r m)))
                    (mem-copy (backend pointer bb) (int->ptr ((obj-ref f 13) sb)) (int* 4 (int* m k)))
                    (ptr-set! (backend pointer dims) 0 m 4)
                    (ptr-set! (backend pointer dims) 4 k 4)
                    (backend run (Gpu %pipeline backend (lit product) (Gpu %product-source))
                      (list ba bb bc dims) k r)
                    (mem-copy (int->ptr ((obj-ref f 13) out)) (backend pointer bc) (int* 4 (int* r k)))
                    (List for-each (fn (_ buf) (backend release buf)) (list ba bb bc dims))))
                ((Matrix %result-class out) %make out)))))))))

(image-transient! (fn (_) (Gpu %forget!)))

(doc (provide x/num/gpu Gpu)
  (example "(boolean? (Gpu available?))" "#t")
  "Gpu: Tensor arithmetic run on the host's GPU in f32, through Metal on macOS: the matrix product.")
