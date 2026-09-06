# Bitwise -- the twin must draw the same bytes

# @weight 3

Two of the ten parity names; the design note is bitwise-parity-a.spec.md's.

## parity

### x-krn

```x
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-krn.xon")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-krn" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-krn-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-awk

```x
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-awk.xon")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-awk" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-awk-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```
