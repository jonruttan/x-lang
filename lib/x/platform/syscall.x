; syscall.x -- x86_64, i386, and Darwin/BSD syscall tables
; lint-known: %param-os %param-arch
; STRING SPELLINGS: %-private byte helpers, NOT Str8 -- the table-selection
; walk below RUNS AT LOAD, and posix.x pulls this file into the x-core boot
; before str8.x exists (#108 strings round: a class call here is boot death).
(module x/platform/syscall)

(import x/core/list)
(import x/core/alist)

; The three tables live under platform/data/ (#38: this file was 95%
; literal data); import registers the names so later imports no-op -- and
; resolves through the import roots, so the tables load in an installed
; tree too (no root-relative path literals at runtime).
(import x/platform/data/syscalls-x86_64)
(import x/platform/data/syscalls-i386)
(import x/platform/data/syscalls-darwin)
(import x/platform/data/syscalls-linux-generic)

; --- platform detection ---
; x-machine is the build triple, e.g. "arm64-apple-darwin25.5.0" vs
; "x86_64-linux-gnu". macOS uses BSD syscall numbers AND different O_* flag
; values, so the file layer keys off this too.
;
; Boot-level byte search, NOT (Str8 includes?): this platform layer loads
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
; DECLARED PARAMS WIN; the triple parse below is the fallback.  The engine's
; build writes what it knows -- os, arch, word size, byte order -- from the
; COMPILER producing the binary, and the wrapper emits those as data ahead of the
; boot (the route %install-root takes, because this layer runs before any file
; I/O exists).  Reading a declaration is the point: a cross-compiled engine
; reports its TARGET, where sniffing a triple at runtime reports whatever string
; the build happened to embed.
;
; `guard` because the rows are absent in two legitimate cases -- an engine whose
; build could not establish a fact writes `unknown` and the wrapper omits it, and
; an older install tree has no declaration at all.  Absent is not wrong; it means
; fall back to reading the triple, which is what this layer did before and still
; can.
(def %declared-os (guard (_ ()) %param-os))
(def %declared-arch (guard (_ ()) %param-arch))

(def os-darwin?
  (match ((eq? %declared-os ()) (%os-contains? "darwin" x-machine 0))
         (#t (eq? %declared-os (lit darwin)))))
(def os-linux?
  (match ((eq? %declared-os ()) (%os-contains? "linux" x-machine 0))
         (#t (eq? %declared-os (lit linux)))))

; --- architecture, parsed HERE and only here ---
; The same triple carries the arch, and it used to be re-sniffed wherever
; someone needed it: lib/x/tool/asm.x had its own darwin test and its own arm64
; test, lib/x/tool/compile.x had a third darwin test.  Three readings of one
; string, and only one of them knew that Darwin spells A64 "arm64" while GNU
; triplets spell it "aarch64" -- so a module that copied the wrong one would
; work on a Mac and mis-detect everywhere else.  The triple is parsed once, and
; tools/check/platform-seam.sh holds it to once.
;
; SNIFFING A TRIPLE IS THE INTERIM, NOT THE DESIGN.  What an engine should hand
; over is a declared (param arch ...) row -- a fact it knows at build time
; rather than a substring of a string it happens to print.  x-engine.xon omits
; params on purpose (they are facts of a BUILD, not of a source tree) and they
; are stamped beside the installed binary.  When that source exists, this is the
; one place that changes.
(def arch-arm64?
  (match ((eq? %declared-arch ())
           (if (%os-contains? "arm64" x-machine 0) #t
             (%os-contains? "aarch64" x-machine 0)))
         (#t (eq? %declared-arch (lit arm64)))))
(def arch-x86-64?
  (match ((eq? %declared-arch ()) (%os-contains? "x86_64" x-machine 0))
         (#t (eq? %declared-arch (lit x86-64)))))

; --- the platform, named once ---
; Every table below is picked by this.  A host that is none of these raises
; here, at load: a syscall number, an O_* value and a struct offset are each
; valid on the wrong platform, so nothing downstream can tell a wrong table
; from a right one.
(def %platform
  (match
    (os-darwin? (lit darwin))
    ((if os-linux? arch-x86-64? #f) (lit linux-x86-64))
    ((if os-linux? arch-arm64? #f) (lit linux-arm64))
    (#t (error (pair (lit unsupported-platform) x-machine)))))

; --- File open-mode flags (O_*) ---
; PLATFORM truth: the O_* flag VALUES differ by OS (verified: macOS
; O_CREAT=512 / O_TRUNC=1024 vs Linux 64 / 512), and on Linux four of them
; differ by architecture, so there is one table per platform and file-modes
; picks at load.  Consumed by
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
  ; O_SYNC is __O_SYNC (04000000) with O_DSYNC folded in, as <fcntl.h> has it.
  (list (lit sync)       1052672)  ; 04010000
  (list (lit path)       2097152)))  ; 010000000

; arm64 Linux: direct, largefile, directory and nofollow trade values with
; x86-64's (arch/arm64/include/uapi/asm/fcntl.h); the rest are the same.
(def %file-modes-linux-arm64 (list
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
  (list (lit directory)  16384)    ; 00040000
  (list (lit nofollow)   32768)    ; 00100000
  (list (lit direct)     65536)    ; 00200000
  (list (lit largefile)  131072)   ; 00400000
  (list (lit noatime)    262144)   ; 01000000
  (list (lit cloexec)    524288)   ; 02000000
  (list (lit sync)       1052672)  ; 04010000
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

(def file-modes
  (match
    ((eq? %platform (lit darwin)) %file-modes-darwin)
    ((eq? %platform (lit linux-arm64)) %file-modes-linux-arm64)
    (#t %file-modes-linux)))

; --- the stat struct ---
; The whole struct as a Struct field spec, one per platform: Darwin's is
; stat64's, Linux x86-64's is its own, and arm64's is the generic one, which
; narrows nlink to a u32 and so puts mode at 16 where x86-64 has it at 24.
; All three are 64-bit layouts.
(def %stat-layout-darwin (list
  (list (lit dev) (lit u32)) (list (lit mode) (lit u16))
  (list (lit nlink) (lit u16)) (list (lit ino) (lit u64))
  (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
  (list (lit rdev) (lit u32)) (list (lit pad) 4)
  (list (lit atime) (lit i64)) (list (lit pad) 8)
  (list (lit mtime) (lit i64)) (list (lit pad) 8)
  (list (lit ctime) (lit i64)) (list (lit pad) 8)
  (list (lit btime) (lit i64)) (list (lit pad) 8)
  (list (lit size) (lit i64)) (list (lit blocks) (lit i64))
  (list (lit blksize) (lit u32))))

(def %stat-layout-linux-x86-64 (list
  (list (lit dev) (lit u64)) (list (lit ino) (lit u64))
  (list (lit nlink) (lit u64)) (list (lit mode) (lit u32))
  (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
  (list (lit pad) 4) (list (lit rdev) (lit u64))
  (list (lit size) (lit i64)) (list (lit blksize) (lit i64))
  (list (lit blocks) (lit i64)) (list (lit atime) (lit i64))
  (list (lit pad) 8) (list (lit mtime) (lit i64)) (list (lit pad) 8)
  (list (lit ctime) (lit i64))))

(def %stat-layout-linux-generic (list
  (list (lit dev) (lit u64)) (list (lit ino) (lit u64))
  (list (lit mode) (lit u32)) (list (lit nlink) (lit u32))
  (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
  (list (lit rdev) (lit u64)) (list (lit pad) 8)
  (list (lit size) (lit i64)) (list (lit blksize) (lit i32))
  (list (lit pad) 4)
  (list (lit blocks) (lit i64)) (list (lit atime) (lit i64))
  (list (lit pad) 8) (list (lit mtime) (lit i64)) (list (lit pad) 8)
  (list (lit ctime) (lit i64))))

(def stat-layout
  (match
    ((eq? %platform (lit darwin)) %stat-layout-darwin)
    ((eq? %platform (lit linux-arm64)) %stat-layout-linux-generic)
    (#t %stat-layout-linux-x86-64)))

; --- syscall numbers ---
(def syscall-id
  (fn (_ call)
    (match
      ((eq? %platform (lit darwin))
        (let ((e (%assoc-get call darwin-syscall-numbers)))
          (if (null? e) -1 (first e))))
      ((eq? %platform (lit linux-arm64))
        (let ((e (%assoc-get call linux-generic-syscall-numbers)))
          (if (null? e) -1 (first e))))
      ; index-of misses with nil; -1 stays this table's OS-domain invalid
      ; marker (never a valid syscall number)
      (#t
        (let ((n (List index-of call x86_64-syscall-names)))
          (if (null? n)
            (let ((m (List index-of call i386-syscall-names)))
              (if (null? m) -1 m))
            n))))))

; --- the door ---
; A name's number answers "which call"; it does not answer "called how", and on
; the generic table the two part: `open` has no number there, and the call that
; does its work takes a directory descriptor first.  A door is the name
; resolved to both -- once, when it is made -- and is what a caller applies.
;
; Six slots always.  The syscall primitive zero-fills what it is not given and
; the kernel reads only the arguments a call declares, so a door passes all six
; and needs no arity.
(def %door-plain (lit (a0 a1 a2 a3 a4 a5)))
(def %door-arg-index
  (lit ((a0 0) (a1 1) (a2 2) (a3 3) (a4 4) (a5 5))))

(def %door-shape
  (fn (_ name)
    (match
      ((eq? %platform (lit linux-arm64))
        (%assoc-get name linux-generic-syscall-shapes))
      (#t ()))))

; A slot as the door holds it: a number for a literal, a one-element list
; holding the argument's index for an argument.
(def %door-slot
  (fn (_ s)
    (match
      ((eq? s (lit cwd)) -100)
      ((number? s) s)
      (#t (%assoc-get s %door-arg-index)))))

(def %door-slot-at
  (fn (loop i slots)
    (match
      ((eq? slots ()) 0)
      ((= i 0) (%door-slot (first slots)))
      (#t (loop (- i 1) (rest slots))))))

(def %door-arg
  (fn (loop i args)
    (match
      ((eq? args ()) ())
      ((= i 0) (first args))
      (#t (loop (- i 1) (rest args))))))

(def %door-value
  (fn (_ slot args)
    (match
      ((number? slot) slot)
      (#t (%door-arg (first slot) args)))))

(doc (def syscall-door
  (fn (_ (param name SYMBOL "The call, by the name the x86-64 and Darwin tables give it"))
    (def shape (%door-shape name))
    (def n (syscall-id (match ((eq? shape ()) name) (#t (first shape)))))
    (def slots (match ((eq? shape ()) %door-plain) (#t (first (rest shape)))))
    (def s0 (%door-slot-at 0 slots))
    (def s1 (%door-slot-at 1 slots))
    (def s2 (%door-slot-at 2 slots))
    (def s3 (%door-slot-at 3 slots))
    (def s4 (%door-slot-at 4 slots))
    (def s5 (%door-slot-at 5 slots))
    (match
      ((< n 0) (error (pair (lit unsupported-syscall) name)))
      (#t
        (fn (_ . args)
          (syscall n
            (%door-value s0 args) (%door-value s1 args) (%door-value s2 args)
            (%door-value s3 args) (%door-value s4 args) (%door-value s5 args)))))))
  (returns CALLABLE "A function of the call's arguments, answering what the syscall primitive answers")
  (note "Raises (unsupported-syscall . NAME) when this platform has neither the call nor a shape standing in for it.")
  (sample "((syscall-door 'close) fd)" "0")
  (sample "((syscall-door 'open) \"/etc/hostname\" 0 0)" "a descriptor, through openat where open has no number")
  "Resolve a system call by name to something that makes it on this platform."))

; The predicates and the tables are names of the sanctioned bare set, bound in
; the root; os-linux? and the two arch predicates were defined here and used
; elsewhere without being listed.  file-modes and stat-layout are plain
; exports: sys/file, sys/posix and the boot loader import them by name.
(doc (provide x/platform/syscall
  (global syscall-id) (global syscall-door)
  (global os-darwin?) (global os-linux?)
  (global arch-arm64?) (global arch-x86-64?)
  (global x86_64-syscall-names) (global i386-syscall-names) (global darwin-syscall-numbers)
  (global linux-generic-syscall-numbers) (global linux-generic-syscall-shapes)
  file-modes stat-layout)
  (note "syscall-id answers a number from this platform's table: Darwin's bare BSD numbers (libc OR-folds the 0x2000000 UNIX class), Linux x86-64's, or the Linux generic table on arm64. syscall-door answers something to call, and is what reaches a call the generic table spells differently.")
  "The platform layer: which OS and architecture this is, and the syscall numbers, call shapes, open flags and stat layout that follow from it.")
