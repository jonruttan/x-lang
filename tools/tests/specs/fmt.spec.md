## fmt: tokenization

### tokenizes simple expression

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "(+ 1 2)"))
  (display (%length %tokens))
  (display " ")
  (display (%length (first %tokens))))
```
---
    1 3

### tokenizes multiple forms

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "(def x 1)\n(def y 2)"))
  (display (%length %tokens)))
```
---
    2

### tokenizes nested expressions

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "(if (> x 0) x (- 0 x))"))
  (def %form (first %tokens))
  (display (first %form))
  (display " ")
  (display (pair? (first (rest %form)))))
```
---
    if t

### tokenizes strings

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "(display \"hello\")"))
  (def %form (first %tokens))
  (display (first %form))
  (display " ")
  (write (first (rest %form))))
```
---
    display "hello"

### tokenizes nil as empty list

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "()"))
  (display (null? %tokens)))
```
---
    t

### preserves integer values

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "42\n"))
  (display (first %tokens)))
```
---
    42

### preserves character literals

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "#\\a\n"))
  (display (char? (first %tokens))))
```
---
    t

### tokenizes def form structure

```scheme
(do
  (def %base (make-base))
  (def %tokens (Tok read-str %base "(def x (+ 1 2))"))
  (def %form (first %tokens))
  (display (first %form))
  (display " ")
  (display (first (rest %form)))
  (display " ")
  (display (pair? (first (rest (rest %form))))))
```
---
    def x t
