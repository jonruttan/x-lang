; # x-lang
;
; ## lib/x/sys/pty.x -- Pty: a program on a pseudo-terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A pseudo-terminal pair comes from libc's posix_openpt, grantpt, unlockpt
; and ptsname -- fixed-signature calls, so the ffi door carries them.  The
; ioctls that set its window and make it a controlling terminal go by
; syscall, as Term reads a window: ioctl is variadic, and on Apple arm64 a
; variadic argument goes on the stack, where the fixed-signature ffi door
; never puts it.  The requests differ by OS, Darwin encoding the direction
; and size into the number.
;
; Darwin keeps no window on a master whose slave no one has open: a
; TIOCSWINSZ on the master before the child has opened the slave is lost.
; So the child sets the window as it attaches, on the slave, and a resize
; later goes to the master, where the kernel signals the program's process
; group with SIGWINCH.
;
; The libc entry points are resolved on each call: a handle is a fact of
; the process, and a state image carries the heap of the one that wrote it.

(module x/sys/pty)

(import x/type/class)
(import x/core/list)
(import x/core/alist)
(import x/sys/posix)
(import x/sys/file)
(import x/platform/syscall file-modes syscall-id)

(def-class Pty ()
  (doc "A pseudo-terminal: (Pty open) a master and the slave's path, (Pty window! fd cols rows) its size, (Pty attach! path cols rows) a forked child's controlling terminal, (Pty fork cols rows) the three together as forkpty(3) does, and (Pty spawn program args cols rows) a program run on one."
    (note "The master answers as given, blocking: a poll loop makes it non-blocking with (Sys nonblock! master), which reaches fcntl as a syscall for the reason window! reaches ioctl as one.")
    (see open) (see window!) (see attach!) (see fork) (see spawn))

  (static
    (method %c (self (param name STRING "A libc function"))
      (doc "The libc entry point named, resolved now." (returns POINTER "Its address"))
      ((prim-ref (lit ffi) (lit dlsym)) ((prim-ref (lit ffi) (lit dlopen)) () 1) name))

    (method %call (self (param name STRING "A libc function") . (param args LIST "Its arguments"))
      (doc "A libc call's int answer, sign-folded: -1 is an error." (returns INTEGER "The answer"))
      (Sys %sign-fold (apply (prim-ref (lit ptr) (lit call)) (pair (Pty %c name) args))))

    (method %ioctl (self (param fd INTEGER "Descriptor")
                         (param request INTEGER "The request number")
                         (param arg ANY "Its argument: an integer or a buffer"))
      (doc "ioctl(2) as a syscall, sign-folded: -1 when this platform's table has no ioctl."
        (returns INTEGER "0, or negative on error"))
      (def id (syscall-id (lit ioctl)))
      (if (< id 0) -1 (Sys %sign-fold (syscall id fd request arg))))

    (method tiocswinsz (self)
      (doc "The TIOCSWINSZ ioctl request for this OS." (returns INTEGER "The request"))
      (if os-darwin? 2148037735 21524))

    (method tiocsctty (self)
      (doc "The TIOCSCTTY ioctl request for this OS." (returns INTEGER "The request"))
      (if os-darwin? 536900705 21518))

    (method open (self)
      (doc "A new pseudo-terminal pair: its master, opened read-write and not as this process's controlling terminal, and the path of its slave, granted and unlocked. Answers nil when the system gives none."
        (returns ANY "(MASTER . SLAVE-PATH), or nil")
        (sample "(Pty open)" "(5 . \"/dev/ttys004\")"))
      (def mode (+ (first (Assoc get (lit rdwr) file-modes)) (first (Assoc get (lit noctty) file-modes))))
      (def m (Pty %call "posix_openpt" mode))
      (match
        ((< m 0) ())
        ((< (Pty %call "grantpt" m) 0) (do (File close m) ()))
        ((< (Pty %call "unlockpt" m) 0) (do (File close m) ()))
        (#t (let ((p ((prim-ref (lit ptr) (lit call)) (Pty %c "ptsname") m)))
              (if (= p 0)
                (do (File close m) ())
                (let ((cvt (prim-ref (lit convert) (lit to))))
                  (pair m (cvt (cvt p (Type named POINTER)) (Type named STRING)))))))))

    (method window! (self (param fd INTEGER "The master, or the slave")
                          (param cols INTEGER "Columns")
                          (param rows INTEGER "Rows"))
      (doc "Set the terminal's window, struct winsize's rows and columns with no pixel size. Set on the master, the kernel signals the program's process group with SIGWINCH. Answers #f when the ioctl fails."
        (returns BOOL "Whether the window was set")
        (note "On Darwin a window set on a master whose slave no one has open is lost: a new terminal's first window is set by attach!, from the child.")
        (sample "(Pty window! master 120 40)" "#t"))
      (def w ((prim-ref (lit str) (lit make)) 16))
      (def p ((prim-ref (lit str) (lit ->ptr)) w))
      (def set (prim-ref (lit ptr) (lit set!)))
      (set p 0 rows 2) (set p 2 cols 2) (set p 4 0 2) (set p 6 0 2)
      (>= (Pty %ioctl fd (Pty tiocswinsz) w) 0))

    (method attach! (self (param path STRING "The slave's path, as open gives it")
                          (param cols INTEGER "Columns")
                          (param rows INTEGER "Rows"))
      (doc "In a forked child: a session of its own, the slave opened as its controlling terminal with its window set, and made its standard input, output and error. Answers #f, having changed nothing past the new session, when the slave cannot be opened."
        (returns BOOL "Whether the slave is now the terminal")
        (sample "(Pty attach! \"/dev/ttys004\" 80 24)" "#t, in the child"))
      (Pty %call "setsid")
      (def fd (File open path (lit rdwr)))
      (if (< fd 0) #f
        (do (Pty %ioctl fd (Pty tiocsctty) 0)
            (Pty window! fd cols rows)
            (Sys dup2 fd 0) (Sys dup2 fd 1) (Sys dup2 fd 2)
            (when (> fd 2) (File close fd))
            #t)))

    (method fork (self (param cols INTEGER "Columns")
                       (param rows INTEGER "Rows")
                       . (param close LIST "Descriptors the child closes"))
      (doc "Fork a child onto a new pseudo-terminal of cols by rows, as forkpty(3) does. The parent gets (PID . MASTER); the child, attached, gets (0 . -1), having closed the master and every descriptor in close. Answers nil when no terminal or no child can be had. A child that cannot open the slave exits 127."
        (returns ANY "(PID . MASTER) in the parent, (0 . -1) in the child, or nil")
        (sample "(Pty fork 80 24)" "(4242 . 5) in the parent"))
      (def pty (Pty open))
      (if (null? pty) ()
        (let ((pid (Sys fork)))
          (match
            ((< pid 0) (do (File close (first pty)) ()))
            ((= pid 0)
              (do (File close (first pty))
                  (List for-each (fn (_ fd) (File close fd)) (if (null? close) () (first close)))
                  (unless (Pty attach! (rest pty) cols rows) (Sys exit 127))
                  (pair 0 -1)))
            (#t (pair pid (first pty)))))))

    (method spawn (self (param program STRING "The program, found on PATH as execvp finds it")
                        (param args LIST "Its arguments, after its name")
                        (param cols INTEGER "Columns")
                        (param rows INTEGER "Rows")
                        . (param close LIST "Descriptors the child closes"))
      (doc "Run program on a new pseudo-terminal of cols by rows: its standard input, output and error, and its controlling terminal. A child the program cannot replace exits 127."
        (returns ANY "(PID . MASTER), or nil when no terminal or no child can be had")
        (note "What the program writes is read from the master; what is written to the master is its input. (Sys wait pid) collects it.")
        (sample "(Pty spawn \"/bin/sh\" () 80 24)" "(4242 . 5)"))
      (def r (Pty fork cols rows (if (null? close) () (first close))))
      (when (if (null? r) #f (= (first r) 0))
        (do (Sys exec program args) (Sys exit 127)))
      r)))

(doc (provide x/sys/pty Pty)
  (note "ioctl goes by syscall, never the fixed-signature ffi door: it is variadic.")
  (note "A new terminal's window is set by the child as it attaches: Darwin loses one set on the master first.")
  "Pty: pseudo-terminals, and a program run on one.")
