; posix.x -- POSIX function wrappers via FFI (dlsym + ptr-call)
(import x/list)
;
; Replaces C shell primitives with pure x-lang using the FFI layer.
; Provides: sh-fork, sh-exec, sh-pipe, sh-dup2, sh-wait, sh-open-read,
;   sh-open-write, sh-open-append, sh-close, sh-chdir, sh-getenv,
;   sh-setenv, sh-getpid, sh-exit
; --- Resolve libc functions ---

(def %libc (dlopen () 1))

(def %resolve (fn (name) (dlsym %libc name)))

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

(note "Process Control")

; --- Simple wrappers (ptr-call auto-converts string args to char*) ---

(doc (def sh-fork (fn () (ptr-call %c-fork)))
  (returns INTEGER "PID of child in parent, 0 in child, -1 on error")
  "Fork the current process.")

(doc (def sh-getpid (fn () (ptr-call %c-getpid)))
  (returns INTEGER "Process ID")
  "Return the current process ID.")

(doc (def sh-exit
  (fn ((param status INTEGER "Exit status code"))
    (ptr-call %c-exit status)))
  "Terminate the process with the given exit status.")

(doc (def sh-wait
  (fn ((param pid INTEGER "Process ID to wait for"))
    (let ((buf (convert (ptr-call %c-malloc 4) %ptr)))
      (ptr-call %c-waitpid pid buf 0)
      (let ((raw (ptr-ref buf 0 4)))
        (ptr-call %c-free buf)
        (/ (% raw 65536) 256)))))
  (returns INTEGER "Exit status of the child process")
  "Wait for a child process and return its exit status.")

(doc (def sh-exec
  (fn ((param name STRING "Program name") (param args LIST "List of argument strings"))
    (let ((all (pair name args)))
      (let ((n (length all)))
        (let ((argv (convert (ptr-call %c-malloc (* (+ n 1) %word-size)) %ptr)))
          (def %fill
            (fn (lst i)
              (if (null? lst)
                (ptr-set-word! argv (* i %word-size) 0)
                (do
                  (ptr-set-word!
                    argv
                    (* i %word-size)
                    (convert (convert (first lst) %ptr) %int))
                  (%fill (rest lst) (+ i 1))))))
          (%fill all 0)
          (ptr-call %c-execvp name argv))))))
  "Replace the current process with the named program. Does not return on success.")

(note "File Descriptors")

(doc (def sh-close
  (fn ((param fd INTEGER "File descriptor to close"))
    (ptr-call %c-close fd)))
  (returns INTEGER "0 on success, -1 on error")
  "Close a file descriptor.")

(doc (def sh-dup2
  (fn ((param old INTEGER "Source file descriptor") (param new INTEGER "Target file descriptor"))
    (ptr-call %c-dup2 old new)))
  (returns INTEGER "New file descriptor, or -1 on error")
  "Duplicate a file descriptor onto another.")

(doc (def sh-pipe
  (fn ()
    (let ((buf (convert (ptr-call %c-malloc 8) %ptr)))
      (ptr-call %c-pipe buf)
      (let ((r (ptr-ref buf 0 4)) (w (ptr-ref buf 4 4)))
        (ptr-call %c-free buf)
        (pair r w)))))
  (returns PAIR "Pair of (read-fd . write-fd)")
  "Create a pipe and return a pair of file descriptors.")

(note "File I/O")

(doc (def sh-open-read
  (fn ((param path STRING "File path to open"))
    (ptr-call %c-open path %O_RDONLY)))
  (returns INTEGER "File descriptor, or -1 on error")
  "Open a file for reading.")

(doc (def sh-open-write
  (fn ((param path STRING "File path to open"))
    (let ((fd (ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_TRUNC)) 438)))
      (if (>= fd 0) (ptr-call %c-fchmod fd 438))
      fd)))
  (returns INTEGER "File descriptor, or -1 on error")
  "Open a file for writing, creating or truncating it.")

(doc (def sh-open-append
  (fn ((param path STRING "File path to open"))
    (let ((fd (ptr-call %c-open path (+ %O_WRONLY (+ %O_CREAT %O_APPEND)) 438)))
      (if (>= fd 0) (ptr-call %c-fchmod fd 438))
      fd)))
  (returns INTEGER "File descriptor, or -1 on error")
  "Open a file for appending, creating it if necessary.")

(note "Environment")

(doc (def sh-chdir
  (fn ((param path STRING "Directory path"))
    (ptr-call %c-chdir path)))
  (returns INTEGER "0 on success, -1 on error")
  "Change the current working directory.")

(doc (def sh-setenv
  (fn ((param name STRING "Variable name") (param val STRING "Variable value"))
    (ptr-call %c-setenv name val 1)))
  (returns INTEGER "0 on success, -1 on error")
  "Set an environment variable, overwriting any existing value.")

(doc (def sh-getenv
  (fn ((param name STRING "Variable name"))
    (let ((result (ptr-call %c-getenv name)))
      (if (= result 0) () (convert (convert result %ptr) %string)))))
  (returns STRING "Variable value, or nil if not set")
  "Get the value of an environment variable.")

(provide x/posix
  sh-fork sh-getpid sh-close sh-dup2 sh-chdir sh-exit
  sh-setenv sh-getenv sh-open-read sh-open-write sh-open-append
  sh-pipe sh-wait sh-exec)
