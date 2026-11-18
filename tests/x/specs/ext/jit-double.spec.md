# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

The JIT's double operations: (f+ a b), f-, f*, f/, f-sqrt, the
comparisons f< and f=, and the conversions i->f and f->i, on words holding
IEEE 754 bit patterns, the payload of a Float and of a double in memory;
and f32-ref and f32-set!, which read and store a single in memory as a
double.
Unlabelled: both 64-bit backends compile the same forms. A double fills
an 8-byte word only, so on a 4-byte word the compile refuses, and each
case answers what the 8-byte compile does when it cannot run, as text: a
decimal past 2^31 is no machine integer on a 4-byte word. Bit
patterns used: 1.0 4607182418800017408, 2.0 4611686018427387904, 3.0
4613937818241073152, 1.5 4609434218613702656, 0.5 4602678819172646912, 2.5
4612811918334230528, 6.0 4618441417868443648, 1000.0 4652007308841189376,
4.0 4616189618054758400, 7.0 4619567317775286272, 9.0 4621256167635550208,
-2.5 -4610560118520545280, 4.5 4616752568008179712, a quiet NaN 9221120237041090560.

## arithmetic

### f+: 1.0 + 2.0 is 3.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f+ a b))) 4607182418800017408 4611686018427387904)
  "4613937818241073152"))
```
---
    4613937818241073152

### f-: 3.0 - 1.0 is 2.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f- a b))) 4613937818241073152 4607182418800017408)
  "4611686018427387904"))
```
---
    4611686018427387904

### f*: 2.0 * 1.5 is 3.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f* a b))) 4611686018427387904 4609434218613702656)
  "4613937818241073152"))
```
---
    4613937818241073152

### f/: 1.0 / 2.0 is 0.5

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f/ a b))) 4607182418800017408 4611686018427387904)
  "4602678819172646912"))
```
---
    4602678819172646912

### nested: (1.0 + 2.0) * 2.0 is 6.0, the left operand kept across the right

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b c) (f* (f+ a b) c))) 4607182418800017408 4611686018427387904 4611686018427387904)
  "4618441417868443648"))
```
---
    4618441417868443648

### through memory: 1.0 and 1.5 loaded, summed to 2.5 and stored back

```x
(display (if (= %word-size 8)
  (do (import x/core/doors str-make str->ptr ptr->int ptr-set-word! ptr-ref-word)
      (def buf (str-make 16))
      (def p (ptr->int (str->ptr buf)))
      (ptr-set-word! (str->ptr buf) 0 4607182418800017408)
      (ptr-set-word! (str->ptr buf) 8 4609434218613702656)
      ((compile-asm '(fn (_ a) (%mem-set-at! a 0 (f+ (%mem-ref-at a 0) (%mem-ref-at a 1))))) p)
      (ptr-ref-word (str->ptr buf) 0))
  "4612811918334230528"))
```
---
    4612811918334230528

### a tail loop: 1.0 added 1000 times is 1000.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (self n acc one) (if (= n 0) acc (self (- n 1) (f+ acc one) one))))
   1000 0 4607182418800017408)
  "4652007308841189376"))
```
---
    4652007308841189376

## square root, comparisons and conversions

### f-sqrt: the square root of 9.0 is 3.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a) (f-sqrt a))) 4621256167635550208)
  "4613937818241073152"))
```
---
    4613937818241073152

### f<: 1.0 < 2.0 is 1

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f< a b))) 4607182418800017408 4611686018427387904)
  "1"))
```
---
    1

### f<: 2.0 < 1.0 is 0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f< a b))) 4611686018427387904 4607182418800017408)
  "0"))
```
---
    0

### f<: a NaN is less than nothing

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f< a b))) 9221120237041090560 4607182418800017408)
  "0"))
```
---
    0

### f=: 2.0 = 2.0 is 1

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f= a b))) 4611686018427387904 4611686018427387904)
  "1"))
```
---
    1

### f=: a NaN is not equal to itself

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (f= a b))) 9221120237041090560 9221120237041090560)
  "0"))
```
---
    0

### f< decides an if

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (if (f< a b) 10 20))) 4611686018427387904 4607182418800017408)
  "20"))
```
---
    20

### i->f: 7 is 7.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ n) (i->f n))) 7)
  "4619567317775286272"))
```
---
    4619567317775286272

### f->i: 2.5 truncates to 2

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a) (f->i a))) 4612811918334230528)
  "2"))
```
---
    2

### f->i: -2.5 truncates toward zero, to -2

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a) (f->i a))) -4610560118520545280)
  "-2"))
```
---
    -2

### a mean: (7.0 + 2.0) / i->f 2, through every kind of operation

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b n) (f/ (f+ a b) (i->f n)))) 4619567317775286272 4611686018427387904 2)
  "4616752568008179712"))
```
---
    4616752568008179712

## the pure twin

word-form-pure runs the same forms through x/num/float's stubs, and answers
the same bits; its comparisons answer #t and #f, as int< does.

### word-form-pure: f-sqrt of 9.0 is 3.0

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure) ((word-form-pure '(fn (_ a) (f-sqrt a))) 4621256167635550208))
  "4613937818241073152"))
```
---
    4613937818241073152

### word-form-pure: f< and f= answer #t and #f

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure) (list ((word-form-pure '(fn (_ a b) (f< a b))) 4607182418800017408 4611686018427387904) ((word-form-pure '(fn (_ a b) (f= a b))) 9221120237041090560 9221120237041090560)))
  "(#t #f)"))
```
---
    (#t #f)

### word-form-pure: i->f and f->i

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure) (list ((word-form-pure '(fn (_ n) (i->f n))) 7) ((word-form-pure '(fn (_ a) (f->i a))) -4610560118520545280)))
  "(4619567317775286272 -2)"))
```
---
    (4619567317775286272 -2)

### word-form-pure and compile-asm agree on a mean

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure) (def %form '(fn (_ a b n) (f/ (f+ a b) (i->f n)))) (= ((word-form-pure %form) 4619567317775286272 4611686018427387904 2) ((compile-asm %form) 4619567317775286272 4611686018427387904 2)))
  "#t"))
```
---
    #t

## singles in memory

(f32-ref a i) is the single, a 32-bit float, at a + 4i bytes as a double,
and (f32-set! a i v) stores the double v there rounded to a single and
answers v. Single bit patterns used: 1.0 1065353216, 1.5 1069547520, 3.0
1077936128, the single nearest 0.1 1036831949, the single nearest a third
1051372203; and the double 0.1 4591870180066957722.

### f32-ref: the single 1.5 at index 1 reads as the double 1.5

```x
(display (if (= %word-size 8)
  (do (import x/core/doors str-make str->ptr ptr->int ptr-set!)
      (def buf (str-make 8))
      (ptr-set! (str->ptr buf) 0 0 4)
      (ptr-set! (str->ptr buf) 4 1069547520 4)
      ((compile-asm '(fn (_ a) (f32-ref a 1))) (ptr->int (str->ptr buf))))
  "4609434218613702656"))
```
---
    4609434218613702656

### f32-set!: the double 0.1 is stored as the nearest single, the singles either side are left, and the double is answered

```x
(display (if (= %word-size 8)
  (do (import x/core/doors str-make str->ptr ptr->int ptr-ref ptr-set!)
      (def buf (str-make 12))
      (ptr-set! (str->ptr buf) 0 286331153 4)
      (ptr-set! (str->ptr buf) 4 0 4)
      (ptr-set! (str->ptr buf) 8 286331153 4)
      (def v ((compile-asm '(fn (_ a v) (f32-set! a 1 v))) (ptr->int (str->ptr buf)) 4591870180066957722))
      (list v (ptr-ref (str->ptr buf) 0 4) (ptr-ref (str->ptr buf) 4 4) (ptr-ref (str->ptr buf) 8 4)))
  "(4591870180066957722 286331153 1036831949 286331153)"))
```
---
    (4591870180066957722 286331153 1036831949 286331153)

### word-form-pure: f32-ref and f32-set! answer and store the same

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure)
      (import x/core/doors str-make str->ptr ptr->int ptr-ref ptr-set!)
      (def buf (str-make 12))
      (ptr-set! (str->ptr buf) 0 1069547520 4)
      (ptr-set! (str->ptr buf) 4 0 4)
      (ptr-set! (str->ptr buf) 8 286331153 4)
      (def p (ptr->int (str->ptr buf)))
      (list ((word-form-pure '(fn (_ a) (f32-ref a 0))) p)
            ((word-form-pure '(fn (_ a v) (f32-set! a 1 v))) p 4591870180066957722)
            (ptr-ref (str->ptr buf) 4 4) (ptr-ref (str->ptr buf) 8 4)))
  "(4609434218613702656 4591870180066957722 1036831949 286331153)"))
```
---
    (4609434218613702656 4591870180066957722 1036831949 286331153)

### word-form-pure and compile-asm agree on a quotient of singles: 1.0 over 3.0 is the single nearest a third

```x
(display (if (= %word-size 8)
  (do (import x/tool/word-form word-form-pure)
      (import x/core/doors str-make str->ptr ptr->int ptr-ref ptr-set!)
      (def %form '(fn (_ a) (f32-set! a 2 (f/ (f32-ref a 0) (f32-ref a 1)))))
      (def run (fn (_ f)
        (def buf (str-make 12))
        (ptr-set! (str->ptr buf) 0 1065353216 4)
        (ptr-set! (str->ptr buf) 4 1077936128 4)
        (ptr-set! (str->ptr buf) 8 0 4)
        (f (ptr->int (str->ptr buf)))
        (ptr-ref (str->ptr buf) 8 4)))
      (list (run (word-form-pure %form)) (run (compile-asm %form))))
  "(1051372203 1051372203)"))
```
---
    (1051372203 1051372203)

## refusals

### an object parameter is not a double

```x
(guard (e #t) (compile-asm '(fn (me buffer score chr) (f+ buffer 1)) () #t) #f)
```
---
    #t
