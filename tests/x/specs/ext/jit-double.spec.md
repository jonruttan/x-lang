# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

The JIT's double arithmetic: (%f+ a b), %f-, %f*, %f/ on words holding
IEEE 754 bit patterns, the payload of a Float and of a double in memory.
Unlabelled: both 64-bit backends compile the same forms. A double fills
an 8-byte word only, so on a 4-byte word the compile refuses, and each
case answers what the 8-byte compile does when it cannot run. Bit
patterns used: 1.0 4607182418800017408, 2.0 4611686018427387904, 3.0
4613937818241073152, 1.5 4609434218613702656, 0.5 4602678819172646912, 2.5
4612811918334230528, 6.0 4618441417868443648, 1000.0 4652007308841189376.

## arithmetic

### %f+: 1.0 + 2.0 is 3.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (%f+ a b))) 4607182418800017408 4611686018427387904)
  4613937818241073152))
```
---
    4613937818241073152

### %f-: 3.0 - 1.0 is 2.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (%f- a b))) 4613937818241073152 4607182418800017408)
  4611686018427387904))
```
---
    4611686018427387904

### %f*: 2.0 * 1.5 is 3.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (%f* a b))) 4611686018427387904 4609434218613702656)
  4613937818241073152))
```
---
    4613937818241073152

### %f/: 1.0 / 2.0 is 0.5

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b) (%f/ a b))) 4607182418800017408 4611686018427387904)
  4602678819172646912))
```
---
    4602678819172646912

### nested: (1.0 + 2.0) * 2.0 is 6.0, the left operand kept across the right

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (_ a b c) (%f* (%f+ a b) c))) 4607182418800017408 4611686018427387904 4611686018427387904)
  4618441417868443648))
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
      ((compile-asm '(fn (_ a) (%mem-set-at! a 0 (%f+ (%mem-ref-at a 0) (%mem-ref-at a 1))))) p)
      (ptr-ref-word (str->ptr buf) 0))
  4612811918334230528))
```
---
    4612811918334230528

### a tail loop: 1.0 added 1000 times is 1000.0

```x
(display (if (= %word-size 8)
  ((compile-asm '(fn (self n acc one) (if (= n 0) acc (self (- n 1) (%f+ acc one) one))))
   1000 0 4607182418800017408)
  4652007308841189376))
```
---
    4652007308841189376

## refusals

### an object parameter is not a double

```x
(guard (e #t) (compile-asm '(fn (me buffer score chr) (%f+ buffer 1)) () #t) #f)
```
---
    #t
