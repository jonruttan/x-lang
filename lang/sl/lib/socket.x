; # Computational Expressions in C
;
; ## socket.x -- Socket Constants
;
; @description Provides socket operation constants for the SL personality.
;   Maps socket call names, protocol families, and socket types
;   to their numeric identifiers using index-of lookup.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do

  ; =========================================================
  ; Socket call identifiers
  ; =========================================================
  ; Maps socket operation names to their socketcall numbers.
  ; Usage: (socketcall-id (lit socket)) => 1
  (def socketcall-id (fn (call)
    (index-of call (list
      (lit none)
      (lit socket)
      (lit bind)
      (lit connect)
      (lit listen)
      (lit accept)
      (lit getsockname)
      (lit getpeername)
      (lit socketpair)
      (lit send)
      (lit recv)
      (lit sendto)
      (lit recvfrom)
      (lit shutdown)
      (lit setsockopt)
      (lit getsockopt)
      (lit sendmsg)
      (lit recvmsg)
      (lit accept4)
    ))))

  ; =========================================================
  ; Protocol family identifiers
  ; =========================================================
  ; Maps protocol family names to their numeric identifiers.
  ; Usage: (protocol-format-id (lit inet)) => 2
  (def protocol-format-id (fn (pf)
    (index-of pf (list
      (lit unspec)
      (lit local)
      (lit inet)
      (lit ax25)
      (lit ipx)
      (lit appletalk)
      (lit netrom)
      (lit bridge)
      (lit atmpvc)
      (lit x25)
      (lit inet6)
      (lit rose)
      (lit decnet)
      (lit netbeui)
      (lit security)
      (lit key)
      (lit netlink)
      (lit packet)
      (lit ash)
      (lit econet)
      (lit atmsvc)
      (lit rds)
      (lit sna)
      (lit irda)
      (lit pppox)
      (lit wanpipe)
      (lit llc)
      ()
      ()
      (lit can)
      (lit tipc)
      (lit bluetooth)
      (lit iucv)
      (lit rxrpc)
      (lit isdn)
      (lit phonet)
      (lit ieee802154)
      (lit caif)
      (lit alg)
      (lit max)
    ))))

  ; =========================================================
  ; Socket type identifiers
  ; =========================================================
  ; Maps socket type names to their numeric identifiers.
  ; Usage: (sock-id (lit stream)) => 1
  (def sock-id (fn (sock)
    (index-of sock (list
      (lit none)
      (lit stream)
      (lit dgram)
      (lit raw)
      (lit rdm)
      (lit seqpacket)
      (lit dccp)
      ()
      ()
      ()
      (lit packet)
    ))))

  (lit socket)
)
