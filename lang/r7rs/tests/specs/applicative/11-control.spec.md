## tail recursion

### tail-recursive factorial

```scheme
(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))) (fact 10 1)
```
---
    3628800

### deep tail recursion

```scheme
(define (loop n) (if (= n 0) (quote done) (loop (- n 1)))) (loop 50000)
```
---
    done
