; file.x -- File: file I/O via POSIX syscalls, homed on the File class.
; One of the four I/O tiers -- Io holds the verbs, Stream redirects
; output, File is the filesystem, Buf is the reader's side; the full
; statement lives in x/type/io.x's header (#365).
;
; Wraps low-level syscalls with symbolic mode flags. The open-mode and stat
; flag tables are exposed as the (File file-modes) / (File stat-flags) methods
; (evaluate either to see the whole table); the I/O ops are methods too
; ((File open), close, read, write, getc, seek, tell, truncate).
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
(import x/platform/dirent)
(import x/codec/struct)   ; the stat-buffer decode rides a field spec (#371)
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
(def %fs-byte-ref (prim-ref 'str 'byte-ref))   ; temp's suffix bytes

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



(def-class File ()
  (doc "Blocking file I/O over raw POSIX syscalls (open/close/read/write/seek)."
    (note "Lifecycle: (File open path mode) -> a file descriptor; thread it through (File read)/(File write)/(File getc)/(File seek); (File close fd) when done.")
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

    ; The seek trio (#360). Raw-tier contract like read/write: the raw
    ; syscall result comes back, negative = -errno. i386's lseek syscall
    ; takes 32-bit offsets (llseek is the 64-bit door there; not wired).
    (method %whence (self (param whence ANY "Seek origin -- symbol or number"))
      (doc "Resolve a seek origin to its POSIX SEEK_* value (identical across Linux/macOS): 'set -> 0, 'cur -> 1, 'end -> 2; a number passes through. Raises a kind-'type Err on anything else -- an unknown origin must not reach the kernel."
        (returns INT "0, 1, 2, or the number given"))
      (match
        ((number? whence) whence)
        ((eq? whence 'set) 0)
        ((eq? whence 'cur) 1)
        ((eq? whence 'end) 2)
        (#t (Err raise 'type "File seek: whence must be 'set, 'cur, 'end, or a number" whence))))

    (method seek (self (param fd INT "File descriptor")
                       (param offset INT "Byte offset, interpreted per whence")
                       . (param whence ANY "Origin -- 'set (absolute, the default), 'cur (relative to the current offset), 'end (relative to end of file); or the numeric 0/1/2"))
      (doc "Reposition a file descriptor's read/write offset (lseek). Seeking past end of file is allowed; a later write there leaves a hole that reads back as zero bytes."
        (returns INT "The new offset from the start of the file, or negative on error")
        (sample "(File seek fd 16)" "16 -- absolute seek")
        (sample "(File seek fd 0 'end)" "the file's size, with the offset now at end")
        (sample "(File seek fd -1 'cur)" "steps the offset back one byte"))
      (syscall (syscall-id 'lseek) fd offset
               (File %whence (if (null? whence) 'set (first whence)))))

    (method tell (self (param fd INT "File descriptor"))
      (doc "The file descriptor's current offset -- (File seek fd 0 'cur)."
        (returns INT "Current offset from the start of the file, or negative on error")
        (sample "(File tell fd)" "the current offset"))
      (File seek fd 0 'cur))

    (method truncate (self (param fd INT "File descriptor, opened writable")
                           . (param size INT "New size in bytes; default the current offset"))
      (doc "Truncate (or extend) the open file to size bytes (ftruncate). The offset does not move -- seek explicitly if it now lies past the end."
        (returns INT "0 on success, negative on error")
        (sample "(File truncate fd 3)" "0 -- the file is now 3 bytes")
        (sample "(File truncate fd)" "0 -- cut at the current offset"))
      (syscall (syscall-id 'ftruncate) fd
               (if (null? size) (File tell fd) (first size))))

    ; ======================================================================
    ; The ergonomic tier (#22): whole-file and filesystem operations that
    ; RAISE a kind-'io Err (via Err from-errno, #20) instead of returning
    ; the raw layer's negative -errno.  The five raw ops above keep their
    ; documented raw contract (absence-model rule 5).
    ; ======================================================================

    ; The per-OS stat-struct field spec, decoded through the Struct codec
    ; (#371 -- this decode was the codec's want-evidence). Pads carry the
    ; layout to each field: Darwin mode u16@4 / mtime i64@48 / size i64@96
    ; (the stat64 layout); Linux mode u32@24 / size i64@48 / mtime i64@88.
    ; Both specs are 64-bit layouts and nothing branches on the width, so a
    ; 32-bit build decodes neighbouring fields.
    ; constraint: word-size = 8 -- stat/stat64 field offsets are 64-bit
    (method %stat-decode (self (param buf STRING "A stat buffer a syscall filled"))
      (doc "Decode a stat64/stat buffer into the public metadata alist."
        (returns ALIST "((size . N) (mode . M) (kind . K) (mtime . T))"))
      (def d (Struct unpack
               (if os-darwin?
                 (list (list 'pad 4) (list 'mode 'u16) (list 'pad 42)
                       (list 'mtime 'i64) (list 'pad 40) (list 'size 'i64))
                 (list (list 'pad 24) (list 'mode 'u32) (list 'pad 20)
                       (list 'size 'i64) (list 'pad 32) (list 'mtime 'i64)))
               buf))
      (def mode (rest (Assoc entry 'mode d)))
      (list (pair 'size (rest (Assoc entry 'size d)))
            (pair 'mode mode)
            (pair 'kind (%mode-kind mode))
            (pair 'mtime (rest (Assoc entry 'mtime d)))))

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
      (File %stat-decode buf))

    (method exists? (self (param path STRING "Path to test"))
      (doc "Does path name an existing filesystem entry? (Any kind -- file, directory, link target...)"
        (returns BOOL "True when stat succeeds")
        (note "Deliberately duplicated across tiers with (Sys file-exists?) (#361): that access(2) door is what boot/module.x can reach before this module loads. Post-boot file work belongs here.")
        (sample "(File exists? \"lib/x.x\")" "#t"))
      (guard (_ #f) (do (File stat path) #t)))

    (method read-all (self (param path STRING "File to read"))
      (doc "The whole file as one string (stat for the size, one read). Raises a kind-'io Err on open/read failure."
        (returns STRING "The file's bytes")
        (sample "(File read-all \"/etc/hostname\")" "the file's contents as a string"))
      (%fs-path path "File read-all")
      (def size (Assoc get 'size (File stat path)))
      (def fd (File open path 'rdonly))
      (when (< fd 0) (error (Err from-errno (%fs-errno fd) 'open path)))
      (def buf (%make-str size))
      (def n (File read fd buf size))
      (def en (if (< n 0) (%fs-errno n) ()))  ; before close clobbers errno
      (File close fd)
      (when (< n 0) (error (Err from-errno en 'read path)))
      (if (= n size) buf (Str8 sub 0 n buf)))

    (method write-all (self (param path STRING "File to write (created/truncated)")
                       (param s STRING "Contents"))
      (doc "Write s as the entire contents of path (create or truncate, mode 0644). Raises a kind-'io Err on failure; returns the byte count written."
        (returns INT "Bytes written")
        (sample "(File write-all \"out.txt\" \"hi\\n\")" "3"))
      (%fs-path path "File write-all")
      (unless (str? s) (Err raise 'type "File write-all: contents must be a string" ()))
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
      (def s (File read-all path))
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
              (#t (batch (dirent-names buf n acc)))))))
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
      ())

    ; --- The metadata doors ---
    ;
    ; A tool tier needs more of the filesystem than reading and writing:
    ; chmod(1) and install -m want the mode, ln(1) wants both link
    ; calls, readlink(1) and realpath(1) want the target, touch(1) wants
    ; the timestamps, and df(1) wants the mount's block counts.  All six
    ; are syscalls the platform table already names.

    (method chmod (self (param path STRING "Path whose mode to set")
                        (param mode INT "Permission bits, e.g. 420 for 0644"))
      (doc "Set a path's permission bits (chmod). Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File chmod \"run.sh\" 493)" "makes it 0755"))
      (%fs-path path "File chmod")
      (def r (syscall (syscall-id 'chmod) path mode))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'chmod path)))
      ())

    (method chown (self (param path STRING "Path whose owner to set")
                        (param uid INT "Owning user id, or -1 to leave it")
                        (param gid INT "Owning group id, or -1 to leave it"))
      (doc "Set a path's owning user and group (chown). Either id may be -1 to leave that half alone. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File chown \"out.txt\" 501 20)" "sets both")
        (sample "(File chown \"out.txt\" -1 20)" "sets only the group"))
      (%fs-path path "File chown")
      (def r (syscall (syscall-id 'chown) path uid gid))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'chown path)))
      ())

    (method link (self (param target STRING "Existing path")
                       (param path STRING "New name for it"))
      (doc "Create a hard link: a second directory entry for the SAME inode, so both names share the file's bytes and it survives until the last one goes. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File link \"a.txt\" \"b.txt\")" "b.txt is now a.txt"))
      (%fs-path target "File link")
      (%fs-path path "File link")
      (def r (syscall (syscall-id 'link) target path))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'link (list target path))))
      ())

    (method symlink (self (param target STRING "What the link should point at")
                          (param path STRING "The link to create"))
      (doc "Create a symbolic link at path pointing at target. The target is stored as WRITTEN and is never resolved here, so it need not exist. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File symlink \"../lib/x.x\" \"here.x\")" "creates the link"))
      (%fs-path target "File symlink")
      (%fs-path path "File symlink")
      (def r (syscall (syscall-id 'symlink) target path))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'symlink (list target path))))
      ())

    (method readlink (self (param path STRING "Symbolic link to read"))
      (doc "The text a symbolic link holds, exactly as it was written -- relative targets come back relative. Raises a kind-'io Err when the path is not a link."
        (returns STRING "The link's target")
        (sample "(File readlink \"here.x\")" "\"../lib/x.x\""))
      (%fs-path path "File readlink")
      (def buf (%make-str 4096))
      (def n (syscall (syscall-id 'readlink) path buf 4096))
      (when (< n 0) (error (Err from-errno (%fs-errno n) 'readlink path)))
      ; readlink does NOT terminate what it writes; the length is the answer
      (Str8 sub 0 n buf))

    (method utimes (self (param path STRING "Path to stamp"))
      (doc "Set a path's access and modification times to the current clock (utimes with a null times pointer) -- what touch(1) means for a file that already exists. Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (note "Explicit timestamps would want a packed pair of timevals, and this module holds no pointer prims to build one; the clock is the door.")
        (sample "(File utimes \"out.txt\")" "bumps both stamps to now"))
      (%fs-path path "File utimes")
      (def r (syscall (syscall-id 'utimes) path ()))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'utimes path)))
      ())

    (method mkfifo (self (param path STRING "FIFO to create")
                    . (param perm INT "Permission bits; default 0644"))
      (doc "Create a named pipe (mknod with the S_IFIFO bit). Raises a kind-'io Err on failure; returns nil."
        (returns ANY "nil")
        (sample "(File mkfifo \"work.pipe\")" "creates the FIFO"))
      (%fs-path path "File mkfifo")
      ; S_IFIFO is 0010000; mknod's device argument is unused for a FIFO
      (def r (syscall (syscall-id 'mknod) path
               (| 4096 (if (null? perm) 420 (first perm))) 0))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'mkfifo path)))
      ())

    (method statfs (self (param path STRING "Any path on the filesystem to measure"))
      (doc "The filesystem holding path, as an alist: ((bsize . BYTES) (blocks . N) (bfree . N) (bavail . N) (files . N) (ffree . N)). Multiply a block count by bsize for bytes. Raises a kind-'io Err on failure."
        (returns ALIST "((bsize . B) (blocks . N) (bfree . N) (bavail . N) (files . N) (ffree . N))")
        (sample "(File statfs \"/\")" "((bsize . 4096) (blocks . 242837545) ...)"))
      (%fs-path path "File statfs")
      ; Darwin's struct carries two 1024-byte mount names after the counts
      (def buf (%make-str 2304))
      (def r (if os-darwin?
               (syscall (syscall-id 'statfs64) path buf)
               (syscall (syscall-id 'statfs) path buf)))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'statfs path)))
      ; The field spec, inlined the way (File %stat-decode)'s is: Darwin's
      ; f_bsize is a u32 leading the struct, Linux's is the second of
      ; eleven longs.  Only the block and inode counts are decoded --
      ; Darwin puts two 1024-byte mount names after them.
      (Struct unpack
        (if os-darwin?
          (list (list 'bsize 'u32) (list 'iosize 'i32)
                (list 'blocks 'u64) (list 'bfree 'u64) (list 'bavail 'u64)
                (list 'files 'u64) (list 'ffree 'u64))
          (list (list 'pad 8) (list 'bsize 'i64)
                (list 'blocks 'u64) (list 'bfree 'u64) (list 'bavail 'u64)
                (list 'files 'u64) (list 'ffree 'u64)))
        buf))

    ; --- The coverage tail (#364) ---

    (method lstat (self (param path STRING "Path to stat, symlinks NOT followed"))
      (doc "File metadata like (File stat), but a symbolic link reports itself (kind 'link) instead of its target -- the door (File walk) uses to avoid following link cycles. Raises a kind-'io Err on failure."
        (returns ALIST "((size . N) (mode . M) (kind . K) (mtime . T))")
        (sample "(File lstat \"some-symlink\")" "((size . 11) (mode . 41453) (kind . link) (mtime . ...))"))
      (%fs-path path "File lstat")
      (def buf (%make-str 160))
      (def r (if os-darwin?
               (syscall (syscall-id 'lstat64) path buf)
               (syscall (syscall-id 'lstat) path buf)))
      (when (< r 0) (error (Err from-errno (%fs-errno r) 'lstat path)))
      (File %stat-decode buf))

    (method copy (self (param from STRING "Source file") (param to STRING "Destination (created/truncated, mode 0644)"))
      (doc "Copy a file's bytes, binary-safe: a 64KB fd-level read/write loop driven by the raw byte counts, never by string length (a string's observable bytes end at the first NUL, so read-all->write-all corrupts binary). Raises a kind-'io Err on failure; returns the byte count copied."
        (returns INT "Bytes copied")
        (sample "(File copy \"a.bin\" \"b.bin\")" "1048576"))
      (%fs-path from "File copy")
      (%fs-path to "File copy")
      (def in (File open from 'rdonly))
      (when (< in 0) (error (Err from-errno (%fs-errno in) 'open from)))
      (def out (File open to (list 'wronly 'creat 'trunc) 420))
      (when (< out 0)
        (let ((en (%fs-errno out)))
          (File close in)
          (error (Err from-errno en 'open to))))
      (def buf (%make-str 65536))
      (def %die (fn (_ r op path)
        (let ((en (%fs-errno r)))
          (File close in)
          (File close out)
          (error (Err from-errno en op path)))))
      (def total
        (let go ((acc 0))
          (let ((n (File read in buf 65536)))
            (match
              ((< n 0) (%die n 'read from))
              ((= n 0) acc)
              (#t (let ((w (File write out buf n)))
                    (match
                      ((< w 0) (%die w 'write to))
                      ; the raw write contract can return short; refuse the
                      ; partial copy loudly rather than looping into it
                      ((< w n) (%die -5 'write to))            ; -EIO
                      (#t (go (+ acc n))))))))))
      (File close in)
      (File close out)
      total)

    (method temp (self . (param prefix STRING "Path prefix for the new file; default \"/tmp/x-\""))
      (doc "Create a fresh temporary file that did not exist before the call: O_CREAT|O_EXCL|O_RDWR, mode 0600, name = prefix + random suffix (bytes from /dev/urandom), retrying on collision. Returns (fd . path); closing and unlinking are the caller's."
        (returns PAIR "(open-fd . path)")
        (sample "(File temp)" "(5 . \"/tmp/x-k29vq1x0\")")
        (sample "(File temp \"/tmp/build-\")" "(6 . \"/tmp/build-8shd02mm\")"))
      (def base (if (null? prefix) "/tmp/x-" (first prefix)))
      (def %rand-name (fn (_)
        ; 8 suffix chars from /dev/urandom, mapped into [a-z0-9]
        (def rfd (File open "/dev/urandom" 'rdonly))
        (when (< rfd 0) (error (Err from-errno (%fs-errno rfd) 'open "/dev/urandom")))
        (def rbuf (%make-str 8))
        (def got (File read rfd rbuf 8))
        (File close rfd)
        (when (< got 8) (error (Err from-errno -5 'read "/dev/urandom")))
        (def %fs-c->i (prim-ref (lit char) (lit ->int)))
        (let go ((i 0) (acc ()))
          (if (= i 8) (bytes->str (%reverse acc))
            (let ((v (% (%fs-c->i (%fs-byte-ref rbuf i)) 36)))
              (go (+ i 1) (pair (if (< v 26) (+ 97 v) (+ 22 v)) acc)))))))
      (let attempt ((left 16))
        (when (= left 0)
          (Err raise 'io "File temp: could not create a fresh name (16 collisions)" base))
        (let ((path (Str8 append base (%rand-name))))
          (let ((fd (File open path (list 'rdwr 'creat 'excl) 384)))
            (if (< fd 0) (attempt (- left 1)) (pair fd path))))))

    (method walk (self (param path STRING "Directory to walk"))
      (doc "Every non-directory entry under path, recursively, as paths RELATIVE to path (files, links, sockets, fifos alike -- filter on (File lstat) kind for finer policy). Recursion decisions ride lstat, so a symlinked directory is REPORTED as its link, never followed (no cycle risk). Order follows the directory tables; treat it as unspecified. Raises a kind-'io Err on failure."
        (returns LIST "Relative path strings")
        (sample "(File walk \"lib/x/num\")" "(\"bigint.x\" \"complex.x\" ...)"))
      (%fs-path path "File walk")
      (let go ((rel "") (names (File list-dir path)) (acc ()))
        (match
          ((null? names) acc)
          (#t
            (let ((name (first names)))
              (let ((r (if (str=? rel "") name (Str8 append rel "/" name))))
                (let ((kind (Assoc get 'kind (File lstat (Str8 append path "/" r)))))
                  (match
                    ((eq? kind 'dir)
                      (go rel (rest names)
                          (go r (File list-dir (Str8 append path "/" r)) acc)))
                    (#t (go rel (rest names) (pair r acc)))))))))))))

(doc (provide x/sys/file File)
  (note "Imports x/platform/syscall for syscall-id; read buffers come from the (str make) core primitive, so File runs under plain x-core. Call (File file-modes) / (File stat-flags) for the symbolic flag tables.")
  "File I/O via POSIX syscalls, homed on the File class.")
