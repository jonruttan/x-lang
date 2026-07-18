; syscall.x -- x86_64, i386, and Darwin/BSD syscall tables
(import x/core/list)
(import x/core/alist)

; x86_64 syscall name table (267 entries, index = syscall number)

(def x86_64-syscall-names
  (lit (
    read
    write
    open
    close
    stat
    fstat
    lstat
    poll
    lseek
    mmap
    mprotect
    munmap
    brk
    rt_sigaction
    rt_sigprocmask
    rt_sigreturn
    ioctl
    pread64
    pwrite64
    readv
    writev
    access
    pipe
    select
    sched_yield
    mremap
    msync
    mincore
    madvise
    shmget
    shmat
    shmctl
    dup
    dup2
    pause
    nanosleep
    getitimer
    alarm
    setitimer
    getpid
    sendfile
    socket
    connect
    accept
    sendto
    recvfrom
    sendmsg
    recvmsg
    shutdown
    bind
    listen
    getsockname
    getpeername
    socketpair
    setsockopt
    getsockopt
    clone
    fork
    vfork
    execve
    exit
    wait4
    kill
    uname
    semget
    semop
    semctl
    shmdt
    msgget
    msgsnd
    msgrcv
    msgctl
    fcntl
    flock
    fsync
    fdatasync
    truncate
    ftruncate
    getdents
    getcwd
    chdir
    fchdir
    rename
    mkdir
    rmdir
    creat
    link
    unlink
    symlink
    readlink
    chmod
    fchmod
    chown
    fchown
    lchown
    umask
    gettimeofday
    getrlimit
    getrusage
    sysinfo
    times
    ptrace
    getuid
    syslog
    getgid
    setuid
    setgid
    geteuid
    getegid
    setpgid
    getppid
    getpgrp
    setsid
    setreuid
    setregid
    getgroups
    setgroups
    setresuid
    getresuid
    setresgid
    getresgid
    getpgid
    setfsuid
    setfsgid
    getsid
    capget
    capset
    rt_sigpending
    rt_sigtimedwait
    rt_sigqueueinfo
    rt_sigsuspend
    sigaltstack
    utime
    mknod
    uselib
    personality
    ustat
    statfs
    fstatfs
    sysfs
    getpriority
    setpriority
    sched_setparam
    sched_getparam
    sched_setscheduler
    sched_getscheduler
    sched_get_priority_max
    sched_get_priority_min
    sched_rr_get_interval
    mlock
    munlock
    mlockall
    munlockall
    vhangup
    modify_ldt
    pivot_root
    _sysctl
    prctl
    arch_prctl
    adjtimex
    setrlimit
    chroot
    sync
    acct
    settimeofday
    mount
    umount2
    swapon
    swapoff
    reboot
    sethostname
    setdomainname
    iopl
    ioperm
    create_module
    init_module
    delete_module
    get_kernel_syms
    query_module
    quotactl
    nfsservctl
    getpmsg
    putpmsg
    afs_syscall
    tuxcall
    security
    gettid
    readahead
    setxattr
    lsetxattr
    fsetxattr
    getxattr
    lgetxattr
    fgetxattr
    listxattr
    llistxattr
    flistxattr
    removexattr
    lremovexattr
    fremovexattr
    tkill
    time
    futex
    sched_setaffinity
    sched_getaffinity
    set_thread_area
    io_setup
    io_destroy
    io_getevents
    io_submit
    io_cancel
    get_thread_area
    lookup_dcookie
    epoll_create
    epoll_ctl_old
    epoll_wait_old
    remap_file_pages
    getdents64
    set_tid_address
    restart_syscall
    semtimedop
    fadvise64
    timer_create
    timer_settime
    timer_gettime
    timer_getoverrun
    timer_delete
    clock_settime
    clock_gettime
    clock_getres
    clock_nanosleep
    exit_group
    epoll_wait
    epoll_ctl
    tgkill
    utimes
    vserver
    mbind
    set_mempolicy
    get_mempolicy
    mq_open
    mq_unlink
    mq_timedsend
    mq_timedreceive
    mq_notify
    mq_getsetattr
    kexec_load
    waitid
    add_key
    request_key
    keyctl
    ioprio_set
    ioprio_get
    inotify_init
    inotify_add_watch
    inotify_rm_watch
    migrate_pages
    openat
    mkdirat
    mknodat
    fchownat
    futimesat
    newfstatat
    unlinkat
    renameat
    linkat
    symlinkat
    readlinkat
    fchmodat
    faccessat
    pselect6
    ppoll
    unshare
    set_robust_list
    get_robust_list
    splice
    tee
    sync_file_range
    vmsplice
    move_pages
    utimensat
    epoll_pwait
    signalfd
    timerfd_create
    eventfd
    fallocate
    timerfd_settime
    timerfd_gettime
    accept4
    signalfd4
    eventfd2
    epoll_create1
    dup3
    pipe2
    inotify_init1
    preadv
    pwritev
    rt_tgsigqueueinfo
    perf_event_open
    recvmmsg
    fanotify_init
    fanotify_mark
    prlimit64
    name_to_handle_at
    open_by_handle_at
    clock_adjtime
    syncfs
    sendmmsg
    setns
    getcpu
    process_vm_readv
    process_vm_writev
    kcmp
    finit_module
  )))
; i386 / BSD / Darwin syscall name table (index = syscall number)


(def i386-syscall-names
  (lit (
    none
    exit
    fork
    read
    write
    open
    close
    waitpid
    creat
    link
    unlink
    execve
    chdir
    time
    mknod
    chmod
    lchown
    nil
    stat
    lseek
    getpid
    mount
    oldmount
    setuid
    getuid
    stime
    ptrace
    alarm
    fstat
    pause
    utime
    nil
    nil
    access
    nice
    nil
    sync
    kill
    rename
    mkdir
    rmdir
    dup
    pipe
    times
    nil
    brk
    setgid
    getgid
    signal
    geteuid
    getegid
    acct
    umount
    nil
    ioctl
    fcntl
    nil
    setpgid
    nil
    olduname
    umask
    chroot
    ustat
    dup2
    getppid
    getpgrp
    setsid
    sigaction
    sgetmask
    ssetmask
    setreuid
    setregid
    sigsuspend
    sigpending
    sethostname
    setrlimit
    getrlimit
    getrusage
    gettimeofday
    settimeofday
    getgroups
    setgroups
    oldselect
    symlink
    lstat
    readlink
    uselib
    swapon
    reboot
    readdir
    mmap
    munmap
    truncate
    ftruncate
    fchmod
    fchown
    getpriority
    setpriority
    nil
    statfs
    fstatfs
    ioperm
    socketcall
    syslog
    setitimer
    getitimer
    stat
    lstat
    fstat
    uname
    iopl
    vhangup
    idle
    vm86old
    wait4
    swapoff
    sysinfo
    ipc
    fsync
    sigreturn
    clone
    setdomainname
    uname
    modify-ldt
    adjtimex
    mprotect
    sigprocmask
    create-module
    init-module
    delete-module
    get-kernel-syms
    quotactl
    getpgid
    fchdir
    bdflush
    sysfs
    personality
    nil
    setfsuid
    getfsgid
    llseek
    getdents
    select
    flock
    msync
    readv
    writev
    getsid
    fdatasync
    sysctl
    mlock
    munlock
    mlockall
    munlockall
    sched-setparam
    sched-getparam
    sched-setscheduler
    sched-getscheduler
    sched-yield
    sched-get-priority-max
    sched-get-priority-min
    sched-rr-get-interval
    nanosleep
    mremap
    setresuid
    getresuid
    vm86
    query-module
    poll
    nfsservctl
    setresgid
    getresgid
    prctl
    rt-sigreturn
    rt-sigaction
    rt-sigprocmask
    rt-sigpending
    rt-sigtimedwait
    rt-sigqueueinfo
    rt-sigsuspend
    pread
    pwrite
    chown
    getcwd
    capget
    capset
    sigaltstack
    sendfile
    nil
    nil
    vfork
  )))
; --- platform detection ---
; x-machine is the build triple, e.g. "arm64-apple-darwin25.5.0" vs
; "x86_64-linux-gnu". macOS uses BSD syscall numbers AND different O_* flag
; values, so the file layer keys off this too.
;
; Boot-level byte search, NOT (Str8 contains?): this platform layer loads
; mid-x-core (sys/posix.x imports it, before the str8 protocol exists), so it
; may use only the boot string accessors. With a not-yet-callable Str8, the
; old form silently captured the UNEVALUATED list -- truthy, so it looked
; right on darwin and would have mis-detected Linux.
(def %os-substr-at?
  (fn (loop needle hay i j)
    (match
      ((>= j (str-length needle)) #t)
      ((eq? (str-ref hay (+ i j)) (str-ref needle j)) (loop needle hay i (+ j 1)))
      (#t #f))))
(def %os-contains?
  (fn (loop needle hay i)
    (match
      ((> (+ i (str-length needle)) (str-length hay)) #f)
      ((%os-substr-at? needle hay i 0) #t)
      (#t (loop needle hay (+ i 1))))))
(def os-darwin? (%os-contains? "darwin" x-machine 0))
(def os-linux? (%os-contains? "linux" x-machine 0))

; --- File open-mode flags (O_*) ---
; PLATFORM truth: the O_* flag VALUES differ by OS (verified: macOS
; O_CREAT=512 / O_TRUNC=1024 vs Linux 64 / 512), so there is one table per
; platform and %file-modes picks at load via os-darwin?.  Consumed by
; sys/file.x (the (File file-modes) method + symbolic open modes) and
; sys/posix.x (its libc open() calls).  Formerly C-bound %O_* constants;
; retired with the ISA audit -- platform data is policy and lives in X.
(def %file-modes-linux (list
  (list (lit accmode)    3)        ; 00000003
  (list (lit rdonly)     0)        ; 00000000
  (list (lit wronly)     1)        ; 00000001
  (list (lit rdwr)       2)        ; 00000002
  (list (lit creat)      64)       ; 00000100
  (list (lit excl)       128)      ; 00000200
  (list (lit noctty)     256)      ; 00000400
  (list (lit trunc)      512)      ; 00001000
  (list (lit append)     1024)     ; 00002000
  (list (lit nonblock)   2048)     ; 00004000
  (list (lit dsync)      4096)     ; 00010000
  (list (lit fasync)     8192)     ; 00020000
  (list (lit direct)     16384)    ; 00040000
  (list (lit largefile)  32768)    ; 00100000
  (list (lit directory)  65536)    ; 00200000
  (list (lit nofollow)   131072)   ; 00400000
  (list (lit noatime)    262144)   ; 01000000
  (list (lit cloexec)    524288)   ; 02000000
  (list (lit sync)       1048576)  ; 04000000
  (list (lit path)       2097152)))  ; 010000000

; Darwin/macOS O_* flag values (from <sys/fcntl.h>) -- note the divergence from
; Linux (creat/trunc/excl especially). Subset File needs plus common flags;
; Linux-only flags (dsync/direct/largefile/noatime/path/...) are omitted.
(def %file-modes-darwin (list
  (list (lit accmode)   3)          ; 0x0003
  (list (lit rdonly)    0)          ; 0x0000
  (list (lit wronly)    1)          ; 0x0001
  (list (lit rdwr)      2)          ; 0x0002
  (list (lit nonblock)  4)          ; 0x0004
  (list (lit append)    8)          ; 0x0008
  (list (lit nofollow)  256)        ; 0x0100
  (list (lit creat)     512)        ; 0x0200
  (list (lit trunc)     1024)       ; 0x0400
  (list (lit excl)      2048)       ; 0x0800
  (list (lit noctty)    131072)     ; 0x20000
  (list (lit directory) 1048576)    ; 0x100000
  (list (lit cloexec)   16777216))) ; 0x1000000

; Select the table for this OS at load.  Both probes explicit: an
; unrecognized platform must fail loudly here, not silently run with Linux
; flag values (wrong O_* values corrupt the interpreter via raw syscalls).
(def %file-modes
  (match
    (os-darwin? %file-modes-darwin)
    (os-linux? %file-modes-linux)
    (#t (error (pair (lit unsupported-platform) x-machine)))))

; Darwin/BSD syscall numbers (from <sys/syscall.h>). Bare numbers: macOS libc
; syscall() OR-folds the UNIX class (0x2000000), so the bare BSD number reaches
; the kernel (verified: syscall(5,...) opens). BSD numbers are sparse, so an
; alist rather than the index=number lists the Linux tables use. Subset File
; needs, plus a few common calls.
(def darwin-syscall-numbers
  (list
    (list (lit exit)   1)  (list (lit fork)  2)
    (list (lit read)   3)  (list (lit write) 4)
    (list (lit open)   5)  (list (lit close) 6)
    (list (lit wait4)  7)  (list (lit unlink) 10)
    (list (lit execve) 59) (list (lit mkdir) 136)
    (list (lit stat)   188) (list (lit fstat) 189) (list (lit lstat) 190)
    (list (lit lseek)  199)))

; syscall-id: look up a syscall number by name. On Darwin, use the BSD alist;
; elsewhere the x86_64 index table (falling back to i386). Returns the number,
; or -1 if not found.
(def syscall-id
  (fn (_ call)
    (if os-darwin?
      (let ((e (assoc-get call darwin-syscall-numbers)))
        (if (null? e) -1 (first e)))
      ; index-of misses with nil; -1 stays this table's OS-domain invalid
      ; marker (never a valid syscall number)
      (let ((n (List index-of call x86_64-syscall-names)))
        (if (null? n)
          (let ((m (List index-of call i386-syscall-names)))
            (if (null? m) -1 m))
          n)))))

(doc (provide x/platform/syscall
  syscall-id os-darwin? x86_64-syscall-names i386-syscall-names darwin-syscall-numbers)
  (note "syscall-id is platform-aware: Darwin -> bare BSD numbers (libc OR-folds the 0x2000000 UNIX class), else Linux x86_64/i386. os-darwin? is the platform flag (from x-machine).")
  "Syscall number tables for x86_64, i386, and Darwin/BSD. Maps symbolic names to syscall numbers.")
