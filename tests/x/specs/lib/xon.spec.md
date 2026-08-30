# Xon codec (x/codec/xon)
# @weight 1

The xon form language: read, closed-vocabulary walk, emit.  The emit
side's escaping is the #224 contract -- what the writer renders, the
reader parses back to the same value.

## xon: read

### reads forms in file order

```scheme
(do
  (import x/codec/xon)
  (def %f (Xon parse "(file \"a.x\" \"sha256:aa\")\n(seed \"n\" \"r\")"))
  (display (%length %f))
  (display " ")
  (display (first (first %f))))
```
---
    2 file

### the final token needs no terminator (the #161 door)

```scheme
(do
  (import x/codec/xon)
  (display (%length (Xon parse "(a) (b)"))))
```
---
    2

## xon: emit

### one form per line, strings quoted

```scheme
(do
  (import x/codec/xon)
  (display (Xon emit (list (list 'file "a.x" "sha256:aa")
                           (list 'seed "n" "r1" "r2")))))
```
---
```output
(file "a.x" "sha256:aa")
(seed "n" "r1" "r2")
```

### a quote in a string argument round-trips

```scheme
(do
  (import x/codec/xon)
  (def %odd "a\"b")
  (def %back (Xon parse (Xon emit (list (list 'file %odd "d")))))
  (display (str=? (first (rest (first %back))) %odd))
  (display " ")
  (display (%length %back)))
```
---
    #t 1

### a backslash in a string argument round-trips

```scheme
(do
  (import x/codec/xon)
  (def %odd "a\\b")
  (def %back (Xon parse (Xon emit (list (list 'file %odd "d")))))
  (display (str=? (first (rest (first %back))) %odd))
  (display " ")
  (display (%length %back)))
```
---
    #t 1

### a newline in a string argument stays on one line

```scheme
(do
  (import x/codec/xon)
  (def %odd "a\nb")
  (def %text (Xon emit (list (list 'file %odd "d"))))
  (def %back (Xon parse %text))
  (display (str=? (first (rest (first %back))) %odd))
  (display " ")
  ; the escaped newline must not split the line: still exactly one form
  (display (%length %back)))
```
---
    #t 1

### emit rejects a non-symbol head

```scheme
(do
  (import x/codec/xon)
  (Xon emit (list (list "nothead" "a"))))
```
---
    Error: #<err:type Xon emit: form head is a symbol>

## xon: walk

### dispatches by head, collects non-nil results in order

```scheme
(do
  (import x/codec/xon)
  (display (Xon walk
    (list (pair 'file (fn (_ f) (first (rest f))))
          (pair 'seed (fn (_ f) ())))
    (fn (_ f) ())
    (list (list 'file "a.x" "d1") (list 'seed "n") (list 'file "b.x" "d2")))))
```
---
    (a.x b.x)

### the unknown handler sees unlisted heads and non-list forms

```scheme
(do
  (import x/codec/xon)
  (def %seen ())
  (Xon walk
    (list (pair 'file (fn (_ f) ())))
    (fn (_ f) (set! %seen (pair f %seen)) ())
    (list (list 'file "a.x" "d") (list 'mystery 1) "bare"))
  (display (%length %seen)))
```
---
    2

## arm-source!: a scratch base keeps $"..." literals

A fresh base has no reader macros, so an interpolated literal would shatter at
its first space and its trailing quote would open a string that never closes.
Armed, the literal survives as a `('%interp "<source text>")` token -- what a
tool that re-emits source (fmt) or inspects it (doc) needs.

### unarmed, the literal shatters into pieces

```scheme
(do (import x/codec/xon)
    (%length (first (Xon parse "(f $\"a {x} b\" 1)" (Base make)))))
```
---
    5

### armed, it is one token carrying its own text

```scheme
(do (import x/codec/xon)
    (def b (Base make))
    (Xon arm-source! b)
    (def form (first (Xon parse "(f $\"a {x} b\" 1)" b)))
    (list (%length form) (first (first (rest form))) (first (rest (first (rest form))))))
```
---
    (3 '%interp "$\"a {x} b\"")

### an ordinary string in the same base is untouched

```scheme
(do (import x/codec/xon)
    (def b (Base make))
    (Xon arm-source! b)
    (first (rest (first (Xon parse "(f \"plain\")" b)))))
```
---
    "plain"
