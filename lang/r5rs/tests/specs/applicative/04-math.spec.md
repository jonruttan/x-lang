# Math stress tests

## expt stress

### large exponentiation

```scheme
(expt 2 30)
```
---
    1073741824

### expt chain

```scheme
(define (pow-sum n) (let loop ((i 0) (acc 0)) (if (= i n) acc (loop (+ i 1) (+ acc (expt 2 i)))))) (= (pow-sum 20) (- (expt 2 20) 1))
```
---
    #t

## gcd/lcm stress

### gcd many pairs

```scheme
(define (gcd-chain n) (let loop ((i 2) (acc (gcd 100 200))) (if (= i n) acc (loop (+ i 1) (gcd acc (* i 7)))))) (gcd-chain 100)
```
---
    1

## quotient/remainder stress

### quotient-remainder invariant over range

```scheme
(define (check-qr a b) (= a (+ (* b (quotient a b)) (remainder a b)))) (let loop ((i -50) (ok #t)) (if (= i 51) ok (loop (+ i 1) (if (= i 0) ok (and ok (check-qr 137 i))))))
```
---
    #t

## named let recursion

### ackermann function

```scheme
(define (ack m n) (cond ((= m 0) (+ n 1)) ((= n 0) (ack (- m 1) 1)) (else (ack (- m 1) (ack m (- n 1)))))) (ack 3 4)
```
---
    125

## do iteration stress

### do with large iteration count

```scheme
(do ((i 0 (+ i 1)) (sum 0 (+ sum i))) ((= i 10000) sum))
```
---
    49995000
