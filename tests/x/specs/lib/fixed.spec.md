# Fixed: fixed-point arithmetic on plain integers
# @weight 1

A fixed-point value is an integer holding a number times 2^k. Operands and
answers are 32-bit signed; products and quotients are exact through 64 bits
on any word. The sweeps pin one answer for an 8-byte word and a 4-byte one.

## products

### a product is shifted down by the fraction bits

```x
(import x/num/fixed fixed*)
(write (list (fixed* 98304 163840 16) (fixed* 1073741824 1073741824 30) (fixed* 2147483647 65536 16) (fixed* 7 9 0)))
```
---
    (245760 1073741824 2147483647 63)

### a negative product rounds down

```x
(import x/num/fixed fixed*)
(write (list (fixed* -98304 163840 16) (fixed* -1 1 16) (fixed* -3 1 1) (fixed* -2147483647 2 1) (fixed* -65536 65536 32) (fixed* 0 -5 8)))
```
---
    (-245760 -1 -2 -2147483647 -1 0)

### a sweep of products

```x
(import x/num/fixed fixed*)
(import x/core/doors int& int* int+ int- int= int>>)
(def %fx-next (fn (_ x) (int& (int+ (int* x 1103515245) 12345) 2147483647)))
(def %fx-sweep*
  (fn (self i x acc)
    (if (int= i 0) acc
      (self (int- i 1) (%fx-next (%fx-next x))
            (int& (int+ (int* acc 31)
                        (fixed* (int- (%fx-next x) 1073741824)
                                (int- (int>> (%fx-next (%fx-next x)) 16) 16384) 16))
                  1073741823)))))
(write (%fx-sweep* 2000 1 0))
```
---
    287266345

## quotients

### a quotient gains the fraction bits

```x
(import x/num/fixed fixed/)
(write (list (fixed/ 98304 163840 16) (fixed/ -98304 163840 16) (fixed/ 98304 -163840 16) (fixed/ 440000 44100000 32) (fixed/ 7 2 0) (fixed/ 1 3 31)))
```
---
    (39321 -39321 -39321 42852281 3 715827882)

### a sweep of quotients

```x
(import x/num/fixed fixed/)
(import x/core/doors int& int* int+ int- int= int>>)
(def %fx-next (fn (_ x) (int& (int+ (int* x 1103515245) 12345) 2147483647)))
(def %fx-sweep/
  (fn (self i x acc)
    (if (int= i 0) acc
      (self (int- i 1) (%fx-next (%fx-next x))
            (int& (int+ (int* acc 31)
                        (fixed/ (int- (int>> (%fx-next x) 16) 16384)
                                (int+ (int>> (%fx-next (%fx-next x)) 16) 1) 16))
                  1073741823)))))
(write (%fx-sweep/ 500 1 0))
```
---
    1013654612

## scaling by a ratio

### a value times a ratio

```x
(import x/num/fixed fixed*/)
(write (list (fixed*/ 1000000 44100 1000) (fixed*/ 2000000000 3 4) (fixed*/ -2000000000 3 4) (fixed*/ 2000000000 -3 -4) (fixed*/ 7 7 7)))
```
---
    (44100000 1500000000 -1500000000 1500000000 7)

### a sweep of ratios

```x
(import x/num/fixed fixed*/)
(import x/core/doors int& int* int+ int- int= int>>)
(def %fx-next (fn (_ x) (int& (int+ (int* x 1103515245) 12345) 2147483647)))
(def %fx-sweep*/
  (fn (self i x acc)
    (if (int= i 0) acc
      (self (int- i 1) (%fx-next (%fx-next (%fx-next x)))
            (int& (int+ (int* acc 31)
                        (fixed*/ (int- (%fx-next x) 1073741824)
                                 (int- (int>> (%fx-next (%fx-next x)) 16) 16384)
                                 (int+ (int>> (%fx-next (%fx-next (%fx-next x))) 17) 16384)))
                  1073741823)))))
(write (%fx-sweep*/ 500 1 0))
```
---
    636614643

## values

### a ratio rounds to the nearest

```x
(import x/num/fixed fixed-ratio)
(write (list (fixed-ratio 3 4 16) (fixed-ratio 1 10 16) (fixed-ratio -1 3 16) (fixed-ratio 1 3 32) (fixed-ratio 5 2 0) (fixed-ratio -5 2 0)))
```
---
    (49152 6554 -21845 1431655765 3 -3)

### whole numbers in and out

```x
(import x/num/fixed fixed fixed-floor fixed-round fixed-clamp)
(write (list (fixed 3 16) (fixed-floor 98304 16) (fixed-floor -98304 16) (fixed-round 98304 16) (fixed-round 98303 16) (fixed-round 5 0) (fixed-clamp 40000 -32768 32767) (fixed-clamp -40000 -32768 32767) (fixed-clamp 5 -32768 32767)))
```
---
    (196608 1 -2 2 1 5 32767 -32768 5)
