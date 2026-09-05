; platform/data/syscalls-darwin.x -- the Darwin/BSD syscall-number alist (#38: split from
; platform/syscall.x, which was 95% literal data). One table per file,
; loaded by syscall.x via include-once; boot-constrained (loads
; mid-x-core through sys/posix.x), so boot accessors only.

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
    (list (lit execve) 59) (list (lit rename) 128)
    (list (lit mkdir)  136) (list (lit rmdir) 137)
    (list (lit stat)   188) (list (lit fstat) 189) (list (lit lstat) 190)
    (list (lit lseek)  199) (list (lit ftruncate) 201)
    ; 64-bit-inode variants (#22): the plain stat trio above returns the
    ; LEGACY 32-bit-ino struct on Darwin; stat64/fstat64/lstat64 return the
    ; layout File stat decodes (mode@4 mtime@48 size@96).  getdirentries64
    ; is Darwin's dirent reader (Linux uses getdents64 from the index table).
    (list (lit stat64) 338) (list (lit fstat64) 339) (list (lit lstat64) 340)
    (list (lit getdirentries64) 344)
    ; wall clock (#21): the timeval decode is OS-shared (sec i64@0; usec
    ; fits the low u32@8 on both -- Darwin's tv_usec is a 32-bit field,
    ; Linux's is an i64 whose value is < 1e6).
    (list (lit gettimeofday) 116)
    ; The metadata and identity tail.  Linux reaches all of these through
    ; the index table already; Darwin's are sparse, so they are named
    ; here.  statfs64 (345), not statfs (157): the legacy number returns
    ; the 32-bit-inode struct, whose f_bsize reads back zero.
    (list (lit chmod) 15) (list (lit chown) 16)
    (list (lit link) 9) (list (lit symlink) 57) (list (lit readlink) 58)
    (list (lit utimes) 138) (list (lit truncate) 200)
    (list (lit mknod) 14) (list (lit chroot) 61)
    (list (lit sync) 36) (list (lit fsync) 95)
    (list (lit statfs64) 345)
    (list (lit getuid) 24) (list (lit geteuid) 25)
    (list (lit getgid) 47) (list (lit getegid) 43)
    (list (lit getgroups) 79) (list (lit setpriority) 96)))

; syscall-id: look up a syscall number by name. On Darwin, use the BSD alist;
; elsewhere the x86_64 index table (falling back to i386). Returns the number,
; or -1 if not found.
