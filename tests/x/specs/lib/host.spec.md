# Host: the machine as the kernel reports it
# @weight 3

`(Host ...)` answers the same records on Linux and Darwin. The first
section asks this kernel and checks what must hold of any machine; its
values change from run to run. The second points the Linux reader at a
fixture `/proc` tree under `tests/x/fixtures/host/proc`, so its values are
fixed and it runs on either kernel. Each fixture case sets the source back
to this kernel's before it ends (`(Host source ())` would read the field, not
clear it), so a later case in the same batch reads the real machine.

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
    (('total 'free 'shared 'buffers 'cached 'reclaimable 'available 'swap-total 'swap-free 'anon 'mapped 'slab 'dirty 'writeback) #t #t #t)

### cpu: ten fields, idle and user counted

```x
(do (import x/sys/host)
  (def c (Host cpu))
  (list (Assoc keys c) (< 0 (Assoc get 'idle c)) (< 0 (Assoc get 'user c))))
```
---
    (('user 'nice 'system 'idle 'iowait 'irq 'softirq 'steal 'guest 'guest-nice) #t #t)

### this process is in the table, owned by this user, with memory and CPU time

```x
(do (import x/sys/host)
  (def me (Sys getpid))
  (def procs (Host processes))
  (def row (List find (fn (_ r) (= me (Assoc get 'pid r))) procs))
  (def one (Host process me))
  (list (Assoc keys row)
        (= (Assoc get 'uid row) (Sys geteuid))
        (and (< 0 (Str8 length (Assoc get 'comm row))) (str=? (Assoc get 'comm row) (Assoc get 'comm one)))
        (< 0 (Assoc get 'rss one))
        (< 0 (Assoc get 'utime one))
        (< 1 (List length procs))))
```
---
    (('pid 'ppid 'pgid 'sid 'uid 'gid 'ruid 'rgid 'state 'comm 'tty 'tty-major 'tty-minor 'nice 'start 'threads 'vsz 'rss 'utime 'stime 'processor) #t #t #t #t #t)

### this process's ids: real and effective user and group, its process group and session

```x
(do (import x/sys/host)
  (def one (Host process (Sys getpid)))
  (list (= (Assoc get 'ruid one) (Sys getuid)) (= (Assoc get 'rgid one) (Sys getgid))
        (= (Assoc get 'gid one) (Sys getegid))
        (< 0 (Assoc get 'pgid one)) (< 0 (Assoc get 'sid one))))
```
---
    (#t #t #t #t #t)

### this process's executable is an absolute path to the engine

```x
(do (import x/sys/host)
  (def e (Host exe (Sys getpid)))
  ; x-bin, or a variant build of it: x-bin-asan, x-bin-cov
  (list (Str8 starts? "/" e) (not (null? (Str8 index-of "/x-bin" e)))))
```
---
    (#t #t)

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

### tasks: Linux counts the run queue and the last pid; Darwin reports none

```x
(do (import x/sys/host)
  (def t (Host tasks))
  (def get (fn (_ k) (Assoc get k t)))
  (list (Assoc keys t)
        (if os-darwin?
          (List all? null? (Assoc vals t))
          (and (<= 1 (get 'running)) (<= (get 'running) (get 'total)) (< 0 (get 'last-pid))))))
```
---
    (('running 'total 'last-pid) #t)

### cpus: a record a processor, each with cpu's fields and idle counted

```x
(do (import x/sys/host)
  (def cs (Host cpus))
  (list (< 0 (List length cs))
        (List all? (fn (_ c) (and (equal? (Assoc keys c) (Assoc keys (Host cpu))) (< 0 (Assoc get 'idle c)))) cs)))
```
---
    (#t #t)

### threads: this process has at least one, each with a record's fields and CPU time

```x
(do (import x/sys/host)
  (def me (Sys getpid))
  (def ts (Host threads me))
  (list (< 0 (List length ts))
        (List all? (fn (_ t) (and (equal? (Assoc keys t) (Assoc keys (Host process me)))
                                  (number? (Assoc get 'pid t)) (number? (Assoc get 'utime t))))
          ts)
        (Host threads 999999999)))
```
---
    (#t #t ())

### maps: this process has readable and writable mappings, resident and dirty

```x
(do (import x/sys/host)
  (def m (Host maps (Sys getpid)))
  (def get (fn (_ k) (Assoc get k m)))
  (list (Assoc keys m) (< 0 (get 'mapped-ro)) (< 0 (get 'mapped-rw)) (< 0 (get 'private-dirty))
        (Host maps 999999999)))
```
---
    (('mapped-ro 'mapped-rw 'stack 'shared-clean 'shared-dirty 'private-clean 'private-dirty) #t #t #t ())

### files: this process's directory, executable, a file it opens by path and inode, and the libraries it maps

```x
(do (import x/sys/host)
  (def path "tests/x/fixtures/host/proc/stat")
  (def fd (File open path 'rdonly))
  (def fs (Host files (Sys getpid)))
  (def fds (Host files (Sys getpid) 'fd))
  (File close fd)
  (def r (List find (fn (_ f) (= fd (Assoc get 'fd f))) fs))
  (def used (fn (_ u) (List filter (fn (_ f) (eq? u (Assoc get 'use f))) fs)))
  (def cwd (first (used 'cwd)))
  (list (Assoc keys r) (Assoc get 'type r) (Str8 ends? "/tests/x/fixtures/host/proc/stat" (Assoc get 'name r))
        (equal? (Host %dev-ino path) (pair (Assoc get 'dev r) (Assoc get 'ino r)))
        (equal? (Host %dev-ino ".") (pair (Assoc get 'dev cwd) (Assoc get 'ino cwd)))
        (List length (used 'exe)) (< 0 (List length (used 'map)))
        (List all? (fn (_ f) (eq? 'fd (Assoc get 'use f))) fds)
        (List map (fn (_ f) (Assoc get 'fd f)) (List take 3 fds))
        (Host files 999999999)))
```
---
    (('use 'fd 'dev 'ino 'type 'name 'id) 'file #t #t #t 1 #t #t (0 1 2) ())

### holders: this process holds its working directory, and its file system; a path that will not stat has none

```x
(do (import x/sys/host)
  (def me (Sys getpid))
  (def hs (Host holders "."))
  (list (List includes? me hs) (List includes? me (Host holders "." #t))
        (equal? hs (List sort < hs)) (Host holders "/no/such/path")))
```
---
    (#t #t #t ())

### utmp: every entry has a user and a type, and users is its user-process entries

```x
(do (import x/sys/host)
  (def es (Host utmp))
  (def kinds '(run-level boot-time new-time old-time init-process login-process user-process dead-process accounting signature shutdown-time))
  (list (List all? (fn (_ e) (and (str? (Assoc get 'user e))
                                  (let ((k (Assoc get 'type e))) (if (null? k) #t (not (null? (List find (fn (_ x) (eq? x k)) kinds))))))) es)
        (= (List length (List filter (fn (_ e) (eq? (Assoc get 'type e) 'user-process)) es))
           (List length (Host users)))))
```
---
    (#t #t)

### counters: faults and open files counted; Darwin reports no context switches

```x
(do (import x/sys/host)
  (def c (Host counters))
  (def get (fn (_ k) (Assoc get k c)))
  (list (Assoc keys c)
        (< 0 (get 'faults)) (< 0 (get 'paged-in))
        (< 0 (get 'open-files)) (<= (get 'open-files) (get 'max-files))
        (if os-darwin? (null? (get 'context-switches)) (< 0 (get 'context-switches)))))
```
---
    (('context-switches 'interrupts 'softirqs 'forks 'running 'blocked 'paged-in 'paged-out 'swap-ins 'swap-outs 'faults 'major-faults 'open-files 'max-files) #t #t #t #t #t)

### disks: each has a name and read and write totals, and one has been read

```x
(do (import x/sys/host)
  (def ds (Host disks))
  (list (< 0 (List length ds))
        (List all? (fn (_ d) (and (str? (Assoc get 'name d)) (number? (Assoc get 'reads d))
                                  (number? (Assoc get 'write-bytes d))))
          ds)
        (List any? (fn (_ d) (< 0 (Assoc get 'read-bytes d))) ds)))
```
---
    (#t #t #t)

### interfaces: each has a name and traffic totals, and a loopback is among them

```x
(do (import x/sys/host)
  (def is (Host interfaces))
  (list (List all? (fn (_ i) (and (str? (Assoc get 'name i)) (number? (Assoc get 'rx-bytes i))
                                  (number? (Assoc get 'tx-packets i))))
          is)
        (List any? (fn (_ i) (Str8 starts? "lo" (Assoc get 'name i))) is)))
```
---
    (#t #t)

### interrupts: Linux counts each source per processor, softirqs too; Darwin reports none

```x
(do (import x/sys/host)
  (def rs (Host interrupts))
  (if os-darwin? (null? rs)
    (and (List any? (fn (_ r) (Assoc get 'soft? r)) rs)
         (List all? (fn (_ r) (and (str? (Assoc get 'name r)) (number? (Assoc get 'total r)))) rs))))
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
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
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
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (list (List map (fn (_ k) (Assoc get k p)) '(ppid pgid sid tty tty-major tty-minor nice start threads vsz utime stime ruid rgid))
        (List map (fn (_ k) (Assoc get k i)) '(tty tty-major tty-minor ruid rgid))
        (= (Assoc get 'uid p) (Sys geteuid))
        (< 0 (Assoc get 'rss i))))
```
---
    ((1 42 42 34816 136 0 -5 1790000010 3 4096 70000000 30000000 1000 100) (() () () () ()) #t #t)

### exe reads the /proc/PID/exe link, and a process with none has no exe

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (Host exe 42) (Host exe 1)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    ("/bin/sh" ())

### args splits cmdline on NUL; an empty cmdline is a kernel thread's

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (Host args 42) (Host args 1) (Host process 7)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
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
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (Assoc vals c))
```
---
    (1000000000 20000000 300000000 4000000000 50000000 60000000 70000000 80000000 90000000 10000000)

### tasks reads /proc/loadavg's run queue and last pid

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def t (Host tasks))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (Assoc vals t))
```
---
    (2 1234 56789)

### cpus reads each cpuN line, and processor is field 39

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def cs (Host cpus))
  (def ps (list (Assoc get 'processor (Host process 42)) (Assoc get 'processor (Host process 1))))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (list (List map (fn (_ c) (list (Assoc get 'user c) (Assoc get 'idle c))) cs) ps))
```
---
    (((600000000 2500000000) (400000000 1500000000)) (3 0))

### a stat line that ends at rss reads, and the fields past its end are nil

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/short")
  (def p (Host process 9))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (List map (fn (_ k) (Assoc get k p)) '(pid ppid comm vsz processor)))
```
---
    (9 1 "sleep" 4096 ())

### threads reads /proc/PID/task: each thread's own name, state, CPU time and processor

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (List map (fn (_ t) (List map (fn (_ k) (Assoc get k t)) '(pid comm state utime stime processor ppid)))
                 (Host threads 42))
               (Host threads 1)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    (((42 "a) b" "R" 70000000 30000000 3 1) (43 "worker" "S" 500000000 200000000 1 1)) ())

### maps sums /proc/PID/smaps as BusyBox does: a device and a guard gap count in no size

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (Assoc vals (Host maps 42)) (Host maps 1)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    ((335872 139264 135168 307200 4096 8192 16384) ())

### files reads the /proc/PID links, the fds in order, a socket joined to /proc/net by inode, and each mapped file once

The links' devices and inodes are this machine's: /dev/null's is read, the
fixture's socket has none to stat.  A maps line spells its own MAJ:MIN,
packed as this platform's stat(2) packs a device.

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def fs (Host files 42))
  (def r (list (List map (fn (_ f) (List map (fn (_ k) (Assoc get k f)) '(use fd type name id proto family port))) fs)
               (equal? (List map (fn (_ f) (list (Assoc get 'dev f) (Assoc get 'ino f))) (List filter (fn (_ f) (eq? 'map (Assoc get 'use f))) fs))
                       (if os-darwin? (lit ((134217729 1234) (4345298946 98765) (5 4242))) (lit ((2049 1234) (66306 98765) (5 4242)))))
               (number? (Assoc get 'ino (List find (fn (_ f) (equal? 0 (Assoc get 'fd f))) fs)))
               (Assoc get 'ino (List find (fn (_ f) (equal? 1 (Assoc get 'fd f))) fs))
               (List map (fn (_ f) (Assoc get 'name f)) (Host files 42 'cwd 'map))
               (Host files 1)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    ((('cwd () 'file "/tmp" () () () ()) ('root () 'file "/" () () () ()) ('exe () 'file "/bin/sh" () () () ()) ('fd 0 'file "/dev/null" () () () ()) ('fd 1 'socket "socket:[12345]" 12345 'tcp 4 8080) ('fd 2 'pipe "pipe:[678]" 678 () () ()) ('fd 3 'file "/tmp/gone (deleted)" () () () ()) ('fd 4 'anon_inode "anon_inode:inotify" () () () ()) ('fd 10 'anon_inode "anon_inode:[eventfd]" () () () ()) ('map () 'file "/bin/busybox" () () () ()) ('map () 'file "/lib/ld-musl-x86_64.so.1" () () () ()) ('map () 'file "/dev/zero (deleted)" () () () ())) #t #t () ("/tmp" "/bin/busybox" "/lib/ld-musl-x86_64.so.1" "/dev/zero (deleted)") ())

### holders reads each process's files: a descriptor, an executable, a whole file system, and a path no process holds

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (list (Host holders "/dev/null") (Host holders "/bin/sh") (Host holders "/dev/null" #t)
               (Host holders "tests/x/specs/lib/host.spec.md")))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    ((42) (42) (42) ())

### counters reads /proc/stat, /proc/vmstat and file-nr: KiB paged to bytes, open files in use

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def c (Host counters))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  (Assoc vals c))
```
---
    (77777 5000 6000 99 3 1 2097152 524288 7 9 123456 321 2000 9223372036854775807)

### interrupts reads both tables; a source counted once has no per-processor counts

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (List map (fn (_ i) (Assoc vals i)) (Host interrupts)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    (("0" ((0 . 44) (2 . 1)) 45 "IO-APIC 2-edge timer" #f) ("8" ((0 . 0) (2 . 0)) 0 "IO-APIC 8-edge rtc0" #f) ("NMI" ((0 . 5) (2 . 6)) 11 "Non-maskable interrupts" #f) ("ERR" () 0 () #f) ("HI" ((0 . 1) (2 . 2)) 3 () #t) ("TIMER" ((0 . 300) (2 . 400)) 700 () #t))

### disks reads /proc/diskstats: sectors to bytes, milliseconds to nanoseconds, an old partition line's four figures

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (List map (fn (_ d) (Assoc vals d)) (Host disks)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    (("sda" 8 0 100 5 1024000 30000000 50 6 512000 40000000 0 60000000 70000000) ("sda1" 8 1 90 4 921600 25000000 45 5 460800 35000000 0 55000000 60000000) ("hda1" 3 1 11 () 11264 () 33 () 22528 () () () ()))

### interfaces reads /proc/net/dev past its two header lines, a total right after the colon too

```x
(do (import x/sys/host)
  (Host source 'linux)
  (Host proc-root "tests/x/fixtures/host/proc")
  (def r (List map (fn (_ i) (Assoc vals i)) (Host interfaces)))
  (Host source (if os-darwin? (lit darwin) (lit linux))) (Host proc-root "/proc")
  r)
```
---
    (("lo" 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0) ("eth0" 123456789 4321 1 2 3 4 5 6 98765 432 7 8 9 10 11 12))
