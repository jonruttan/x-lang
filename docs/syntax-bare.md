# bare x: the reader

*The syntax of x before any library loads — the surface any implementation
of the reader (C, Rust, or otherwise) must match. The booted language's
syntax is [syntax.md](syntax.md); this document is the floor it stands on.*

## The engine

The reader is type-driven: every registered type may carry an `analyse`
hook (score a candidate token), a `read` hook (build the value), and a
`delimit` hook (declare characters that terminate *other* tokens). The
engine feeds the input to every analyse hook and takes the best score:

- **Specific literals score positive; the symbol fallback scores
  negative.** A positive score always wins — that is why `-7` is an
  integer and `1a` reads as the integer `1` followed by the symbol `a`.
- **Equal scores go to the later-registered type** (C built-ins beat
  custom types on ties; custom types are checked first but lose ties).
- **Only three types carry delimit hooks at boot**: whitespace
  (`\t \n \v \f \r` space), list (`(` `)` `.`), comment (`;`). Nothing
  else terminates a token. This is a design decision, not an accident:
  **delimiters are type-supplied**, so a dialect chooses what punctuates
  its tokens by registering delimit hooks — the core does not hardcode
  more structure than lists, comments, and space.

## Literals at the bare layer

**Integers.** `[+-]?` then digits; `0x`/`0X` prefixes hex. Signs are part
of the literal: `-1` and `+7` are integers at every stage of boot — no
arithmetic workaround is ever needed for a negative literal. (`-` and `+`
alone decline the integer analyser and fall back to symbols, which is how
the operators exist.)

**Strings.** `"…"` with escapes `\"` `\\` `\n` `\t` `\r` `\0` `\xHH`.
Unknown escapes are preserved literally. `\0` embeds a real NUL.

**Characters.** `#\x` (any single byte), `#\€` (UTF-8 glyph), and the
named set `#\alarm #\backspace #\delete #\escape #\newline #\null
#\return #\space #\tab`. Character literals are part of the bare reader —
they work from the first line of boot.

**Symbols.** The fallback: any run of characters not cut by a registered
delimiter. Consequently a bare symbol may contain `"`, `#`, `'`, and
anything else non-delimiting — `abc"def` is one symbol here. Dialects
that want more punctuation add delimit hooks in-language; the core stays
permissive.

**Lists and pairs.** `(a b c)`, dotted tails `(a . b)`, and the tail-only
form `( . x)`, which reads as `x` itself — a list that is only a tail IS
the tail. Its idiomatic use is the bare-variadic parameter list:
`(fn ( . rest) rest)`.

**Comments.** `;` to end of line. No block comments.

## What the bare layer is NOT

- `#t` and `#f` are **symbols** here; the boot library binds them to the
  boolean singletons.
- No quote family: `'x`, `` `x ``, `,x`, `,@x` are library reader macros;
  at the bare layer `'x` is part of a symbol.
- No floats, rationals, complexes, bignums, vectors (`#(…)`), or regexes
  (`#/…/`) — all library- or dialect-added. A `1.5`-shaped token reads as
  the integer `1`, the dot sentinel, and the integer `5`.
- **No writer.** The bare interpreter produces no textual representation
  of values; `write`/`display` are pure x-lang (the boot printer).
  Output at this layer is the single raw-bytes door `(io write-str s)`.

## Known sharp edges (tracked in issue #45)

- Leading-zero integers currently read as octal via base auto-detection
  (`019` → `1`); ruling pending to make leading-zero decimal (`0x` stays
  hex).
- The `1a` → `1`,`a` split and symbol permissiveness are documented
  behavior, not bugs — the scoring rules above are the specification.
