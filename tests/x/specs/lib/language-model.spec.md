# LanguageModel: text in, text out
# @weight 3

A `LanguageModel` is a `Transformer` and the `BytePair` of its
vocabulary: it takes a text and answers it with the pieces the model
writes after it. The model is the small one of
`tests/x/lib/transformer-fixture.x`, 11 items and 8 positions, and its
vocabulary here is the letters a to k, an item each, with no merges, so
"bf" is the ids 1 and 5.

## generate

### generate answers the text of the ids Transformer generates

```x
(import x/num/language-model)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "c" 2 "d" 3 "e" 4 "f" 5 "g" 6 "h" 7 "i" 8 "j" 9 "k" 10)) ()))
  (def lm (LanguageModel make m b))
  (equal? (lm generate "bf" 2) (b decode (m generate (list 1 5) 2))))
```
---
    #t

### each hands over every new piece, in order, and answers the whole text

```x
(import x/num/language-model)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "c" 2 "d" 3 "e" 4 "f" 5 "g" 6 "h" 7 "i" 8 "j" 9 "k" 10)) ()))
  (def lm (LanguageModel make m b))
  (def got ())
  (def whole (lm each "bf" 2 (fn (_ piece) (set! got (pair piece got)))))
  (list (List length got) (equal? whole (Str8 append "bf" (Str8 join "" (List reverse got))))))
```
---
    (2 #t)

## what is refused

### a text of no pieces, and parts that are not a Transformer and a BytePair

```x
(import x/num/language-model)
(include "tests/x/lib/transformer-fixture.x")
(do
  (def m (transformer-fixture-model))
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1)) ()))
  (list (guard (e (Err label e)) ((LanguageModel make m b) generate "" 2))
        (guard (e (Err label e)) (LanguageModel make 1 b))
        (guard (e (Err label e)) (LanguageModel make m 1))))
```
---
    ('value 'type 'type)
