; stream.x -- Stream: output redirection as first-class streams (pure X).
; One of the four I/O tiers -- Io holds the verbs, Stream redirects
; output, File is the filesystem, Buf is the reader's side; the full
; statement lives in x/type/io.x's header (#365).
;
; display/write emit to the base's `fileout` fd -- an integer ATOM in the io
; `files` group (filein fileout fileerr write-buf buffer), whose rows the
; layout contract names.  The base is just a pair tree, so redirection is
; first/set-first! on the fileout cell -- no C primitive needed. A Stream wraps
; a target fd; write to it directly, or redirect the current output through it.
;
; NOTE the accessors: the fd is an ATOM at (first cell) -- read with `first`,
; set with `set-first!`. NOT first-int/set-first-int! (those read/write a raw
; stack-int and corrupt the atom cell -- that is intrinsics.x's stale %stderr).
;
; File-backed streams need the radon dialect (File open/close/write -> syscall).
(import x/sys/file)
(import x/type/class)

; --- the fileout cell: the fd display/write currently target ---
; The committed `files` route, then its 2nd cell.  This walked the base by
; literal first/rest steps until 2026-08-23, which assumed one engine's layout.
(def %files (fn (_) (%reflect-base-cell (lit files))))
(def %fileout-cell (fn (_) (first (rest (%files)))))

; Read the current output fd.
(def %output-fd (fn (_) (first (%fileout-cell))))

; Point output at FD; return the previous fd (pass it back to restore).
(def %set-output-fd!
  (fn (_ fd)
    (let ((cell (%fileout-cell)))
      (let ((prev (first cell)))
        (%set-first! cell fd)
        prev))))

; Run THUNK with output redirected to FD, restoring the prior fd afterward --
; even if THUNK errors (guard restores, then re-raises via (error e)).
(def %with-fd
  (fn (_ fd thunk)
    (let ((prev (%set-output-fd! fd)))
      (guard (e (%set-output-fd! prev) (error e))
        (let ((result (thunk)))
          (%set-output-fd! prev)
          result)))))

(def-class Stream ()
  (doc "A first-class output stream over a file descriptor: write to it, or redirect display/write output through it for the duration of a thunk."
    (note "Pure X: display/write target the base's fileout fd (an atom in the io `files` group, whose rows the layout contract names); a Stream just pushes/pops that fd.")
    (note "(Stream to-fd fd) wraps an existing fd (not owned). (Stream to-file path) opens path for writing and OWNS it -- (close) closes it. (Stream stdout)/(Stream stderr) are conveniences.")
    (note "File-backed streams (to-file, write, with-file) need the radon dialect (File open/close/write -> syscall/make-str).")
    (sample "(Stream with-file \"grid.svg\" (fn (_) (grid ->svg)))" "saves whatever (grid ->svg) displays into grid.svg")
    (sample "(let ((s (Stream to-file \"out.txt\"))) (s with (fn (_) (display \"hi\"))) (s close))" "writes \"hi\" to out.txt, then closes it"))

  fd        ; the target file descriptor (set by every constructor)
  owned?    ; #t if this stream opened the fd, so (close) should close it

  (static
    ; --- constructors ---
    (method to-fd (self (param fd INT "An already-open file descriptor"))
      (doc "Wrap an already-open fd in a stream. Not owned -- (close) is a no-op."
        (returns Stream "A stream writing to FD")
        (sample "(Stream to-fd 2)" "a stream onto stderr"))
      (new-from self (list 'fd fd 'owned? ())))

    (method to-file (self (param path STRING "File path to open for writing"))
      (doc "Open PATH for writing (wronly|creat|trunc) and wrap its fd in an OWNED stream -- (close) closes the file. Needs the radon dialect."
        (returns Stream "An owned stream writing to PATH")
        (note "A newly created file gets mode 0644 (File open's default perm); open via File directly if you need other permission bits.")
        (sample "(Stream to-file \"grid.svg\")" "an owned stream that truncates/creates grid.svg"))
      (new-from self
        (list 'fd (File open path (list 'wronly 'creat 'trunc))
              'owned? #t)))

    (method stdout (self)
      (doc "A stream onto stdout (fd 1)." (returns Stream "stdout stream"))
      (Stream to-fd 1))
    (method stderr (self)
      (doc "A stream onto stderr (fd 2)." (returns Stream "stderr stream"))
      (Stream to-fd 2))

    ; --- introspection ---
    (method output-fd (self)
      (doc "The file descriptor display/write currently emit to."
        (returns INT "the current output fd")
        (sample "(Stream output-fd)" "1 (stdout), normally"))
      (%output-fd))

    ; --- thunk redirect helpers ---
    (method with-fd (self (param fd INT "Target file descriptor")
                                    (param thunk CALLABLE "Zero-arg thunk to run"))
      (doc "Run THUNK with display/write redirected to FD, restoring the previous target afterward (even if THUNK errors)."
        (returns ANY "THUNK's result")
        (sample "(Stream with-fd 2 (fn (_) (display \"to stderr\")))" "displays to stderr, returns nil"))
      (%with-fd fd thunk))

    (method with-file (self (param path STRING "File path to write")
                                      (param thunk CALLABLE "Zero-arg thunk to run"))
      (doc "Open PATH for writing, run THUNK with all output going to it, then restore the previous output and close PATH (even if THUNK errors). The one-call way to save streamed output to a file."
        (returns ANY "THUNK's result")
        (sample "(Stream with-file \"grid.svg\" (fn (_) (grid ->svg)))" "saves (grid ->svg)'s output to grid.svg"))
      (let ((s (Stream to-file path)))
        (guard (e (s close) (error e))
          (let ((result (s with thunk)))
            (s close)
            result)))))

  ; --- instance methods ---
  (method fd (self)
    (doc "The file descriptor this stream writes to." (returns INT "the fd"))
    (member 'fd))

  (method with (self (param thunk CALLABLE "Zero-arg thunk to run"))
    (doc "Run THUNK with the current display/write output redirected to this stream, restoring afterward (even if THUNK errors)."
      (returns ANY "THUNK's result")
      (sample "(s with (fn (_) (display x)))" "displays x to the stream s"))
    (%with-fd (member 'fd) thunk))

  (method write (self (param data STRING "Bytes to write")
                      (param size INT "Number of bytes"))
    (doc "Write SIZE bytes of DATA directly to the stream's fd. Needs the radon dialect."
      (returns INT "Bytes written, or negative on error"))
    (File write (member 'fd) data size))

  (method display (self (param v ANY "Value to render"))
    (doc "Render V (display form) to this stream."
      (returns ANY "nil"))
    (%with-fd (member 'fd) (fn (_) (display v))))

  (method close (self)
    (doc "Close the stream's fd if it owns it (opened via to-file); a no-op for wrapped fds (to-fd/stdout/stderr)."
      (returns ANY "File close result, or nil when not owned"))
    (if (member 'owned?) (File close (member 'fd)) ())))

(doc (provide x/sys/stream Stream)
  (note "Redirection is pure X -- push/pop the base's fileout fd (an atom in the io `files` group); no C primitive. File targets need the radon dialect.")
  "Output redirection as first-class Streams: to-fd/to-file/stdout/stderr, (s with thunk)/write/display/close, plus the with-fd / with-file helpers.")
