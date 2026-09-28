# Documentation discovery (apropos / help)
# @weight 1

The `apropos` and `help` cases pin argument handling: they assert the calls
complete without error (a bare-symbol `apropos`/`help` used to raise "Unbound
SYMBOL"), not the exact rendered doc text. The class case pins the headings
`(help Class)` prints.

## apropos

### accepts a bare symbol

```x
(do (apropos upcase) #t)
```
---
    #t

### accepts a string

```x
(do (apropos "upcase") #t)
```
---
    #t

### accepts a quoted symbol

```x
(do (apropos 'gcd) #t)
```
---
    #t

### no matches is not an error

```x
(do (apropos "zzzznotamethod") #t)
```
---
    #t

## help

### a bare method name resolves to matching methods rather than erroring

```x
(do (help upcase) #t)
```
---
    #t

### a genuinely unknown name still completes

```x
(do (help totallyunknownxyz) #t)
```
---
    #t

## help on a class

A class's own data is its static fields and an instance's data its fields, so
both are headed `fields:`, the static ones under `static:`. The output goes to
a file and only the heading lines are kept: a name is coloured when
`x/repl/ansi` is loaded, a heading never is.

### heads a class's data fields, static and instance

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/stream)
  (def-class DocHelpShape ()
    (static (made 0)
            (method make (self) (new DocHelpShape)))
    (size 1)
    (method grow (self) (set-field! 'size (+ (field 'size) 1))))
  (def doc-help-tmp (File temp "/tmp/x-doc-help-"))
  (File close (first doc-help-tmp))
  (Stream with-file (rest doc-help-tmp) (fn (_) (help DocHelpShape)))
  (def doc-help-lines (Str8 split "\n" (File read-all (rest doc-help-tmp))))
  (File unlink (rest doc-help-tmp))
  (List filter (fn (_ l) (Str8 ends? ":" l)) doc-help-lines))
```
---
    ("  static:" "    fields:" "    methods:" "  fields:" "  methods:")

## provide registration

### the List class module is registered

```x
(null? (%module-find 'x/type/list))
```
---
    #f

### boot modules register retroactively

```x
(null? (%module-find 'x/boot/module))
```
---
    #f
