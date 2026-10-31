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

### answers the matching names, sorted

```x
(apropos "gcd")
```
---
    ('Num/gcd)

### answers () when nothing matches

```x
(null? (apropos "zzzznotamethod"))
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

### a value that is not a name answers rather than crashing

`help` is an operative, so its argument arrives as written; a number or a
list used to be handed to `symbol->str` and walked as a string pointer.

```x
(do (help 42) (help (list 1 2)) (help "gcd") (help Num 42) (help 42 gcd) #t)
```
---
    #t

### a quoted symbol finds the same entry as the bare one

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/stream)
  (def doc-help-capture
    (fn (_ thunk)
      (let ((tmp (File temp "/tmp/x-doc-help-")))
        (File close (first tmp))
        (Stream with-file (rest tmp) thunk)
        (let ((text (File read-all (rest tmp))))
          (File unlink (rest tmp))
          text))))
  (list
    (str=? (doc-help-capture (fn (_) (help 'gcd)))
           (doc-help-capture (fn (_) (help gcd))))
    (str=? (doc-help-capture (fn (_) (help 'Num 'gcd)))
           (doc-help-capture (fn (_) (help Num gcd))))
    (Str8 starts? "Num/gcd:" (doc-help-capture (fn (_) (help Num gcd))))))
```
---
    (#t #t #t)

## help on a name with no entry

A name with no entry of its own is answered by what it is: a module not yet
loaded, the last segment of documented names, a binding with no doc, or
nothing.  Only the first line of each answer is pinned.

### says what the name is before saying there is no doc

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/stream)
  (def doc-help-first
    (fn (_ thunk)
      (let ((tmp (File temp "/tmp/x-doc-help-")))
        (File close (first tmp))
        (Stream with-file (rest tmp) thunk)
        (let ((text (File read-all (rest tmp))))
          (File unlink (rest tmp))
          (first (Str8 split "\n" text))))))
  (def doc-help-bound 1)
  (list
    (doc-help-first (fn (_) (help x/sys/pty)))
    (doc-help-first (fn (_) (help gcd)))
    (doc-help-first (fn (_) (help doc-help-bound)))
    (doc-help-first (fn (_) (help totallyunknownxyz)))))
```
---
    ("x/sys/pty is not loaded; (import x/sys/pty) loads it, then (help x/sys/pty) reads it" "No top-level doc for gcd; documented names ending in /gcd:" "doc-help-bound is bound but has no documentation" "No documentation for totallyunknownxyz")

### apropos says when nothing matches, and hides % names unless asked

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/stream)
  (def doc-help-tmp (File temp "/tmp/x-doc-help-"))
  (File close (first doc-help-tmp))
  (Stream with-file (rest doc-help-tmp) (fn (_) (apropos "zzzznotamethod")))
  (def doc-help-text (File read-all (rest doc-help-tmp)))
  (File unlink (rest doc-help-tmp))
  (list doc-help-text
        (List any? (fn (_ n) (Str8 starts? "%" (symbol->str n))) (apropos "map"))
        (List any? (fn (_ n) (Str8 starts? "%" (symbol->str n))) (apropos "%map"))))
```
---
    ("no documented name contains \"zzzznotamethod\"\n" #f #t)

## help on a class

A class's own data is its static fields and an instance's data its fields, so
both are headed `fields:`, the static ones under `static:`. The output goes to
a file and only the heading lines are kept: a name is coloured when
`x/repl/ansi` is loaded, a heading never is.

### leaves members named with % out of the listing

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/stream)
  (def-class DocHelpHooks ()
    (static (method %make-hook (self) 1)
            (method make (self) (new DocHelpHooks)))
    (method %repr (self) "#<hooks>")
    (method bump (self) 1))
  (def doc-help-tmp (File temp "/tmp/x-doc-help-"))
  (File close (first doc-help-tmp))
  (Stream with-file (rest doc-help-tmp) (fn (_) (help DocHelpHooks)))
  (def doc-help-text (File read-all (rest doc-help-tmp)))
  (Stream with-file (rest doc-help-tmp) (fn (_) (help DocHelpHooks %repr)))
  (def doc-help-member (File read-all (rest doc-help-tmp)))
  (File unlink (rest doc-help-tmp))
  (list (Str8 includes? "%" doc-help-text)
        (Str8 includes? "bump" doc-help-text)
        (Str8 includes? "make" doc-help-text)
        (Str8 includes? "%repr" doc-help-member)))
```
---
    (#f #t #t #t)

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
