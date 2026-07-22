; posix.x -- Sys: POSIX system calls as static methods, via FFI (%dlsym + ptr-call)
(import x/core/list)
; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))

(import x/type/class)
(import x/core/alist)
(import x/platform/syscall)

; O_* open flags from the platform table (%file-modes, x/platform/syscall) --
; the single source of platform truth, shared with sys/file.x.  Formerly
; C-bound constants; retired with the ISA audit.
(def %O_RDONLY (first (%assoc-get (lit rdonly) %file-modes)))
(def %O_WRONLY (first (%assoc-get (lit wronly) %file-modes)))
(def %O_CREAT  (first (%assoc-get (lit creat)  %file-modes)))
(def %O_TRUNC  (first (%assoc-get (lit trunc)  %file-modes)))
(def %O_APPEND (first (%assoc-get (lit append) %file-modes)))

; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref (lit ptr) (lit call)))
(def %ptr-ref (prim-ref (lit ptr) (lit ref)))
(def %ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))
(def %dlopen (prim-ref (lit ffi) (lit dlopen)))
(def %dlsym (prim-ref (lit ffi) (lit dlsym)))

; GC-owned byte regions for FFI out-params (pipe's fd pair, fd-read's read
; block): allocate as a string -- the collector owns the region, so there is
; no free call to miss and nothing leaks when an error unwinds mid-call --
; then hand libc its raw pointer via (str ->ptr).
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))

; Sign-fold an FFI int return: on Linux, %ptr-call hands libc's -1 back
; ZERO-EXTENDED (4294967295) -- an int-returning callee writes only the
; low 32 bits of the return register -- so (< r 0) reads failure as
; success (Darwin sign-extends; CI caught socket.x's tcp-connect
; "succeeding" against a closed port). Fold the u32 range's top half
; back to negative before any sign test. This is the canonical home;
; socket.x's %sk-fold aliases it. Int returns ONLY -- never fold a
; pointer return (malloc/getenv/mmap/__errno_location), those use the
; full register.
(def %sys-fold
  (fn (_ r) (if (> r 2147483647) (- r 4294967296) r)))

;
; Pure x-lang over the FFI layer; the libc resolves stay %-private. Loads after
; object.x (needs def-class) -- every caller (repl, ansi, logo, tools) is
; post-object.

; --- Resolve libc functions ---

(def %libc (%dlopen () 1))

(def %resolve (fn (_ name) (%dlsym %libc name)))

(def %c-fork (%resolve "fork"))

(def %c-execvp (%resolve "execvp"))

(def %c-pipe (%resolve "pipe"))

(def %c-dup2 (%resolve "dup2"))

(def %c-waitpid (%resolve "waitpid"))

(def %c-open (%resolve "open"))

(def %c-close (%resolve "close"))

(def %c-fchmod (%resolve "fchmod"))

(def %c-chdir (%resolve "chdir"))

(def %c-getenv (%resolve "getenv"))

(def %c-setenv (%resolve "setenv"))

(def %c-getpid (%resolve "getpid"))

(def %c-exit (%resolve "_exit"))

(def %c-malloc (%resolve "malloc"))

(def %c-free (%resolve "free"))

(def %c-isatty (%resolve "isatty"))

(def-class Sys ()
  (static
    ; --- Process control ---
    (method fork (self)
      (doc "Fork the current process." (returns INT "PID of child in parent, 0 in child, -1 on error"))
      (%sys-fold (%ptr-call %c-fork)))
    (method getpid (self)
      (doc "Return the current process ID." (returns INT "Process ID"))
      (%sys-fold (%ptr-call %c-getpid)))
    (method exit (self (param status INT "Exit status code"))
      (doc "Terminate the process with the given exit status.")
      (%ptr-call %c-exit status))
    (method wait (self (param pid INT "Process ID to wait for"))
      (doc "Wait for a child process and return its exit status."
        (returns INT "Exit status of the child process"))
      (let ((buf (%cvt (%ptr-call %c-malloc 4) %ptr)))
        (%ptr-call %c-waitpid pid buf 0)
        (let ((raw (%ptr-ref buf 0 4)))
          (%ptr-call %c-free buf)
          (/ (% raw 65536) 256))))
    (method exec (self (param name STRING "Program name") (param args LIST "List of argument strings"))
      (doc "Replace the current process with the named program. Does not return on success.")
      (let ((all (pair name args)))
        (let ((n (%length all)))
          (let ((argv (%cvt (%ptr-call %c-malloc (* (+ n 1) %word-size)) %ptr)))
            (def %fill
              (fn (self lst i)
                (if (null? lst)
                  (%ptr-set-word! argv (* i %word-size) 0)
                  (do
                    (%ptr-set-word!
                      argv
                      (* i %word-size)
                      (%cvt (%cvt (first lst) %ptr) %int))
                    (self (rest lst) (+ i 1))))))
            (%fill all 0)
            (%sys-fold (%ptr-call %c-execvp name argv))))))
    ; --- File descriptors ---
    (method close (self (param fd INT "File descriptor to close"))
      (doc "Close a file descriptor." (returns INT "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-close fd)))
    (method dup2 (self (param old INT "Source file descriptor") (param new INT "Target file descriptor"))
      (doc "Duplicate a file descriptor onto another." (returns INT "New file descriptor, or -1 on error"))
      (%sys-fold (%ptr-call %c-dup2 old new)))
    (method pipe (self)
      (doc "Create a pipe and return a pair of file descriptors." (returns PAIR "Pair of (read-fd . write-fd)"))
      ; The two 4-byte fds land in a GC-owned (str make) region; the outer
      ; let keeps the backing string alive across the ptr reads.
      (let ((s (%make-str 8)))
        (let ((buf (%str->ptr s)))
          (%ptr-call %c-pipe buf)
          (pair (%ptr-ref buf 0 4) (%ptr-ref buf 4 4)))))
    ; --- File I/O (O_* flags from the platform table, resolved at load above) ---
    (method open-read (self (param path STRING "File path to open"))
      (doc "Open a file for reading." (returns INT "File descriptor, or -1 on error"))
      (%sys-fold (%ptr-call %c-open path %O_RDONLY)))
    (method open-write (self (param path STRING "File path to open"))
      (doc "Open a file for writing, creating or truncating it." (returns INT "File descriptor, or -1 on error"))
      (let ((fd (%sys-fold (%ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_TRUNC)) 438))))
        (if (>= fd 0) (%ptr-call %c-fchmod fd 438))
        fd))
    (method open-append (self (param path STRING "File path to open"))
      (doc "Open a file for appending, creating it if necessary." (returns INT "File descriptor, or -1 on error"))
      (let ((fd (%sys-fold (%ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_APPEND)) 438))))
        (if (>= fd 0) (%ptr-call %c-fchmod fd 438))
        fd))
    (method fd-write (self (param fd NUMBER "File descriptor") (param s STRING "String to write"))
      (doc "Write a string to a file descriptor." (returns NUMBER "Bytes written"))
      (%sys-fold (%ptr-call (%resolve "write") fd s (%str-length s))))
    (method fd-read (self (param fd NUMBER "File descriptor to read from")
                          (param n NUMBER "Maximum number of bytes to read"))
      (doc "Read up to n bytes from a file descriptor (libc read via FFI)."
        (returns LIST "Byte values (0-255) in read order; () at EOF or on error")
        (sample "(Sys fd-read fd 4)" "(112 9 240 3)"))
      ; Read into a GC-owned (str make) region -- like `pipe`, no free call:
      ; the collector owns the backing string (bound in the outer let so it
      ; outlives the ptr walk). %ptr-ref returns a signed cell, so mask each
      ; to a byte. got<=0 (EOF/error) leaves the loop at i<0 and yields ().
      (let ((s (%make-str n)))
        (let ((buf (%str->ptr s)))
          (let ((got (%sys-fold (%ptr-call (%resolve "read") fd buf n))))
            (let go ((i (- got 1)) (acc ()))
              (if (< i 0) acc
                (go (- i 1) (pair (& (%ptr-ref buf i 1) 255) acc))))))))
    (method file-exists? (self (param path STRING "File path to check"))
      (doc "Check if a file exists (via access with F_OK=0)." (returns BOOL "True if file exists"))
      (= (%sys-fold (%ptr-call (%resolve "access") path 0)) 0))
    ; --- Environment ---
    (method chdir (self (param path STRING "Directory path"))
      (doc "Change the current working directory." (returns INT "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-chdir path)))
    (method setenv (self (param name STRING "Variable name") (param val STRING "Variable value"))
      (doc "Set an environment variable, overwriting any existing value." (returns INT "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-setenv name val 1)))
    (method getenv (self (param name STRING "Variable name"))
      (doc "Get the value of an environment variable." (returns STRING "Variable value, or nil if not set"))
      ; POINTER return -- must NOT go through %sys-fold (see its comment).
      (let ((result (%ptr-call %c-getenv name)))
        (if (= result 0) () (%cvt (%cvt result %ptr) %string))))
    (method isatty (self (param fd NUMBER "File descriptor to test"))
      (doc "Test whether a file descriptor refers to a terminal (TTY)."
        (returns BOOL "True if fd refers to a terminal")
        (sample "(Sys isatty 1)" "#t"))
      (= 1 (%sys-fold (%ptr-call %c-isatty fd))))
    ; clock was previously reached via the catalog auto-class (ns sys); authored
    ; here as the catalog bridge retires (R4). Cold path -> inline prim-ref.
    (method clock (self)
      (doc "Current process CPU time in microseconds (for timing / the `time` form). WALL-clock time is (Sys time) / (Sys time-of-day)."
        (returns INT "Microseconds of CPU time consumed"))
      ((prim-ref (lit sys) (lit clock))))

    ; --- Wall clock (#21) ---
    ; libc gettimeofday into a GC-owned 16-byte buffer; the timeval decode
    ; is OS-shared: tv_sec is an i64 at 0 on both; tv_usec at 8 fits a u32
    ; read on both (Darwin's field IS 32-bit; Linux's is an i64 < 1e6).
    (method time-of-day (self)
      (doc "Wall-clock time from gettimeofday: (unix-seconds . microseconds)."
        (returns PAIR "(seconds . microseconds)")
        (sample "(Sys time-of-day)" "(1752861000 . 123456)"))
      (let ((s (%make-str 16)))
        (let ((buf (%str->ptr s)))
          (let ((r (%sys-fold (%ptr-call (%resolve "gettimeofday") buf 0))))
            (when (< r 0) (error (Err from-errno (Err errno-of r) (lit gettimeofday) ())))
            (pair (%ptr-ref buf 0 8) (%ptr-ref buf 8 4))))))

    (method time (self)
      (doc "Wall-clock time as unix seconds (UTC). CPU time is (Sys clock); civil dates are the Date class (x/sys/date)."
        (returns INT "Seconds since the unix epoch")
        (sample "(Sys time)" "1752861000"))
      (first (Sys time-of-day)))))

(doc (provide x/sys/posix Sys)
  (note "POSIX via the Sys class: (Sys fork), (Sys exec name args), (Sys pipe),")
  (note "(Sys open-read path), (Sys getenv name), (Sys isatty fd), ...")
  "POSIX system call wrappers, homed on the Sys class.")
