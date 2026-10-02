# Opts: the command line, parsed against a declaration
# @weight 1

A caller declares its options once -- a list that stand alone, a list
that take an argument -- and every spelling getopt(3) accepts is
understood against that one declaration.  The point is not brevity:
it is that the CHECK and the READ can no longer disagree, which is
what three silent defects in x-coreutils came down to.

## the spellings

### a flag stands alone, and clusters

```x
(do (import x/sys/opts)
  (def o (Opts parse (list "-a" "-b" "-c") () (list "-ac")))
  (list (Opts on? o "-a") (Opts on? o "-b") (Opts on? o "-c")))
```
---
    (#t #f #t)

### a value comes attached or separated, and either way reads the same

```x
(do (import x/sys/opts)
  (def v (list "-k"))
  (list (Opts value (Opts parse () v (list "-k2")) "-k")
        (Opts value (Opts parse () v (list "-k" "2")) "-k")))
```
---
    ("2" "2")

### a value may end a cluster, taking the rest of the token or the next one

```x
(do (import x/sys/opts)
  (def f (list "-n")) (def v (list "-k"))
  (list (Opts value (Opts parse f v (list "-nk2")) "-k")
        (Opts value (Opts parse f v (list "-nk" "2")) "-k")
        (Opts on? (Opts parse f v (list "-nk2")) "-n")))
```
---
    ("2" "2" #t)

### a repeated value keeps every occurrence, and `value` answers the last

```x
(do (import x/sys/opts)
  (def o (Opts parse () (list "-e") (list "-e" "a" "-e" "b")))
  (list (Opts values o "-e") (Opts value o "-e")))
```
---
    (("a" "b") "b")

### the long forms

```x
(do (import x/sys/opts)
  (list (Opts on? (Opts parse (list "--all") () (list "--all")) "--all")
        (Opts value (Opts parse () (list "--out") (list "--out=f")) "--out")))
```
---
    (#t "f")

## what is NOT an option

### a bare dash is stdin, and a negative number is an operand

```x
(do (import x/sys/opts)
  (list (Opts operands (Opts parse (list "-r") () (list "-")))
        (Opts operands (Opts parse (list "-r") () (list "-5")))))
```
---
    (("-") ("-5"))

### `--` ends the options, whatever follows looks like

```x
(do (import x/sys/opts)
  (Opts operands (Opts parse (list "-r") () (list "-r" "--" "-r" "f"))))
```
---
    ("-r" "f")

### options may follow operands, unless the caller says otherwise

`echo hi -n` prints `hi -n`: an applet whose operands can look like
flags takes parse-leading, which stops at the first of them.

```x
(do (import x/sys/opts)
  (list (Opts operands (Opts parse (list "-n") () (list "f" "-n" "g")))
        (Opts on? (Opts parse (list "-n") () (list "f" "-n")) "-n")
        (Opts operands (Opts parse-leading (list "-n") () (list "f" "-n" "g")))
        (Opts on? (Opts parse-leading (list "-n") () (list "f" "-n")) "-n")))
```
---
    (("f" "g") #t ("f" "-n" "g") #f)

### `on?` asks about PRESENCE, not which list the flag was declared in

A caller that had to remember whether `-m` stood alone or took an
argument would be re-deriving the declaration it already made.

```x
(do (import x/sys/opts)
  (def o (Opts parse (list "-v") (list "-m") (list "-v" "-m" "700")))
  (list (Opts on? o "-v") (Opts on? o "-m") (Opts on? o "-x")
        (Opts value o "-m")))
```
---
    (#t #t #f "700")

## the undeclared

### an unknown option is REMEMBERED, not raised: the caller words it

```x
(do (import x/sys/opts)
  (list (Opts unknown (Opts parse (list "-a") () (list "-z")))
        (Opts unknown (Opts parse (list "-a") () (list "-az")))
        (Opts unknown (Opts parse (list "-a") () (list "-a" "f")))))
```
---
    ("-z" "-az" ())

### a value option with nothing after it is undeclared usage, not a nil value

```x
(do (import x/sys/opts)
  (def o (Opts parse () (list "-k") (list "-k")))
  (list (Opts unknown o) (Opts value o "-k")))
```
---
    ("-k" ())

### an absent value answers the default, and an absent flag is false

```x
(do (import x/sys/opts)
  (def o (Opts parse (list "-v") (list "-w") ()))
  (list (Opts value o "-w" "6") (Opts value o "-w") (Opts on? o "-v")))
```
---
    ("6" () #f)

## a real declaration

### sort's own option set, read the way sort reads it

```x
(do (import x/sys/opts)
  (def f (list "-n" "-r" "-u" "-b" "-d" "-f" "-i" "-c" "-s" "-g" "-M"))
  (def v (list "-k" "-t" "-o"))
  (def o (Opts parse f v (list "-t," "-k2,2" "-nr" "in.txt")))
  (list (Opts value o "-t") (Opts value o "-k")
        (Opts on? o "-n") (Opts on? o "-r") (Opts on? o "-u")
        (Opts operands o) (Opts unknown o)))
```
---
    ("," "2,2" #t #t #f ("in.txt") ())

## a declaration with its help text

A command that prints usage declares its options as rows carrying their
descriptions.  The rows are what parse accepts AND what usage prints, so
an option cannot be taken and undocumented, nor documented and refused.

### the rows declare the flags and the valued options

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "" ()
           (list (Opts flag "-a" "All")
                 (Opts arg "-o" "FILE" "Output to FILE")
                 (Opts text "\t\tmore")
                 (Opts hidden (Opts flag "-z" "")))))
  (list (Opts name d) (Opts flags d) (Opts valued d)))
```
---
    ("t" ("-a" "-z") ("-o"))

### parse takes the declaration in place of the two lists

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "" ()
           (list (Opts flag "-a" "All") (Opts arg "-o" "FILE" "Out"))))
  (def o (Opts parse d (list "-ao" "x" "f")))
  (list (Opts on? o "-a") (Opts value o "-o") (Opts operands o)
        (Opts unknown (Opts parse d (list "-b")))
        (Opts operands (Opts parse-leading d (list "f" "-a")))))
```
---
    (#t "x" ("f") "-b" ("f" "-a"))

### a row's spellings are one option, whichever was given

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "" ()
           (list (Opts flag "-q" "--quiet" "Quiet")
                 (Opts arg "-O" "--output-document" "FILE" "Save to FILE"))))
  (def o (Opts parse d (list "--quiet" "-O" "a" "--output-document=b")))
  (list (Opts on? o "-q") (Opts on? o "--quiet")
        (Opts values o "-O") (Opts value o "--output-document")))
```
---
    (#t #t ("a" "b") "b")

### a hidden row is accepted

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "" () (list (Opts hidden (Opts flag "-I" "")))))
  (list (Opts on? (Opts parse d (list "-I")) "-I") (Opts usage d)))
```
---
    (#t "Usage: t\n")

## help

### help is --help as the FIRST argument, as busybox asks it

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "" () ()))
  (list (Opts help? d (list "--help")) (Opts help? d (list "--help" "f"))
        (Opts help? d (list "f" "--help")) (Opts help? d ())))
```
---
    (#t #t #f #f)

### a command may turn help off, as test, true, false and echo do

```x
(do (import x/sys/opts)
  (Opts help? (Opts declare "true" "" () () (pair 'help #f)) (list "--help")))
```
---
    #f

## the layout

Busybox's: `Usage: NAME SYNOPSIS`, a blank line, the summary, then each
listed row as a tab, its spellings and argument, and tabs out to the
description column -- the first tab stop past the widest option.

### the description column is the first tab stop past the widest option

```x
(do (import x/sys/opts)
  (def d (Opts declare "head" "[OPTIONS] [FILE]..."
           "Print first 10 lines of FILEs (or stdin).\nWith more than one FILE, precede each with a filename header."
           (list (Opts arg "-n" "N[bkm]" "Print first N lines")
                 (Opts text "\t\t\t(b:*512 k:*1024 m:*1024^2)")
                 (Opts flag "-q" "Never print headers"))))
  (str=? (Opts usage d)
    "Usage: head [OPTIONS] [FILE]...\n\nPrint first 10 lines of FILEs (or stdin).\nWith more than one FILE, precede each with a filename header.\n\n\t-n N[bkm]\tPrint first N lines\n\t\t\t(b:*512 k:*1024 m:*1024^2)\n\t-q\t\tNever print headers\n"))
```
---
    #t

### a set column wins, and a row past it still gets one tab

```x
(do (import x/sys/opts)
  (def d (Opts declare "t" "[-s] [-d SEP]" "Fields"
           (list (Opts flag "-s" "Strict")
                 (Opts arg "--output-delimiter" "SEP" "Output delimiter"))
           (pair 'column 16)))
  (str=? (Opts usage d)
    "Usage: t [-s] [-d SEP]\n\nFields\n\n\t-s\tStrict\n\t--output-delimiter SEP\tOutput delimiter\n"))
```
---
    #t

### with no summary and no rows, the Usage: line alone

```x
(do (import x/sys/opts)
  (list (Opts usage (Opts declare "tsort" "[FILE]" () ()))
        (Opts usage (Opts declare "tsort" "[FILE]" "Topological sort" ()))
        (Opts usage (Opts declare "t" "" () ()))))
```
---
    ("Usage: tsort [FILE]\n" "Usage: tsort [FILE]\n\nTopological sort\n" "Usage: t\n")

### a banner leads the text

```x
(do (import x/sys/opts)
  (Opts usage (Opts declare "t" "FILE" () () (pair 'banner "T v1 multi-call binary."))))
```
---
    "T v1 multi-call binary.\n\nUsage: t FILE\n"
