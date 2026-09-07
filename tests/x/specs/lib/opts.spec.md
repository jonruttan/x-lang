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
