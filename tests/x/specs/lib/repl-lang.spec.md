# Lang: the languages a session switches between
# @weight 1

A prompt is a bundle of the REPL's seams: `%repl-prompt`, `%repl-prompt-more`,
`%repl-print`, `%repl-paint`, `%repl-marks`, `%repl-complete` and
`%repl-eval-line`. `Lang` keeps such bundles by name, `(Lang use! NAME)`
installs one, and `(lang NAME)` is the same switch as a verb typed at the
prompt. x-lang's own is registered as `"x"` by the files that own its parts.

Every case that switches away switches back with `(lang x)`, so the seams a
later file reads are the platform's. The editor cases import `x/repl/line`,
which registers what it owns into `"x"` whether or not there is a terminal.

## the registry

### x is registered first, and is current until something else is installed

```x
(list (first (Lang names)) (Lang current))
```
---
    ("x" "x")

### the vocabulary is the seven seams and the two banner names

```x
(list (List length (Lang keys)) (first (Lang keys)))
```
---
    (9 '%repl-prompt)

### what boot registers for x: the prompts and the printer

```x
(list (Assoc get '%repl-prompt (Lang get "x"))
      (Assoc get '%repl-prompt-more (Lang get "x"))
      (procedure? (Assoc get '%repl-print (Lang get "x"))))
```
---
    ("> " "..   " #t)

### register! keeps the alist, and get answers it

```x
(do (Lang register! "t1" (list (pair '%repl-prompt "t1> ") (pair '%repl-paint ())))
    (Lang get "t1"))
```
---
    (('%repl-prompt . "t1> ") ('%repl-paint))

### registering again merges: given keys replace, others stay

```x
(do (Lang register! "t1" (list (pair '%repl-prompt-more "t1.. ")))
    (list (Assoc get '%repl-prompt (Lang get "t1"))
          (Assoc get '%repl-prompt-more (Lang get "t1"))
          (Assoc has? '%repl-paint (Lang get "t1"))))
```
---
    ("t1> " "t1.. " #t)

### a symbol names a lang as well as a string

```x
(list (Lang get 't1) (Lang get "t1"))
```
---
    ((('%repl-prompt-more . "t1.. ") ('%repl-prompt . "t1> ") ('%repl-paint)) (('%repl-prompt-more . "t1.. ") ('%repl-prompt . "t1> ") ('%repl-paint)))

### a key outside the vocabulary is refused

```x
(guard (e (Err tag e))
  (Lang register! "t2" (list (pair '%repl-nope 1))))
```
---
    'lang

### an entry that is not a pair is refused

```x
(guard (e (Err tag e))
  (Lang register! "t2" (list '%repl-prompt)))
```
---
    'lang

### a name nobody registered is refused

```x
(guard (e (Err tag e)) (Lang use! "nobody"))
```
---
    'lang

## installing one

### use! sets the seams the lang names

```x
(do (Lang use! "t1")
    (let ((r (list (Lang current) %repl-prompt %repl-prompt-more %repl-paint)))
      (lang x)
      r))
```
---
    ("t1" "t1> " "t1.. " ())

### a seam the lang does not name takes x's value

```x
(do (Lang register! "t3" (list (pair '%repl-prompt "t3> ")))
    (Lang use! "t3")
    (let ((r (list %repl-prompt %repl-prompt-more
                   (same? %repl-print (Assoc get '%repl-print (Lang get "x"))))))
      (lang x)
      r))
```
---
    ("t3> " "..   " #t)

### switching back restores x

```x
(do (lang t1)
    (lang x)
    (list (Lang current) %repl-prompt %repl-prompt-more
          (same? %repl-print (Assoc get '%repl-print (Lang get "x")))))
```
---
    ("x" "> " "..   " #t)

### (lang NAME) takes a bare name or a string

```x
(do (lang t1)
    (let ((a %repl-prompt))
      (lang "t3")
      (let ((b %repl-prompt))
        (lang x)
        (list a b %repl-prompt))))
```
---
    ("t1> " "t3> " "> ")

### (lang) lists the registered langs and names the current one

```x
(do (lang) ())
```
---
```output
current: x  registered: x t1 t3
```

## with the editor loaded

### the editor registers its line evaluator and completer as x's

```x
(do (import x/repl/line)
    (let ((%ln-eval-line (eval (lit %ln-eval-line) (module x/repl/line)))
          (%ln-candidates (eval (lit %ln-candidates) (module x/repl/line))))
      (list (same? (Assoc get '%repl-eval-line (Lang get "x")) %ln-eval-line)
            (same? (Assoc get '%repl-complete (Lang get "x")) %ln-candidates)
            (procedure? (Assoc get '%repl-paint (Lang get "x")))
            (procedure? (Assoc get '%repl-marks (Lang get "x"))))))
```
---
    (#t #t #t #t)

### a lang's line evaluator replaces the editor's, and x's comes back

```x
(do (import x/repl/line)
    (let ((%ln-eval-line (eval (lit %ln-eval-line) (module x/repl/line)))
          (%ln-candidates (eval (lit %ln-candidates) (module x/repl/line))))
      (let ((mine (fn (_ s) ())))
        (Lang register! "t4" (list (pair '%repl-eval-line mine) (pair '%repl-complete ())))
        (lang t4)
        (let ((during (list (same? %repl-eval-line mine) (null? %repl-complete)
                            (null? (Line completer)))))
          (lang x)
          (list during (same? %repl-eval-line %ln-eval-line)
                (same? %repl-complete %ln-candidates)
                (same? (Line completer) %ln-candidates))))))
```
---
    ((#t #t #t) #t #t #t)

### (Line completer f) sets the seam the lang bundle names

```x
(do (import x/repl/line)
    (let ((mine (fn (_ e) (pair "" ()))))
      (Line completer mine)
      (let ((r (same? %repl-complete mine)))
        (lang x)
        r)))
```
---
    #t
