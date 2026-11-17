# Metal: buffers shared with the GPU, and kernels run over them
# @weight 2

Metal loaded with dlopen, the way Sdl loads SDL3. The framework is on
macOS only, so each case asks `(Metal available?)` first and, on a host
with no Metal device, answers what the device would have: the file passes
everywhere and tests the GPU where there is one.

## the device

### available? answers a boolean on any host

```x
(do (import x/sys/darwin/metal)
  (boolean? (Metal available?)))
```
---
    #t

### the device has a name

```x
(do (import x/sys/darwin/metal)
  (if (Metal available?)
    (< 0 (Str8 length (Metal device-name)))
    #t))
```
---
    #t

### with no device, a message that needs one raises a label io

```x
(do (import x/sys/darwin/metal)
  (if (Metal available?)
    (lit (io io))
    (list (guard (e (Err label e)) (Metal buffer 8))
          (guard (e (Err label e)) (Metal device-name)))))
```
---
    ('io 'io)

## buffers

### a fresh buffer is zeros, and a word written through its pointer reads back

```x
(do (import x/sys/darwin/metal) (import x/core/doors ptr-ref-word ptr-set-word!)
  (if (Metal available?)
    (do (def buf (Metal buffer 16))
        (def before (list (ptr-ref-word (Metal pointer buf) 0) (ptr-ref-word (Metal pointer buf) 8)))
        (ptr-set-word! (Metal pointer buf) 8 77)
        (def after (ptr-ref-word (Metal pointer buf) 8))
        (Metal release buf)
        (list before after))
    (lit ((0 0) 77))))
```
---
    ((0 0) 77)

## kernels

### a kernel run across a width doubles each element in place

```x
(do (import x/sys/darwin/metal) (import x/core/doors ptr-ref ptr-set!)
  (if (Metal available?)
    (do (def buf (Metal buffer 16))
        (def p (Metal pointer buf))
        (List for-each (fn (_ i) (ptr-set! p (* 4 i) (+ i 1) 4)) (list 0 1 2 3))
        (def twice (Metal compile "kernel void twice(device uint* a [[buffer(0)]], uint2 at [[thread_position_in_grid]]) { a[at.x] *= 2; }" "twice"))
        (Metal run twice (list buf) 4 1)
        (def out (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3)))
        (Metal release twice)
        (Metal release buf)
        out)
    (lit (2 4 6 8))))
```
---
    (2 4 6 8)

### a pipeline runs again, on the bytes the last run left

```x
(do (import x/sys/darwin/metal) (import x/core/doors ptr-ref ptr-set!)
  (if (Metal available?)
    (do (def buf (Metal buffer 4))
        (def p (Metal pointer buf))
        (ptr-set! p 0 1 4)
        (def twice (Metal compile "kernel void twice(device uint* a [[buffer(0)]], uint2 at [[thread_position_in_grid]]) { a[at.x] *= 2; }" "twice"))
        (let go ((i 0)) (when (< i 10) (do (Metal run twice (list buf) 1 1) (go (+ i 1)))))
        (def out (ptr-ref p 0 4))
        (Metal release twice)
        (Metal release buf)
        out)
    1024))
```
---
    1024

### a kernel is called once for each point of the grid, x across and y down

```x
(do (import x/sys/darwin/metal) (import x/core/doors ptr-ref)
  (if (Metal available?)
    (do (def buf (Metal buffer 24))
        (def p (Metal pointer buf))
        (def number (Metal compile "kernel void number(device uint* a [[buffer(0)]], uint2 at [[thread_position_in_grid]]) { a[at.y * 3 + at.x] = at.y * 10 + at.x; }" "number"))
        (Metal run number (list buf) 3 2)
        (def out (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3 4 5)))
        (Metal release number)
        (Metal release buf)
        out)
    (lit (0 1 2 10 11 12))))
```
---
    (0 1 2 10 11 12)

### buffers are bound in order: a product of two 2 x 2 matrices of 32-bit floats

The elements are written and read as the bits of single floats: 1.0 to
4.0 going in, and 7.0, 10.0, 15.0 and 22.0 coming out.

```x
(do (import x/sys/darwin/metal) (import x/core/doors ptr-ref ptr-set!)
  (if (Metal available?)
    (do (def a (Metal buffer 16))
        (def c (Metal buffer 16))
        (def dims (Metal buffer 12))
        (List for-each (fn (_ at) (ptr-set! (Metal pointer a) (* 4 (first at)) (rest at) 4))
          (lit ((0 . 1065353216) (1 . 1073741824) (2 . 1077936128) (3 . 1082130432))))
        (List for-each (fn (_ i) (ptr-set! (Metal pointer dims) (* 4 i) 2 4)) (list 0 1 2))
        (def product (Metal compile "kernel void product(device const float* a [[buffer(0)]], device const float* b [[buffer(1)]], device float* c [[buffer(2)]], device const uint* dims [[buffer(3)]], uint2 at [[thread_position_in_grid]]) { uint m = dims[1], k = dims[2]; float sum = 0.0f; for (uint j = 0; j < m; j++) sum += a[at.y * m + j] * b[j * k + at.x]; c[at.y * k + at.x] = sum; }" "product"))
        (Metal run product (list a a c dims) 2 2)
        (def out (List map (fn (_ i) (ptr-ref (Metal pointer c) (* 4 i) 4)) (list 0 1 2 3)))
        (Metal release product)
        (List for-each (fn (_ buf) (Metal release buf)) (list a c dims))
        out)
    (lit (1088421888 1092616192 1097859072 1102053376))))
```
---
    (1088421888 1092616192 1097859072 1102053376)

## errors

### source that does not compile raises a label value

```x
(do (import x/sys/darwin/metal)
  (if (Metal available?)
    (guard (e (Err label e)) (Metal compile "kernel void k( {" "k"))
    (lit value)))
```
---
    'value

### a name the source has no kernel for raises a label value, and says so

```x
(do (import x/sys/darwin/metal)
  (if (Metal available?)
    (guard (e (list (Err label e) (e msg)))
      (Metal compile "kernel void k(device uint* a [[buffer(0)]]) { }" "other"))
    (lit (value "Metal compile: no kernel named other"))))
```
---
    ('value "Metal compile: no kernel named other")
