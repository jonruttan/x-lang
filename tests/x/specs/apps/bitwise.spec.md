# Bitwise -- the owl sigil, drawn for a project

# @weight 3

`apps/bitwise` draws the ASCII owl from every source header for a named
project: the owl is set from Roboto Mono outlines, the field it sits on and
its accent hue come from sha256(name), and the project's own `bitwise.xon`
adds its mascot, colours and idiom.  Every quantity is an integer, so the
picture is a function of the name alone -- and the gallery's browser twin,
`apps/bitwise/gallery/bitwise.js`, must produce the identical bytes: see
`bitwise-parity.spec.md` for the digests both sides answer.

## seeding

### the name seeds the field, and the walk lands where the twin lands

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (def p (Bitwise params "x-lang"))
  (display (list (p get 'opname) (p get 'bit) (p get 'a) (p get 'b) (p get 'n) (p get 'hue10) (p get 'lit)))
  (newline)
  (display (p get 'formula)))
```
---
```output
(xor 3 11 15 32 2616 512)
(x*11) ^ (y*15) >> 3 & 1
```

### a near-solid field walks the bit, then the operator

`(p get 'lit)` sits inside the 18%..82% gate for every name the walk
touches; these two are the ones whose first draw was outside it.

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (List for-each
    (fn (_ name)
      (let ((p (Bitwise params name)))
        (display (list name (p get 'opname) (p get 'bit) (p get 'n) (p get 'lit)))
        (newline)))
    (list "x-cc" "x-r5rs" "x-engine-c")))
```
---
```output
(x-cc and 1 32 768)
(x-r5rs and 4 24 433)
(x-engine-c and 2 16 64)
```

## the picture

### the owl is set from outlines, by glyph index, with the eyes coloured

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-lang.xon")
  (def svg (first (Bitwise render "x-lang" "mark" "" "" "o")))
  (display (list (Str8 includes? "<path id=\"o-47\" d=\"M" svg)
                 (Str8 includes? "<use href=\"#o-47\" transform=\"translate(" svg)
                 (Str8 includes? "<g fill=\"hsl(261.6,58%,46%)\"><use href=\"#o-47\"" svg)
                 (Str8 includes? "<g fill=\"#161a22\"><use href=\"#o-14\"" svg)
                 (> (Str8 length svg) 20000))))
```
---
```output
(#t #t #t #t #t)
```

### a divergence from the twin is reported at its first byte

```scheme
(do
  (import-path! "apps")
  (import bitwise/gen)
  (Bitwise root! "apps/bitwise")
  (display (list (Bitwise diff "same" "same") (first (Bitwise diff "<rect x=\"6.62\"/>" "<rect x=\"6.63\"/>")) (first (rest (Bitwise diff "<rect x=\"6.62\"/>" "<rect x=\"6.63\"/>"))))))
```
---
```output
(#t differ-at 12)
```

## the command line

### a README's first paragraph becomes a one-sentence tagline

Links become their text, emphasis is dropped, the cut is the first sentence
end, and an unclosed parenthesis is dropped with what follows it.

```scheme
(do
  (import-path! "apps")
  (import bitwise/cli)
  (Bitwise root! "apps/bitwise")
  (display (BitwiseCli %unlink "A [Kernel](https://x) surface on [x-lang][xl], riding"))
  (newline)
  (display (BitwiseCli %tagline "tests/x/fixtures/bitwise/README.md")))
```
---
```output
A Kernel surface on x-lang, riding
A fixture for x-lang's owl, the second tool of the self-hosting arc
```

### --all gathers each project's costume, writes every format, and an index

Both fixture projects carry their own `bitwise.xon`, so the costume column
and the gathered `costumes.xon` are this case's own doing, not a leftover
from an earlier one.

```scheme
(do
  (import-path! "apps")
  (import bitwise/cli)
  (Bitwise root! "apps/bitwise")
  (import x/codec/json)
  (BitwiseCli main (list "x-bin" "--" "--all" "--root" "tests/x/fixtures/bitwise/root" "--out" "build/bitwise-spec"))
  (def index (Json parse (File read-all "build/bitwise-spec/index.json")))
  (display (List map (fn (_ d) (list (d get "name") (d get "kind") (d get "tagline"))) index))
  (newline)
  (display (List map (fn (_ f) (File exists? (%path-join "build/bitwise-spec" f)))
             (list "x-lang-mark.svg" "x-lang-avatar.svg" "x-lang-banner.svg" "x-fixture-banner.svg")))
  (newline)
  (display (Str8 includes? "(costume \"x-fixture\"" (File read-all "build/bitwise-spec/costumes.xon"))))
```
---
```output
x-lang          xor    bit 3  n=32  hue 261.6                           (def owl '{O,O})
x-fixture       xor    bit 3  n=24  hue  90.9  the fixture              (fixture)
((x-lang the language The language, as a fixture) (x-fixture a language on x-lang A fixture for x-lang's owl, the second tool of the self-hosting arc))
(#t #t #t #t)
#t
```

### --json answers the seeded parameters for one name

```scheme
(do
  (import-path! "apps")
  (import bitwise/cli)
  (Bitwise root! "apps/bitwise")
  (Bitwise costume-load! "tests/x/fixtures/bitwise/costumes/x-awk.xon")
  (import x/codec/json)
  (def out (Io display-to-str (Json emit (rest (Bitwise render "x-awk" "mark" "" "" "o")))))
  (display (list (Str8 includes? "\"opname\":\"or\"" out) (Str8 includes? "\"costume\":\"the auk\"" out))))
```
---
```output
(#t #t)
```
