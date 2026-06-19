# @lib ../tests/x/lib/fmt.x

The Fmt formatter methods. Kept separate from fmt.spec.md's tokenizer cases:
a known, separately-tracked bug (repeated Tok read-str on one process) fires
when many token-reads run alongside these in a single batch.

## Fmt class

### comment? detects a comment token
```scheme
(Fmt comment? (list (lit %comment) "hi"))
```
---
    #t

### width measures a form (symbols write as (lit x): 13, not 7)
```scheme
(display (Fmt width (lit (+ 1 2))))
```
---
    13

### build-table returns a lookup table
```scheme
(pair? (Fmt build-table (list (list (lit if) (pair (lit fmt) (lit head-1))))))
```
---
    #t

### lookup finds a present construct's props
```scheme
(pair? (Fmt lookup (lit if) (Fmt build-table (list (list (lit if) (pair (lit fmt) (lit head-1)))))))
```
---
    #t

### lookup of a missing key returns nil
```scheme
(null? (Fmt lookup (lit nope) (Fmt build-table (list (list (lit if) (pair (lit fmt) (lit head-1)))))))
```
---
    #t

### get-prop pulls a property from a property list
```scheme
(eq? (Fmt get-prop (lit fmt) (list (pair (lit fmt) (lit head-1)))) (lit head-1))
```
---
    #t

### expr writes a short form as-is
```scheme
(Fmt expr (lit (+ 1 2)) 0)
```
---
    ((lit +) 1 2)

### body prints forms one per line
```scheme
(Fmt body (list (lit a) (lit b)) 0)
```
---
    (lit b)

### list indents a wide form (default layout)
```scheme
(Fmt list (lit (alpha beta gamma delta epsilon zeta eta theta iota kappa)) 0 (Fmt build-table ()))
```
---
      (lit kappa))

### tokens formats top-level tokens through the pipeline
```scheme
(Fmt tokens (Tok read-str (Base make) "(+ 1 2)") (Fmt build-table ()))
```
---
    ((lit +) 1 2)
