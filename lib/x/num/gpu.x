; gpu.x -- Gpu: Tensor arithmetic run on the host's GPU.
;
; Gpu is the front the numeric library sends GPU work through.  It names
; no system: it asks the backends it knows for one that is available, and
; today there is one, x/sys/darwin/metal.  A second backend answers the
; same messages as Metal -- buffer, pointer, compile, run, release -- and
; brings its own kernel source.
;
;   (Gpu available?)   -> #t when this host has a GPU a backend reaches
;   (Gpu hold t)       -> a copy of t, in f32, whose bytes the GPU holds
;   (Gpu held? t)      -> #t for a tensor whose bytes the GPU holds
;   (Gpu release t)    -> the bytes given back; t is not to be used again
;   (Gpu product a b)  -> the matrix product of a and b, in f32
;
; The elements are f32: a GPU kernel's floats are 32-bit.  An operand of
; another encoding is cast as (t as 'f32) casts it.
;
; A held tensor is a Tensor or a Matrix like any other, whose data is a
; buffer the processor and the GPU both address.  Every Tensor operation
; works on it where it lies, its views share the buffer, and a GPU kernel
; reads it with no copy.  product answers a held result when either
; operand is held, and nothing is copied in or out: a chain of products
; stays on the GPU.  With two ordinary operands their bytes are copied
; into buffers, and the result is copied out into an ordinary Matrix.
;
; Nothing gives a held tensor's buffer back but release: the collector
; does not know of it.  The buffer is shared by the tensor's views, and
; release ends them all: using one afterwards raises a label 'state.  A
; held tensor does not outlast its process, so it is not to be kept in a
; state image.
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
(import x/core/doors image-transient! int* int->ptr int< int= mem-copy obj-ref ptr->int ptr-set!)

(def-class Gpu ()
  (doc "Tensor arithmetic run on the host's GPU, in f32, through whichever backend is available: Metal on macOS."
    (note "A GPU sums in single precision, so a result can differ in its last bits from the same operation by Tensor's kernels cast to f32.")
    (note "A held tensor's bytes are in a buffer the GPU shares: product reads and answers held tensors with no copy. Only (Gpu release t) gives a buffer back.")
    (note "On a host with no GPU, hold and product raise a label 'io: ask available? first.")
    (example "(boolean? (Gpu available?))" "#t")
    (see available?) (see hold) (see product))
  (static
    ; The product's kernel in the Metal Shading Language.  dims holds the
    ; inner length m and the result's columns k, then each operand's
    ; offset and its strides along its two axes, in elements: an operand is
    ; read through them where it lies, a view as well as a whole buffer.
    ; The grid is k across and the result's rows down.
    (%product-source "#include <metal_stdlib>
using namespace metal;
kernel void product(device const float* a [[buffer(0)]],
                    device const float* b [[buffer(1)]],
                    device float* c [[buffer(2)]],
                    device const uint* dims [[buffer(3)]],
                    uint2 at [[thread_position_in_grid]]) {
  uint m = dims[0], k = dims[1];
  uint ao = dims[2] + at.y * dims[3], as = dims[4];
  uint bo = dims[5] + at.x * dims[7], bs = dims[6];
  float sum = 0.0f;
  for (uint j = 0; j < m; j++) sum += a[ao + j * as] * b[bo + j * bs];
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

    (method %held-state? (self (param st LIST "A tensor's state"))
      (doc "Whether the state's data is a buffer the GPU holds."
        (returns BOOL "#t for a held tensor's state")
        (sample "(Gpu %held-state? ((Tensor zeros 2) %st))" "#f"))
      (pair? (List ref 4 st)))

    (method %in-buffer (self (param backend ANY "The backend class")
                             (param st LIST "A contiguous f32 state"))
      (doc "A fresh buffer holding a copy of the state's elements, in row-major order."
        (returns INTEGER "The buffer, of at least 4 bytes")
        (sample "(Gpu %in-buffer Metal (Gpu %f32 t))" "a buffer"))
      (let ((f (Tensor %fast)))
        (let ((bytes (int* 4 ((obj-ref f 1) (List ref 1 st)))))
          (let ((buf (backend buffer (if (int< bytes 4) 4 bytes))))
            (if (int< bytes 4) ()
              (mem-copy (backend pointer buf) (int->ptr ((obj-ref f 13) st)) bytes))
            buf))))

    ; An operand as the kernel reads it: (BUFFER OFFSET STRIDES LENT?).  A
    ; held f32 tensor is read where it lies, through its offset and
    ; strides; any other is cast and copied into a buffer lent for the run.
    (method %operand (self backend t)
      (let ((f (Tensor %fast)) (st (t %st)))
        (if (if (eq? (first st) (lit f32)) (Gpu %held-state? st) #f)
          (do ((obj-ref f 18) st)        ; raises when the bytes were given back
              (list (rest (List ref 4 st)) (List ref 3 st) (List ref 2 st) #f))
          (let ((c (Gpu %f32 t)))
            (list (Gpu %in-buffer backend c) 0 ((obj-ref f 2) (List ref 1 c)) #t)))))

    (method available? (self)
      (doc "Whether this host has a GPU a backend reaches."
        (returns BOOL "#t on an Apple silicon Mac")
        (sample "(Gpu available?)" "#t on an Apple silicon Mac"))
      (not (null? (Gpu %backend))))

    (method hold (self (param t Tensor "A tensor of any real encoding"))
      (doc "A contiguous f32 copy of t whose bytes are in a buffer the GPU shares: a Tensor or a Matrix as t is, on which every operation works, and which product reads with no copy. Give the buffer back with release. Raises a label 'io on a host with no GPU."
        (returns Tensor "A fresh held tensor of t's extent")
        (sample "(let ((h (Gpu hold (Tensor from '(1 2.5))))) (list (h encoding) (h ->list) (Gpu held? h)))" "('f32 (1.0 2.5) #t) on a host with a GPU")
        (see release) (see held?))
      (def backend (Gpu %need-backend))
      (let ((f (Tensor %fast)) (c (Gpu %f32 t)))
        (let ((buf (Gpu %in-buffer backend c)) (ext (List ref 1 c)))
          (t %wrap (list (lit f32) ext ((obj-ref f 2) ext) 0
                         (pair (ptr->int (backend pointer buf)) buf))))))

    (method held? (self (param t Tensor "Any tensor"))
      (doc "Whether the tensor's bytes are in a buffer the GPU shares: a tensor from hold, a product of one, or a view of either."
        (returns BOOL "#t for a held tensor, released or not")
        (example "(Gpu held? (Tensor from '(1 2)))" "#f"))
      (Gpu %held-state? (t %st)))

    (method release (self (param t Tensor "A held tensor"))
      (doc "Give a held tensor's buffer back. The tensor and every view that shares the buffer are finished: using one afterwards raises a label 'state. Releasing a tensor already released, or one that is not held, does nothing."
        (returns ANY "nil")
        (example "(null? (Gpu release (Tensor from '(1 2))))" "#t")
        (sample "(Gpu release h)" "nil, h's buffer given back"))
      (let ((data (List ref 4 (t %st))))
        (if (if (pair? data) (not (int= (first data) 0)) #f)
          (let ((buf (rest data)))
            (%set-first! data 0)
            (%set-rest! data ())
            ((Gpu %need-backend) release buf))
          ()))
      ())

    (method product (self (param a Tensor "A Matrix, or a Tensor of two axes")
                          (param b Tensor "A Matrix, or a rank-1 Tensor, whose rows match a's columns"))
      (doc "The matrix product of a and b computed on the GPU in f32: element (i j) is the sum over k of a's (i k) times b's (k j). A rank-1 b is a column, and the product is then a rank-1 Tensor. A held f32 operand is read where it lies; any other is cast to f32 and copied in. The result is held when either operand is, to be given back with release, and an ordinary Matrix otherwise. Raises a label 'io on a host with no GPU, and a label 'value when the extents do not fit."
        (returns Tensor "A fresh f32 Matrix of a's rows and b's columns, or a rank-1 Tensor for a rank-1 b")
        (sample "((Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((0 1) (1 0)))) ->list)" "((2.0 1.0) (4.0 3.0)) on a host with a GPU")
        (see available?) (see hold))
      (def backend (Gpu %need-backend))
      (let ((f (Tensor %fast)) (ea (List ref 1 (a %st))) (eb (List ref 1 (b %st)))
            (held (if (Gpu held? a) #t (Gpu held? b))))
        (if (int= (List length ea) 2) ()
          (Err raise (lit value) "Gpu product: a has two axes" ea))
        (if (if (int= (List length eb) 1) #t (int= (List length eb) 2)) ()
          (Err raise (lit value) "Gpu product: b has one axis or two" eb))
        (let ((r (first ea)) (m (List ref 1 ea)) (column (int= (List length eb) 1)))
          (let ((k (if column 1 (List ref 1 eb))) (ext (if column (list r) (list r (List ref 1 eb)))))
            (if (int= m (first eb)) ()
              (Err raise (lit value) "Gpu product: a's columns and b's rows differ" (list m (first eb))))
            (let ((bytes (int* 4 (int* r k))))
              (let ((oa (Gpu %operand backend a)) (ob (Gpu %operand backend b))
                    (bc (backend buffer (if (int< bytes 4) 4 bytes))) (dims (backend buffer 32)))
                ; a product with no elements, or summed over none, is the zeros a fresh buffer holds
                (if (if (int= r 0) #t (if (int= m 0) #t (int= k 0))) ()
                  (let ((sa (List ref 2 oa)) (sb (List ref 2 ob)))
                    (List for-each (fn (_ w) (ptr-set! (backend pointer dims) (int* 4 (first w)) (rest w) 4))
                      (list (pair 0 m) (pair 1 k)
                            (pair 2 (List ref 1 oa)) (pair 3 (first sa)) (pair 4 (List ref 1 sa))
                            (pair 5 (List ref 1 ob)) (pair 6 (first sb)) (pair 7 (if column 0 (List ref 1 sb)))))
                    (backend run (Gpu %pipeline backend (lit product) (Gpu %product-source))
                      (list (first oa) (first ob) bc dims) k r)))
                (backend release dims)
                (List for-each (fn (_ o) (if (List ref 3 o) (backend release (first o)) ())) (list oa ob))
                (let ((out (if held
                             (list (lit f32) ext ((obj-ref f 2) ext) 0 (pair (ptr->int (backend pointer bc)) bc))
                             (let ((o ((obj-ref f 4) (lit f32) ext)))
                               (if (int< bytes 4) ()
                                 (mem-copy (int->ptr ((obj-ref f 13) o)) (backend pointer bc) bytes))
                               (backend release bc)
                               o))))
                  ((Matrix %result-class out) %make out))))))))))

(image-transient! (fn (_) (Gpu %forget!)))

(doc (provide x/num/gpu Gpu)
  (example "(boolean? (Gpu available?))" "#t")
  "Gpu: Tensor arithmetic run on the host's GPU in f32, through Metal on macOS: tensors held in buffers the GPU shares, and the matrix product.")
