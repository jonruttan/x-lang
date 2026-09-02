# apps/bitwise — Bitwise, the owl sigil, drawn for a project

```
    ., .,
    {O,O}
    (   )
     " "
```

Bitwise is the owl stamped in the header of every x source file. This app
keeps it exactly that: the glyphs, set from Roboto Mono's outlines so it is
the same owl on every machine. The project's name decides everything around
it: `sha256(name)` seeds a bitwise function over a cell grid for the owl to
sit on, and the accent hue. A project with a mascot, a logo colour or an
idiom of its own wears it as a costume. Same name, same picture, forever.

```sh
x -l bitwise -- --all --png                  # every project under ../, three formats each
x -l bitwise -- x-awk                        # the mark, SVG on stdout
x -l bitwise -- x-awk --fmt banner --tagline "POSIX awk on x-lang" --kind "a language on x-lang" -o x-awk.svg --png
x -l bitwise -- x-awk --json                 # the seeded parameters
```

Formats: `mark` (owl over its field, square, transparent ground, viewBox
100×100), `avatar` (512×512 on paper, for a repo or org avatar), `banner`
(1280×640 with name, tagline, reference line and the field formula, the
GitHub social-preview size). `--all` discovers `x-expr`, `x-lang`,
`engines/*` and `languages/*` under `--root` (default `..`, the x workspace
when run from this checkout), reads each tagline from the first paragraph of
its README, and writes into `--out` (default `build/bitwise`) plus an
`index.json`. `--png` shells out to `rsvg-convert` when it is on PATH.

## Files

| file | what |
|---|---|
| `run.x` | the entry: boots the core, arms the roots, runs the command line |
| `gen.x` | class `Bitwise`: seeding, field, palette, costume, the owl, the formats; `(Bitwise render name fmt tagline kind uid)`, `(Bitwise params name)`, `(Bitwise diff a b)` |
| `cli.x` | class `BitwiseCli`: arguments, workspace discovery, README taglines, files and PNGs; `(BitwiseCli main args)` |
| `glyphs.xon` | printable ASCII, λ and ▲ as outlines from Roboto Mono Regular (Apache-2.0); ▲ borrowed from Menlo |
| `langs.xon` | the costumes: per project, glyph rows, colours, a reference line |
| `gallery/bitwise.js` | the browser twin: the same integer geometry, byte-identical output |
| `gallery/gallery.tmpl.html`, `gallery/build.js` | the live page: `node apps/bitwise/gallery/build.js` → `build/bitwise/gallery.html` |
| `gallery/parity.js` | prints the twin's digests in the shape `tests/x/specs/apps/bitwise-parity.spec.md` asserts |

Each file is one class and one public global, every helper a `%`-static on
it (the tree's rule for `%`-globals); the data root is armed with
`(Bitwise root! dir)`, by the entry from `%install-root` and by a spec as
`apps/bitwise`.

## How a picture is made

Every quantity is an integer. Geometry is carried in micro-units and
formatted half-up to one, two or four decimals, so the picture is a function
of the name alone and the twin computes the identical bytes with the same
integer arithmetic. The first ten digest bytes settle the traits:

| digest bytes | trait |
|---|---|
| 0–1 | hue of the accent, to a tenth of a degree |
| 2 | operator: xor · and · or · rings · moire · prod |
| 3 | which bit of the result is sampled (1–4) |
| 4, 5 | odd multipliers a, b (1–15) |
| 6, 7 | field offset (0–31 cells) |
| 8 | salt xor'd into the field |
| 9 | grid resolution: 16 · 20 · 24 · 32 |

Cell `(x, y)` is lit when the chosen bit of `f(x, y)` is set. A near-empty or
near-solid field (under 18% or over 82% lit) advances the bit, then the
operator, deterministically, until the field reads as a texture. The owl
itself is never generated.

## Costumes

`langs.xon` holds one `(costume "NAME" ...)` form per project; every field
is optional:

```
(costume "x-python"
  (mascot "the two Python snakes")        shown on the gallery card and in the readout
  (logo "Python blue and yellow")         printed where the hue would be
  (accent 207 51 44)                      h s l: replaces the hashed hue in the field and the eyes
  (secondary 45 100 42)                   the colour for role b
  (eyes (207 51 44) (45 100 42))          two-tone eyes, left then right
  (rows "., .," "{OvO}" "( py)" " \" \"")  the owl's glyph rows in costume: printable ASCII, λ or ▲
  (roles "ii ii" "ieifi" "i aai" " i i ") same shape: i ink, e/f the eyes, a accent, b secondary
  (reference "print(\"{O,O}\")"))         one line in the project's own language, on the banner
```

Every costumed owl wears the `v` beak (the auk keeps its `>` bill) and
carries its logo on its belly:
`( C )` for the C projects, `( λ )` for the Schemes, `({+})` for
sweet-expressions, `(/./)` for grep, `(vau)` for Kernel, `( py)` for Python,
`( ▲ )` for Logo, `(awk)`, `(sed)`, `(all)`, `( | )`, `( $ )`, `(int)`.
x-lang itself keeps a plain belly. The Rust engine is Ferris: `{OvO}` over `V   V`.

## Changing the design

`gen.x` is the definition; `gallery/bitwise.js` follows it. After a change to
either, regenerate the digests both must answer and put them in the parity
spec:

```sh
node apps/bitwise/gallery/parity.js
```

Never edit a rendered SVG by hand; change the generator and re-render. A
project renames, its field changes, and that is the point. The owl does not
change, ever.

`glyphs.xon` was extracted once from `RobotoMono-Regular.ttf` with a
fontTools one-off (kept outside the tree, beside the font); a wider glyph set
is a re-extraction, not an edit.
