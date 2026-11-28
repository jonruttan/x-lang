# Vulkan: buffers shared with the GPU, and grid forms run over them
# @weight 2

Vulkan loaded with dlopen, the way Sdl loads SDL3. Each case asks
`(Vulkan available?)` first and, on a host with no Vulkan device, answers
what the device would have: the file passes everywhere and tests the
device where there is one. A software device counts: where lavapipe is
installed these cases run on it.

## the device

### available? answers a boolean on any host

```x
(do (import x/sys/vulkan)
  (boolean? (Vulkan available?)))
```
---
    #t

### the device has a name

```x
(do (import x/sys/vulkan)
  (if (Vulkan available?)
    (< 0 (Str8 length (Vulkan device-name)))
    #t))
```
---
    #t

### with no device, a message that needs one raises a label io

```x
(do (import x/sys/vulkan)
  (if (Vulkan available?)
    (lit (io io))
    (list (guard (e (Err label e)) (Vulkan buffer 8))
          (guard (e (Err label e)) (Vulkan device-name)))))
```
---
    ('io 'io)

### a discrete GPU is taken before an integrated one, and a software device last

Vulkan numbers a device's type: 1 integrated, 2 discrete, 3 virtual, 4 a
software device. The lowest rank is taken.

```x
(do (import x/sys/vulkan)
  (List map (fn (_ kind) (Vulkan %rank kind)) (list 2 1 3 4 0)))
```
---
    (0 1 2 3 4)

## buffers

### a fresh buffer is zeros, and a word written through its pointer reads back

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref-word ptr-set-word!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 16))
        (def before (list (ptr-ref-word (Vulkan pointer buf) 0) (ptr-ref-word (Vulkan pointer buf) 8)))
        (ptr-set-word! (Vulkan pointer buf) 8 77)
        (def after (ptr-ref-word (Vulkan pointer buf) 8))
        (Vulkan release buf)
        (list before after))
    (lit ((0 0) 77))))
```
---
    ((0 0) 77)

## kernels

### a kernel run across a width doubles each element in place

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 16))
        (def p (Vulkan pointer buf))
        (List for-each (fn (_ i) (ptr-set! p (* 4 i) (+ i 1) 4)) (list 0 1 2 3))
        (def twice (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x (* 2 (i32-ref a at-x))))) "twice"))
        (Vulkan run twice (list buf) 4 1)
        (def out (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3)))
        (Vulkan release twice)
        (Vulkan release buf)
        out)
    (lit (2 4 6 8))))
```
---
    (2 4 6 8)

### a grid is covered by whole groups, and a thread past it does nothing

A row is run in groups of 64. Of 100 elements the first 70 are the grid:
two groups, 128 threads, of which the last 58 are past it and leave the
elements after the 70th as they were.

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 400))
        (def p (Vulkan pointer buf))
        (def one (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x 1))) "one"))
        (Vulkan run one (list buf) 70 1)
        (def out (List fold (fn (_ sum i) (+ sum (ptr-ref p (* 4 i) 4))) 0 (List range 0 100)))
        (Vulkan release one)
        (Vulkan release buf)
        out)
    70))
```
---
    70

### a pipeline runs again, on the bytes the last run left

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 4))
        (def p (Vulkan pointer buf))
        (ptr-set! p 0 1 4)
        (def twice (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x (* 2 (i32-ref a at-x))))) "twice"))
        (let go ((i 0)) (when (< i 10) (do (Vulkan run twice (list buf) 1 1) (go (+ i 1)))))
        (def out (ptr-ref p 0 4))
        (Vulkan release twice)
        (Vulkan release buf)
        out)
    1024))
```
---
    1024

### steps run in order in one command buffer, each on what the last left

A step is a kernel's run made ready. Three steps here are three kernels'
runs in one command buffer, waited for once: add 1, double, add 1.

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 4))
        (def p (Vulkan pointer buf))
        (ptr-set! p 0 3 4)
        (def twice (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x (* 2 (i32-ref a at-x))))) "twice"))
        (def more (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x (+ 1 (i32-ref a at-x))))) "more"))
        (def up (Vulkan %step more (list buf) 1 1))
        (Vulkan %run-steps (list up (Vulkan %step twice (list buf) 1 1) up))
        (def out (ptr-ref p 0 4))
        (Vulkan release twice)
        (Vulkan release more)
        (Vulkan release buf)
        out)
    9))
```
---
    9

### a kernel is called once for each point of the grid, x across and y down

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 24))
        (def p (Vulkan pointer buf))
        (def number (Vulkan %kernel (lit (fn (_ a) (i32-set! a (+ (* at-y 3) at-x) (+ (* at-y 10) at-x)))) "number"))
        (Vulkan run number (list buf) 3 2)
        (def out (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3 4 5)))
        (Vulkan release number)
        (Vulkan release buf)
        out)
    (lit (0 1 2 10 11 12))))
```
---
    (0 1 2 10 11 12)

### a kernel compiled for a row is compiled again for a grid

One pipeline is run on a row and then on a grid two points down: the
kernel is compiled for each shape, and writes each point's place across.

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 24))
        (def p (Vulkan pointer buf))
        (def across (Vulkan %kernel (lit (fn (_ a) (i32-set! a (+ (* at-y 3) at-x) (+ 1 at-x)))) "across"))
        (Vulkan run across (list buf) 3 1)
        (def row (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3 4 5)))
        (Vulkan run across (list buf) 3 2)
        (def grid (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 1 2 3 4 5)))
        (Vulkan release across)
        (Vulkan release buf)
        (list row grid))
    (lit ((1 2 3 0 0 0) (1 2 3 1 2 3)))))
```
---
    ((1 2 3 0 0 0) (1 2 3 1 2 3))

### buffers are bound in order: a product of two 2 x 2 matrices of 32-bit floats

The elements are written and read as the bits of single floats: 1.0 to
4.0 going in, and 7.0, 10.0, 15.0 and 22.0 coming out.

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def a (Vulkan buffer 16))
        (def c (Vulkan buffer 16))
        (def dims (Vulkan buffer 12))
        (List for-each (fn (_ at) (ptr-set! (Vulkan pointer a) (* 4 (first at)) (rest at) 4))
          (lit ((0 . 1065353216) (1 . 1073741824) (2 . 1077936128) (3 . 1082130432))))
        (List for-each (fn (_ i) (ptr-set! (Vulkan pointer dims) (* 4 i) 2 4)) (list 0 1 2))
        (def product
          (Vulkan %kernel
            (lit (fn (_ a b c dims)
                   (let ((m (i32-ref dims 1)) (k (i32-ref dims 2)))
                     (f32-set! c (+ (* at-y k) at-x)
                       (let sum ((j 0) (s (i->f 0)))
                         (if (< j m)
                           (sum (+ j 1) (f+ s (f* (f32-ref a (+ (* at-y m) j)) (f32-ref b (+ (* j k) at-x)))))
                           s))))))
            "product"))
        (Vulkan run product (list a a c dims) 2 2)
        (def out (List map (fn (_ i) (ptr-ref (Vulkan pointer c) (* 4 i) 4)) (list 0 1 2 3)))
        (Vulkan release product)
        (List for-each (fn (_ buf) (Vulkan release buf)) (list a c dims))
        out)
    (lit (1088421888 1092616192 1097859072 1102053376))))
```
---
    (1088421888 1092616192 1097859072 1102053376)

### a team's sum is the same in every member

A point's team is 32 threads. Each takes the element at its own place,
team-sum adds the 32 up, and every member writes the sum over its
element: 32 elements of 1.0 become 32 of 32.0, whose bits are 1107296256.

```x
(do (import x/sys/vulkan) (import x/core/doors ptr-ref ptr-set!)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 128))
        (def p (Vulkan pointer buf))
        (List for-each (fn (_ i) (ptr-set! p (* 4 i) 1065353216 4)) (List range 0 32))
        (def all (Vulkan %kernel (lit (fn (_ a) (let ((s (team-sum (f32-ref a member)))) (f32-set! a member s)))) "all"))
        (Vulkan run all (list buf) 1 1)
        (def out (List map (fn (_ i) (ptr-ref p (* 4 i) 4)) (list 0 15 31)))
        (Vulkan release all)
        (Vulkan release buf)
        out)
    (lit (1107296256 1107296256 1107296256))))
```
---
    (1107296256 1107296256 1107296256)

## errors

### a form that is not a grid form raises a label value

A pipeline is made from the form before any device is asked for, so this
is refused on every host.

```x
(do (import x/sys/vulkan)
  (guard (e (Err label e)) (Vulkan %kernel (lit (fn (_ a) (sin (f32-ref a 0)))) "k")))
```
---
    'value

### buffers that are not as many as the form's raise a label value

```x
(do (import x/sys/vulkan)
  (if (Vulkan available?)
    (do (def buf (Vulkan buffer 4))
        (def k (Vulkan %kernel (lit (fn (_ a b) (i32-set! a 0 (i32-ref b 0)))) "k"))
        (def r (guard (e (Err label e)) (Vulkan run k (list buf) 1 1)))
        (Vulkan release buf)
        r)
    (lit value)))
```
---
    'value
