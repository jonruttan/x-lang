## cond-expand

### match r7rs feature

```scheme
(cond-expand (r7rs 'yes) (else 'no))
```
---
    yes

### match x-lang feature

```scheme
(cond-expand (x-lang 'yes) (else 'no))
```
---
    yes

### no match falls through to else

```scheme
(cond-expand (chicken 'no) (else 'fallback))
```
---
    fallback

### and feature requirement

```scheme
(cond-expand ((and r7rs x-lang) 'both) (else 'no))
```
---
    both

### or feature requirement

```scheme
(cond-expand ((or chicken r7rs) 'found) (else 'no))
```
---
    found

### not feature requirement

```scheme
(cond-expand ((not chicken) 'yes) (else 'no))
```
---
    yes

### not with present feature

```scheme
(cond-expand ((not r7rs) 'yes) (else 'no))
```
---
    no

### complex nested features

```scheme
(cond-expand ((and r7rs (not chicken)) 'x-r7rs) (else 'other))
```
---
    x-r7rs

### features list

```scheme
(pair? %features)
```
---
    #t

### first clause wins

```scheme
(cond-expand (r7rs 'first) (x-lang 'second) (else 'third))
```
---
    first

### body with multiple expressions

```scheme
(cond-expand (r7rs (define x 10) (+ x 5)) (else 0))
```
---
    15
