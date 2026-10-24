; net/tls.x -- Tls: TLS client sessions, as Http's https:// urls ride them.
;
;   (Tls connect quad port [opts]) -> session; opts: (host . NAME) for the
;                                     name sent and checked, (list 'insecure)
;                                     to skip the check -- never the default
;   (Tls send session s)           -> bytes written
;   (Tls recv-run session n)       -> (STRING . COUNT); nil at orderly close
;   (Tls recv-bytes session n)     -> byte list; nil at orderly close
;   (Tls close session)            -> nil
;
; The protocol is x/net/tls13's, written in x: TLS 1.3 with X25519 and
; ChaCha20-Poly1305, the server authenticated by its CertificateVerify and
; its chain to one of Mozilla's roots for NAME.  No C library is opened.
; Every failure is a label 'io naming it -- what Http and its callers read
; as a connection that went wrong.  A host is a DOTTED QUAD here (the
; Socket contract); resolve names first ((Socket resolve)).
(module x/net/tls)
(import x/net/tls13)

(def-class Tls ()
  (doc "TLS client sessions written in x (x/net/tls13): connect/send/recv-run/recv-bytes/close, the server's certificate checked against Mozilla's roots by default."
    (sample "(let ((s (Tls connect \"140.82.114.3\" 443 (list (pair 'host \"github.com\"))))) (Tls send s req) (Tls recv-run s 65536))" "response bytes")
    (see connect) (see recv-run))
  (static
    (method connect (self (param quad STRING "Dotted-quad IPv4 address (resolve names via (Socket resolve))")
                          (param port INTEGER "Port, usually 443")
                          . (param opts ALIST "Options: (host . NAME) for SNI and the certificate check against NAME; ('insecure) to skip the check"))
      (doc "Open an authenticated TLS session (TLS 1.3): TCP connect, the handshake, and the server's certificate and CertificateVerify checked for NAME against Mozilla's roots. A failure raises a label 'io naming it."
        (returns OBJECT "The session")
        (sample "(Tls connect \"140.82.114.3\" 443 (list (pair 'host \"github.com\")))" "a verified session"))
      (Tls13 connect quad port (if (null? opts) () (first opts))))
    (method send (self (param session OBJECT "A (Tls connect) session")
                       (param s ANY "The bytes: a region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "Send all the bytes through the session; raises a label 'io on failure."
        (returns INTEGER "Bytes written"))
      (Tls13 send session s))
    (method recv-bytes (self (param session OBJECT "A (Tls connect) session")
                             (param maxlen INTEGER "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a byte list (the lossless carrier); nil at an orderly close; raises a label 'io on failure."
        (returns ANY "Byte list, or nil at orderly close"))
      (Tls13 recv-bytes session maxlen))
    (method recv-run (self (param session OBJECT "A (Tls connect) session")
                           (param maxlen INTEGER "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a RUN: (STRING . COUNT), NUL bytes included. nil at an orderly close; raises a label 'io on failure."
        (returns ANY "(STRING . COUNT), or nil at orderly close"))
      (Tls13 recv-run session maxlen))
    (method close (self (param session OBJECT "A (Tls connect) session"))
      (doc "Send close_notify and close the connection."
        (returns ANY "nil"))
      (Tls13 close session))))

(doc (provide x/net/tls Tls)
  (note "TLS 1.3 written in x (x/net/tls13): the server authenticated against Mozilla's roots by default; ('insecure) is the explicit development override. Hosts are quads: (Socket resolve) turns names into them; Http wires the two together for https:// urls.")
  "TLS client sessions, homed on the Tls class.")
