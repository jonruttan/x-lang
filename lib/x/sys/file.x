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
(import x/type/class)

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
      ((pair? mode) (%fold (fn (_ acc flag) (| acc (%mode->int flag))) 0 mode))
      (#t (first (Assoc get mode %file-modes))))))

; --- errno recovery (#22) ---
; Homed on the Err class ((Err errno-of r), lazily resolving the per-OS
; errno location -- CI once caught a wrong -(-1) guess here as
; enoent-pinned-eperm on Linux).  Thin local alias; fetch errno BEFORE
; any intervening syscall (a close on the error path would clobber it).
(def %fs-errno (fn (_ r) (Err errno-of r)))

; Boundary guard for the ergonomic tier: a path must be a string.  The
; class dispatch binds a MISSING argument as nil, and a nil path fed to
; the raw syscall layer surfaces as a baffling EFAULT ("Bad address") --
; or worse through the REPL error path.  Fail as 'type at the door.
(def %fs-path
  (fn (_ path what)
    (unless (str? path)
      (Err raise 'type (Str8 append what ": path must be a string") ()))
    path))

; --- Struct decoding helpers (#22: stat + dirent are per-OS byte layouts) ---
; Little-endian byte peeks over a (str make N) buffer filled by a syscall.
(def %fs-byte-ref (prim-ref 'str 'byte-ref))
(def %fs-char->int (prim-ref 'char '->int))
(def %peek-u8 (fn (_ b i) (%fs-char->int (%fs-byte-ref b i))))
(def %peek-u16 (fn (_ b i) (+ (%peek-u8 b i) (<< (%peek-u8 b (+ i 1)) 8))))
(def %peek-u32 (fn (_ b i) (+ (%peek-u16 b i) (<< (%peek-u16 b (+ i 2)) 16))))
(def %peek-i64 (fn (_ b i) (+ (%peek-u32 b i) (<< (%peek-u32 b (+ i 4)) 32))))

; File kind from the S_IFMT bits of a stat mode.
(def %mode-kind
  (fn (_ mode)
    (let ((fmt (& mode 61440)))
      (match
        ((= fmt 32768) 'file)
        ((= fmt 16384) 'dir)
        ((= fmt 40960) 'link)
        ((= fmt 8192)  'char)
        ((= fmt 24576) 'block)
        ((= fmt 4096)  'fifo)
        ((= fmt 49152) 'socket)
        (#t 'unknown)))))

; Decode one getdents64/getdirentries64 batch buffer into entry names.
;   Linux  dirent64: ino u64@0, off u64@8, reclen u16@16, type u8@18, name z@19
;   Darwin dirent64: ino u64@0, seekoff u64@8, reclen u16@16, namlen u16@18,
;                    type u8@20, name@21
; A zero reclen would never advance -- treated as end (corrupt buffer guard).
(def %dirent-name
  (fn (_ buf start limit)
    (let go ((i start) (acc ()))
      (if (>= i limit) (list->str (%reverse acc))
        (let ((c (%peek-u8 buf i)))
          (if (= c 0) (list->str (%reverse acc))
            (go (+ i 1) (pair (%fs-byte-ref buf i) acc))))))))

(def %dirents
  (fn (_ buf n acc)
    (let go ((off 0) (acc acc))
      (if (>= off n) acc
        (let ((reclen (%peek-u16 buf (+ off 16))))
          (if (= reclen 0) acc
            (let ((name (if os-darwin?
                          (%dirent-name buf (+ off 21)
                            (+ (+ off 21) (%peek-u16 buf (+ off 18))))
                          (%dirent-name buf (+ off 19) (+ off reclen)))))
              (go (+ off reclen)
                  (if (= (%peek-i64 buf off) 0) acc  ; ino 0 = deleted slot
                    (pair name acc))))))))))

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
        (sample "(first (Assoc get 'rdwr (File file-modes)))" "2"))
      %file-modes)

    (method stat-flags (self)
      (doc "The stat mode-flag table: an alist mapping each symbolic S_* name to its numeric Linux value, for decoding a stat result's st_mode (the ifmt bits select the file type; the rest are permission and set-id/sticky bits)."
        (returns LIST "Alist of (symbol value) for: ifmt ifdir ifchr ifblk ifreg ififo iflnk ifsock isuid isgid isvtx iread iwrite iexec")
        (sample "(File stat-flags)" "the full (symbol value) table")
        (sample "(first (Assoc get 'ifdir (File stat-flags)))" "16384"))
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
            (Str8 ref 0 buffer)))))

    ; ======================================================================
    ; The ergonomic tier (#22): whole-file and filesystem operations that
    ; RAISE a kind-'io Err (via Err from-errno, #20) instead of returning
    ; the raw layer's negative -errno.  The five raw ops above keep their
    ; documented raw contract (absence-model rule 5).
    ; ======================================================================

    (method stat (self (param path STRING "Path to stat"))
      (doc "File metadata as an alist: ((size . BYTES) (mode . RAW) (kind . SYM) (mtime . UNIX-SECONDS)). kind is one of 'file 'dir 'link 'char 'block 'fifo 'socket (from the S_IFMT bits). Raises a kind-'io Err on failure."
        (returns ALIST "((size . N) (mode . M) (kind . K) (mtime . T))")
        (sample "(File stat \"lib/x.x\")" "((size . 461) (mode . 33188) (kind . file) (mtime . 1752861000))"))
      (%fs-path path "File stat")
      (def buf (%make-str 160))
      (def r (if os-darwin?
               (syscall (syscall-id 'stat64) path buf)
               (syscall (syscall-id 'stat) path buf)))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'stat path)))
      (def mode (if os-darwin? (%peek-u16 buf 4) (%peek-u32 buf 24)))
      (list (pair 'size (%peek-i64 buf (if os-darwin? 96 48)))
            (pair 'mode mode)
            (pair 'kind (%mode-kind mode))
            (pair 'mtime (%peek-i64 buf (if os-darwin? 48 88)))))

    (method exists? (self (param path STRING "Path to test"))
      (doc "Does path name an existing filesystem entry? (Any kind -- file, directory, link target...)"
        (returns BOOL "True when stat succeeds")
        (sample "(File exists? \"lib/x.x\")" "#t"))
      (guard (_ #f) (do (File stat path) #t)))

    (method slurp (self (param path STRING "File to read"))
      (doc "The whole file as one string (stat for the size, one read). Raises a kind-'io Err on open/read failure."
        (returns STRING "The file's bytes")
        (sample "(File slurp \"/etc/hostname\")" "the file's contents as a string"))
      (%fs-path path "File slurp")
      (def size (Assoc get 'size (File stat path)))
      (def fd (File open path 'rdonly))
      (when (< fd 0) (error (Err from-errno (%fs-errno fd) 'open path)))
      (def buf (%make-str size))
      (def n (File read fd buf size))
      (def en (if (< n 0) (%fs-errno n) ()))  ; before close clobbers errno
      (File close fd)
      (when (< n 0) (error (Err from-errno en 'read path)))
      (if (= n size) buf (Str8 sub 0 n buf)))

    (method spit (self (param path STRING "File to write (created/truncated)")
                       (param s STRING "Contents"))
      (doc "Write s as the entire contents of path (create or truncate, mode 0644). Raises a kind-'io Err on failure; returns the byte count written."
        (returns INT "Bytes written")
        (sample "(File spit \"out.txt\" \"hi\\n\")" "3"))
      (%fs-path path "File spit")
      (unless (str? s) (Err raise 'type "File spit: contents must be a string" ()))
      ; symbolic modes: the O_* numbers differ per OS (%file-modes is per-OS)
      (def fd (File open path (list 'wronly 'creat 'trunc) 420))
      (when (< fd 0) (error (Err from-errno (%fs-errno fd) 'open path)))
      (def n (File write fd s (Str8 length s)))
      (def en (if (< n 0) (%fs-errno n) ()))  ; before close clobbers errno
      (File close fd)
      (when (< n 0) (error (Err from-errno en 'write path)))
      n)

    (method read-lines (self (param path STRING "File to read"))
      (doc "The file as a list of lines (split on newline; a trailing final newline yields no empty last line)."
        (returns LIST "List of line strings")
        (sample "(File read-lines \"/etc/hosts\")" "(\"127.0.0.1 localhost\" ...)"))
      (%fs-path path "File read-lines")
      (def s (File slurp path))
      (def all (Str8 split "\n" s))
      (if (null? all) all
        (let ((lastc (List last all)))
          (if (str=? lastc "") (List init all) all))))

    (method list-dir (self (param path STRING "Directory to list"))
      (doc "The directory's entry names as a list of strings, '.' and '..' excluded. Per-OS dirent decoding over getdents64 (Linux) / getdirentries64 (Darwin). Raises a kind-'io Err on failure."
        (returns LIST "Entry-name strings")
        (sample "(File list-dir \"lib\")" "(\"x-core.x\" \"x.x\" ...)"))
      (%fs-path path "File list-dir")
      (def fd (File open path 'rdonly))
      (when (< fd 0) (error (Err from-errno (%fs-errno fd) 'open path)))
      (def buf (%make-str 4096))
      (def basep (%make-str 8))   ; Darwin getdirentries64's position cookie
      (def names
        (let batch ((acc ()))
          (let ((n (if os-darwin?
                     (syscall (syscall-id 'getdirentries64) fd buf 4096 basep)
                     (syscall (syscall-id 'getdents64) fd buf 4096))))
            (match
              ((< n 0) (let ((en (%fs-errno n)))  ; before close clobbers errno
                         (File close fd)
                         (error (Err from-errno en 'readdir path))))
              ((= n 0) acc)
              (#t (batch (%dirents buf n acc)))))))
      (File close fd)
      (List reject (fn (_ nm) (or (str=? nm ".") (str=? nm ".."))) names))

    (method mkdir (self (param path STRING "Directory to create")
                        . (param perm INT "Permission bits; default 0755"))
      (doc "Create a directory (default mode 0755). Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File mkdir \"build/out\")" "creates the directory"))
      (%fs-path path "File mkdir")
      (def r (syscall (syscall-id 'mkdir) path (if (null? perm) 493 (first perm))))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'mkdir path)))
      ())

    (method unlink (self (param path STRING "File to remove"))
      (doc "Remove a file (not a directory -- see rmdir). Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File unlink \"out.txt\")" "removes the file"))
      (%fs-path path "File unlink")
      (def r (syscall (syscall-id 'unlink) path))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'unlink path)))
      ())

    (method rmdir (self (param path STRING "Empty directory to remove"))
      (doc "Remove an empty directory. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File rmdir \"build/out\")" "removes the directory"))
      (%fs-path path "File rmdir")
      (def r (syscall (syscall-id 'rmdir) path))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'rmdir path)))
      ())

    (method rename (self (param from STRING "Existing path") (param to STRING "New path"))
      (doc "Rename/move a filesystem entry. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File rename \"a.txt\" \"b.txt\")" "moves a.txt to b.txt"))
      (%fs-path from "File rename")
      (%fs-path to "File rename")
      (def r (syscall (syscall-id 'rename) from to))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'rename (list from to))))
      ())))

(doc (provide x/sys/file File)
  (note "Imports x/platform/syscall for syscall-id; read buffers come from the (str make) core primitive, so File runs under plain x-core. Call (File file-modes) / (File stat-flags) for the symbolic flag tables.")
  "File I/O via POSIX syscalls, homed on the File class.")
