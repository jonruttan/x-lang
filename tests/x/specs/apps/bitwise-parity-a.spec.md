# Bitwise -- the twin must draw the same bytes

# @weight 3

`apps/bitwise/gen.x` owns the design; `apps/bitwise/gallery/bitwise.js` is
its browser twin, and the two must produce byte-identical SVG for a name in
every format.  The twin's renderings are checked in
under `tests/x/fixtures/bitwise/expected/` (`node apps/bitwise/gallery/parity.js
--write`), and each case here compares gen.x's bytes against them with a
native string compare -- hashing a 60KB picture in pure x costs more than
drawing it.  Two files of four names each, to stay well inside a batch's
budget.  A design change regenerates the fixtures and re-runs these.

## parity

One case per name, so the runner's seam collect keeps each render's garbage
from slowing the next.

### x-lang

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-lang" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-lang-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-engine-rust

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-engine-rust" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-engine-rust-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-python

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-python" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-python-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```

### x-logo

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def tag "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture")
  (List for-each
    (fn (_ fmt)
      (display (list fmt (Bitwise diff (first (Bitwise render "x-logo" fmt tag "a language on x-lang" "o"))
                                      (File read-all (%str-concat (list "tests/x/fixtures/bitwise/expected/x-logo-" fmt ".svg"))))))
      (newline))
    (list "mark" "avatar" "banner")))
```
---
```output
(mark #t)
(avatar #t)
(banner #t)
```
