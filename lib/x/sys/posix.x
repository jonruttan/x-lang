; posix.x -- Sys: POSIX system calls as static methods, via FFI (%dlsym + ptr-call)
(import x/core/list)
; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))

(import x/type/object)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref (lit ptr) (lit call)))
(def %ptr-ref (prim-ref (lit ptr) (lit ref)))
(def %ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))
(def %dlopen (prim-ref (lit ffi) (lit dlopen)))
(def %dlsym (prim-ref (lit ffi) (lit dlsym)))

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
      (doc "Fork the current process." (returns INTEGER "PID of child in parent, 0 in child, -1 on error"))
      (%ptr-call %c-fork))
    (method getpid (self)
      (doc "Return the current process ID." (returns INTEGER "Process ID"))
      (%ptr-call %c-getpid))
    (method exit (self (param status INTEGER "Exit status code"))
      (doc "Terminate the process with the given exit status.")
      (%ptr-call %c-exit status))
    (method wait (self (param pid INTEGER "Process ID to wait for"))
      (doc "Wait for a child process and return its exit status."
        (returns INTEGER "Exit status of the child process"))
      (let ((buf (%cvt (%ptr-call %c-malloc 4) %ptr)))
        (%ptr-call %c-waitpid pid buf 0)
        (let ((raw (%ptr-ref buf 0 4)))
          (%ptr-call %c-free buf)
          (/ (% raw 65536) 256))))
    (method exec (self (param name STRING "Program name") (param args LIST "List of argument strings"))
      (doc "Replace the current process with the named program. Does not return on success.")
      (let ((all (pair name args)))
        (let ((n (length all)))
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
            (%ptr-call %c-execvp name argv)))))
    ; --- File descriptors ---
    (method close (self (param fd INTEGER "File descriptor to close"))
      (doc "Close a file descriptor." (returns INTEGER "0 on success, -1 on error"))
      (%ptr-call %c-close fd))
    (method dup2 (self (param old INTEGER "Source file descriptor") (param new INTEGER "Target file descriptor"))
      (doc "Duplicate a file descriptor onto another." (returns INTEGER "New file descriptor, or -1 on error"))
      (%ptr-call %c-dup2 old new))
    (method pipe (self)
      (doc "Create a pipe and return a pair of file descriptors." (returns PAIR "Pair of (read-fd . write-fd)"))
      (let ((buf (%cvt (%ptr-call %c-malloc 8) %ptr)))
        (%ptr-call %c-pipe buf)
        (let ((r (%ptr-ref buf 0 4)) (w (%ptr-ref buf 4 4)))
          (%ptr-call %c-free buf)
          (pair r w))))
    ; --- File I/O (O_* flags are platform constants bound by the FFI layer) ---
    (method open-read (self (param path STRING "File path to open"))
      (doc "Open a file for reading." (returns INTEGER "File descriptor, or -1 on error"))
      (%ptr-call %c-open path %O_RDONLY))
    (method open-write (self (param path STRING "File path to open"))
      (doc "Open a file for writing, creating or truncating it." (returns INTEGER "File descriptor, or -1 on error"))
      (let ((fd (%ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_TRUNC)) 438)))
        (if (>= fd 0) (%ptr-call %c-fchmod fd 438))
        fd))
    (method open-append (self (param path STRING "File path to open"))
      (doc "Open a file for appending, creating it if necessary." (returns INTEGER "File descriptor, or -1 on error"))
      (let ((fd (%ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_APPEND)) 438)))
        (if (>= fd 0) (%ptr-call %c-fchmod fd 438))
        fd))
    (method fd-write (self (param fd NUMBER "File descriptor") (param s STRING "String to write"))
      (doc "Write a string to a file descriptor." (returns NUMBER "Bytes written"))
      (%ptr-call (%resolve "write") fd s (str-length s)))
    (method fd-read (self (param fd NUMBER "File descriptor to read from")
                          (param n NUMBER "Maximum number of bytes to read"))
      (doc "Read up to n bytes from a file descriptor (libc read via FFI)."
        (returns LIST "Byte values (0-255) in read order; () at EOF or on error")
        (example "(Sys fd-read fd 4)" "(112 9 240 3)"))
      ; Read into a fresh block, then copy the bytes out before freeing it --
      ; the same malloc/%ptr-ref/free dance as `pipe`. %ptr-ref returns a signed
      ; cell, so mask each to a byte. got<=0 (EOF/error) leaves the loop at i<0
      ; and yields ().
      (let ((buf (%cvt (%ptr-call %c-malloc n) %ptr)))
        (let ((got (%ptr-call (%resolve "read") fd buf n)))
          (let ((bytes (let go ((i (- got 1)) (acc ()))
                         (if (< i 0) acc
                           (go (- i 1) (pair (& (%ptr-ref buf i 1) 255) acc))))))
            (%ptr-call %c-free buf)
            bytes))))
    (method file-exists? (self (param path STRING "File path to check"))
      (doc "Check if a file exists (via access with F_OK=0)." (returns BOOLEAN "True if file exists"))
      (= (%ptr-call (%resolve "access") path 0) 0))
    ; --- Environment ---
    (method chdir (self (param path STRING "Directory path"))
      (doc "Change the current working directory." (returns INTEGER "0 on success, -1 on error"))
      (%ptr-call %c-chdir path))
    (method setenv (self (param name STRING "Variable name") (param val STRING "Variable value"))
      (doc "Set an environment variable, overwriting any existing value." (returns INTEGER "0 on success, -1 on error"))
      (%ptr-call %c-setenv name val 1))
    (method getenv (self (param name STRING "Variable name"))
      (doc "Get the value of an environment variable." (returns STRING "Variable value, or nil if not set"))
      (let ((result (%ptr-call %c-getenv name)))
        (if (= result 0) () (%cvt (%cvt result %ptr) %string))))
    (method isatty (self (param fd NUMBER "File descriptor to test"))
      (doc "Test whether a file descriptor refers to a terminal (TTY)."
        (returns BOOLEAN "True if fd refers to a terminal")
        (example "(Sys isatty 1)" "#t"))
      (= 1 (%ptr-call %c-isatty fd)))
    ; clock was previously reached via the catalog auto-class (ns sys); authored
    ; here as the catalog bridge retires (R4). Cold path -> inline prim-ref.
    (method clock (self)
      (doc "Current process CPU time in microseconds (for timing / the `time` form)."
        (returns INT "Microseconds of CPU time consumed"))
      ((prim-ref (lit sys) (lit clock))))))

(doc (provide x/sys/posix Sys)
  (note "POSIX via the Sys class: (Sys fork), (Sys exec name args), (Sys pipe),")
  (note "(Sys open-read path), (Sys getenv name), (Sys isatty fd), ...")
  "POSIX system call wrappers, homed on the Sys class.")
