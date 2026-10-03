; posix.x -- Sys: POSIX system calls as static methods, via FFI (%dlsym + ptr-call)
(module x/sys/posix)

; The base type handles, from their public door, fetched once at load.
(def %int (Type named INTEGER))
(def %ptr (Type named POINTER))
(def %string (Type named STRING))

(import x/core/list)
; Fetch the conversion dispatcher from the catalogue (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))

(import x/type/class)
(import x/core/alist)
(import x/platform/syscall file-modes syscall-id)

; O_* open flags from the platform table (file-modes, x/platform/syscall) --
; the single source of platform truth, shared with sys/file.x.  Formerly
; C-bound constants; retired with the ISA audit.
(def %O_RDONLY (first (%assoc-get (lit rdonly) file-modes)))
(def %O_WRONLY (first (%assoc-get (lit wronly) file-modes)))
(def %O_CREAT  (first (%assoc-get (lit creat)  file-modes)))
(def %O_TRUNC  (first (%assoc-get (lit trunc)  file-modes)))
(def %O_APPEND (first (%assoc-get (lit append) file-modes)))

; Fetch the ptr/ffi prims from the catalogue (ns `ptr`/`ffi` are de-registered, R5).
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
; r is the INT the FFI hands back, never nil, so the test and the fold run
; on the engine's integer < and -: the library's > and - are generic, and
; the fold runs on every system call.
(def %sys-int< (prim-ref (lit int) (lit <)))
(def %sys-int- (prim-ref (lit int) (lit -)))
(def %sys-fold
  (fn (_ r)
    (match
      ((%sys-int< 2147483647 r) (%sys-int- r 4294967296))
      (#t r))))

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
    ; The sign-fold of an FFI int return (%sys-fold, above), for the other
    ; files that call libc themselves: x/repl/term and x/sys/socket.
    (method %sign-fold (self r)
      (%sys-fold r))
    ; --- Process control ---
    (method fork (self)
      (doc "Fork the current process." (returns INTEGER "PID of child in parent, 0 in child, -1 on error"))
      (%sys-fold (%ptr-call %c-fork)))
    (method getpid (self)
      (doc "Return the current process ID." (returns INTEGER "Process ID"))
      (%sys-fold (%ptr-call %c-getpid)))
    (method exit (self (param status INTEGER "Exit status code"))
      (doc "Terminate the process with the given exit status.")
      (%ptr-call %c-exit status))
    (method wait (self (param pid INTEGER "Process ID to wait for"))
      (doc "Wait for a child and return how it ended."
        (returns INTEGER "Exit status 0-255 for a normal exit; 128+N when signal N killed the child (the shell convention)")
        (note "The old contract returned WEXITSTATUS unconditionally, so a signal-killed child reported 0 -- success (#226)."))
      ; Status word lands in a GC-owned (str make) region (see pipe).
      ; Low 7 bits = the killing signal, 0 for a normal exit; the exit
      ; code rides bits 8-15.
      (let ((s (%make-str 4)))
        (let ((buf (%str->ptr s)))
          (%ptr-call %c-waitpid pid buf 0)
          (let ((raw (%ptr-ref buf 0 4)))
            (let ((sig (% raw 128)))
              (if (= sig 0) (/ (% raw 65536) 256) (+ 128 sig)))))))
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
    ; --- Signals ---
    ; POSIX-fixed numbers (identical on Darwin and Linux); named here so
    ; call sites stop carrying magic 2/1/15 literals (#226).
    (sigint 2 "SIGINT: terminal interrupt (ctrl-c)")
    (sigkill 9 "SIGKILL: uncatchable, unignorable kill")
    (sigterm 15 "SIGTERM: polite termination request")
    (sig-dfl 0 "signal(2) disposition: restore the default action")
    (sig-ign 1 "signal(2) disposition: ignore the signal")
    (method kill (self (param pid INTEGER "Process ID")
                       (param sig INTEGER "Signal number, e.g. (Sys sigterm)"))
      (doc "Send a signal to a process." (returns INTEGER "0 on success, -1 on error"))
      ; Cold path: resolve per call (the file-exists? pattern), keeping
      ; the module inside its %-globals budget.
      (%sys-fold (%ptr-call (%resolve "kill") pid sig)))
    (method signal (self (param sig INTEGER "Signal number")
                         (param disposition INTEGER "(Sys sig-ign) or (Sys sig-dfl) ONLY -- an x-lang closure cannot be a C signal handler"))
      (doc "Set a signal's disposition to ignore or default."
        (returns ANY "The previous disposition; meaningful only when it was one of the two constants"))
      ; signal(2) returns a POINTER (the old handler) -- never %sys-fold
      ; a pointer return (see the fold's comment above).
      (%ptr-call (%resolve "signal") sig disposition))
    (sigwinch 28 "SIGWINCH: the terminal's window changed size (28 on Darwin and Linux)")
    (sigttou 22 "SIGTTOU: a background process set or wrote to its terminal (22 on Darwin and Linux)")
    (method sigtstp (self)
      (doc "SIGTSTP, the terminal's stop key (^Z): 18 on Darwin, 20 on Linux."
        (returns INTEGER "The signal number"))
      (if os-darwin? 18 20))
    (method sigstop (self)
      (doc "SIGSTOP, the stop no handler can catch: 17 on Darwin, 19 on Linux."
        (returns INTEGER "The signal number"))
      (if os-darwin? 17 19))
    (method catch-signal (self (param sig INTEGER "Signal number"))
      (doc "Catch a signal: from now on its arrival is recorded for take-signal, and nothing else happens -- what it means is the caller's to decide. A read or poll waiting when it arrives is interrupted."
        (returns INTEGER "0, or -1 when sig cannot be caught or this engine records no signals"))
      (let ((catch (prim-ref (lit signal) (lit catch))))
        (if (null? catch) -1 (catch sig))))
    (method take-signal (self (param sig INTEGER "Signal number"))
      (doc "Whether a caught signal arrived since the last take, clearing the record; two arrivals between takes are one."
        (returns BOOL "True when it arrived"))
      (let ((take (prim-ref (lit signal) (lit take))))
        (if (null? take) #f (= (take sig) 1))))
    ; --- File descriptors ---
    (method close (self (param fd INTEGER "File descriptor to close"))
      (doc "Close a file descriptor." (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-close fd)))
    (method dup2 (self (param old INTEGER "Source file descriptor") (param new INTEGER "Target file descriptor"))
      (doc "Duplicate a file descriptor onto another." (returns INTEGER "New file descriptor, or -1 on error"))
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
      (doc "Open a file for reading." (returns INTEGER "File descriptor, or -1 on error"))
      (%sys-fold (%ptr-call %c-open path %O_RDONLY)))
    (method open-write (self (param path STRING "File path to open"))
      (doc "Open a file for writing, creating or truncating it." (returns INTEGER "File descriptor, or -1 on error"))
      (let ((fd (%sys-fold (%ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_TRUNC)) 438))))
        (if (>= fd 0) (%ptr-call %c-fchmod fd 438))
        fd))
    (method open-append (self (param path STRING "File path to open"))
      (doc "Open a file for appending, creating it if necessary." (returns INTEGER "File descriptor, or -1 on error"))
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
      (doc "Check if a file exists (via access with F_OK=0)."
        (returns BOOL "True if file exists")
        (note "Deliberately duplicated across profiles with (File exists?) (#361): boot/module.x resolves imports through THIS door before sys/file (stat + Err, the ergonomic sibling) can load. Post-boot callers doing file work generally want the File class."))
      (= (%sys-fold (%ptr-call (%resolve "access") path 0)) 0))
    ; --- Environment ---
    (method chdir (self (param path STRING "Directory path"))
      (doc "Change the current working directory -- (Sys getcwd) reads it back." (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-chdir path)))
    (method getcwd (self)
      (doc "The current working directory (getcwd) -- the symmetric half of (Sys chdir) (#361)."
        (returns STRING "Absolute path, or nil on failure")
        (sample "(Sys getcwd)" "\"/home/user/project\""))
      ; POINTER return (the buffer on success, NULL on failure) -- must NOT
      ; go through %sys-fold (see its comment). Cold path: resolve per call.
      (let ((s (%make-str 4096)))
        (let ((r (%ptr-call (%resolve "getcwd") (%str->ptr s) 4096)))
          (if (= r 0) () (%cvt (%cvt r %ptr) %string)))))
    (method setenv (self (param name STRING "Variable name") (param val STRING "Variable value"))
      (doc "Set an environment variable, overwriting any existing value -- (Sys unsetenv) removes it." (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call %c-setenv name val 1)))
    (method getenv (self (param name STRING "Variable name"))
      (doc "Get the value of an environment variable." (returns STRING "Variable value, or nil if not set"))
      ; POINTER return -- must NOT go through %sys-fold (see its comment).
      (let ((result (%ptr-call %c-getenv name)))
        (if (= result 0) () (%cvt (%cvt result %ptr) %string))))
    (method unsetenv (self (param name STRING "Variable name"))
      (doc "Remove an environment variable -- the symmetric half of (Sys setenv) (#361). Removing an absent name succeeds."
        (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call (%resolve "unsetenv") name)))
    (method environ (self)
      (doc "The whole environment as a list of \"NAME=VALUE\" strings, in table order (#361). Split an entry at its FIRST '=' only -- values may themselves contain '='."
        (returns LIST "\"NAME=VALUE\" strings")
        (sample "(Sys environ)" "(\"HOME=/home/user\" \"TERM=xterm-256color\" ...)"))
      ; environ is a DATA symbol: deref the char** once, then walk word by
      ; word (byte offsets, %word-size stride) to the NULL terminator; each
      ; entry is a C-string pointer. Pointer values throughout -- no fold.
      (let ((envp (%ptr-ref (%resolve "environ") 0 %word-size)))
        (let go ((i 0) (acc ()))
          (let ((e (%ptr-ref (%cvt envp %ptr) (* i %word-size) %word-size)))
            (if (= e 0) (%reverse acc)
              (go (+ i 1) (pair (%cvt (%cvt e %ptr) %string) acc)))))))
    ; --- Process identity and the machine ---
    ;
    ; The tool profile's remaining questions: who am I (id, whoami, groups),
    ; what am I running on (uname, arch, nproc), and the two process-state
    ; doors nice(1) and chroot(1).  All libc, so all portable -- no
    ; syscall numbers appear here.
    (method getuid (self)
      (doc "The process's REAL user id -- who invoked it, before any setuid."
        (returns INTEGER "User id")
        (sample "(Sys getuid)" "501"))
      (%sys-fold (%ptr-call (%resolve "getuid"))))
    (method geteuid (self)
      (doc "The process's EFFECTIVE user id -- who it acts as, which is what a permission check reads."
        (returns INTEGER "User id"))
      (%sys-fold (%ptr-call (%resolve "geteuid"))))
    (method getgid (self)
      (doc "The process's real group id."
        (returns INTEGER "Group id"))
      (%sys-fold (%ptr-call (%resolve "getgid"))))
    (method getegid (self)
      (doc "The process's effective group id."
        (returns INTEGER "Group id"))
      (%sys-fold (%ptr-call (%resolve "getegid"))))
    (method getgroups (self)
      (doc "The process's supplementary group ids, as a list. getgroups is asked its own count first, so the buffer is never guessed."
        (returns LIST "Group ids")
        (sample "(Sys getgroups)" "(20 12 61 79)"))
      ; size 0 with a null list is the documented "how many?" call
      (let ((n (%sys-fold (%ptr-call (%resolve "getgroups") 0 0))))
        (if (< n 1) ()
          (let ((buf (%make-str (* n 4))))
            (let ((p (%str->ptr buf)))
              (%ptr-call (%resolve "getgroups") n p)
              (let go ((i 0) (acc ()))
                (if (= i n) (%reverse acc)
                  (go (+ i 1) (pair (%ptr-ref p (* i 4) 4) acc)))))))))
    ; struct utsname is five fixed char arrays back to back, and the
    ; array WIDTH is the whole per-OS difference: Darwin's _SYS_NAMELEN
    ; is 256, Linux's is 65 (with a sixth domainname field after).
    (method uname (self)
      (doc "The running system, as an alist: ((sysname . S) (nodename . S) (release . S) (version . S) (machine . S)). sysname is \"Darwin\" or \"Linux\"; machine is the architecture uname -m prints."
        (returns ALIST "((sysname . S) (nodename . S) (release . S) (version . S) (machine . S))")
        (sample "(Sys uname)" "((sysname . \"Darwin\") ... (machine . \"arm64\"))"))
      ; This module loads mid-x-core, before the Struct codec exists, so
      ; the five fields are read as C strings at their own offsets --
      ; each array is NUL-terminated and none needs the codec.
      (let ((w (if os-darwin? 256 65)))
        (let ((buf (%make-str (* w 6))))
          (%ptr-call (%resolve "uname") (%str->ptr buf))
          (let ((base (%cvt (%str->ptr buf) %int)))
            (def %at (fn (_ k) (%cvt (%cvt (+ base (* k w)) %ptr) %string)))
            (list (pair (lit sysname) (%at 0)) (pair (lit nodename) (%at 1))
                  (pair (lit release) (%at 2)) (pair (lit version) (%at 3))
                  (pair (lit machine) (%at 4)))))))
    (method cpu-count (self)
      (doc "How many processors are online (sysconf _SC_NPROCESSORS_ONLN) -- what nproc(1) reports. Answers 1 when the query fails, never 0."
        (returns INTEGER "Processor count, at least 1")
        (sample "(Sys cpu-count)" "10"))
      ; _SC_NPROCESSORS_ONLN is one of the sysconf names that is NOT
      ; shared: 58 on Darwin, 84 on Linux.
      (let ((n (%sys-fold (%ptr-call (%resolve "sysconf") (if os-darwin? 58 84)))))
        (if (< n 1) 1 n)))
    (method sync (self)
      (doc "Flush the filesystem write buffers (sync). Returns nil; there is nothing to fail."
        (returns ANY "nil"))
      (%ptr-call (%resolve "sync"))
      ())
    (method fsync (self (param fd INTEGER "File descriptor to flush"))
      (doc "Flush ONE open file's buffers to disk (fsync), rather than the whole system."
        (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call (%resolve "fsync") fd)))
    (method nice (self (param increment INTEGER "Amount to add to the scheduling priority"))
      (doc "Raise the process's nice value -- a HIGHER number means a LOWER priority, and only a privileged process may lower it."
        (returns INTEGER "The new nice value, or -1 on error"))
      (%sys-fold (%ptr-call (%resolve "nice") increment)))
    (method chroot (self (param path STRING "New filesystem root"))
      (doc "Change the process's filesystem root. Privileged: an unprivileged caller gets -1 with EPERM."
        (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call (%resolve "chroot") path)))
    ; --- Sleep (#361) ---
    (method sleep (self (param seconds INTEGER "Whole seconds to block"))
      (doc "Block for the given number of seconds (libc sleep). A signal can wake it early; sub-second waits are (Sys usleep)."
        (returns INTEGER "0 after the full interval; the seconds left unslept when a signal woke it early"))
      (%sys-fold (%ptr-call (%resolve "sleep") seconds)))
    (method usleep (self (param micros INTEGER "Microseconds to block"))
      (doc "Block for the given number of microseconds (libc usleep) -- the sub-second door; whole seconds read better through (Sys sleep)."
        (returns INTEGER "0 on success, -1 on error"))
      (%sys-fold (%ptr-call (%resolve "usleep") micros)))
    (method isatty (self (param fd NUMBER "File descriptor to test"))
      (doc "Test whether a file descriptor refers to a terminal (TTY)."
        (returns BOOL "True if fd refers to a terminal")
        (sample "(Sys isatty 1)" "#t"))
      (= 1 (%sys-fold (%ptr-call %c-isatty fd))))

    ; --- Waiting on several descriptors ---
    ; struct pollfd is an int fd then two shorts, events and revents, eight
    ; bytes; the bits are the same on Darwin and Linux: POLLIN 1, POLLPRI 2,
    ; POLLOUT 4, POLLERR 8, POLLHUP 16, POLLNVAL 32.
    (method poll (self (param fds LIST "((FD . EVENTS) ...): each descriptor and what to wait for, a list of in and out")
                       (param timeout INTEGER "Milliseconds to wait: -1 waits without end, 0 does not wait"))
      (doc "Wait until a descriptor is ready, through poll(2). Answers each one that is, with what it is ready for -- among in, out, hup (the other end closed), err and nval (not an open descriptor) -- or nil when the timeout passes first. A signal that interrupts the wait answers nil as well, so a caller's loop asks again; any other failure raises an io Err."
        (returns LIST "((FD . EVENTS) ...) for the ready descriptors, or nil")
        (sample "(Sys poll (list (pair 0 (list 'in)) (pair sock (list 'in))) 1000)" "((5 in)) -- the socket has bytes to read"))
      (def pset (prim-ref (lit ptr) (lit set!)))
      (def n (%length fds))
      (def region (%make-str (* 8 (if (= n 0) 1 n))))
      (def p (%str->ptr region))
      (let put ((l fds) (off 0))
        (unless (null? l)
          (do (pset p off (first (first l)) 4)
              (pset p (+ off 4) (Sys %poll-bits (rest (first l))) 2)
              (pset p (+ off 6) 0 2)
              (put (rest l) (+ off 8)))))
      (def r (%sys-fold (%ptr-call (%resolve "poll") p n timeout)))
      (match
        ((> r 0)
          (let walk ((l fds) (off 0) (acc ()))
            (if (null? l) (%reverse acc)
              (let ((rev (%ptr-ref p (+ off 6) 2)))
                (walk (rest l) (+ off 8)
                      (if (= rev 0) acc
                        (pair (pair (first (first l)) (Sys %poll-events rev)) acc)))))))
        ((= r 0) ())
        ((= (Err errno-of r) 4) ())             ; EINTR, the same number on both
        (#t (error (Err from-errno (Err errno-of r) (lit poll) ())))))

    (method %poll-bits (self (param events LIST "Symbols: in, out"))
      (doc "The pollfd events bits for a list of in and out."
        (returns INTEGER "POLLIN | POLLOUT as asked"))
      (let go ((l events) (bits 0))
        (match
          ((null? l) bits)
          ((eq? (first l) (lit in)) (go (rest l) (if (= (& bits 1) 0) (+ bits 1) bits)))
          ((eq? (first l) (lit out)) (go (rest l) (if (= (& bits 4) 0) (+ bits 4) bits)))
          (#t (Err raise (lit value) "Sys poll: an event is in or out" (first l))))))

    (method %poll-events (self (param rev INTEGER "A pollfd's revents"))
      (doc "The symbols for a revents word: in (POLLIN or POLLPRI), out, err, hup, nval."
        (returns LIST "The events, in that order"))
      (def bit (fn (_ mask name rest) (if (= (& rev mask) 0) rest (pair name rest))))
      (bit 3 (lit in) (bit 4 (lit out) (bit 8 (lit err) (bit 16 (lit hup) (bit 32 (lit nval) ()))))))

    (method nonblock! (self (param fd INTEGER "Descriptor")
                            . (param on BOOL "#f makes it wait again; the default is #t"))
      (doc "Make reads and writes on fd answer at once rather than wait -- O_NONBLOCK through fcntl(2) -- or, given #f, wait again. A read with nothing to read then fails with EAGAIN, and a connect that cannot finish at once with EINPROGRESS, for poll to wait on. Raises an io Err when fcntl fails."
        (returns BOOL "#t")
        (note "Reached as a SYSCALL, as Term's ioctl is: fcntl is variadic, and on Apple arm64 a variadic argument goes on the stack, where the fixed-signature ffi door never puts it.")
        (sample "(Sys nonblock! sock)" "#t"))
      (def id (syscall-id (lit fcntl)))
      (def nb (first (%assoc-get (lit nonblock) file-modes)))
      (def flags (%sys-fold (syscall id fd 3 0)))          ; F_GETFL
      (when (< flags 0) (error (Err from-errno (Err errno-of flags) (lit fcntl) fd)))
      (def has (not (= (& flags nb) 0)))
      (def want
        (match
          ((if (null? on) #t (first on)) (if has flags (+ flags nb)))
          (#t (if has (- flags nb) flags))))
      (def r (%sys-fold (syscall id fd 4 want)))           ; F_SETFL
      (when (< r 0) (error (Err from-errno (Err errno-of r) (lit fcntl) fd)))
      #t)
    ; clock was previously reached via the catalogue auto-class (ns sys); authored
    ; here as the catalogue bridge retires (R4). Cold path -> inline prim-ref.
    (method clock (self)
      (doc "Current process CPU time in microseconds (the (Sys time) profiler reads this). WALL-clock time is (Sys now) / (Sys time-of-day)."
        (returns INTEGER "Microseconds of CPU time consumed"))
      ((prim-ref (lit sys) (lit clock))))

    ; The verb seat (#108 rethink, ruled 2026-07-22): (Sys time thunk) TIMES;
    ; the wall-clock reading it displaced is (Sys now). A thunk parameter by
    ; necessity -- class dispatch evaluates arguments, so an op cannot ride a
    ; static seat (probed) -- and it RETURNS the measurement: mechanism
    ; returns data, printing is the caller's policy ((display (Sys time ...))
    ; is the chatty spelling). Need the thunk's result too? Capture it
    ; through the closure: (def r ()) (Sys time (fn () (set! r ...))).
    (method time (self (param thunk CALLABLE "Zero-argument fn to run and time"))
      (doc "Run THUNK and return its elapsed CPU time in microseconds. The thunk's result is discarded -- capture it via the closure when needed."
        (returns INTEGER "Elapsed CPU microseconds")
        (example "(number? (Sys time (fn () (List fold + 0 (List range 0 100)))))" "#t")
        (sample "(Sys time (fn () (heavy-computation)))" "1234"))
      (let ((t0 ((prim-ref (lit sys) (lit clock)))))
        (do (thunk)
            (- ((prim-ref (lit sys) (lit clock))) t0))))

    ; --- Wall clock (#21) ---
    ; libc gettimeofday into a GC-owned 16-byte buffer; the timeval decode
    ; is OS-shared: tv_sec is an i64 at 0 on both; tv_usec at 8 fits a u32
    ; read on both (Darwin's field IS 32-bit; Linux's is an i64 < 1e6).
    ; That is the 64-bit timeval; a 32-bit one puts tv_usec at 4, and the
    ; 4-byte usec read is a widening (ptr ref) -- host byte order.
    ; constraint: word-size = 8 -- struct timeval field offsets are 64-bit
    ; constraint: endian = little -- widening (ptr ref) of tv_usec
    (method time-of-day (self)
      (doc "Wall-clock time from gettimeofday: (unix-seconds . microseconds)."
        (returns PAIR "(seconds . microseconds)")
        (sample "(Sys time-of-day)" "(1752861000 . 123456)"))
      (let ((s (%make-str 16)))
        (let ((buf (%str->ptr s)))
          (let ((r (%sys-fold (%ptr-call (%resolve "gettimeofday") buf 0))))
            (when (< r 0) (error (Err from-errno (Err errno-of r) (lit gettimeofday) ())))
            (pair (%ptr-ref buf 0 8) (%ptr-ref buf 8 4))))))

    (method now (self)
      (doc "Wall-clock time as unix seconds (UTC) -- the noun reading; (Sys time thunk) is the verb. CPU time is (Sys clock); civil dates are the Date class (x/sys/date)."
        (returns INTEGER "Seconds since the unix epoch")
        (sample "(Sys now)" "1752861000"))
      (first (Sys time-of-day)))

    ; --- Time zone ---
    ; libc's localtime_r into a GC-owned struct tm, after tzset so a TZ set
    ; since the last call is read.  Glibc's and Darwin's struct tm share the
    ; fields read here: tm_isdst an int at 32, tm_gmtoff a long at 40 (an
    ; offset within a day, so its low 32 bits, sign-folded), tm_zone a char*
    ; at 48.  Those are 64-bit offsets, and the low half of tm_gmtoff is read
    ; as an int: the word-size and endian constraints time-of-day declares
    ; for this file hold here too.
    (method zone (self (param secs INTEGER "Unix seconds: the instant whose zone to read"))
      (doc "The local time zone in force at unix second secs, from the C library's localtime_r: its offset from UTC in seconds east, its abbreviation, and whether it is daylight time. TZ in the environment chooses the zone, as it does for every C program; with none set, the system's."
        (returns ALIST "((offset . SECONDS-EAST) (name . STRING) (dst . BOOL))")
        (note "Civil fields in local time are (Date local secs).")
        (sample "(Sys zone (Sys now))" "((offset . -14400) (name . \"EDT\") (dst . #t))"))
      (let ((t (%make-str 8)) (tm (%make-str 64)))
        (%ptr-set-word! (%str->ptr t) 0 secs)
        (%ptr-call (%resolve "tzset"))
        (when (= 0 (%ptr-call (%resolve "localtime_r") (%str->ptr t) (%str->ptr tm)))
          (Err raise (lit value) "Sys zone: localtime_r cannot convert the time" secs))
        (let ((p (%str->ptr tm)))
          (list (pair (lit offset) (%sys-fold (%ptr-ref p 40 4)))
                (pair (lit name) (%cvt (%cvt (%ptr-ref p 48 8) %ptr) %string))
                (pair (lit dst) (> (%ptr-ref p 32 4) 0))))))

    ; zone's inverse: libc's mktime over a struct tm of local fields, with
    ; tm_isdst -1 so the C library decides whether daylight time is in
    ; force -- and so resolves a time a change skips or repeats as it does
    ; for every C program.  The fields are ints at 0 to 20 and tm_isdst at
    ; 32, as zone reads them; the rest of the struct is zeroed first.
    (method local->unix (self (param year INTEGER "Year")
                              (param month INTEGER "Month, 1-12")
                              (param day INTEGER "Day of the month")
                              (param hour INTEGER "Hour, 0-23")
                              (param minute INTEGER "Minute")
                              (param second INTEGER "Second"))
      (doc "Unix seconds for a civil time in the local zone, from the C library's mktime: the zone TZ chooses, daylight time decided by the C library. Fields past their range carry into the next, as mktime's do."
        (returns INTEGER "Seconds since the unix epoch")
        (note "The inverse of the clock fields (Date local) reads; (Date local->unix date) takes a date alist.")
        (sample "(Sys local->unix 2026 9 21 10 13 20)" "1790000000, under TZ=EST5EDT,M3.2.0,M11.1.0"))
      (let ((tm (%make-str 64)) (set (prim-ref (lit ptr) (lit set!))))
        (let ((p (%str->ptr tm)))
          (%ptr-set-word! p 0 0) (%ptr-set-word! p 8 0) (%ptr-set-word! p 16 0)
          (%ptr-set-word! p 24 0) (%ptr-set-word! p 32 0) (%ptr-set-word! p 40 0)
          (%ptr-set-word! p 48 0) (%ptr-set-word! p 56 0)
          (set p 0 second 4) (set p 4 minute 4) (set p 8 hour 4)
          (set p 12 day 4) (set p 16 (- month 1) 4) (set p 20 (- year 1900) 4)
          (set p 32 -1 4)
          (%ptr-call (%resolve "tzset"))
          (%ptr-call (%resolve "mktime") p))))))))

(doc (provide x/sys/posix Sys)
  (note "POSIX via the Sys class: (Sys fork), (Sys exec name args), (Sys pipe),")
  (note "(Sys open-read path), (Sys getenv name), (Sys isatty fd), ...")
  "POSIX system call wrappers, homed on the Sys class.")
