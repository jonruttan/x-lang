; posix.x -- POSIX function wrappers via FFI (dlsym + ptr-call)
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
; --- Simple wrappers (ptr-call auto-converts string args to char*) ---

(def sh-fork (fn () (ptr-call %c-fork)))

(def sh-getpid (fn () (ptr-call %c-getpid)))

(def sh-close (fn (fd) (ptr-call %c-close fd)))

(def sh-dup2 (fn (old new) (ptr-call %c-dup2 old new)))

(def sh-chdir (fn (path) (ptr-call %c-chdir path)))

(def sh-exit (fn (status) (ptr-call %c-exit status)))

(def sh-setenv
  (fn (name val) (ptr-call %c-setenv name val 1)))
; --- getenv: returns char*, convert to string (or () if NULL) ---

(def sh-getenv
  (fn (name)
    (let ((result (ptr-call %c-getenv name)))
      (if (= result 0) () (ptr->string (int->ptr result))))))
; --- open variants ---
; macOS flags: O_RDONLY=0, O_WRONLY=1, O_CREAT=512, O_TRUNC=1024, O_APPEND=8

(def sh-open-read (fn (path) (ptr-call %c-open path 0)))

(def sh-open-write
  (fn (path)
    (let ((fd (ptr-call %c-open path 1537 438)))
      (if (>= fd 0) (ptr-call %c-fchmod fd 438))
      fd)))

(def sh-open-append
  (fn (path)
    (let ((fd (ptr-call %c-open path 521 438)))
      (if (>= fd 0) (ptr-call %c-fchmod fd 438))
      fd)))
; --- pipe: allocate int[2], call pipe(), read back fds ---

(def sh-pipe
  (fn ()
    (let ((buf (int->ptr (ptr-call %c-malloc 8))))
      (ptr-call %c-pipe buf)
      (let ((r (ptr-ref buf 0 4)) (w (ptr-ref buf 4 4)))
        (ptr-call %c-free buf)
        (pair r w)))))
; --- waitpid: allocate int for status, wait, extract exit code ---

(def sh-wait
  (fn (pid)
    (let ((buf (int->ptr (ptr-call %c-malloc 4))))
      (ptr-call %c-waitpid pid buf 0)
      (let ((raw (ptr-ref buf 0 4)))
        (ptr-call %c-free buf)
        (/ (% raw 65536) 256)))))
; --- exec: build C argv array, call execvp ---

(def sh-exec
  (fn (name args)
    (let ((all (pair name args)))
      (let ((n (length all)))
        (let ((argv (int->ptr (ptr-call %c-malloc (* (+ n 1) 8)))))
          (def %fill
            (fn (lst i)
              (if (null? lst)
                (ptr-set-word! argv (* i 8) 0)
                (do
                  (ptr-set-word!
                    argv
                    (* i 8)
                    (ptr->int (string->ptr (first lst))))
                  (%fill (rest lst) (+ i 1))))))
          (%fill all 0)
          (ptr-call %c-execvp name argv))))))
