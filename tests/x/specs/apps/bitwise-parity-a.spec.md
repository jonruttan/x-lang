# Bitwise -- the twin must draw the same bytes

# @weight 3

`apps/bitwise/gen.x` owns the design; `apps/bitwise/gallery/bitwise.js` is
its browser twin, and the two must produce byte-identical SVG for a name in
every format.  The twin's renderings are checked in
under `tests/x/fixtures/bitwise/expected/` (`node apps/bitwise/gallery/parity.js
--write`), and each case here compares gen.x's bytes against them with a
native string compare -- hashing a 60KB picture in pure x costs more than
drawing it.  Five files of two names each: a render is three seconds and
the suite runs one file per job, so two names is one short job and ten is a
long pole.  A design change regenerates the fixtures and re-runs these.

## parity

One case per name, so the runner's seam collect keeps each render's garbage
from slowing the next.

### x-lang

```x
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-lang.xon")
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

```x
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-engine-rust.xon")
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
