# @weight 1
## x/core/doors

### an imported door is the catalogue object

```x
(import x/core/doors int< int+ str-byte-ref type-of)
(list (same? int< (prim-ref (lit int) (lit <)))
      (same? int+ (prim-ref (lit int) (lit +)))
      (same? type-of (prim-ref (lit type) (lit of)))
      (int< 1 2) (int+ 1 2) (str-byte-ref "ab" 1))
```
---
    (#t #t #t #t 3 #\b)

### a loop through imported doors allocates what one through local defs does

```x
(import x/core/doors int< int+)
(def %doors-loop (fn (self i) (if (int< i 100) (self (int+ i 1)) i)))
(def %doors-l< (prim-ref (lit int) (lit <)))
(def %doors-l+ (prim-ref (lit int) (lit +)))
(def %doors-loop2 (fn (self i) (if (%doors-l< i 100) (self (%doors-l+ i 1)) i)))
(def %doors-cost
  (fn (_ f)
    (Heap collect)
    (def before (Heap count))
    (f 0)
    (- (Heap count) before)))
(- (%doors-cost %doors-loop) (%doors-cost %doors-loop2))
```
---
    0

### the platform operators cost more than the doors over the same loop

```x
(import x/core/doors int< int+)
(def %doors-loop3 (fn (self i) (if (int< i 100) (self (int+ i 1)) i)))
(def %doors-loop4 (fn (self i) (if (< i 100) (self (+ i 1)) i)))
(def %doors-cost2
  (fn (_ f)
    (Heap collect)
    (def before (Heap count))
    (f 0)
    (- (Heap count) before)))
(< (%doors-cost2 %doors-loop3) (%doors-cost2 %doors-loop4))
```
---
    #t

### a scoped module importing a door holds its own copy

```x
(import x/codec/crc32)
(eval (lit (int< 1 2)) (module x/codec/crc32))
```
---
    #t

### the module is documented

```x
(str? ((Doc entry (lit x/core/doors)) desc))
```
---
    #t
