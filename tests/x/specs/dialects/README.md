# Dialect entry-point smokes

The shipped dialects had **zero** end-to-end coverage until this family (#70).
Every numeric spec runs against a bespoke `@lib` harness, which passes -- so the
tower is well covered while the launchers users actually run were covered
not at all. That is how #49 shipped: a dialect that cannot add two numbers.

These run each entry point **as the README documents it** -- `@lib <dialect>`
is exactly `cat lib/<dialect> program.x | ./x-bin`. That distinction is the whole
point: `x-base.x` has no `(repl)`, so its forms reach the C read-eval loop,
while the dialect entries (`he.x`, `xe.x`, `rn.x`) end with `(repl)` and go
through the x-lang REPL reader instead. #49 lives on the second path only.

The noble-gas rename (#95) named the entries he/xe/rn; `x.x` is the
default pointer (bare `sh x.sh` boots helium), and its group proves the
pointer path itself boots -- `check-dialect-cover` demands a group per
`lib/*.x` file, and walks every spec in this directory to find them.

One file per dialect (#320): as a single file the six `@lib` groups ran
six library boots back-to-back inside one runner job (~17s of boot for 26
tests), an un-splittable critical path.  As siblings they schedule in
parallel.  Keep one taste-level form per dialect feature; a smoke test,
not a tower suite -- depth belongs in `e2e/numeric-tower.spec.md`.
