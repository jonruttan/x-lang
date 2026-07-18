; socket.x -- Socket constants
(import x/core/list)

; Misses return -1: these are OS-domain ids and -1 is the OS's own invalid
; marker (boundary vocabulary, like JSON's `null` symbol) -- NOT the library's
; nil-miss discipline. index-of itself misses with nil; %os-id converts.
(def %os-id (fn (_ i) (if (null? i) -1 i)))

; Socket call identifiers
; Usage: (socketcall-id 'socket) => 1
(def socketcall-id (fn (call)
  (%os-id (List index-of call (list
    'none 'socket 'bind 'connect
    'listen 'accept 'getsockname 'getpeername
    'socketpair 'send 'recv 'sendto
    'recvfrom 'shutdown 'setsockopt 'getsockopt
    'sendmsg 'recvmsg 'accept4)))))

; Protocol family identifiers
; Usage: (protocol-format-id 'inet) => 2
(def protocol-format-id (fn (pf)
  (%os-id (List index-of pf (list
    'unspec 'local 'inet 'ax25 'ipx
    'appletalk 'netrom 'bridge 'atmpvc 'x25
    'inet6 'rose 'decnet 'netbeui 'security
    'key 'netlink 'packet 'ash 'econet
    'atmsvc 'rds 'sna 'irda 'pppox
    'wanpipe 'llc () () 'can 'tipc
    'bluetooth 'iucv 'rxrpc 'isdn 'phonet
    'ieee802154 'caif 'alg 'max)))))

; Socket type identifiers
; Usage: (sock-id 'stream) => 1
(def sock-id (fn (sock)
  (%os-id (List index-of sock (list
    'none 'stream 'dgram 'raw 'rdm
    'seqpacket 'dccp () () () 'packet)))))

(doc (provide x/platform/socket socketcall-id protocol-format-id sock-id)
  "Socket constant lookup tables for Linux socketcall, protocol families, and socket types.")
