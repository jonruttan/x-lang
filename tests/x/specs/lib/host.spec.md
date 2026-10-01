# Host: the machine as the kernel reports it
# @weight 3

`(Host ...)` answers the same records on Linux and Darwin. The first
section asks this kernel and checks what must hold of any machine; its
values change from run to run. The second points the Linux reader at a
fixture `/proc` tree under `tests/x/fixtures/host/proc`, so its values are
fixed and it runs on either kernel. Each fixture case puts the source back
before it ends, so a later case in the same batch reads the real machine.

## this kernel

### boot time is in the past and load is three non-negative numbers

```x
(do (import x/sys/host)
  (def b (Host boot-time))
  (def l (Host load))
  (list (< 0 b) (<= b (Sys now)) (List length l)
        (List none? (fn (_ x) (Float < x 0)) l)))
```
---
    (#t #t 3 #t)

### memory: a total, free within it, swap free within swap

```x
(do (import x/sys/host)
  (def m (Host memory))
  (def get (fn (_ k) (Assoc get k m)))
  (list (Assoc keys m)
        (< 0 (get 'total))
        (<= (get 'free) (get 'total))
        (<= (get 'swap-free) (get 'swap-total))))
```
---
    (('total 'free 'shared 'buffers 'cached 'reclaimable 'available 'swap-total 'swap-free) #t #t #t)

### cpu: eight fields, idle and user counted

```x
(do (import x/sys/host)
  (def c (Host cpu))
  (list (Assoc keys c) (< 0 (Assoc get 'idle c)) (< 0 (Assoc get 'user c))))
```
---
    (('user 'nice 'system 'idle 'iowait 'irq 'softirq 'steal) #t #t)

### this process is in the table, owned by this user, with memory and CPU time

```x
(do (import x/sys/host)
  (def me (Sys getpid))
  (def row (List find (fn (_ r) (= me (Assoc get 'pid r))) (Host processes)))
  (def one (Host process me))
  (list (Assoc keys row)
        (= (Assoc get 'uid row) (Sys geteuid))
        (and (< 0 (Str8 length (Assoc get 'comm row))) (str=? (Assoc get 'comm row) (Assoc get 'comm one)))
        (< 0 (Assoc get 'rss one))
        (< 0 (Assoc get 'utime one))
        (< 1 (List length (Host processes)))))
```
---
    (('pid 'ppid 'uid 'state 'comm 'tty 'nice 'start 'threads 'vsz 'rss 'utime 'stime) #t #t #t #t #t)

### this process's arguments are strings; a pid that does not exist has no record

```x
(do (import x/sys/host)
  (def a (Host args (Sys getpid)))
  (list (< 0 (List length a)) (List all? (fn (_ s) (and (str? s) (< 0 (Str8 length s)))) a) (Host process 999999999)))
```
---
    (#t #t ())

### users: every session has a user, a tty and a login time

```x
(do (import x/sys/host)
  (List all? (fn (_ u) (and (str? (Assoc get 'user u)) (str? (Assoc get 'tty u))
                            (< 0 (Assoc get 'time u))))
    (Host users)))
```
---
    #t

## a fixture /proc

### processes skips a directory that is not a pid and reads both rows

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (List sort-by (fn (_ p) (Assoc get 'pid p)) (Host processes)))
  (Host source ()) (Host proc-root "/proc")
  (List map (fn (_ p) (list (Assoc get 'pid p) (Assoc get 'comm p) (Assoc get 'state p))) r))
```
---
    ((1 "init" "S") (42 "a) b" "R"))

### a row's fields: ppid, tty, nice, start from btime, threads, size, CPU time

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def p (Host process 42))
  (def i (Host process 1))
  (Host source ()) (Host proc-root "/proc")
  (list (List map (fn (_ k) (Assoc get k p)) '(ppid tty nice start threads vsz utime stime))
        (Assoc get 'tty i)
        (= (Assoc get 'uid p) (Sys geteuid))
        (< 0 (Assoc get 'rss i))))
```
---
    ((1 34816 -5 1790000010 3 4096 70000000 30000000) () #t #t)

### args splits cmdline on NUL; an empty cmdline is a kernel thread's

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (Host args 42) (Host args 1) (Host process 7)))
  (Host source ()) (Host proc-root "/proc")
  r)
```
---
    (("sh" "-c" "echo hi") () ())

### cpu reads the aggregate line, ticks to nanoseconds

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def c (Host cpu))
  (Host source ()) (Host proc-root "/proc")
  (Assoc vals c))
```
---
    (1000000000 20000000 300000000 4000000000 50000000 60000000 70000000 80000000)
