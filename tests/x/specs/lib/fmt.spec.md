# Fmt: width estimation

`Fmt` is the comment-preserving pretty printer; its layout decisions ride on
`(Fmt width form)`. Width counts CODE POINTS, not bytes — byte counts
misalign any non-ASCII source (true display columns for double-width and
combining glyphs are a known gap; see the glossary's width entry).

## width

### counts the written form's code points

```scheme
(do (import x/tool/fmt) (Fmt width (list 10 20)))
```
---
    7

### non-ASCII is counted in code points, not bytes

```scheme
(do (import x/tool/fmt) (Fmt width "€€"))
```
---
    4
