; socket.x -- Socket constants
(import x/core/list)

; Misses return -1: these are OS-domain ids and -1 is the OS's own invalid
; marker (boundary vocabulary, like JSON's `null` symbol) -- NOT the library's
; nil-miss discipline. index-of itself misses with nil; %os-id converts.
(def %os-id (fn (_ i) (if (null? i) (- 0 1) i)))

; Socket call identifiers
; Usage: (socketcall-id (lit socket)) => 1
(def socketcall-id (fn (call)
  (%os-id (List index-of call (list
    (lit none) (lit socket) (lit bind) (lit connect)
    (lit listen) (lit accept) (lit getsockname) (lit getpeername)
    (lit socketpair) (lit send) (lit recv) (lit sendto)
    (lit recvfrom) (lit shutdown) (lit setsockopt) (lit getsockopt)
    (lit sendmsg) (lit recvmsg) (lit accept4))))))

; Protocol family identifiers
; Usage: (protocol-format-id (lit inet)) => 2
(def protocol-format-id (fn (pf)
  (%os-id (List index-of pf (list
    (lit unspec) (lit local) (lit inet) (lit ax25) (lit ipx)
    (lit appletalk) (lit netrom) (lit bridge) (lit atmpvc) (lit x25)
    (lit inet6) (lit rose) (lit decnet) (lit netbeui) (lit security)
    (lit key) (lit netlink) (lit packet) (lit ash) (lit econet)
    (lit atmsvc) (lit rds) (lit sna) (lit irda) (lit pppox)
    (lit wanpipe) (lit llc) () () (lit can) (lit tipc)
    (lit bluetooth) (lit iucv) (lit rxrpc) (lit isdn) (lit phonet)
    (lit ieee802154) (lit caif) (lit alg) (lit max))))))

; Socket type identifiers
; Usage: (sock-id (lit stream)) => 1
(def sock-id (fn (sock)
  (%os-id (List index-of sock (list
    (lit none) (lit stream) (lit dgram) (lit raw) (lit rdm)
    (lit seqpacket) (lit dccp) () () () (lit packet))))))

(doc (provide x/platform/socket socketcall-id protocol-format-id sock-id)
  "Socket constant lookup tables for Linux socketcall, protocol families, and socket types.")
