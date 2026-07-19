; socket.x -- Socket: TCP over libc FFI, homed on the Socket class (#29).
;
; Extracted from logo/serve.x's proven plumbing (its constants were
; Darwin-only, hardcoded app-side; anyone wanting a TCP client rebuilt
; sockaddr packing from scratch). The FFI-libc route is deliberate: the
; syscall-number path would drag in Linux's socketcall indirection; libc
; socket()/bind()/... exist identically on both OSes.
;
; IPv4 only, blocking, no DNS: `host` is a dotted quad ("127.0.0.1").
; Failures raise kind-'io Errs via (Err from-errno (Err errno-of r) ...).

(import x/sys/posix)
(import x/type/object)
(import x/core/list)

; libc doors (cold: fetched once at load; calls go through %ptr-call)
(def %sk-ptr-call (prim-ref 'ptr 'call))
(def %sk-ptr-set! (prim-ref 'ptr 'set!))
(def %sk-ptr->str (prim-ref 'ptr '->str))
(def %sk-int->ptr (prim-ref 'int '->ptr))
(def %sk-dlopen (prim-ref 'ffi 'dlopen))
(def %sk-dlsym (prim-ref 'ffi 'dlsym))
(def %sk-libc (%sk-dlopen () 1))
(def %sk (fn (_ name) (%sk-dlsym %sk-libc name)))
(def %c-socket (%sk "socket"))
(def %c-bind (%sk "bind"))
(def %c-listen (%sk "listen"))
(def %c-accept (%sk "accept"))
(def %c-connect (%sk "connect"))
(def %c-send (%sk "send"))
(def %c-recv (%sk "recv"))
(def %c-close (%sk "close"))
(def %c-setsockopt (%sk "setsockopt"))
(def %c-malloc (%sk "malloc"))
(def %c-free (%sk "free"))
(def %c-memset (%sk "memset"))

; Per-OS socket-level constants. AF_INET=2 and SOCK_STREAM=1 agree on
; both; the SOL/SO pair does not.
(def %AF-INET 2)
(def %SOCK-STREAM 1)
(def %SOL-SOCKET (if os-darwin? 65535 1))
(def %SO-REUSEADDR (if os-darwin? 4 2))

(def %sk-set1! (fn (_ p off v) (%sk-ptr-set! p off v 1)))

; Sign-fold an FFI int return -- the canonical fold (and the full story:
; Linux ptr-call zero-extends libc's -1; Darwin sign-extends) is
; %sys-fold in x/sys/posix, imported above. Alias kept for the call
; sites below.
(def %sk-fold %sys-fold)

; Parse a dotted quad into its four octets; kind-'value Err on anything
; else (no DNS here by design).
(def %parse-quad
  (fn (_ host)
    (def parts (Str8 split "." host))
    (def octets
      (map (fn (_ p)
             (if (str=? p "") (Err raise 'value (Str8 append "Socket: bad IPv4 address: " host) ())
               (str->number p)))
           parts))
    (when (not (= (length octets) 4))
      (Err raise 'value (Str8 append "Socket: bad IPv4 address: " host) ()))
    (List for-each
      (fn (_ o) (when (or (null? o) (< o 0) (> o 255))
                  (Err raise 'value (Str8 append "Socket: bad IPv4 address: " host) ())))
      octets)
    octets))

; Fill a fresh sockaddr_in (16 bytes, malloc'd -- caller frees): Darwin
; leads with a length byte + 1-byte family; Linux with a 2-byte family.
; Port is network order (big-endian) on both; addr defaults to INADDR_ANY.
(def %make-sockaddr-in
  (fn (_ port host)
    (def addr (%sk-int->ptr (%sk-ptr-call %c-malloc 16)))
    (%sk-ptr-call %c-memset addr 0 16)
    (if os-darwin?
      (do (%sk-set1! addr 0 16) (%sk-set1! addr 1 %AF-INET))
      (do (%sk-set1! addr 0 %AF-INET) (%sk-set1! addr 1 0)))
    (%sk-set1! addr 2 (/ port 256))
    (%sk-set1! addr 3 (% port 256))
    (unless (null? host)
      (let ((o (%parse-quad host)))
        (%sk-set1! addr 4 (List ref 0 o))
        (%sk-set1! addr 5 (List ref 1 o))
        (%sk-set1! addr 6 (List ref 2 o))
        (%sk-set1! addr 7 (List ref 3 o))))
    addr))

; Raise a kind-'io Err for a failed call (fetch errno FIRST -- any
; intervening libc call clobbers it), freeing addr if given.
(def %sk-fail
  (fn (_ r op detail addr)
    (def en (Err errno-of r))
    (unless (null? addr) (%sk-ptr-call %c-free addr))
    (error (Err from-errno en op detail))))

(def-class Socket ()
  (doc "Blocking IPv4 TCP over libc FFI: listen/accept on the server side, connect on the client side, send/recv/close on both."
    (note "No DNS: hosts are dotted quads (\"127.0.0.1\"). Failures raise kind-'io Errs with errno detail; recv answers nil at orderly EOF (absence, not a sentinel).")
    (sample "(let ((fd (Socket tcp-connect \"127.0.0.1\" 8080))) (Socket send fd \"ping\") (Socket recv fd 4096))" "the reply string"))
  (static
    (method tcp-listen (self (param port INT "Port to bind")
                             . (param backlog INT "Listen backlog; default 16"))
      (doc "Create a TCP server socket: socket + SO_REUSEADDR + bind(INADDR_ANY, port) + listen."
        (returns INT "The listening file descriptor")
        (sample "(Socket tcp-listen 8080)" "a listening fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket %AF-INET %SOCK-STREAM 0)))
      (when (< fd 0) (%sk-fail fd 'socket port ()))
      ; SO_REUSEADDR: an int 1 (4 LE bytes) so quick restarts do not
      ; trip on TIME_WAIT.
      (def optval (%sk-int->ptr (%sk-ptr-call %c-malloc 4)))
      (%sk-ptr-call %c-memset optval 0 4)
      (%sk-set1! optval 0 1)
      (%sk-ptr-call %c-setsockopt fd %SOL-SOCKET %SO-REUSEADDR optval 4)
      (%sk-ptr-call %c-free optval)
      (def addr (%make-sockaddr-in port ()))
      (def r (%sk-fold (%sk-ptr-call %c-bind fd addr 16)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'bind port addr)))
      (%sk-ptr-call %c-free addr)
      (def lr (%sk-fold (%sk-ptr-call %c-listen fd (if (null? backlog) 16 (first backlog)))))
      (when (< lr 0) (do (%sk-ptr-call %c-close fd) (%sk-fail lr 'listen port ())))
      fd)

    (method accept (self (param fd INT "Listening file descriptor"))
      (doc "Block until a client connects; the peer address is discarded (stat the fd's peer later if wanted)."
        (returns INT "The connected client file descriptor")
        (sample "(Socket accept listen-fd)" "a client fd"))
      (def cfd (%sk-fold (%sk-ptr-call %c-accept fd 0 0)))
      (when (< cfd 0) (%sk-fail cfd 'accept fd ()))
      cfd)

    (method tcp-connect (self (param host STRING "Dotted-quad IPv4 address")
                              (param port INT "Port to connect to"))
      (doc "Open a TCP connection to host:port (no DNS -- dotted quads only)."
        (returns INT "The connected file descriptor")
        (sample "(Socket tcp-connect \"127.0.0.1\" 8080)" "a connected fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket %AF-INET %SOCK-STREAM 0)))
      (when (< fd 0) (%sk-fail fd 'socket port ()))
      (def addr (%make-sockaddr-in port host))
      (def r (%sk-fold (%sk-ptr-call %c-connect fd addr 16)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'connect (list host port) addr)))
      (%sk-ptr-call %c-free addr)
      fd)

    (method send (self (param fd INT "Connected file descriptor")
                       (param s STRING "Bytes to send"))
      (doc "Send the whole string; raises on failure."
        (returns INT "Bytes sent"))
      (def r (%sk-fold (%sk-ptr-call %c-send fd s (str-length s) 0)))
      (when (< r 0) (%sk-fail r 'send fd ()))
      r)

    (method recv (self (param fd INT "Connected file descriptor")
                       (param maxlen INT "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a string; nil at orderly EOF (the peer closed); raises on failure."
        (returns ANY "The received string, or nil at EOF"))
      (def buf (%sk-int->ptr (%sk-ptr-call %c-malloc (+ maxlen 1))))
      (def n (%sk-fold (%sk-ptr-call %c-recv fd buf maxlen 0)))
      (when (< n 0)
        (let ((en (Err errno-of n)))
          (%sk-ptr-call %c-free buf)
          (error (Err from-errno en 'recv fd))))
      (if (= n 0)
        (do (%sk-ptr-call %c-free buf) ())
        (let ((s (do (%sk-set1! buf n 0) (%sk-ptr->str buf))))
          (%sk-ptr-call %c-free buf)
          s)))

    (method close (self (param fd INT "File descriptor to close"))
      (doc "Close a socket file descriptor."
        (returns ANY "nil"))
      (%sk-ptr-call %c-close fd)
      ())))

(doc (provide x/sys/socket Socket)
  (note "First consumer: x/logo/serve.x (whose Darwin-only constants this replaces). Recv truncates at the first NUL byte (ptr->str) -- fine for text protocols; binary recv needs a byte-list door, tracked with the Buf work.")
  "Blocking IPv4 TCP on the Socket class, over libc FFI.")
