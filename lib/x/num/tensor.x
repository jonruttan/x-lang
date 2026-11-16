; tensor.x -- Tensor: an n-dimensional array of numbers packed in bytes.
;
; A tensor is an encoding, an extent, strides, an offset and a byte region.
; The encoding says how each element is stored: f64, an IEEE double; i64,
; a 64-bit integer; or c128, a complex number as two doubles, its real part
; first.  f64 and i64 take 8 bytes, c128 16.  The extent is the length of
; each axis, (2 3) for two rows of three, and its length is the rank.  The
; strides say how many elements to step along each axis, and the offset is
; the index of the first element in the region.  A fresh tensor is laid out
; row-major: the last axis is contiguous.
;
; A view shares another tensor's bytes and differs only in its extent,
; strides and offset: transpose, slice and reshape of a contiguous tensor
; are views, and writing through one is seen through the other.  So are a
; c128 tensor's real and imaginary parts: f64 views of every other double.
; Broadcasting is a view too: an axis of length 1 stretches to any length
; with a stride of 0, so (a add 1) and a row added to every row of a matrix
; run the same kernel as two tensors of one extent.
;
; The arithmetic is kernels, each written once as a word form
; (x/tool/word-form) over a run of elements, a start and a stride per
; operand: the element-wise operations, the reductions, fill, copy and the
; casts.  A c128 kernel reads and writes an element's two doubles; complex
; numbers have no order, so c128 has no min, max, least or greatest.  An operation walks the outer axes in x and hands each run of
; the last axis to its kernel; operands that are all contiguous and of one
; extent are one run.  A kernel runs pure until it has done about a
; compile's worth of steps, then compiles through compile-asm, and the
; compiled one is adopted only after it writes the bytes the pure one
; writes on the check inputs.  A pure step allocates, so a pure kernel runs
; in budgeted calls and the heap is collected between them once the churn
; passes %window, as x/num/fourier's are.
;
; An instance holds one field, its state: the list (ENC EXTENT STRIDES
; OFFSET DATA).  The work is done by closures over states, made once and
; kept in %fast-cell, which call one another directly: a class dispatch
; costs about as much as a thousand objects, and an operation that went
; through one per step would cost more than its arithmetic.
;
; On a 4-byte word a double is two words: f64 tensors run their pure
; kernels only, and i64 is refused, since an element does not fit a word.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/tensor)
(import x/type/class)
(import x/type/vector)
(import x/type/list)
(import x/sys/gc)
(import x/num/float float float-of f-div libm-fn)
(import x/tool/word-form word-form-pure)
(import x/tool/compiled)
(import x/core/doors int+ int- int* int/ int< int= int->ptr mem-copy mem-cmp obj-ref ptr->int
  ptr-ref-word ptr-set-word! str->ptr str->sym str-make type-make-instance type-of type?)

(def-class Tensor ()
  (doc "An n-dimensional array of numbers packed in bytes, each element an f64 (an IEEE double), an i64 (a 64-bit integer) or a c128 (a complex number, two doubles). Transpose, slice and reshape answer views that share the bytes; the element-wise operations broadcast, an axis of length 1 stretching to the other operand's; the arithmetic runs in kernels that compile once they have run long enough."
    (note "The extent is the length of each axis, (2 3) for two rows of three; rank is its length. Indexes are 0-based and a negative one counts from the end.")
    (example "((Tensor from '((1.5 2) (3 4))) ->list)" "((1.5 2.0) (3.0 4.0))")
    (example "(((Tensor from '((1 2) (3 4.5))) add (Tensor from '(10 20))) ->list)" "((11.0 22.0) (13.0 24.5))")
    (see from) (see zeros) (see add) (see sum) (see slice) (see jit!))

  st        ; the state: (ENC EXTENT STRIDES OFFSET DATA)

  (static
    ; --- making tensors -----------------------------------------------------
    (method zeros (self (param extent INTEGER|LIST "Axis lengths, or one length for rank 1")
                        . (param enc LIST "Optional encoding: f64 (the default) or i64"))
      (doc "A tensor of the given extent, every element 0."
        (returns Tensor "A fresh row-major tensor")
        (example "((Tensor zeros '(2 2)) ->list)" "((0.0 0.0) (0.0 0.0))")
        (sample "((Tensor zeros 3 'i64) ->list)" "(0 0 0) on an 8-byte word; i64 is refused on a 4-byte word"))
      (self fill extent 0 (self %enc-or enc (lit f64))))

    (method fill (self (param extent INTEGER|LIST "Axis lengths, or one length for rank 1")
                       (param x NUMBER "The value of every element")
                       . (param enc LIST "Optional encoding; by default i64 for an integer, else f64"))
      (doc "A tensor of the given extent, every element x."
        (returns Tensor "A fresh row-major tensor")
        (example "((Tensor fill '(2 3) 7.5) ->list)" "((7.5 7.5 7.5) (7.5 7.5 7.5))")
        (example "((Tensor fill 2 0.5) ->list)" "(0.5 0.5)"))
      (let ((f (self %fast)))
        (let ((st ((obj-ref f 4) (self %enc-or enc (self %enc-of (list x))) (self %extent extent))))
          ((obj-ref f 9) st x)
          (self %make st))))

    (method from (self (param x LIST|VECTOR|NUMBER "Numbers, nested as lists or vectors, one level per axis")
                       . (param enc LIST "Optional encoding; by default c128 when an element is complex, i64 when every element is an integer, else f64"))
      (doc "A tensor holding the numbers of x, its extent read off the nesting. Every list at one depth must have the same length."
        (returns Tensor "A fresh row-major tensor")
        (example "((Tensor from '((1 2 3) (4 5 6))) extent)" "(2 3)")
        (example "((Tensor from '(1 2.5)) ->list)" "(1.0 2.5)")
        (example "((Tensor from '(1 2) 'f64) ->list)" "(1.0 2.0)")
        (example "((Tensor from (list 1 (Complex make 0 2))) ->list)" "(1.0+0.0i 0.0+2.0i)"))
      (let ((f (self %fast)) (ext (self %extent-of x)) (xs (self %flatten x)))
        (let ((st ((obj-ref f 4) (self %enc-or enc (self %enc-of xs)) ext)))
          (let ((a ((obj-ref f 13) st)) (put ((obj-ref f 6) (first st))))
            (def go (fn (go i xs) (if (null? xs) () (do (put a i (first xs)) (go (int+ i 1) (rest xs))))))
            (go 0 xs))
          (self %make st))))

    (method range (self (param n INTEGER "The count, at least 0")
                        . (param enc LIST "Optional encoding: i64 (the default) or f64"))
      (doc "The rank-1 tensor 0, 1, ..., n - 1."
        (returns Tensor "A fresh tensor of extent (n)")
        (example "((Tensor range 3 'f64) ->list)" "(0.0 1.0 2.0)")
        (sample "((Tensor range 4) ->list)" "(0 1 2 3) on an 8-byte word, (0.0 1.0 2.0 3.0) on a 4-byte word"))
      (let ((f (self %fast)))
        (let ((st ((obj-ref f 4) (self %enc-or enc (if (int= %word-size 8) (lit i64) (lit f64))) (self %extent n))))
          (let ((a ((obj-ref f 13) st)) (put ((obj-ref f 6) (first st))))
            (def go (fn (go i) (if (int< i n) (do (put a i i) (go (int+ i 1))) ())))
            (go 0))
          (self %make st))))

    (method encodings (self)
      (doc "The encodings a tensor's elements can have."
        (returns LIST "The encoding symbols")
        (example "(Tensor encodings)" "('f64 'i64 'c128)"))
      (list (lit f64) (lit i64) (lit c128)))

    (method complex (self (param re Tensor|NUMBER "The real parts")
                          (param im Tensor|NUMBER "The imaginary parts, broadcasting with re"))
      (doc "The c128 tensor whose real parts are re and imaginary parts im, broadcast as add is."
        (returns Tensor "A fresh c128 tensor of the broadcast extent")
        (example "((Tensor complex (Tensor from '(1 2)) (Tensor from '(3 -4))) ->list)" "(1.0+3.0i 2.0-4.0i)"))
      (let ((f (self %fast))
            (r (if (number? re) ((Tensor fill () re (lit f64)) %st) (re %st)))
            (i (if (number? im) ((Tensor fill () im (lit f64)) %st) (im %st))))
        (let ((out ((obj-ref f 4) (lit c128) ((obj-ref f 16) (List ref 1 r) (List ref 1 i)))))
          ((obj-ref f 17) (self %part out 0) r)
          ((obj-ref f 17) (self %part out 1) i)
          (self %make out))))

    ; The f64 view of the c128 state ST's real (PART 0) or imaginary (1) parts.
    (method %part (self st part)
      (list (lit f64) (List ref 1 st) (List map (fn (_ k) (int* 2 k)) (List ref 2 st))
            (int+ (int* 2 (List ref 3 st)) part) (List ref 4 st)))

    ; --- the kernels' lane --------------------------------------------------
    (method jit! (self)
      (doc "Build every kernel's compiled version (JIT; ARM64 and x86-64) now, adopting each one that writes the bytes its pure version does on the check inputs. Answers the names of the compiled kernels in use; the results are the same either way. A kernel does this on its own once it has run about as long as compiling it takes."
        (returns LIST "The names of the kernels running compiled, () where none can be built")
        (sample "(Tensor jit!)" "every kernel's name where a JIT backend is, () elsewhere"))
      (List map (fn (_ k) (self %jit (first k))) (self %kernel-specs))
      (self compiled))

    (method compiled (self)
      (doc "The names of the kernels that run compiled."
        (returns LIST "Kernel names, such as f64-add")
        (sample "(Tensor compiled)" "() until a kernel has run long enough or (Tensor jit!) is sent"))
      (List map first
        (List filter (fn (_ e) (first (rest e))) (first (self %lanes-cell)))))

    ; --- making and checking ----------------------------------------------
    (method %enc-or (self opts default)
      (let ((e (if (null? opts) default (first opts))))
        (match
          ((eq? e (lit f64)) e)
          ((eq? e (lit c128)) e)
          ((eq? e (lit i64))
            (if (int= %word-size 8) e
              (Err raise (lit value) "Tensor: i64 needs an 8-byte word" e)))
          (#t (Err raise (lit value) "Tensor: no such encoding" e)))))

    ; c128 when an element is complex, i64 when every element is a machine
    ; integer and the word holds one, else f64.
    (method %enc-of (self xs)
      (match
        ((List any? (fn (_ x) (self %complex? x)) xs) (lit c128))
        ((if (int= %word-size 8) (List all? (fn (_ x) (type? x (type-of 0))) xs) #f) (lit i64))
        (#t (lit f64))))

    ; x/num/complex, loaded on first use as (TYPE . MAKE): a tensor of
    ; reals never needs it, and loading it would raise the peak of every
    ; program that uses Tensor.  No Complex value exists until it is
    ; loaded, so an integer or a Float is known not to be one without it.
    ; MAKE is read from the module's environment, where the load binds it.
    (%complex-cell (pair () ()))
    (method %complex (self)
      (if (null? (first (self %complex-cell)))
        (%set-first! (self %complex-cell)
          ((fn (_)
             (import x/num/complex)
             (let ((make (eval (lit make-complex) (Module env (lit x/num/complex)))))
               (pair (type-of (make 0 1)) make)))))
        ())
      (first (self %complex-cell)))
    (method %complex? (self x)
      (if (type? x (type-of 0)) #f (if (type? x float) #f (type? x (first (self %complex))))))
    (method %make-complex (self re im) ((rest (self %complex)) re im))

    (method %extent (self ext)
      (let ((e (if (type? ext (type-of 0)) (list ext) ext)))
        (if (List all? (fn (_ n) (if (type? n (type-of 0)) (not (int< n 0)) #f)) e) e
          (Err raise (lit value) "Tensor: an extent is axis lengths, integers of at least 0" ext))))

    (method %extent-of (self x)
      (match
        ((Vector vector? x) (self %extent-of (Vector ->list x)))
        ((pair? x)
          (let ((inner (List map (fn (_ y) (self %extent-of y)) x)))
            (if (List all? (fn (_ e) (equal? e (first inner))) inner)
              (pair (List length x) (first inner))
              (Err raise (lit value) "Tensor from: the lists at one depth differ in length" x))))
        ((null? x) (list 0))
        (#t ())))

    (method %flatten (self x)
      (match
        ((Vector vector? x) (self %flatten (Vector ->list x)))
        ((pair? x) (List flat-map (fn (_ y) (self %flatten y)) x))
        ((null? x) ())
        (#t (list x))))

    ; --- the fast closures ------------------------------------------------
    ; Made once, kept in a vector; (obj-ref F K) is closure K:
    ;    1 size-of EXT          2 row-major EXT         3 contiguous? ST
    ;    4 new ENC EXT          5 get ENC -> (fn A I)   6 put ENC -> (fn A I X)
    ;    7 zip WHICH ST OTHER   8 reduce WHICH ST       9 fill! ST X
    ;   10 convert ST ENC      11 view ST EXT STR OFF  12 index ST IDX
    ;   13 addr ST             14 drive NAME S        15 bits X
    ;   16 broadcast EA EB      17 assign! DST SRC
    ; A state is (ENC EXTENT STRIDES OFFSET DATA); OTHER is a state or a number.
    (%fast-cell (pair () ()))
    (method %fast (self)
      (if (null? (first (self %fast-cell)))
        (%set-first! (self %fast-cell) (self %make-fast))
        ())
      (first (self %fast-cell)))

    ; Scratch words: A 0, B 1, O 2 (addresses), AS 3, BS 4, OS 5 (strides),
    ; CNT 6, K 7, BUDGET 8, the i64 accumulator 13 and fill value 14; the f64
    ; accumulator and fill value are doubles 16 and 17, past the words on
    ; either word width, and c128's accumulator and fill value are the two
    ; doubles 16 and 17, real then imaginary.  An operand's SLOT is the words of its (address .
    ; stride): A (0 . 3), B (1 . 4), the output O (2 . 5).
    (method %make-fast (self)
      (let ((int-t (type-of 0)) (f64 (lit f64)) (c128 (lit c128))
            (fget (word-form-pure (lit (fn (_ a i) (f-ref a i)))))
            (fset (word-form-pure (lit (fn (_ a i v) (f-set! a i v)))))
            (i->d (libm-fn (lit %tensor-i->d) "i->d" ()))
            (lanes (self %lanes-cell)) (debt (self %debt-cell))
            (window (self %window)) (step-cost (self %step-cost)) (run-cost (self %run-cost))
            (jit-after (self %jit-after)) (big 1073741823))
        ; --- lists, without a dispatch a call
        (def len (fn (go l n) (if (null? l) n (go (rest l) (int+ n 1)))))
        (def nth (fn (go k l) (if (int= k 0) (first l) (go (int- k 1) (rest l)))))
        (def rev (fn (go l acc) (if (null? l) acc (go (rest l) (pair (first l) acc)))))
        (def every (fn (go p l) (if (null? l) #t (if (p (first l)) (go p (rest l)) #f))))
        (def map1 (fn (go f l) (if (null? l) () (pair (f (first l)) (go f (rest l))))))
        (def map2 (fn (go f a b) (if (null? a) () (pair (f (first a) (first b)) (go f (rest a) (rest b))))))
        (def map3 (fn (go f a b c) (if (null? a) () (pair (f (first a) (first b) (first c)) (go f (rest a) (rest b) (rest c))))))
        (def same (fn (go a b) (if (null? a) (null? b) (if (null? b) #f (if (int= (first a) (first b)) (go (rest a) (rest b)) #f)))))
        ; --- states
        (def enc-of (fn (_ st) (first st)))
        (def ext-of (fn (_ st) (first (rest st))))
        (def str-of (fn (_ st) (first (rest (rest st)))))
        (def off-of (fn (_ st) (first (rest (rest (rest st))))))
        (def data-of (fn (_ st) (first (rest (rest (rest (rest st)))))))
        (def size-of (fn (go ext) (if (null? ext) 1 (int* (first ext) (go (rest ext))))))
        (def row-major
          (fn (go ext) (if (null? ext) () (let ((r (go (rest ext)))) (pair (if (null? r) 1 (int* (first (rest ext)) (first r))) r)))))
        (def contig? (fn (_ st) (if (int< (size-of (ext-of st)) 2) #t (same (row-major (ext-of st)) (str-of st)))))
        (def width (fn (_ enc) (if (eq? enc c128) 16 8)))
        (def base (fn (_ st) (ptr->int (str->ptr (data-of st)))))
        (def addr (fn (_ st) (int+ (base st) (int* (width (enc-of st)) (off-of st)))))
        (def make (fn (_ enc ext str off data) (list enc ext str off data)))
        (def new
          (fn (_ enc ext)
            (make enc ext (row-major ext) 0 (str-make (int* (width enc) (let ((n (size-of ext))) (if (int< n 1) 1 n)))))))
        (def view (fn (_ st ext str off) (make (enc-of st) ext str off (data-of st))))
        ; --- elements
        (def bits
          (fn (_ x) (match ((type? x float) (first x)) ((type? x int-t) (i->d x)) (#t (first (float-of x))))))
        (def int-of
          (fn (_ x) (if (type? x int-t) x (Err raise (lit type) "Tensor: an i64 element is an integer" x))))
        (def cx-cell (pair () ()))
        (def cx (fn (_) (if (null? (first cx-cell)) (%set-first! cx-cell (Tensor %complex)) ()) (first cx-cell)))
        (def cx? (fn (_ x) (if (type? x int-t) #f (if (type? x float) #f (type? x (first (cx)))))))
        (def make-complex (fn (_ re im) ((rest (cx)) re im)))
        (def re-of (fn (_ x) (if (cx? x) (first (first x)) x)))
        (def im-of (fn (_ x) (if (cx? x) (rest (first x)) 0)))
        (def get
          (fn (_ enc)
            (match
              ((eq? enc f64) (fn (_ a i) (type-make-instance float (fget a i))))
              ((eq? enc c128)
                (fn (_ a i)
                  (make-complex (type-make-instance float (fget a (int* 2 i)))
                                (type-make-instance float (fget a (int+ (int* 2 i) 1))))))
              (#t (fn (_ a i) (ptr-ref-word (int->ptr a) (int* 8 i)))))))
        (def put
          (fn (_ enc)
            (match
              ((eq? enc f64)
                (fn (_ a i x)
                  (if (cx? x) (Err raise (lit type) "Tensor: a complex number needs a c128 tensor" x) ())
                  (fset a i (bits x))))
              ((eq? enc c128)
                (fn (_ a i x) (fset a (int* 2 i) (bits (re-of x))) (fset a (int+ (int* 2 i) 1) (bits (im-of x)))))
              (#t (fn (_ a i x) (ptr-set-word! (int->ptr a) (int* 8 i) (int-of x)))))))
        (def index
          (fn (_ st idx)
            (if (int= (len idx 0) (len (ext-of st) 0)) ()
              (Err raise (lit value) "Tensor: one index per axis" idx))
            (def go
              (fn (go idx ext str acc)
                (if (null? idx) acc
                  (let ((n (first ext)) (i (first idx)))
                    (let ((j (if (int< i 0) (int+ i n) i)))
                      (if (if (int< j 0) #t (not (int< j n)))
                        (Err raise (lit value) "Tensor: index out of range" i) ())
                      (go (rest idx) (rest ext) (rest str) (int+ acc (int* j (first str)))))))))
            (go idx (ext-of st) (str-of st) (off-of st))))
        ; --- memory and the lane
        (def owe!
          (fn (_ k)
            (let ((d (int+ (first debt) k)))
              (if (int< d window) (%set-first! debt d)
                (do (%set-first! debt 0) (Heap collect))))))
        (def lane
          (fn (_ name)
            (def find (fn (go l) (if (null? l) () (if (eq? (first (first l)) name) (first l) (go (rest l))))))
            (let ((e (find (first lanes))))
              (if (null? e) (Tensor %lane-new name) e))))
        (def ran!
          (fn (_ name steps)
            (owe! (int* steps step-cost))
            (let ((e (lane name)))
              (let ((t (int+ (nth 3 e) steps)))
                (%set-first! (rest (rest (rest e))) t)
                (if (int< t jit-after) () (Tensor %jit name))))))
        (def set-word! (fn (_ s i v) (ptr-set-word! (str->ptr s) (int* i %word-size) v)))
        (def drive
          (fn (_ name s)
            (let ((at (int* 8 %word-size)) (sa (ptr->int (str->ptr s))))
              (def go
                (fn (go)
                  (let ((e (lane name)))
                    (let ((c (nth 1 e)) (k (nth 2 e)))
                      (let ((b (if c big (int/ window step-cost))))
                        (ptr-set-word! (str->ptr s) at b)
                        (let ((r (k sa)))
                          (if c () (ran! name (int- b (ptr-ref-word (str->ptr s) at))))
                          (if (int= r 0) (go) ())))))))
              (go)
              (owe! run-cost))))
        ; --- runs
        ; (each OFFS STRIDES COUNT) for each run of the last axis: OFFS each
        ; state's element offset at the run's start, STRIDES its stride along
        ; the run.  STS share extent EXT.  Contiguous states are one run.
        (def runs
          (fn (_ sts ext each)
            (let ((r (len ext 0)) (n (size-of ext)))
              (match
                ((int= n 0) ())
                ((int= r 0) (each (map1 off-of sts) (map1 (fn (_ st) 0) sts) 1))
                ((every contig? sts) (each (map1 off-of sts) (map1 (fn (_ st) 1) sts) n))
                (#t
                  (let ((last (int- r 1)))
                    (def go
                      (fn (go axis offs)
                        (if (int= axis last)
                          (each offs (map1 (fn (_ st) (nth last (str-of st))) sts) (nth last ext))
                          (let ((n (nth axis ext)) (steps (map1 (fn (_ st) (nth axis (str-of st))) sts)))
                            (def walk
                              (fn (walk j offs)
                                (if (int< j n)
                                  (do (go (int+ axis 1) offs)
                                      (walk (int+ j 1) (map2 int+ offs steps)))
                                  ())))
                            (walk 0 offs)))))
                    (go 0 (map1 off-of sts))))))))
        (def apply-kernel
          (fn (_ name s sts slots ext)
            (let ((bases (map2 pair (map1 base sts) (map1 (fn (_ st) (width (enc-of st))) sts))))
              (runs sts ext
                (fn (_ offs strides cnt)
                  (map3 (fn (_ slot a o) (set-word! s (first slot) (int+ (first a) (int* (rest a) o)))) slots bases offs)
                  (map2 (fn (_ slot st) (set-word! s (rest slot) st)) slots strides)
                  (set-word! s 6 cnt)
                  (set-word! s 7 0)
                  (drive name s))))))
        (def kname (fn (_ enc which) (str->sym (Str8 append (symbol->str enc) "-" (symbol->str which)))))
        ; --- broadcasting
        (def broadcast
          (fn (_ ea eb)
            (def go
              (fn (go ra rb acc)
                (match
                  ((if (null? ra) (null? rb) #f) acc)
                  ((null? ra) (go ra (rest rb) (pair (first rb) acc)))
                  ((null? rb) (go (rest ra) rb (pair (first ra) acc)))
                  ((int= (first ra) (first rb)) (go (rest ra) (rest rb) (pair (first ra) acc)))
                  ((int= (first ra) 1) (go (rest ra) (rest rb) (pair (first rb) acc)))
                  ((int= (first rb) 1) (go (rest ra) (rest rb) (pair (first ra) acc)))
                  (#t (Err raise (lit value) "Tensor: the extents do not broadcast" (list ea eb))))))
            (go (rev ea ()) (rev eb ()) ())))
        ; ST as a view of extent EXT: missing leading axes and stretched ones step 0.
        (def stretch
          (fn (_ st ext)
            (let ((pad (int- (len ext 0) (len (ext-of st) 0))))
              (def go
                (fn (go i ext es ss)
                  (match
                    ((null? ext) ())
                    ((int< i pad) (pair 0 (go (int+ i 1) (rest ext) es ss)))
                    (#t (pair (if (if (int= (first es) 1) (not (int= (first ext) 1)) #f) 0 (first ss))
                              (go (int+ i 1) (rest ext) (rest es) (rest ss)))))))
              (view st ext (go 0 ext (ext-of st) (str-of st)) (off-of st)))))
        ; --- operations
        (def fill!
          (fn (_ st x)
            (let ((s (str-make 256)) (enc (enc-of st)))
              (match
                ((eq? enc f64) (fset (ptr->int (str->ptr s)) 17 (bits x)))
                ((eq? enc c128)
                  (do (fset (ptr->int (str->ptr s)) 16 (bits (re-of x))) (fset (ptr->int (str->ptr s)) 17 (bits (im-of x)))))
                (#t (set-word! s 14 (int-of x))))
              (apply-kernel (kname enc (lit fill)) s (list st) (list (pair 2 5)) (ext-of st))
              st)))
        (def convert
          (fn (_ st enc)
            (if (if (eq? (enc-of st) c128) (not (eq? enc c128)) #f)
              (Err raise (lit value) "Tensor: a c128 tensor has no real copy; take its real or imaginary part" enc) ())
            (let ((out (new enc (ext-of st))))
              (if (if (eq? enc (enc-of st)) (contig? st) #f)
                (mem-copy (str->ptr (data-of out)) (int->ptr (addr st)) (int* (width enc) (size-of (ext-of st))))
                (apply-kernel
                  (if (eq? enc (enc-of st)) (kname enc (lit copy))
                    (str->sym (Str8 append (symbol->str (enc-of st)) "->" (symbol->str enc))))
                  (str-make 256) (list st out) (list (pair 0 3) (pair 2 5)) (ext-of st)))
              out)))
        ; A number as a rank-0 state, in the encoding an operation with ENC needs.
        (def scalar
          (fn (_ x enc)
            (let ((e (match ((cx? x) c128)
                            ((if (eq? enc (lit i64)) (type? x int-t) #f) (lit i64))
                            (#t f64))))
              (let ((st (new e ())))
                ((put e) (addr st) 0 x)
                st))))
        (def zip
          (fn (_ which a other)
            (let ((b (if (pair? other) other (scalar other (enc-of a)))))
              (let ((enc (match
                           ((if (eq? (enc-of a) c128) #t (eq? (enc-of b) c128)) c128)
                           ((if (eq? which (lit div)) #t (if (eq? (enc-of a) f64) #t (eq? (enc-of b) f64))) f64)
                           (#t (lit i64)))))
                (if (if (eq? enc c128) (if (eq? which (lit min)) #t (eq? which (lit max))) #f)
                  (Err raise (lit value) "Tensor: complex numbers have no order" which) ())
                (let ((a (if (eq? (enc-of a) enc) a (convert a enc)))
                      (b (if (eq? (enc-of b) enc) b (convert b enc))))
                  (let ((ext (broadcast (ext-of a) (ext-of b))))
                    (let ((out (new enc ext)))
                      (apply-kernel (kname enc which) (str-make 256)
                        (list (stretch a ext) (stretch b ext) out) (list (pair 0 3) (pair 1 4) (pair 2 5)) ext)
                      out)))))))
        (def reduce
          (fn (_ which st)
            (let ((enc (enc-of st)))
              (if (if (eq? enc c128) (not (eq? which (lit sum))) #f)
                (Err raise (lit value) "Tensor: complex numbers have no order" which) ())
              (if (int= (size-of (ext-of st)) 0)
                (if (eq? which (lit sum))
                  (match ((eq? enc f64) (float-of 0)) ((eq? enc c128) (make-complex (float-of 0) (float-of 0))) (#t 0))
                  (Err raise (lit value) "Tensor: no least or greatest of no elements" ()))
                (let ((s (str-make 256)))
                  (let ((init (if (eq? which (lit sum)) 0 ((get enc) (base st) (off-of st)))))
                    (match
                      ((eq? enc f64) (fset (ptr->int (str->ptr s)) 16 (bits init)))
                      ((eq? enc c128) (do (fset (ptr->int (str->ptr s)) 16 (bits 0)) (fset (ptr->int (str->ptr s)) 17 (bits 0))))
                      (#t (set-word! s 13 init))))
                  (apply-kernel (kname enc which) s (list st) (list (pair 0 3)) (ext-of st))
                  (match
                    ((eq? enc f64) (type-make-instance float (fget (ptr->int (str->ptr s)) 16)))
                    ((eq? enc c128)
                      (make-complex (type-make-instance float (fget (ptr->int (str->ptr s)) 16))
                                    (type-make-instance float (fget (ptr->int (str->ptr s)) 17))))
                    (#t (ptr-ref-word (str->ptr s) (int* 13 %word-size)))))))))
        ; SRC broadcast into DST, an f64 state, converted from i64 if it is one.
        (def assign!
          (fn (_ dst src)
            (apply-kernel (if (eq? (enc-of src) f64) (kname f64 (lit copy)) (lit i64->f64))
              (str-make 256) (list (stretch src (ext-of dst)) dst) (list (pair 0 3) (pair 2 5)) (ext-of dst))
            dst))
        (Vector of size-of row-major contig? new get put zip reduce fill! convert view index addr drive bits
          broadcast assign!)))

    ; --- the lanes ----------------------------------------------------------
    ; As x/num/fourier's: what the pure kernels allocate is owed in objects
    ; and the heap collected once the debt passes %window.  A pure step
    ; makes %step-cost objects (arm64's first, armv7's second) and a run's
    ; dispatch %run-cost.  A kernel compiles once it has run %jit-after pure
    ; steps, about as long as compiling it takes.
    (%window 4400000)
    (%step-cost (if (int= %word-size 8) 280 2200))
    (%run-cost 6000)
    (%jit-after 50000)
    (%debt-cell (pair 0 ()))
    ; Each kernel's lane: (NAME COMPILED? FN STEPS TRIED?).
    (%lanes-cell (pair () ()))

    (method %lane-new (self name)
      (let ((e (list name #f (word-form-pure (self %form-of name)) 0 #f)))
        (%set-first! (self %lanes-cell) (pair e (first (self %lanes-cell))))
        e))

    (method %lane (self name)
      (let ((e (Assoc entry name (first (self %lanes-cell)))))
        (if (null? e) (self %lane-new name) e)))

    ; Build kernel NAME's compiled version once, through Compiled, which
    ; installs it in the lane only when the check agrees, and puts the pure
    ; one back before a state image is written.
    (method %jit (self name)
      (let ((e (self %lane name)))
        (if (List ref 4 e) ()
          (let ((pure (List ref 2 e)) (form (self %form-of name)) (check (self %check-of name)))
            (%set-first! (List drop 4 e) #t)
            (Compiled make-on-demand (str->sym (Str8 append "tensor-" (symbol->str name))) pure
              (fn (_)
                (import x/tool/word-form-jit)
                (first ((prim-ref (lit word-form) (lit jit-make)) (list form)
                        (fn (_ engine) (check (first engine))))))
              (fn (_ v)
                (%set-first! (List drop 1 e) (not (eq? v pure)))
                (%set-first! (List drop 2 e) v)))))
        name))

    ; --- kernels from other modules --------------------------------------
    ; A module built on Tensor, x/num/matrix, registers its own kernels
    ; here and runs them on the same lanes: (NAME FORM CHECK), FORM the
    ; word form and CHECK (fn (_ compiled) -> BOOL), true when the compiled
    ; kernel writes what the pure one does.  A kernel keeps the lane's
    ; convention: BUDGET in scratch word 8, answering 1 when its run is
    ; done and 0 when the budget is spent.
    (%registered-cell (pair () ()))
    (method %register! (self name form check)
      (if (null? (Assoc entry name (first (self %registered-cell))))
        (%set-first! (self %registered-cell) (pair (list name form check) (first (self %registered-cell))))
        ())
      name)
    (method %form-of (self name)
      (let ((e (Assoc entry name (first (self %registered-cell)))))
        (if (null? e) (self %form name) (List ref 1 e))))
    (method %check-of (self name)
      (let ((e (Assoc entry name (first (self %registered-cell)))))
        (if (null? e) (fn (_ compiled) (Tensor %agrees? name compiled)) (List ref 2 e))))

    ; --- the class a result takes ------------------------------------------
    ; A subclass, Matrix, keeps its class through the operations that keep
    ; what makes it one.  %make builds an instance of this class from a
    ; state for the making methods; %result-class answers the class an
    ; operation's result takes, here the class itself.
    (method %make (self st) (new-from self (list (lit st) st)))
    (method %result-class (self st) self)

    ; The compiled kernel against the pure one: both run over the same
    ; check inputs, eight elements of A and B, each into an output and a
    ; scratch of its own, and the outputs and accumulators must agree to
    ; the byte.
    (method %agrees? (self name compiled)
      (let ((enc (List ref 2 (self %spec name))) (pure (word-form-pure (self %form name)))
            (out-bytes (if (eq? (List ref 3 (self %spec name)) (lit c128)) 128 64)))
        (let ((a (self %check-input enc (list 3 -2 7 0 -5 9 1 4)))
              (b (self %check-input enc (list 2 8 -1 5 3 -4 6 2))))
          (let ((r1 (self %check-run pure a b)) (r2 (self %check-run compiled a b)))
            (if (int= (mem-cmp (str->ptr (first r1)) (str->ptr (first r2)) out-bytes) 0)
              (int= (mem-cmp (int->ptr (int+ (ptr->int (str->ptr (rest r1))) 104))
                             (int->ptr (int+ (ptr->int (str->ptr (rest r2))) 104)) 40) 0)
              #f)))))

    ; Eight elements in ENC, the address of their region: quarters for f64,
    ; and for c128 quarters with an imaginary part of their own.
    (method %check-input (self enc xs)
      (let ((f (self %fast)))
        (let ((st ((obj-ref f 4) enc (list 8))))
          (let ((put ((obj-ref f 6) enc)) (a ((obj-ref f 13) st)))
            (def go
              (fn (go i xs)
                (if (null? xs) ()
                  (do (put a i
                        (match
                          ((eq? enc (lit f64)) (f-div (float-of (first xs)) (float-of 4)))
                          ((eq? enc (lit c128))
                            (self %make-complex (f-div (float-of (first xs)) (float-of 4)) (f-div (float-of (int- 1 (first xs))) (float-of 8))))
                          (#t (first xs))))
                      (go (int+ i 1) (rest xs))))))
            (go 0 xs)
            (pair st a)))))

    ; (OUT . SCRATCH) after KERN has run over A and B on a fresh scratch.
    (method %check-run (self kern a b)
      (let ((out (str-make 128)) (s (str-make 256)) (fset (word-form-pure (lit (fn (_ a i v) (f-set! a i v))))))
        (let ((w (fn (_ i v) (ptr-set-word! (str->ptr s) (int* i %word-size) v))))
          (w 0 (rest a)) (w 1 (rest b)) (w 2 (ptr->int (str->ptr out)))
          (w 3 1) (w 4 1) (w 5 1) (w 6 8) (w 7 0) (w 8 1073741823) (w 13 3) (w 14 5)
          (fset (ptr->int (str->ptr s)) 16 (first (float-of 3)))
          (fset (ptr->int (str->ptr s)) 17 (first (float-of 5)))
          (kern (ptr->int (str->ptr s)))
          (pair out s))))

    ; --- the kernels, written once ------------------------------------------
    ; A kernel is named for its encoding and operation, f64-add, and its
    ; spec is (NAME KIND IN OUT WHICH).  map2 is O[k] = A[k] which B[k],
    ; fold is ACC = ACC which A[k] (sum, least, greatest), fill is O[k] = V,
    ; and map1 is O[k] = A[k] converted from IN to OUT.  Each answers 1 when
    ; its run is done and 0 when its budget is spent.
    (method %kernel-specs (self)
      (let ((encs (if (int= %word-size 8) (list (lit f64) (lit i64)) (list (lit f64)))))
        (List append
          (List flat-map
            (fn (_ enc)
              (List append
                (List map (fn (_ which) (list (self %name enc which) (lit map2) enc enc which))
                  (if (eq? enc (lit f64)) (list (lit add) (lit sub) (lit mul) (lit div) (lit min) (lit max))
                    (list (lit add) (lit sub) (lit mul) (lit min) (lit max))))
                (List map (fn (_ which) (list (self %name enc which) (lit fold) enc enc which))
                  (list (lit sum) (lit least) (lit greatest)))
                (list (list (self %name enc (lit fill)) (lit fill) enc enc ())
                      (list (self %name enc (lit copy)) (lit map1) enc enc ()))))
            encs)
          (List map (fn (_ which) (list (self %name (lit c128) which) (lit map2) (lit c128) (lit c128) which))
            (list (lit add) (lit sub) (lit mul) (lit div)))
          (list (list (lit c128-sum) (lit fold) (lit c128) (lit c128) (lit sum))
                (list (lit c128-fill) (lit fill) (lit c128) (lit c128) ())
                (list (lit c128-copy) (lit map1) (lit c128) (lit c128) ())
                (list (lit f64->c128) (lit map1) (lit f64) (lit c128) ()))
          (if (int= %word-size 8)
            (list (list (lit i64->f64) (lit map1) (lit i64) (lit f64) ())
                  (list (lit f64->i64) (lit map1) (lit f64) (lit i64) ())
                  (list (lit i64->c128) (lit map1) (lit i64) (lit c128) ()))
            ()))))

    (method %name (self enc which) (str->sym (Str8 append (symbol->str enc) "-" (symbol->str which))))

    (method %spec (self name)
      (let ((e (Assoc entry name (self %kernel-specs))))
        (if (null? e) (Err raise (lit value) "Tensor: no such kernel" name) e)))

    (method %form (self name)
      (let ((spec (self %spec name)))
        (let ((kind (List ref 1 spec)) (in (List ref 2 spec)) (out (List ref 3 spec)) (which (List ref 4 spec)))
          (list (lit fn) (lit (self s))
            (list (lit match)
              (list (list (lit =) (self %w 8) 0) 0)
              (list (list (lit <) (self %w 7) (self %w 6))
                (list (lit do)
                  (match
                    ((eq? out (lit c128)) (self %c128-step kind which in))
                    ((eq? kind (lit map2))
                      (self %vset out 2 5 (self %op which in (self %vref in 0 3) (self %vref in 1 4))))
                    ((eq? kind (lit fold))
                      (self %acc! in (self %op which in (self %acc in) (self %vref in 0 3))))
                    ((eq? kind (lit fill)) (self %vset out 2 5 (self %v out)))
                    (#t (self %vset out 2 5 (self %conv in out (self %vref in 0 3)))))
                  (list (lit %mem-set!) (lit s) 7 (list (lit +) (self %w 7) 1))
                  (list (lit %mem-set!) (lit s) 8 (list (lit -) (self %w 8) 1))
                  (lit (self s))))
              (lit (#t 1)))))))

    (method %w (self k) (list (lit %mem-ref) (lit s) k))

    ; --- c128 steps --------------------------------------------------------
    ; Element K's real part is the double 2 K STRIDE from the operand's
    ; address, its imaginary part the double after.  PART is 0 or 1.
    (method %cref (self addr stride part)
      (list (lit f-ref) (self %w addr)
            (list (lit +) (list (lit *) 2 (list (lit *) (self %w 7) (self %w stride))) part)))
    (method %cset (self addr stride part v)
      (list (lit f-set!) (self %w addr)
            (list (lit +) (list (lit *) 2 (list (lit *) (self %w 7) (self %w stride))) part) v))
    (method %sd (self k) (list (lit f-ref) (lit s) k))

    ; One step of a kernel whose output is c128.  The quotient is Smith's,
    ; which divides by the larger part of the divisor, with its ratio at 18
    ; and denominator at 19.
    (method %c128-step (self kind which in)
      (let ((ar (self %cref 0 3 0)) (ai (self %cref 0 3 1)) (br (self %cref 1 4 0)) (bi (self %cref 1 4 1)))
        (match
          ((eq? kind (lit fill))
            (list (lit do) (self %cset 2 5 0 (self %sd 16)) (self %cset 2 5 1 (self %sd 17))))
          ((eq? kind (lit fold))
            (list (lit do)
              (list (lit f-set!) (lit s) 16 (list (lit f+) (self %sd 16) ar))
              (list (lit f-set!) (lit s) 17 (list (lit f+) (self %sd 17) ai))))
          ((eq? kind (lit map1))
            (if (eq? in (lit c128))
              (list (lit do) (self %cset 2 5 0 ar) (self %cset 2 5 1 ai))
              (list (lit do)
                (self %cset 2 5 0 (self %conv in (lit f64) (self %vref in 0 3)))
                (self %cset 2 5 1 (list (lit i->f) 0)))))
          ((if (eq? which (lit add)) #t (eq? which (lit sub)))
            (let ((op (if (eq? which (lit add)) (lit f+) (lit f-))))
              (list (lit do) (self %cset 2 5 0 (list op ar br)) (self %cset 2 5 1 (list op ai bi)))))
          ((eq? which (lit mul))
            (list (lit do)
              (self %cset 2 5 0 (list (lit f-) (list (lit f*) ar br) (list (lit f*) ai bi)))
              (self %cset 2 5 1 (list (lit f+) (list (lit f*) ar bi) (list (lit f*) ai br)))))
          (#t
            (let ((abs (fn (_ x) (list (lit if) (list (lit f<) x (list (lit i->f) 0)) (list (lit f-) (list (lit i->f) 0) x) x)))
                  (r (self %sd 18)) (d (self %sd 19)))
              (list (lit if) (list (lit f<) (abs br) (abs bi))
                (list (lit do)
                  (list (lit f-set!) (lit s) 18 (list (lit f/) br bi))
                  (list (lit f-set!) (lit s) 19 (list (lit f+) (list (lit f*) br r) bi))
                  (self %cset 2 5 0 (list (lit f/) (list (lit f+) (list (lit f*) ar r) ai) d))
                  (self %cset 2 5 1 (list (lit f/) (list (lit f-) (list (lit f*) ai r) ar) d)))
                (list (lit do)
                  (list (lit f-set!) (lit s) 18 (list (lit f/) bi br))
                  (list (lit f-set!) (lit s) 19 (list (lit f+) br (list (lit f*) bi r)))
                  (self %cset 2 5 0 (list (lit f/) (list (lit f+) ar (list (lit f*) ai r)) d))
                  (self %cset 2 5 1 (list (lit f/) (list (lit f-) ai (list (lit f*) ar r)) d)))))))))
    ; Element K of the operand whose address is word ADDR and stride word STRIDE.
    (method %vref (self enc addr stride)
      (list (if (eq? enc (lit f64)) (lit f-ref) (lit %mem-ref-at))
            (self %w addr) (list (lit *) (self %w 7) (self %w stride))))
    (method %vset (self enc addr stride v)
      (list (if (eq? enc (lit f64)) (lit f-set!) (lit %mem-set-at!))
            (self %w addr) (list (lit *) (self %w 7) (self %w stride)) v))
    (method %acc (self enc)
      (if (eq? enc (lit f64)) (list (lit f-ref) (lit s) 16) (self %w 13)))
    (method %acc! (self enc v)
      (if (eq? enc (lit f64)) (list (lit f-set!) (lit s) 16 v) (list (lit %mem-set!) (lit s) 13 v)))
    (method %v (self enc)
      (if (eq? enc (lit f64)) (list (lit f-ref) (lit s) 17) (self %w 14)))
    (method %conv (self in out x)
      (match
        ((eq? in out) x)
        ((eq? out (lit f64)) (list (lit i->f) x))
        (#t (list (lit f->i) x))))
    ; X which Y as a form: the arithmetic, or the lesser or greater by <.
    (method %op (self which enc x y)
      (let ((f (eq? enc (lit f64))))
        (match
          ((eq? which (lit add)) (list (if f (lit f+) (lit +)) x y))
          ((eq? which (lit sum)) (list (if f (lit f+) (lit +)) x y))
          ((eq? which (lit sub)) (list (if f (lit f-) (lit -)) x y))
          ((eq? which (lit mul)) (list (if f (lit f*) (lit *)) x y))
          ((eq? which (lit div)) (list (lit f/) x y))
          ((if (eq? which (lit min)) #t (eq? which (lit least)))
            (list (lit if) (list (if f (lit f<) (lit <)) x y) x y))
          (#t (list (lit if) (list (if f (lit f<) (lit <)) y x) x y))))))

  ; --- the tensor -------------------------------------------------------------
  (method encoding (self)
    (doc "How each element is stored: f64, i64 or c128."
      (returns SYMBOL "The encoding")
      (example "((Tensor from '(1.5 2)) encoding)" "'f64"))
    (first (field (lit st))))

  (method extent (self)
    (doc "The length of each axis."
      (returns LIST "Axis lengths, outermost first")
      (example "((Tensor zeros '(2 3)) extent)" "(2 3)"))
    (first (rest (field (lit st)))))

  (method rank (self)
    (doc "The number of axes."
      (returns INTEGER "The extent's length")
      (example "((Tensor zeros '(2 3 4)) rank)" "3"))
    (List length (first (rest (field (lit st))))))

  (method size (self)
    (doc "The number of elements."
      (returns INTEGER "The product of the extent")
      (example "((Tensor zeros '(2 3)) size)" "6"))
    ((obj-ref (Tensor %fast) 1) (first (rest (field (lit st))))))

  (method strides (self)
    (doc "The elements stepped along each axis: row-major for a fresh tensor, otherwise whatever its view says. A broadcast axis steps 0."
      (returns LIST "One stride per axis")
      (example "((Tensor zeros '(2 3)) strides)" "(3 1)")
      (example "(((Tensor zeros '(2 3)) transpose) strides)" "(1 3)"))
    (first (rest (rest (field (lit st))))))

  (method contiguous? (self)
    (doc "Whether the elements lie row-major with nothing between them, so the tensor is one run of memory."
      (returns BOOL "#t for a fresh tensor, a reshape of one, or a slice of the outermost axis")
      (example "((Tensor zeros '(2 3)) contiguous?)" "#t")
      (example "(((Tensor zeros '(2 3)) transpose) contiguous?)" "#f"))
    ((obj-ref (Tensor %fast) 3) (field (lit st))))

  (method ref (self . (param idx LIST "One index per axis; negative counts from the end"))
    (doc "The element at the given indexes."
      (returns NUMBER "A Float for f64, an integer for i64, a Complex for c128")
      (example "((Tensor from '((1 2) (3 4.5))) ref 1 0)" "3.0")
      (example "((Tensor from '(1.5 2.5)) ref -1)" "2.5"))
    (let ((f (Tensor %fast)) (st (field (lit st))))
      (((obj-ref f 5) (first st)) (ptr->int (str->ptr (List ref 4 st))) ((obj-ref f 12) st idx))))

  (method set! (self . (param args LIST "One index per axis, then the value"))
    (doc "Store a value at the given indexes. A view shares its bytes, so the change shows through every tensor over them."
      (returns Tensor "self")
      (example "(((Tensor zeros 3) set! 1 9) ->list)" "(0.0 9.0 0.0)"))
    (let ((f (Tensor %fast)) (st (field (lit st)))
          (idx (List take (int- (List length args) 1) args)) (x (List last args)))
      (((obj-ref f 6) (first st)) (ptr->int (str->ptr (List ref 4 st))) ((obj-ref f 12) st idx) x)
      self))

  (method ->list (self)
    (doc "The elements as lists nested one level per axis; a rank-0 tensor answers its one element."
      (returns LIST "Nested lists of numbers")
      (example "((Tensor range 4 'f64) ->list)" "(0.0 1.0 2.0 3.0)"))
    (let ((st (field (lit st))))
      (let ((get ((obj-ref (Tensor %fast) 5) (first st))) (a (ptr->int (str->ptr (List ref 4 st)))))
        (def go
          (fn (go ext str off)
            (if (null? ext) (get a off)
              (let ((n (first ext)) (s (first str)))
                (def each (fn (each j off) (if (int< j n) (pair (go (rest ext) (rest str) off) (each (int+ j 1) (int+ off s))) ())))
                (each 0 off)))))
        (go (List ref 1 st) (List ref 2 st) (List ref 3 st)))))

  ; --- views ------------------------------------------------------------------
  (method transpose (self)
    (doc "The view with the axes in reverse order: element (i j) of a matrix's transpose is element (j i) of the matrix."
      (returns Tensor "A view sharing self's bytes")
      (example "(((Tensor from '((1 2 3) (4 5 6)) 'f64) transpose) ->list)" "((1.0 4.0) (2.0 5.0) (3.0 6.0))"))
    (let ((st (field (lit st))))
      (self %wrap ((obj-ref (Tensor %fast) 11) st (List reverse (List ref 1 st)) (List reverse (List ref 2 st)) (List ref 3 st)))))

  (method slice (self (param axis INTEGER "The axis to cut; negative counts from the end")
                      (param start INTEGER "The first index kept; negative counts from the end")
                      (param end INTEGER "The index after the last kept; negative counts from the end"))
    (doc "The view of indexes start up to end along one axis, every other axis whole."
      (returns Tensor "A view sharing self's bytes")
      (example "(((Tensor range 6 'f64) slice 0 1 4) ->list)" "(1.0 2.0 3.0)")
      (example "(((Tensor from '((1 2 3) (4 5 6)) 'f64) slice 1 1 3) ->list)" "((2.0 3.0) (5.0 6.0))"))
    (let ((st (field (lit st))) (r (self rank)))
      (let ((ax (if (int< axis 0) (int+ axis r) axis)))
        (if (if (int< ax 0) #t (not (int< ax r)))
          (Err raise (lit value) "Tensor slice: no such axis" axis) ())
        (let ((n (List ref ax (List ref 1 st))))
          (let ((s (if (int< start 0) (int+ start n) start)) (e (if (int< end 0) (int+ end n) end)))
            (if (if (int< s 0) #t (if (int< n e) #t (int< e s)))
              (Err raise (lit value) "Tensor slice: the range is outside the axis" (list start end)) ())
            (self %wrap
              ((obj-ref (Tensor %fast) 11) st
                (List map (fn (_ i len) (if (int= i ax) (int- e s) len)) (List range 0 r) (List ref 1 st))
                (List ref 2 st)
                (int+ (List ref 3 st) (int* s (List ref ax (List ref 2 st)))))))))))

  (method reshape (self (param extent INTEGER|LIST "The new axis lengths; their product must be the size"))
    (doc "The same elements in row-major order under another extent: a view when self is contiguous, else a view of a copy."
      (returns Tensor "A tensor of the new extent")
      (example "(((Tensor range 6 'f64) reshape '(2 3)) ->list)" "((0.0 1.0 2.0) (3.0 4.0 5.0))"))
    (let ((f (Tensor %fast)) (ext (Tensor %extent extent)) (st (field (lit st))))
      (if (int= ((obj-ref f 1) ext) (self size)) ()
        (Err raise (lit value) "Tensor reshape: the extent holds a different number of elements" extent))
      (let ((src (if ((obj-ref f 3) st) st ((obj-ref f 10) st (first st)))))
        (self %wrap ((obj-ref f 11) src ext ((obj-ref f 2) ext) (List ref 3 src))))))

  (method copy (self)
    (doc "A contiguous copy with bytes of its own."
      (returns Tensor "A fresh tensor of the same extent and encoding")
      (example "((((Tensor range 3 'f64) transpose) copy) ->list)" "(0.0 1.0 2.0)"))
    (let ((st (field (lit st)))) (self %wrap ((obj-ref (Tensor %fast) 10) st (first st)))))

  (method as (self (param enc SYMBOL "The encoding: f64, i64 or c128"))
    (doc "A contiguous copy in another encoding. f64 to i64 truncates toward zero; f64 or i64 to c128 gives each element a 0 imaginary part. A c128 tensor is refused: take its real or imaginary part."
      (returns Tensor "A fresh tensor of the same extent")
      (example "(((Tensor from '(1 2)) as 'f64) ->list)" "(1.0 2.0)")
      (sample "(((Tensor from '(2.5 -2.5)) as 'i64) ->list)" "(2 -2) on an 8-byte word; i64 is refused on a 4-byte word"))
    (self %wrap ((obj-ref (Tensor %fast) 10) (field (lit st)) (Tensor %enc-or (list enc) (lit f64)))))

  ; --- complex parts ----------------------------------------------------------
  (method real (self)
    (doc "The real parts: for c128 an f64 view sharing self's bytes, so writing through it changes self; for f64 or i64, self."
      (returns Tensor "An f64 view for c128, else self")
      (example "(((Tensor complex (Tensor from '(1 2)) 5) real) ->list)" "(1.0 2.0)"))
    (let ((st (field (lit st))))
      (if (eq? (first st) (lit c128)) (self %wrap (Tensor %part st 0)) self)))

  (method imaginary (self)
    (doc "The imaginary parts: for c128 an f64 view sharing self's bytes; for f64 or i64, a fresh tensor of zeros."
      (returns Tensor "An f64 view for c128, else zeros of self's extent and encoding")
      (example "(((Tensor complex (Tensor from '(1 2)) 5) imaginary) ->list)" "(5.0 5.0)"))
    (let ((st (field (lit st))) (f (Tensor %fast)))
      (if (eq? (first st) (lit c128)) (self %wrap (Tensor %part st 1))
        (self %wrap ((obj-ref f 9) ((obj-ref f 4) (first st) (List ref 1 st)) 0)))))

  (method conjugate (self)
    (doc "The complex conjugates, each imaginary part negated: a fresh c128 tensor for c128, a copy of self otherwise."
      (returns Tensor "A fresh tensor of self's extent and encoding")
      (example "((((Tensor from '(1 2)) as 'c128) conjugate) ->list)" "(1.0+0.0i 2.0+0.0i)"))
    (if (eq? (first (field (lit st))) (lit c128))
      (self %wrap ((Tensor complex (self real) ((self imaginary) mul -1)) %st))
      (self copy)))

  ; --- arithmetic -------------------------------------------------------------
  (method add (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise sum. Extents broadcast from the last axis, an axis of length 1 stretching; a c128 operand makes the result c128, else an f64 operand makes it f64."
      (returns Tensor "A fresh tensor of the broadcast extent")
      (example "(((Tensor from '(1 2 3) 'f64) add 10) ->list)" "(11.0 12.0 13.0)")
      (example "(((Tensor from '((1 2) (3 4))) add (Tensor from '(0.5 1))) ->list)" "((1.5 3.0) (3.5 5.0))"))
    (self %zip (lit add) other))

  (method sub (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise difference, self minus other, broadcast as add is."
      (returns Tensor "A fresh tensor of the broadcast extent")
      (example "(((Tensor from '(5 7) 'f64) sub 2) ->list)" "(3.0 5.0)"))
    (self %zip (lit sub) other))

  (method mul (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise product, broadcast as add is. An i64 product wraps at 64 bits."
      (returns Tensor "A fresh tensor of the broadcast extent")
      (example "(((Tensor from '(1 2 3) 'f64) mul (Tensor from '(4 5 6))) ->list)" "(4.0 10.0 18.0)"))
    (self %zip (lit mul) other))

  (method div (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise quotient, self over other, in f64, or c128 when either operand is, broadcast as add is."
      (returns Tensor "A fresh f64 or c128 tensor of the broadcast extent")
      (example "(((Tensor from '(1 2 3)) div 2) ->list)" "(0.5 1.0 1.5)"))
    (self %zip (lit div) other))

  (method min (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise lesser, broadcast as add is. Against a NaN the other operand is kept. c128 is refused: complex numbers have no order."
      (returns Tensor "A fresh tensor of the broadcast extent")
      (example "(((Tensor from '(1 5 3) 'f64) min 2) ->list)" "(1.0 2.0 2.0)"))
    (self %zip (lit min) other))

  (method max (self (param other Tensor|NUMBER "A tensor that broadcasts with self, or a number"))
    (doc "The element-wise greater, broadcast as add is. Against a NaN the other operand is kept. c128 is refused: complex numbers have no order."
      (returns Tensor "A fresh tensor of the broadcast extent")
      (example "(((Tensor from '(1 5 3) 'f64) max 2) ->list)" "(2.0 5.0 3.0)"))
    (self %zip (lit max) other))

  ; --- reductions -------------------------------------------------------------
  (method sum (self)
    (doc "The sum of every element: a Float for f64, an integer (wrapping at 64 bits) for i64, a Complex for c128."
      (returns NUMBER "The sum; 0 for no elements")
      (example "((Tensor from '((1 2) (3 4)) 'f64) sum)" "10.0")
      (example "((Tensor range 4 'f64) sum)" "6.0"))
    ((obj-ref (Tensor %fast) 8) (lit sum) (field (lit st))))

  (method least (self)
    (doc "The least element. A NaN loses to every number. c128 is refused: complex numbers have no order."
      (returns NUMBER "The least element; a raise for no elements")
      (example "((Tensor from '(3 -1 2) 'f64) least)" "-1.0"))
    ((obj-ref (Tensor %fast) 8) (lit least) (field (lit st))))

  (method greatest (self)
    (doc "The greatest element. A NaN loses to every number. c128 is refused: complex numbers have no order."
      (returns NUMBER "The greatest element; a raise for no elements")
      (example "((Tensor from '(3 -1 2) 'f64) greatest)" "3.0"))
    ((obj-ref (Tensor %fast) 8) (lit greatest) (field (lit st))))

  (method mean (self)
    (doc "The mean of every element: a Float, or a Complex for c128."
      (returns NUMBER "The sum over the size")
      (example "((Tensor from '(1 2 3 4)) mean)" "2.5"))
    (let ((n (self size)))
      (if (int= n 0) (Err raise (lit value) "Tensor mean: no elements" ())
        (if (eq? (self encoding) (lit c128))
          (Tensor %make-complex (f-div ((self real) sum) (float-of n)) (f-div ((self imaginary) sum) (float-of n)))
          (f-div (float-of (self sum)) (float-of n))))))

  ; --- inside -----------------------------------------------------------------
  (method %st (self) (field (lit st)))
  (method %wrap (self st)
    (let ((c ((class-of self) %result-class st))) (new-from c (list (lit st) st))))
  (method %zip (self which other)
    (self %wrap
      ((obj-ref (Tensor %fast) 7) which (field (lit st))
        (if (if (object? other) (instance-of? other Tensor) #f) (other %st) other)))))

(doc (provide x/num/tensor Tensor)
  "Tensor: n-dimensional arrays of f64, i64 or c128 packed in bytes, with views that share them, broadcasting element-wise arithmetic and reductions run in kernels that compile once they have run long enough."
  (example "(((Tensor range 6 'f64) reshape '(2 3)) sum)" "15.0"))
