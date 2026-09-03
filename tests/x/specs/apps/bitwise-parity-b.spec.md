# Bitwise -- the twin must draw the same bytes

# @weight 3

`apps/bitwise/gen.x` owns the design; `apps/bitwise/gallery/bitwise.js` is
its browser twin, and the two must produce byte-identical SVG for a name in
every format.  The twin's renderings are checked in
under `tests/x/fixtures/bitwise/expected/` (`node apps/bitwise/gallery/parity.js
--write`), and each case here compares gen.x's bytes against them with a
native string compare -- hashing a 60KB picture in pure x costs more than
drawing it.  Two files of five names each, to stay well inside a batch's
budget.  A design change regenerates the fixtures and re-runs these.

## parity

One case per name, so the runner's seam collect keeps each render's garbage
from slowing the next.

### x-awk

```scheme
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

### x-r5rs

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-r5rs.xon")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-r5rs" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-r5rs-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-sweet

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-sweet.xon")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-sweet" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-sweet-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### hello, world

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "hello, world" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/hello-world-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-cc

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-cc.xon")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-cc" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-cc-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```
