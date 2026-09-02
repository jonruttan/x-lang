# `apps/` — in-tree application entries

`x -l NAME` resolves three things in order: `lib/NAME.x`, then
`apps/NAME/run.x`, then a lang bundle declaring `NAME` under `langs/`
([the lang contract](../docs/lang-contract.md)). This directory is the second
step.

**One occupant: [`bitwise/`](bitwise/README.md)**, the owl sigil drawn for a
project (`x -l bitwise -- --all`). Logo lived here before it — it is what the
second step was added for (#35) — and it left for
[x-logo](https://github.com/jonruttan/x-logo) when the bundle format could
carry it. Bitwise is the shape's second use: a program that belongs to this
repository and is not a language.

## When something belongs here

An app entry is **self-booting**: it opens with `(include "lib/x-core.x")` and
addresses the tree around it, which is why `tools/check/path-literals.sh`
exempts `apps/*/run.x` from the root-relative-literal rule and nothing else.
That freedom is also its ceiling — a self-booting entry is nailed to this
tree, so anything meant to be installed, pinned or versioned separately wants
to be a bundle instead, where the wrapper boots the dialect and arms the root
for it.

So: a program that is part of *this repository* and is run through `-l`.
Anything that is its own artifact is a lang.

## What still runs over it

The mechanism is live and gated even with no occupants:

- `x.sh` resolves the second step (`APPS_PATH`)
- `make boot` amalgamates every `apps/*/run.x` into `build/boot/`
- `make install` and `tools/release/package.sh` ship the tree, and the payload
  fingerprint digests it alongside `lib` and `boot`
- `check-path-literals` exempts the entries and only the entries

Each of those handles the empty case without special-casing it; adding a
directory here is the whole of adding an app.
