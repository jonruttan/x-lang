# @lib ../tests/x/lib/indent.x
# @weight 2

`Indent` (`lib/x/reader/indent.x`) is the stack discipline under
indentation-sensitive grouping (#520). Logo and x-sweet each owned a copy of it;
this is the one both now drive.

Two layers. **Measurement** answers what column a line begins at, and is where
the tab question lives. **The stack** answers what opened and what closed, and is
where the unmatched-dedent question lives. Both questions are constructor
policy, because the two previous implementations answered them differently and
neither wrote down that it had chosen.

The per-character functions are registered under catalog ns `indent`; the
harness caches them as `%adv` / `%msr` / `%cls`.

## Indent advance

### a space is one column

```x
(write (%adv 0 #\space 8))
(newline)
```
---
    1

### a tab from column 0 reaches the first stop

```x
(write (%adv 0 #\tab 8))
(newline)
```
---
    8

### a tab advances to the next stop, it does not add the stop

This is the disagreement no suite caught. x-sweet added 8; SRFI-110 and CPython
both advance to the next multiple of 8. They differ exactly when a tab is not
the first thing on the line, which is why a suite with no tab case could not see
it.

```x
(write (%adv 1 #\tab 8))
(newline)
```
---
    8

### a tab from a column already on a stop moves a full stop

```x
(write (%adv 8 #\tab 8))
(newline)
```
---
    16

### a tab stop of one is a tab counting as one column

Logo's answer, expressed as policy rather than as a different code path: the
next multiple of 1 after n is n+1, so Logo's rule is this rule.

```x
(write (%adv 3 #\tab 1))
(newline)
```
---
    4

### anything else leaves the column alone

The caller decides that the run has ended; measurement does not guess.

```x
(write (%adv 4 #\x 8))
(newline)
```
---
    4

## Indent measure

### counts a run of spaces

```x
(write (%msr "    x" 0 8))
(newline)
```
---
    4

### stops at the first non-whitespace character

```x
(write (%msr "  a    b" 0 8))
(newline)
```
---
    2

### measures from an offset, for a token carrying its own newline

```x
(write (%msr "\n   word" 1 8))
(newline)
```
---
    3

### mixes tabs and spaces on the stops

```x
(write (%msr " \t x" 0 8))
(newline)
```
---
    9

### a line with no indentation is column zero

```x
(write (%msr "x" 0 8))
(newline)
```
---
    0

## Indent scan

### hands back the column and the index together

```x
(write (Indent scan "  x" 0 8))
(newline)
```
---
    (2 . 2)

### the column and the index diverge once a tab is worth more than one

A consumer that reconstructed the index by adding the column to its start would
slice here at 8 rather than at 1. Logo computed exactly that, correctly, only
because its tab was worth one column.

```x
(write (Indent scan "\tx" 0 8))
(newline)
```
---
    (8 . 1)

## Indent classify

### deeper

```x
(write (%cls 4 0))
(newline)
```
---
    'deeper

### same

```x
(write (%cls 4 4))
(newline)
```
---
    'same

### shallower

```x
(write (%cls 2 4))
(newline)
```
---
    'shallower

## Indent stack

### a fresh indenter has column zero open

```x
(def i1 (Indent make))
(write (list (i1 column) (i1 depth)))
(newline)
```
---
    (0 1)

### a deeper line opens

```x
(def i2 (Indent make))
(write (i2 feed 4))
(newline)
```
---
    ('open)

### an equal line is the same block

```x
(def i3 (Indent make))
(i3 feed 4)
(write (i3 feed 4))
(newline)
```
---
    ('same)

### a dedent closes and then continues

Every result ends with exactly one `open` or `same`, so a caller never counts
levels itself -- the loop both previous implementations owned.

```x
(def i4 (Indent make))
(i4 feed 4)
(write (i4 feed 0))
(newline)
```
---
    ('close 'same)

### one dedent can close several levels at once

```x
(def i5 (Indent make))
(i5 feed 2)
(i5 feed 4)
(i5 feed 6)
(write (i5 feed 0))
(newline)
```
---
    ('close 'close 'close 'same)

### the column follows the stack

```x
(def i6 (Indent make))
(i6 feed 4)
(i6 feed 8)
(i6 feed 4)
(write (list (i6 column) (i6 depth)))
(newline)
```
---
    (4 2)

### close-all closes what is open and reports no continuation

```x
(def i7 (Indent make))
(i7 feed 2)
(i7 feed 4)
(write (i7 close-all))
(newline)
```
---
    ('close 'close)

### close-all on an unindented stream is empty

```x
(def i8 (Indent make))
(write (i8 close-all))
(newline)
```
---
    ()

### close-all leaves the indenter reusable

```x
(def i9 (Indent make))
(i9 feed 4)
(i9 close-all)
(write (list (i9 column) (i9 depth)))
(newline)
```
---
    (0 1)

### reset! closes everything without reporting

```x
(def ia (Indent make))
(ia feed 4)
(ia reset!)
(write (list (ia column) (ia depth)))
(newline)
```
---
    (0 1)

## Indent unmatched dedent

The third disagreement, and the one with three defensible answers. A line at
column 2 when 0 and 4 are open matches no level; what that means is policy.

### by default it is an error, which is Python's answer

```x
(def j1 (Indent make))
(j1 feed 4)
(write (j1 feed 2))
(newline)
```
---
    Error: #<err:indent unindent does not match any outer indentation level>

### 'open opens a level at the odd column, which is Logo's answer

```x
(def j2 (Indent make 8 'open))
(j2 feed 4)
(write (j2 feed 2))
(newline)
```
---
    ('close 'open)

### 'open leaves the odd column on the stack

```x
(def j3 (Indent make 8 'open))
(j3 feed 4)
(j3 feed 2)
(write (list (j3 column) (j3 depth)))
(newline)
```
---
    (2 2)

### 'close hands the line to the nearest enclosing level

```x
(def j4 (Indent make 8 'close))
(j4 feed 4)
(write (j4 feed 2))
(newline)
```
---
    ('close 'same)

### 'close leaves the odd column off the stack

```x
(def j5 (Indent make 8 'close))
(j5 feed 4)
(j5 feed 2)
(write (list (j5 column) (j5 depth)))
(newline)
```
---
    (0 1)

### an indent from the current level is never a mismatch

Only a dedent can land between levels, so a genuine indent opens under every
policy -- including the one that would otherwise raise.

```x
(def j6 (Indent make))
(write (j6 feed 3))
(newline)
```
---
    ('open)

### policy is per instance, not global

```x
(def k1 (Indent make 1 'open))
(def k2 (Indent make))
(write (list (%adv 0 #\tab 1) (k2 feed 4)))
(newline)
```
---
    (1 ('open))
