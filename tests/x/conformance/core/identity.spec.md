# Conformance: the engine says which engine it is (profile `core`)

Two implementations exist, so "which engine is this?" is a question with a wrong
answer available. These two bindings are how a running process answers it:
`x-release` is the release this build was cut as, `x-version` the
implementation's own version number.

THE DECLARATION IS NOT A SUBSTITUTE. `x-engine.xon` answers the same question
about the DIRECTORY it sits in, which is the right subject for a build system
and the wrong one for a bug report: a wrapper can be pointed at one engine and
run another. These answer for the process.

WHAT IS NOT REQUIRED IS THE CONTENT. An engine may spell its release however it
likes — a tag, a hash, `dev` — and the cases below say only that it is a
non-empty string. x-lang compares release strings for EQUALITY and never parses
them, so any spelling works as long as two different builds are two different
strings.

`x-machine` is deliberately absent from this file. It is the build triple as a
bound value, and the declared `(param os ...)` / `(param arch ...)` rows beside
the binary replaced it as the platform door; it stays in the vocabulary as
`meta/platform` for engines that ship no build params, required by nothing.

### the engine reports its release, as a non-empty string

covers: x-release

```scheme
(def %len (%coord (lit str) (lit byte-len)))
(%ok (match ((= (%len x-release) 0) ()) (#t #t)))
```
---
    *** ERROR: ok

### the engine reports its own version, as a non-empty string

covers: x-version

```scheme
(def %len (%coord (lit str) (lit byte-len)))
(%ok (match ((= (%len x-version) 0) ()) (#t #t)))
```
---
    *** ERROR: ok

## the two are separate facts -- deliberately not tested

An engine that aliased one binding to the other would answer one question twice
and pass everything above. There is no case for it, on purpose: nothing in
x-lang requires them to DIFFER. A project that versions its engine by its
release would report the same string for both and be entirely correct, so a
distinctness case would fail an honest engine to catch a careless one.

What x-lang actually needs is that each is present, is a string, and CHANGES
when the thing it names changes -- and no single-process test can observe the
second half. That obligation is on the engine's release process, not on this
suite.

(The first attempt at this section was a case reaching for a `str =?`
coordinate. There is none -- string equality bottoms out in `mem cmp` -- and
the missing coordinate crashed the engine, which the runner correctly reported
as "produced nothing; a crash" rather than as a failed assertion.)
