; file.x -- File I/O via POSIX syscalls
;
; Wraps low-level syscalls with symbolic mode flags.
; Requires x-or dialect (syscall primitive).
(import x/core/list)
(import x/core/alist)

; File open mode flags (Linux O_* constants)
(doc (def file-modes (list
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
  (list (lit path)       2097152)  ; 010000000
))
  "Alist of symbolic file open mode flags to numeric O_* values.")

; Stat mode flags (Linux S_* constants)
(doc (def stat-flags (list
  (list (lit ifmt)   61440)  ; 0170000 - these bits determine file type
  (list (lit ifdir)  16384)  ; 0040000 - directory
  (list (lit ifchr)  8192)   ; 0020000 - character device
  (list (lit ifblk)  24576)  ; 0060000 - block device
  (list (lit ifreg)  32768)  ; 0100000 - regular file
  (list (lit ififo)  4096)   ; 0010000 - fifo
  (list (lit iflnk)  40960)  ; 0120000 - symbolic link
  (list (lit ifsock) 49152)  ; 0140000 - socket
  (list (lit isuid)  2048)   ; 04000 - set user id on execution
  (list (lit isgid)  1024)   ; 02000 - set group id on execution
  (list (lit isvtx)  512)    ; 01000 - save swapped text (sticky)
  (list (lit iread)  256)    ; 00400 - read by owner
  (list (lit iwrite) 128)    ; 00200 - write by owner
  (list (lit iexec)  64)     ; 00100 - execute by owner
))
  "Alist of stat mode flags to numeric S_* values.")

; --- File I/O functions ---

(doc (def fopen (fn (pathname mode)
  (if (symbol? mode)
    (set! mode (first (assoc-get mode file-modes))))
  (syscall (syscall-id (lit open)) pathname mode)))
  (param pathname STRING "File path to open")
  (param mode ANY "Numeric flags or symbol from file-modes (e.g. rdonly, wronly, rdwr)")
  (returns INTEGER "File descriptor, or negative on error")
  "Open a file, returning a file descriptor.")

(doc (def fclose (fn (fd)
  (syscall (syscall-id (lit close)) fd)))
  (param fd INTEGER "File descriptor to close")
  (returns INTEGER "0 on success, negative on error")
  "Close a file descriptor.")

(doc (def fread (fn (fd buffer size)
  (syscall (syscall-id (lit read)) fd buffer size)))
  (param fd INTEGER "File descriptor to read from")
  (param buffer STRING "Buffer to read into")
  (param size INTEGER "Maximum bytes to read")
  (returns INTEGER "Bytes read, 0 at EOF, negative on error")
  "Read bytes from a file descriptor into a buffer.")

(doc (def fwrite (fn (fd buffer size)
  (syscall (syscall-id (lit write)) fd buffer size)))
  (param fd INTEGER "File descriptor to write to")
  (param buffer STRING "Data to write")
  (param size INTEGER "Number of bytes to write")
  (returns INTEGER "Bytes written, or negative on error")
  "Write bytes from a buffer to a file descriptor.")

(doc (def fgetc (fn (fd)
  (let ((buffer (make-str 1)))
    (let ((bytes-read (fread fd buffer 1)))
      (if (<= bytes-read 0)
        (- 0 1)
        (str-ref buffer 0))))))
  (param fd INTEGER "File descriptor to read from")
  (returns CHAR "Character read, or -1 at EOF")
  "Read a single character from a file descriptor.")

(doc (provide x/sys/file
  file-modes stat-flags fopen fclose fread fwrite fgetc)
  "File I/O via POSIX syscalls with symbolic mode flags.")
