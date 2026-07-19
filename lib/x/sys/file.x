; file.x -- File: file I/O via POSIX syscalls, homed on the File class.
;
; Wraps low-level syscalls with symbolic mode flags. The open-mode and stat
; flag tables are exposed as the (File file-modes) / (File stat-flags) methods
; (evaluate either to see the whole table); the five I/O ops are methods too
; ((File open), close, read, write, getc).
;
; Lifecycle: (File open path mode) hands back a file descriptor (a small
; non-negative integer); pass it to read/write/getc; (File close fd) releases
; it. Every op returns the raw syscall result -- a negative value signals an
; error (the kernel's -errno), (File read) returns 0 at end-of-file.
;
;   (let ((fd (File open "/etc/hostname" 'rdonly)))
;     (let ((buf ((prim-ref 'str 'make) 64)))
;       (let ((n (File read fd buf 64)))    ; n bytes now live in buf
;         (File close fd)
;         n)))
;
; Dependencies: this module imports x/platform/syscall for `syscall-id` (the
; name->number lookup). Read buffers come from (str make n) -- a GC-owned
; n-byte string region (fetched below as %make-str) -- so File runs under
; plain x-core; no extra dialect is needed.
(import x/core/list)
(import x/core/alist)
(import x/platform/syscall)
(import x/type/object)

; GC-owned read buffers: (str make n) allocates an n-byte string region the
; collector owns (no free needed). Fetched once here; getc allocates per call.
(def %make-str (prim-ref 'str 'make))

; --- The flag tables (surfaced via the methods below) ---
; Static value members can't carry help text, so the tables live as data and
; the (File file-modes)/(File stat-flags) methods expose + document them.
; The O_* open-flag tables (%file-modes) are PLATFORM truth and live in
; x/platform/syscall.x (imported above), shared with sys/posix.x.  The S_*
; stat flags below are POSIX-standard and identical across Linux/macOS, so
; they are not split per platform and stay here.

; Stat mode flags (Linux S_* constants)
(def %stat-flags (list
  (list 'ifmt   61440)  ; 0170000 - these bits determine file type
  (list 'ifdir  16384)  ; 0040000 - directory
  (list 'ifchr  8192)   ; 0020000 - character device
  (list 'ifblk  24576)  ; 0060000 - block device
  (list 'ifreg  32768)  ; 0100000 - regular file
  (list 'ififo  4096)   ; 0010000 - fifo
  (list 'iflnk  40960)  ; 0120000 - symbolic link
  (list 'ifsock 49152)  ; 0140000 - socket
  (list 'isuid  2048)   ; 04000 - set user id on execution
  (list 'isgid  1024)   ; 02000 - set group id on execution
  (list 'isvtx  512)    ; 01000 - save swapped text (sticky)
  (list 'iread  256)    ; 00400 - read by owner
  (list 'iwrite 128)    ; 00200 - write by owner
  (list 'iexec  64)))   ; 00100 - execute by owner

; Resolve an open-mode argument to a single numeric flag set:
;   a number   -> passed straight through (e.g. 577)
;   a symbol   -> looked up in %file-modes (e.g. 'rdwr -> 2)
;   a list     -> each element resolved and bitwise-OR'd together, so callers
;                 can write (list 'wronly 'creat 'trunc) -> 577
(def %mode->int
  (fn (_ mode)
    (match
      ((number? mode) mode)
      ((pair? mode) (fold (fn (_ acc flag) (| acc (%mode->int flag))) 0 mode))
      (#t (first (assoc-get mode %file-modes))))))

(def-class File ()
  (doc "Blocking file I/O over raw POSIX syscalls (open/close/read/write)."
    (note "Lifecycle: (File open path mode) -> a file descriptor; thread it through (File read)/(File write)/(File getc); (File close fd) when done.")
    (note "Return values are the raw syscall results: a negative number is an error (-errno). (File read) returns the byte count, 0 at EOF; (File getc) returns -1 at EOF.")
    (note "read/write/getc operate on a caller-allocated string buffer -- allocate one with (str make N), fetched via (prim-ref 'str 'make): read fills it and returns how many bytes landed; write sends `size` bytes out of it.")
    (note "(File open)'s mode is flexible: a number passes straight through; a single symbol (rdonly, wronly, ...) resolves via (File file-modes); a list of symbols is OR'd together -- (list 'wronly 'creat 'trunc) is 577. Call (File file-modes) for the full table, or (File stat-flags) for the stat S_* flags.")
    (note "`syscall-id` is pulled in automatically (imports x/platform/syscall); `syscall` and (str make) are core primitives, so File runs under plain x-core.")
    (sample "(let ((fd (File open \"/etc/hostname\" 'rdonly))) (let ((buf ((prim-ref 'str 'make) 64))) (let ((n (File read fd buf 64))) (File close fd) n)))" "the byte count read into buf, with the fd closed afterward"))
  (static
    (method file-modes (self)
      (doc "The file open-mode table: an alist mapping each symbolic O_* flag name to its numeric Linux value. Use a key as (File open)'s mode argument; OR numeric values together for combined flags."
        (returns LIST "Alist of (symbol value) for: accmode rdonly wronly rdwr creat excl noctty trunc append nonblock dsync fasync direct largefile directory nofollow noatime cloexec sync path")
        (sample "(File file-modes)" "the full (symbol value) table")
        (sample "(first (assoc-get 'rdwr (File file-modes)))" "2"))
      %file-modes)

    (method stat-flags (self)
      (doc "The stat mode-flag table: an alist mapping each symbolic S_* name to its numeric Linux value, for decoding a stat result's st_mode (the ifmt bits select the file type; the rest are permission and set-id/sticky bits)."
        (returns LIST "Alist of (symbol value) for: ifmt ifdir ifchr ifblk ifreg ififo iflnk ifsock isuid isgid isvtx iread iwrite iexec")
        (sample "(File stat-flags)" "the full (symbol value) table")
        (sample "(first (assoc-get 'ifdir (File stat-flags)))" "16384"))
      %stat-flags)

    (method open (self (param pathname STRING "File path to open")
                       (param mode ANY "Open mode -- a number (e.g. 577), one symbol from (File file-modes) (e.g. 'rdonly), or a list of symbols OR'd together (e.g. (list 'wronly 'creat 'trunc))")
                       . (param perm ANY "Permission bits for a newly created file when the mode includes creat; default 0644. Ignored when the file is not created."))
      (doc "Open a file, returning a file descriptor."
        (returns INT "File descriptor, or negative on error")
        (sample "(File open \"/etc/hostname\" 'rdonly)" "a file descriptor opened read-only")
        (sample "(File open \"out.svg\" (list 'wronly 'creat 'trunc))" "an fd opened for writing, new file mode 0644 (577 = O_WRONLY|O_CREAT|O_TRUNC)")
        (sample "(File open \"x\" 'creat 511)" "create with mode 0777 (511)"))
      ; Always pass the 3rd open() arg: the kernel ignores it unless O_CREAT is
      ; set, so it is harmless for non-creating opens and correct for creating
      ; ones. 420 = 0644 (rw-r--r--).
      (syscall (syscall-id 'open) pathname (%mode->int mode)
               (if (null? perm) 420 (first perm))))

    (method close (self (param fd INT "File descriptor to close"))
      (doc "Close a file descriptor."
        (returns INT "0 on success, negative on error")
        (sample "(File close fd)" "0"))
      (syscall (syscall-id 'close) fd))

    (method read (self (param fd INT "File descriptor to read from")
                       (param buffer STRING "Buffer to read into")
                       (param size INT "Maximum bytes to read"))
      (doc "Read bytes from a file descriptor into a buffer."
        (returns INT "Bytes read, 0 at EOF, negative on error")
        (sample "(File read fd buf 64)" "bytes read into buf (0 at EOF)"))
      (syscall (syscall-id 'read) fd buffer size))

    (method write (self (param fd INT "File descriptor to write to")
                        (param buffer STRING "Data to write")
                        (param size INT "Number of bytes to write"))
      (doc "Write bytes from a buffer to a file descriptor."
        (returns INT "Bytes written, or negative on error")
        (sample "(File write fd \"hello\" 5)" "5"))
      (syscall (syscall-id 'write) fd buffer size))

    (method getc (self (param fd INT "File descriptor to read from"))
      (doc "Read a single character from a file descriptor."
        (returns CHAR "Character read, or -1 at EOF")
        (sample "(File getc fd)" "the next byte as a char, or -1 at EOF"))
      (let ((buffer (%make-str 1)))
        (let ((bytes-read (File read fd buffer 1)))
          (if (<= bytes-read 0)
            -1
            (str-ref buffer 0)))))))

(doc (provide x/sys/file File)
  (note "Imports x/platform/syscall for syscall-id; read buffers come from the (str make) core primitive, so File runs under plain x-core. Call (File file-modes) / (File stat-flags) for the symbolic flag tables.")
  "File I/O via POSIX syscalls, homed on the File class.")
