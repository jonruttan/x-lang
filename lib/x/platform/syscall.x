; syscall.x -- x86_64, i386, and Darwin/BSD syscall tables
; STRING SPELLINGS: %-private byte helpers, NOT Str8 -- the table-selection
; walk below RUNS AT LOAD, and posix.x pulls this file into the x-core boot
; before str8.x exists (#108 strings round: a class call here is boot death).
(import x/core/list)
(import x/core/alist)

; The three tables live under platform/data/ (#38: this file was 95%
; literal data); import registers the names so later imports no-op -- and
; resolves through the import roots, so the tables load in an installed
; tree too (no root-relative path literals at runtime).
(import x/platform/data/syscalls-x86_64)
(import x/platform/data/syscalls-i386)
(import x/platform/data/syscalls-darwin)

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
      ((>= j (%str-length needle)) #t)
      ((eq? (%str-ref hay (+ i j)) (%str-ref needle j)) (loop needle hay i (+ j 1)))
      (#t #f))))
(def %os-contains?
  (fn (loop needle hay i)
    (match
      ((> (+ i (%str-length needle)) (%str-length hay)) #f)
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

(def syscall-id
  (fn (_ call)
    (if os-darwin?
      (let ((e (%assoc-get call darwin-syscall-numbers)))
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
