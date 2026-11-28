# Tui width: text fitted to a number of columns
# @weight 1

## Cut

### the leading part that fits, a wide character never split

`中` takes two columns: with one column left it is left out.

```x
(do (import x/tui/width)
  (list (Width cut "hello" 3) (Width cut "hello" 9) (Width cut "hello" 0)
        (Width cut "a中b" 2) (Width cut "a中b" 3) (Width cut "café" 4)))
```
---
    ("hel" "hello" "" "a" "a中" "café")

### the trailing part that fits

```x
(do (import x/tui/width)
  (list (Width cut-start "hello" 3) (Width cut-start "hello" 9) (Width cut-start "hello" 0)
        (Width cut-start "a中b" 2) (Width cut-start "a中b" 3)))
```
---
    ("llo" "hello" "" "b" "中b")

## Pad

### exactly the width, on the side the alignment leaves

A centred text's odd space goes after it.

```x
(do (import x/tui/width)
  (list (Width pad "ab" 5 'left) (Width pad "ab" 5 'right) (Width pad "ab" 5 'centre)
        (Width pad "hello" 3 'left) (Width pad "" 2 'right)))
```
---
    ("ab   " "   ab" " ab  " "hel" "  ")

### a wide character cut at the edge leaves a space

```x
(do (import x/tui/width)
  (list (Width pad "a中" 2 'left) (Width pad "a中" 2 'right) (Width text (Width pad "中中" 3 'centre))))
```
---
    ("a " " a" 3)

### another alignment, or another end, is refused

```x
(do (import x/tui/width)
  (list (guard (e (Err label e)) (Width pad "ab" 5 'middle))
        (guard (e (Err label e)) (Width elide "hello world" 8 "…" 'middle))))
```
---
    ('value 'value)

## Elide

### a text that fits is itself; a longer one ends, or starts, with the mark

```x
(do (import x/tui/width)
  (list (Width elide "hello" 5 "…" 'end) (Width elide "hello world" 8 "…" 'end)
        (Width elide "hello world" 8 "…" 'start) (Width elide "hello world" 8 "..." 'end)
        (Width elide "a中中b" 4 "…" 'end)))
```
---
    ("hello" "hello w…" "…o world" "hello..." "a中…")

### no room past the mark shows as much of the mark as fits

```x
(do (import x/tui/width)
  (list (Width elide "hello" 1 "…" 'end) (Width elide "hello" 2 "..." 'start) (Width elide "hello" 0 "…" 'end)))
```
---
    ("…" ".." "")

## The plain functions

### text-fit answers the byte where the fitting part ends, from a byte

```x
(do (import x/tui/width text-fit)
  (list (text-fit "hello" 0 3) (text-fit "hello" 2 9) (text-fit "a中b" 1 1) (text-fit "a中b" 1 2)))
```
---
    (3 5 1 4)
