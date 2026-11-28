# grid forms: a kernel written once, as each GPU backend takes it
# @weight 1

A grid form is a `(fn ...)` form over 32-bit words and singles, run once
for each point of a grid on a GPU. `grid-form-metal` answers it in the
Metal Shading Language, and `x/tool/spirv` as the SPIR-V Vulkan takes;
both are text and words, so these cases need no GPU.

## the Metal Shading Language

### a buffer is bound at its parameter's place, and holds what its loads say

`a` is loaded as singles and `n` as words, so the first is a buffer of
floats and the second of ints.

```x
(import x/tool/grid-form grid-form-metal)
(let ((text (grid-form-metal (lit (fn (_ a n) (if (< at-x (i32-ref n 0)) (f32-set! a at-x (f32-ref a at-x))))) "copy")))
  (list (Str8 includes? "kernel void copy(" text)
        (Str8 includes? "device float* b0 [[buffer(0)]]" text)
        (Str8 includes? "device int* b1 [[buffer(1)]]" text)))
```
---
    (#t #t #t)

### a loop is a named let called in tail position

```x
(import x/tool/grid-form grid-form-metal)
(let ((text (grid-form-metal
              (lit (fn (_ a) (f32-set! a 0 (let go ((j 0) (s (i->f 0))) (if (< j 4) (go (+ j 1) (f+ s (f32-ref a j))) s)))))
              "sum")))
  (list (Str8 includes? "for (;;) {" text) (Str8 includes? "continue;" text) (Str8 includes? "break;" text)))
```
---
    (#t #t #t)

### a form that names a team takes a simdgroup to a point

With no team a point is a thread; with one, a point is 32 threads across
and team-sum is the simdgroup's sum.

```x
(import x/tool/grid-form grid-form-metal)
(let ((flat (grid-form-metal (lit (fn (_ a) (f32-set! a at-x (i->f at-x)))) "flat"))
      (team (grid-form-metal (lit (fn (_ a) (let ((s (team-sum (f32-ref a member)))) (if (= member 0) (f32-set! a at-x s))))) "team")))
  (list (Str8 includes? "int(at.x)" flat) (Str8 includes? "simdgroup" flat)
        (Str8 includes? "int(at.x / 32)" team) (Str8 includes? "simd_sum(" team)
        (Str8 includes? "thread_index_in_simdgroup" team)))
```
---
    (#t #f #t #t #t)

### a Float in the form is a constant

```x
(import x/tool/grid-form grid-form-metal)
(import x/num/float float-of)
(Str8 includes? "(0.5f)"
  (grid-form-metal (list (lit fn) (lit (_ a)) (list (lit f32-set!) (lit a) 0 (list (lit f*) (float-of "0.5") (lit (f32-ref a 0))))) "half"))
```
---
    #t

## refusals

### what is not a grid form raises a label value

An unknown operator, a float where an integer goes, a loop called where
its value is, a buffer loaded as both, and a name that is not bound.

```x
(import x/tool/grid-form grid-form-metal)
(List map
  (fn (_ form) (guard (e (Err label e)) (grid-form-metal form "k")))
  (lit ((fn (_ a) (sin (f32-ref a 0)))
        (fn (_ a) (f32-ref a (i->f 0)))
        (fn (_ a) (let go ((j 0)) (+ 1 (go j))))
        (fn (_ a) (f32-set! a 0 (i->f (i32-ref a 0))))
        (fn (_ a) (f32-set! a 0 b))
        (lambda (a) a))))
```
---
    ('value 'value 'value 'value 'value 'value)

## SPIR-V

### a module opens with SPIR-V's number and its version, 1.3

The words are four bytes each, the lowest first. The fourth is the bound,
one above the last id.

```x
(import x/tool/grid-form grid-form-plan)
(import x/tool/spirv)
(import x/core/doors ptr-ref str->ptr)
(let ((made (Spirv %kernel (grid-form-plan (lit (fn (_ a) (f32-set! a at-x (i->f at-y))))) 8 8)))
  (let ((word (fn (_ i) (ptr-ref (str->ptr (first made)) (* 4 i) 4))))
    (list (word 0) (word 1) (< 0 (word 3)) (= 0 (% (rest made) 4))
          ; the last instruction ends the function
          (word (- (/ (rest made) 4) 1)))))
```
---
    (119734787 66304 #t #t 65592)

### the group is the one asked for, and 32 by 1 for a team

The execution mode's instruction is six words: its length and number, the
entry point, LocalSize (17), and the group across, down and deep.

```x
(import x/tool/grid-form grid-form-plan)
(import x/tool/spirv)
(import x/core/doors ptr-ref str->ptr)
(let ((group
        (fn (_ form across down)
          (let ((made (Spirv %kernel (grid-form-plan form) across down)))
            (let ((word (fn (_ i) (ptr-ref (str->ptr (first made)) (* 4 i) 4))))
              (let find ((i 5))
                (if (if (= (word i) 393232) (= (word (+ i 2)) 17) #f)
                  (list (word (+ i 3)) (word (+ i 4)) (word (+ i 5)))
                  (find (+ i 1)))))))))
  (list (group (lit (fn (_ a) (f32-set! a at-x (i->f at-y)))) 8 8)
        (group (lit (fn (_ a) (f32-set! a at-x (i->f at-y)))) 64 1)
        (group (lit (fn (_ a) (let ((s (team-sum (f32-ref a member)))) (if (= member 0) (f32-set! a at-x s))))) 64 1)))
```
---
    ((8 8 1) (64 1 1) (32 1 1))
