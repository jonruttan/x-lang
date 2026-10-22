# Pty: a program on a pseudo-terminal
# @weight 2

Each case opens a real pseudo-terminal pair; the spawn cases run a child
on it and read back, from the master, what the child wrote.

## the harness

### a descriptor read to its end: here a pipe, below a master

```x
(import x/sys/pty)
(import x/sys/posix)
(import x/sys/file)
(import x/repl/term)

; Everything the master gives until the child's side closes: read answers
; 0, or -1 (EIO) once the slave is gone.
(def %pty-drain
  (fn (_ fd)
    (def buf ((prim-ref 'str 'make) 256))
    (let go ((acc ""))
      (let ((n (File read fd buf 256)))
        (if (<= n 0) acc (go (Str8 append acc (Str8 sub 0 n buf))))))))

(def %pty-ends?
  (fn (_ s tail)
    (if (< (Str8 length s) (Str8 length tail)) #f
      (str=? (Str8 sub (- (Str8 length s) (Str8 length tail)) (Str8 length tail) s) tail))))

(def %pty-fds (Sys pipe))
(Sys fd-write (rest %pty-fds) "one\ntwo")
(Sys close (rest %pty-fds))
(def %pty-got (%pty-drain (first %pty-fds)))
(Sys close (first %pty-fds))
(list %pty-got (%pty-ends? %pty-got "two") (%pty-ends? "o" "two"))
```
---
    ("one\ntwo" #t #f)

## open

### a master that is a terminal and the slave's path under /dev

```x
(do
  (def p (Pty open))
  (def r (list (>= (first p) 0) (Sys isatty (first p)) (Str8 sub 0 5 (rest p))))
  (File close (first p))
  r)
```
---
    (#t #t "/dev/")

## window!

### a window set on the slave is the one the terminal reports

```x
(do
  (def p (Pty open))
  (def s (File open (rest p) (list 'rdwr 'noctty)))
  (def r (list (Pty window! s 100 30) (Term measure s)))
  (File close s) (File close (first p))
  r)
```
---
    (#t (100 . 30))

### set on the master once the slave is open, it reaches the slave

```x
(do
  (def p (Pty open))
  (def s (File open (rest p) (list 'rdwr 'noctty)))
  (Pty window! s 80 24)
  (def r (list (Pty window! (first p) 132 43) (Term measure s)))
  (File close s) (File close (first p))
  r)
```
---
    (#t (132 . 43))

### a descriptor that is no terminal answers #f

```x
(do
  (def fds (Sys pipe))
  (def r (Pty window! (first fds) 80 24))
  (Sys close (first fds)) (Sys close (rest fds))
  r)
```
---
    #f

## spawn

### stty size in the child reports the window it was spawned at

```x
(do
  (def c (Pty spawn "stty" (list "size") 91 27))
  (def out (%pty-drain (rest c)))
  (File close (rest c))
  (list (Sys wait (first c)) out))
```
---
    (0 "27 91\r\n")

### a resize on the master while the child runs is what it reads next

```x
(do
  (def c (Pty spawn "/bin/sh" (list "-c" "echo r; read x; stty size") 80 24))
  (def m (rest c))
  (def buf ((prim-ref 'str 'make) 64))
  (def first-read (Str8 sub 0 (File read m buf 64) buf))
  (Pty window! m 50 20)
  (File write m "\n" 1)
  (def out (%pty-drain m))
  (File close m)
  (list (Sys wait (first c)) (Str8 sub 0 1 first-read) (%pty-ends? out "20 50\r\n")))
```
---
    (0 "r" #t)

### a program that cannot be run exits 127

```x
(do
  (def c (Pty spawn "/nonexistent/x-pty-spec" () 80 24))
  (%pty-drain (rest c))
  (File close (rest c))
  (Sys wait (first c)))
```
---
    127

## fork

### the child is attached: its terminal is the slave, at the window given

```x
(do
  (def c (Pty fork 70 21))
  (when (= (first c) 0)
    (do (def w (Term measure 0))
        (Sys fd-write 1 (Str8 append (if (Sys isatty 1) "tty " "no ")
                                     ((prim-ref 'convert 'to) (first w) (Type named STRING) 10) "x"
                                     ((prim-ref 'convert 'to) (rest w) (Type named STRING) 10) "\n"))
        (Sys exit 0)))
  (def out (%pty-drain (rest c)))
  (File close (rest c))
  (list (Sys wait (first c)) out))
```
---
    (0 "tty 70x21\r\n")
