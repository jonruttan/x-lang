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
(import x/type/class)
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
      (%map (fn (_ p)
             (if (str=? p "") (Err raise 'value (Str8 append "Socket: bad IPv4 address: " host) ())
               (%str->number p)))
           parts))
    (when (not (= (%length octets) 4))
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
      (def r (%sk-fold (%sk-ptr-call %c-send fd s (Str8 length s) 0)))
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

    (method resolve (self (param name STRING "Hostname to resolve"))
      (doc "The host's first IPv4 address as a dotted quad, via getaddrinfo (#412) -- the DNS door; every other Socket method still takes quads. Raises kind-'io with the gai code when resolution fails, kind-'value when the name has no IPv4 address."
        (returns STRING "A dotted quad, e.g. \"140.82.114.3\"")
        (sample "(Socket resolve \"localhost\")" "\"127.0.0.1\""))
      (def %pref-word (prim-ref (lit ptr) (lit ref-word)))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      ; struct addrinfo, 64-bit: ai_family i32@4 and ai_next*@40 agree
      ; across the OSes; Darwin and glibc SWAP the middle pointers --
      ; ai_addr rides @32 on Darwin (canonname @24) and @24 on Linux.
      (def addr-off (if os-darwin? 32 24))
      (def rescell-region (%make-str 8))
      (def rescell (%str->ptr rescell-region))
      (def r (%sk-fold (%sk-ptr-call (%sk "getaddrinfo") name 0 0 rescell)))
      (when (not (= r 0))
        (Err raise (lit io) (Str8 append "Socket resolve: getaddrinfo failed for " name) r))
      (def head (%pref-word rescell 0))
      (def quad
        (let walk ((node head))
          (match
            ((= node 0) ())
            (#t
              (let ((np (%sk-int->ptr node)))
                (match
                  ((= (& (%pref np 4 4) 65535) 2)          ; AF_INET
                    (let ((sa (%pref-word np addr-off)))
                      (if (= sa 0) (walk (%pref-word np 40))
                        (let ((sp (%sk-int->ptr sa)))
                          (Str8 append
                            (%number->str (& (%pref sp 4 1) 255)) "."
                            (%number->str (& (%pref sp 5 1) 255)) "."
                            (%number->str (& (%pref sp 6 1) 255)) "."
                            (%number->str (& (%pref sp 7 1) 255)))))))
                  (#t (walk (%pref-word np 40)))))))))
      (%sk-ptr-call (%sk "freeaddrinfo") (%sk-int->ptr head))
      (when (null? quad)
        (Err raise (lit value) (Str8 append "Socket resolve: no IPv4 address for " name) ()))
      quad)

    (method recv-bytes (self (param fd INT "Connected file descriptor")
                            (param maxlen INT "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a BYTE LIST -- the lossless door (recv's string return truncates at the first NUL; this one carries binary intact, #374); nil at orderly EOF; raises on failure."
        (returns ANY "Byte list (0-255 values), or nil at EOF"))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (def buf (%sk-int->ptr (%sk-ptr-call %c-malloc maxlen)))
      (def n (%sk-fold (%sk-ptr-call %c-recv fd buf maxlen 0)))
      (when (< n 0)
        (let ((en (Err errno-of n)))
          (%sk-ptr-call %c-free buf)
          (error (Err from-errno en 'recv fd))))
      (def out
        (let go ((i (- n 1)) (acc ()))
          (if (< i 0) acc
            (go (- i 1) (pair (& (%pref buf i 1) 255) acc)))))
      (%sk-ptr-call %c-free buf)
      (if (= n 0) () out))

    (method close (self (param fd INT "File descriptor to close"))
      (doc "Close a socket file descriptor."
        (returns ANY "nil"))
      (%sk-ptr-call %c-close fd)
      ())

    ; --- UDP (#364). SOCK_DGRAM = 2 on both OSes. Cold paths resolve
    ; sendto/recvfrom per call ((%sk ...)), keeping the module's %-globals
    ; budget flat.

    (method udp-bind (self (param port INT "Port to bind (INADDR_ANY)"))
      (doc "Create a UDP socket bound to port on all interfaces -- the receiving end. Read with (Socket recv-from fd n) for sender identity, or plain (Socket recv) when it does not matter."
        (returns INT "The bound datagram file descriptor")
        (sample "(Socket udp-bind 9999)" "a bound fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket %AF-INET 2 0)))
      (when (< fd 0) (%sk-fail fd 'socket port ()))
      (def addr (%make-sockaddr-in port ()))
      (def r (%sk-fold (%sk-ptr-call %c-bind fd addr 16)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'bind port addr)))
      (%sk-ptr-call %c-free addr)
      fd)

    (method udp-connect (self (param host STRING "Dotted-quad IPv4 address")
                              (param port INT "Destination port"))
      (doc "Create a CONNECTED UDP socket: the peer address is fixed once, and the plain (Socket send)/(Socket recv) pair then works datagram-wise -- the request/reply shape. For unconnected sends use (Socket send-to)."
        (returns INT "The connected datagram file descriptor")
        (sample "(Socket udp-connect \"127.0.0.1\" 9999)" "a connected fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket %AF-INET 2 0)))
      (when (< fd 0) (%sk-fail fd 'socket port ()))
      (def addr (%make-sockaddr-in port host))
      (def r (%sk-fold (%sk-ptr-call %c-connect fd addr 16)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'connect (list host port) addr)))
      (%sk-ptr-call %c-free addr)
      fd)

    (method send-to (self (param fd INT "Datagram file descriptor")
                          (param s STRING "Bytes to send (one datagram)")
                          (param host STRING "Dotted-quad IPv4 destination")
                          (param port INT "Destination port"))
      (doc "Send one datagram to host:port through an unconnected UDP socket."
        (returns INT "Bytes sent"))
      (def addr (%make-sockaddr-in port host))
      (def r (%sk-fold (%sk-ptr-call (%sk "sendto") fd s (Str8 length s) 0 addr 16)))
      (when (< r 0) (%sk-fail r 'sendto (list host port) addr))
      (%sk-ptr-call %c-free addr)
      r)

    (method recv-from (self (param fd INT "Bound datagram file descriptor")
                            (param maxlen INT "Maximum bytes to receive"))
      (doc "Block for one datagram; return it WITH the sender's identity. Like recv, the payload string truncates at the first NUL byte (ptr->str) -- fine for text protocols."
        (returns PAIR "(payload . (host . port))")
        (sample "(Socket recv-from fd 4096)" "(\"ping\" . (\"127.0.0.1\" . 51234))"))
      (def buf (%sk-int->ptr (%sk-ptr-call %c-malloc (+ maxlen 1))))
      (def addr (%sk-int->ptr (%sk-ptr-call %c-malloc 16)))
      (def alen (%sk-int->ptr (%sk-ptr-call %c-malloc 4)))
      (%sk-ptr-call %c-memset addr 0 16)
      (%sk-set1! alen 0 16)
      (%sk-set1! alen 1 0) (%sk-set1! alen 2 0) (%sk-set1! alen 3 0)
      (def %free-all (fn (_)
        (%sk-ptr-call %c-free buf)
        (%sk-ptr-call %c-free addr)
        (%sk-ptr-call %c-free alen)))
      (def n (%sk-fold (%sk-ptr-call (%sk "recvfrom") fd buf maxlen 0 addr alen)))
      (when (< n 0)
        (let ((en (Err errno-of n)))
          (%free-all)
          (error (Err from-errno en 'recvfrom fd))))
      (def %u8at (prim-ref (lit ptr) (lit ref)))
      (def %oct (fn (_ i) (& (%u8at addr i 1) 255)))
      (def sender
        (pair (Str8 append (%number->str (%oct 4)) "." (%number->str (%oct 5)) "."
                           (%number->str (%oct 6)) "." (%number->str (%oct 7)))
              (+ (* 256 (%oct 2)) (%oct 3))))
      (%sk-set1! buf n 0)
      (def payload (%sk-ptr->str buf))
      (%free-all)
      (pair payload sender))

    ; --- Unix-domain stream sockets (#364). AF_UNIX = 1 on both OSes;
    ; sockaddr_un = family header + NUL-terminated path (Darwin leads
    ; with a length byte, like sockaddr_in). accept/send/recv/close are
    ; the same methods TCP uses.

    (method %sockaddr-un (self (param path STRING "Filesystem socket path (under 100 bytes)"))
      (doc "Build a malloc'd sockaddr_un for path -- the caller frees. Raises kind-'value past 99 bytes (the struct's path field is 104)."
        (returns PTR "The packed address (110 bytes)"))
      (def plen (Str8 length path))
      (when (> plen 99)
        (Err raise 'value "Socket: unix path exceeds sockaddr_un capacity" path))
      (def addr (%sk-int->ptr (%sk-ptr-call %c-malloc 110)))
      (%sk-ptr-call %c-memset addr 0 110)
      (if os-darwin?
        (do (%sk-set1! addr 0 (+ plen 3)) (%sk-set1! addr 1 1))
        (do (%sk-set1! addr 0 1) (%sk-set1! addr 1 0)))
      (def %b (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (let go ((i 0))
        (unless (= i plen)
          (do (%sk-set1! addr (+ 2 i) (%c->i (%b path i)))
              (go (+ i 1)))))
      addr)

    (method unix-listen (self (param path STRING "Filesystem socket path to create")
                              . (param backlog INT "Listen backlog; default 16"))
      (doc "Create a unix-domain stream server socket at path: socket + bind + listen. The path must not already exist (bind refuses) -- unlink a stale one first; accept/send/recv/close are shared with TCP."
        (returns INT "The listening file descriptor")
        (sample "(Socket unix-listen \"/tmp/app.sock\")" "a listening fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket 1 %SOCK-STREAM 0)))
      (when (< fd 0) (%sk-fail fd 'socket path ()))
      (def addr (Socket %sockaddr-un path))
      (def r (%sk-fold (%sk-ptr-call %c-bind fd addr 110)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'bind path addr)))
      (%sk-ptr-call %c-free addr)
      (def lr (%sk-fold (%sk-ptr-call %c-listen fd (if (null? backlog) 16 (first backlog)))))
      (when (< lr 0) (do (%sk-ptr-call %c-close fd) (%sk-fail lr 'listen path ())))
      fd)

    (method unix-connect (self (param path STRING "Filesystem socket path to connect to"))
      (doc "Open a unix-domain stream connection to the socket at path."
        (returns INT "The connected file descriptor")
        (sample "(Socket unix-connect \"/tmp/app.sock\")" "a connected fd"))
      (def fd (%sk-fold (%sk-ptr-call %c-socket 1 %SOCK-STREAM 0)))
      (when (< fd 0) (%sk-fail fd 'socket path ()))
      (def addr (Socket %sockaddr-un path))
      (def r (%sk-fold (%sk-ptr-call %c-connect fd addr 110)))
      (when (< r 0) (do (%sk-ptr-call %c-close fd) (%sk-fail r 'connect path addr)))
      (%sk-ptr-call %c-free addr)
      fd)))

(doc (provide x/sys/socket Socket)
  (note "First consumer: x/logo/serve.x (whose Darwin-only constants this replaces). Recv truncates at the first NUL byte (ptr->str) -- fine for text protocols; recv-bytes is the lossless byte-list door (#374).")
  "Blocking IPv4 TCP on the Socket class, over libc FFI.")
