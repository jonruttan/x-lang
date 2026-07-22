; err.x -- Err: structured errors -- kind + message + data (#20)
;
; An error VALUE is any x value (the C error prim raises whatever it is
; handed); Err is the structured convention on top:
;
;   (Err raise 'io "open failed" '((path . "/tmp/x")))
;
; The kind vocabulary is BLESSED BUT OPEN (any symbol is legal; these are
; the words the stdlib itself uses -- see contributing.md):
;
;   'type   wrong shape/type of argument
;   'value  right type, bad content (parse failures, out of domain)
;   'index  out of range
;   'io     errno-backed OS boundary (see from-errno)
;   'state  wrong lifecycle state (uninitialized, already closed)
;   'user   everything untagged -- ALL legacy bare-string errors
;
; (Err kind-of v) is TOTAL: an Err answers its kind, any other value
; (bare string, C error atom) answers 'user -- so one match discriminates
; old and new errors alike:
;
;   (guard (e (match
;               ((eq? (Err kind-of e) 'io) (retry))
;               (#t (error e))))          ; re-raise what we don't handle
;     body)
;
; Loaded in boot after the REPL (raise sites bind Err at CALL time, so
; late is fine); the errno table picks its per-OS column at load via
; os-darwin? (global since platform/syscall.x, itself boot-loaded).

(import x/type/class)
(import x/core/alist)

; --- errno -> (sym message) ---
;
; Numbers 1-34 are identical on Darwin and Linux; the divergent tail is
; picked at load. Entries: (num sym message), strerror-style messages.

(def %errno-base
  '((1 eperm "Operation not permitted")
    (2 enoent "No such file or directory")
    (3 esrch "No such process")
    (4 eintr "Interrupted system call")
    (5 eio "Input/output error")
    (6 enxio "Device not configured")
    (7 e2big "Argument list too long")
    (8 enoexec "Exec format error")
    (9 ebadf "Bad file descriptor")
    (10 echild "No child processes")
    (12 enomem "Cannot allocate memory")
    (13 eacces "Permission denied")
    (14 efault "Bad address")
    (16 ebusy "Resource busy")
    (17 eexist "File exists")
    (18 exdev "Cross-device link")
    (19 enodev "Operation not supported by device")
    (20 enotdir "Not a directory")
    (21 eisdir "Is a directory")
    (22 einval "Invalid argument")
    (23 enfile "Too many open files in system")
    (24 emfile "Too many open files")
    (27 efbig "File too large")
    (28 enospc "No space left on device")
    (29 espipe "Illegal seek")
    (30 erofs "Read-only file system")
    (31 emlink "Too many links")
    (32 epipe "Broken pipe")
    (33 edom "Numerical argument out of domain")
    (34 erange "Result too large")))

(def %errno-darwin
  '((11 edeadlk "Resource deadlock avoided")
    (35 eagain "Resource temporarily unavailable")
    (36 einprogress "Operation now in progress")
    (48 eaddrinuse "Address already in use")
    (49 eaddrnotavail "Cannot assign requested address")
    (51 enetunreach "Network is unreachable")
    (54 econnreset "Connection reset by peer")
    (57 enotconn "Socket is not connected")
    (60 etimedout "Operation timed out")
    (61 econnrefused "Connection refused")
    (62 eloop "Too many levels of symbolic links")
    (63 enametoolong "File name too long")
    (65 ehostunreach "No route to host")
    (66 enotempty "Directory not empty")))

(def %errno-linux
  '((11 eagain "Resource temporarily unavailable")
    (35 edeadlk "Resource deadlock avoided")
    (36 enametoolong "File name too long")
    (39 enotempty "Directory not empty")
    (40 eloop "Too many levels of symbolic links")
    (98 eaddrinuse "Address already in use")
    (99 eaddrnotavail "Cannot assign requested address")
    (101 enetunreach "Network is unreachable")
    (104 econnreset "Connection reset by peer")
    (107 enotconn "Socket is not connected")
    (110 etimedout "Connection timed out")
    (111 econnrefused "Connection refused")
    (113 ehostunreach "No route to host")
    (115 einprogress "Operation now in progress")))

(def %errno-table
  (%append %errno-base (if os-darwin? %errno-darwin %errno-linux)))

; Lazily-resolved errno location for (Err errno-of): () = unresolved,
; 'missing = libc lacks the symbol, else the dlsym'd function pointer.
(def %errno-loc-cell (pair () ()))

(def %errno-find
  (fn (self n table)
    (if (null? table) ()
      (if (= (first (first table)) n)
        (first table)
        (self n (rest table))))))

(def-class Err ()
  (doc "Structured error value: kind symbol + message string + data alist."
    (note "The kind vocabulary is blessed but open: 'type 'value 'index 'io 'state 'user (see contributing.md). Raise with (Err raise ...) or (error (Err make ...)); discriminate in a guard with (Err kind-of e) -- total over all error values, legacy bare strings answer 'user.")
    (example "((Err make 'io \"boom\" ()) kind)" "'io")
    (example "(guard (e (Err kind-of e)) (Err raise 'state \"closed\" ()))" "'state"))
  kind
  msg
  data
  (method kind? (self (param k SYMBOL "Kind to test against"))
    (doc "Test this error's kind."
      (returns BOOL "True when the error's kind is k")
      (example "((Err make 'io \"x\" ()) kind? 'io)" "#t"))
    (eq? (self kind) k))
  (method %repr (self)
    (doc "Inspection form: #<err:KIND MESSAGE>."
      (returns STRING "The repr string"))
    (Str8 append "#<err:" (symbol->str (self kind)) " " (self msg) ">"))
  (static
    (method make (self (param kind SYMBOL "Error kind, e.g. 'io")
                       (param msg STRING "Human-readable message")
                       (param data ALIST "Context alist (or ())"))
      (doc "Construct an Err value."
        (returns OBJECT "The Err instance")
        (example "(Err make 'value \"bad\" ())" "#<err:value bad>"))
      (new Err kind kind msg msg data data))

    (method raise (self (param kind SYMBOL "Error kind, e.g. 'io")
                        (param msg STRING "Human-readable message")
                        (param data ALIST "Context alist (or ())"))
      (doc "Construct an Err and raise it: (error (Err make kind msg data))."
        (returns ANY "Does not return"))
      (error (Err make kind msg data)))

    (method err? (self (param v ANY "Any value"))
      (doc "Test whether v is an Err instance."
        (returns BOOL "True for Err instances only")
        (example "(Err err? 42)" "#f"))
      (if (object? v) (eq? (class-of v) Err) #f))

    (method kind-of (self (param v ANY "Any error value"))
      (doc "The kind of any error value -- TOTAL: non-Err values (legacy bare strings, C error atoms) answer 'user, so one match discriminates old and new errors."
        (returns SYMBOL "The Err's kind, or 'user")
        (example "(Err kind-of \"bare string\")" "'user")
        (example "(Err kind-of (Err make 'index \"oops\" ()))" "'index"))
      (if (Err err? v) (v kind) 'user))

    (method errno-of (self (param r INT "A failed call's raw return value (negative)"))
      (doc "Recover the CURRENT errno after a failed libc/syscall call. The syscall prim routes through libc on both OSes, returning a bare -1 with the reason parked behind the per-thread errno location -- __error() on Darwin, __errno_location() on Linux; this derefs it (lazily resolving the symbol once). Falls back to (- 0 r) on a libc without the symbol. Fetch BEFORE any intervening call (a close on the error path clobbers errno)."
        (returns INT "The positive errno"))
      (when (null? (first %errno-loc-cell))
        (%set-first! %errno-loc-cell
          (let ((loc ((prim-ref 'ffi 'dlsym) ((prim-ref 'ffi 'dlopen) () 1)
                      (if os-darwin? "__error" "__errno_location"))))
            (if (null? loc) 'missing loc))))
      (if (eq? (first %errno-loc-cell) 'missing)
        (- 0 r)
        ((prim-ref 'ptr 'ref)
          ((prim-ref 'int '->ptr) ((prim-ref 'ptr 'call) (first %errno-loc-cell)))
          0 4)))

    (method from-errno (self (param n INT "errno, positive or the syscall layer's negative -errno")
                             (param op SYMBOL "The operation, e.g. 'open")
                             . (param detail ANY "Optional context value, e.g. the path"))
      (doc "Translate an errno into a kind-'io Err. The message is strerror-style prefixed with op; data carries ((errno . N) (sym . ENOENT-style-symbol) (op . OP) (detail . D)). Numbers are per-OS (picked at load via os-darwin?); unknown numbers get sym 'unknown."
        (returns OBJECT "The Err instance")
        (example "((Err from-errno 2 'open \"/nope\") msg)" "\"open: No such file or directory\"")
        (example "(Assoc get 'errno ((Err from-errno -2 'open ()) data))" "2"))
      (def en (if (< n 0) (- 0 n) n))
      (def hit (%errno-find en %errno-table))
      (def sym (if (null? hit) 'unknown (first (rest hit))))
      (def text (if (null? hit) "Unknown error" (first (rest (rest hit)))))
      (def d (if (null? detail) () (first detail)))
      (Err make 'io
        (Str8 append (symbol->str op) ": " text)
        (list (pair 'errno en) (pair 'sym sym) (pair 'op op) (pair 'detail d))))))

(doc (provide x/type/err Err)
  (note "The structured-error convention: kind + message + data over the untyped C error prim. See the header comment for the kind vocabulary and the guard/match idiom.")
  "Structured errors: the Err class, kind taxonomy, errno translation.")
