; net/tls.x -- Tls: TLS client sessions over Socket fds, via libssl FFI (#412).
;
; The https amendment to #374's ruling: OpenSSL/LibreSSL's client core is
; plain (non-variadic) functions throughout, so it binds over the dlopen
; FFI like libm/libz -- no new C. The variadic blocker was libcurl's.
;
;   (Tls connect host port [opts]) -> session; opts: (list 'insecure)
;                                     skips verification (self-signed dev
;                                     endpoints -- never the default)
;   (Tls send session s)           -> bytes written
;   (Tls recv-bytes session n)     -> byte list; nil at orderly close
;   (Tls close session)            -> nil (frees SSL, ctx, and the fd)
;
; Verification is ON by default: the build's default CA paths PLUS the
; system bundle at /etc/ssl/cert.pem (the union is harmless where either
; is absent), SNI set, hostname checked (SSL_set1_host). A failed
; handshake raises kind-'io carrying the X509 verify-result code when
; verification is what failed (10 = expired, 18 = self-signed, ...).
;
; Library resolution order: libssl.so.3 (Linux), the Homebrew OpenSSL 3
; paths (arm/intel -- also what CI's macOS runners carry), then the
; VERSIONED system LibreSSL (/usr/lib/libssl.48.dylib -- the unversioned
; name is dlopen-ABORTED by the OS, learned the hard way). A host is a
; DOTTED QUAD here (the Socket contract); resolve names first
; ((Socket resolve), the getaddrinfo door).
;
; Sessions are (ssl ctx fd) triples. Cold paths: symbols resolve per
; call; zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/core/list)
(import x/sys/socket)

(def-class Tls ()
  (doc "TLS client sessions over Socket fds via the system libssl (dlopen FFI): connect/send/recv-bytes/close, certificate verification and hostname checking on by default."
    (sample "(let ((s (Tls connect \"140.82.114.3\" 443 (list (pair 'host \"github.com\"))))) (Tls send s req) (Tls recv-bytes s 65536))" "response bytes")
    (see connect) (see recv-bytes))
  (static
    ; Resolve one libssl (or libcrypto) symbol, per call.
    (method %sym (self (param name STRING "Function name"))
      (doc "The named symbol from the first loadable TLS library: libssl.so.3, Homebrew OpenSSL 3 (arm/intel), or the versioned system LibreSSL. Raises kind-'io when none loads."
        (returns PTR "The function pointer"))
      (def %dlopen (prim-ref (lit ffi) (lit dlopen)))
      (def %dlsym (prim-ref (lit ffi) (lit dlsym)))
      (def lib
        (let try ((paths (list "libssl.so.3"
                               "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib"
                               "/usr/local/opt/openssl@3/lib/libssl.3.dylib"
                               "/usr/lib/libssl.48.dylib"
                               "/usr/lib/libssl.46.dylib")))
          (match
            ((null? paths) (Err raise (lit io) "Tls: no usable libssl found" ()))
            (#t (let ((h (%dlopen (first paths) 1)))
                  (if h h (try (rest paths))))))))
      (%dlsym lib name))

    ; Fold a 32-bit int return (the %sys-fold rule, locally).
    (method %fold (self (param raw INT "Raw FFI return"))
      (doc "Fold a zero-extended 32-bit int return back to signed."
        (returns INT "The signed value"))
      (if (> raw 2147483647) (- raw 4294967296) raw))

    (method connect (self (param quad STRING "Dotted-quad IPv4 address (resolve names via (Socket resolve))")
                          (param port INT "Port, usually 443")
                          . (param opts ALIST "Options: (host . NAME) for SNI + hostname verification against NAME (recommended when connecting by resolved quad); ('insecure) to skip verification entirely"))
      (doc "Open a verified TLS session: TCP connect, then handshake with SNI, the system trust stores, and hostname checking. A failed handshake raises kind-'io -- carrying the X509 verify code when verification failed (10 expired, 18 self-signed, 62 hostname mismatch)."
        (returns LIST "The session (ssl ctx fd)")
        (sample "(Tls connect \"140.82.114.3\" 443 (list (pair 'host \"github.com\")))" "a verified session"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def o (if (null? opts) () (first opts)))
      (def sni (let ((e (Assoc entry (lit host) o))) (if (null? e) () (rest e))))
      (def insecure? (not (null? (Assoc entry (lit insecure) o))))
      (def ctx (%call (Tls %sym "SSL_CTX_new") (%call (Tls %sym "TLS_client_method"))))
      (when (= ctx 0) (Err raise (lit io) "Tls: SSL_CTX_new failed" ()))
      (unless insecure?
        (do (%call (Tls %sym "SSL_CTX_set_verify") ctx 1 0)   ; SSL_VERIFY_PEER
            (%call (Tls %sym "SSL_CTX_set_default_verify_paths") ctx)
            ; the system bundle too -- the union is harmless where absent
            (%call (Tls %sym "SSL_CTX_load_verify_locations") ctx "/etc/ssl/cert.pem" 0)))
      (def fd (Socket tcp-connect quad port))
      (def ssl (%call (Tls %sym "SSL_new") ctx))
      (when (= ssl 0)
        (let ()
          (Socket close fd)
          (%call (Tls %sym "SSL_CTX_free") ctx)
          (Err raise (lit io) "Tls: SSL_new failed" ())))
      (%call (Tls %sym "SSL_set_fd") ssl fd)
      (unless (null? sni)
        ; SNI: SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME=55, name_type=0, name)
        (do (%call (Tls %sym "SSL_ctrl") ssl 55 0 sni)
            (unless insecure?
              (%call (Tls %sym "SSL_set1_host") ssl sni))))
      (def cr (Tls %fold (%call (Tls %sym "SSL_connect") ssl)))
      (when (not (= cr 1))
        (let ((vres (%call (Tls %sym "SSL_get_verify_result") ssl)))
          (%call (Tls %sym "SSL_free") ssl)
          (%call (Tls %sym "SSL_CTX_free") ctx)
          (Socket close fd)
          (if (= vres 0)
            (Err raise (lit io) "Tls: handshake failed" cr)
            (Err raise (lit io) "Tls: certificate verification failed (X509 code in the payload)" vres))))
      (list ssl ctx fd))

    (method send (self (param session LIST "A (Tls connect) session")
                       (param s STRING "Bytes to send"))
      (doc "Send the whole string through the session; raises kind-'io on failure."
        (returns INT "Bytes written"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def r (Tls %fold (%call (Tls %sym "SSL_write") (first session) s (Str8 length s))))
      (when (<= r 0) (Err raise (lit io) "Tls: write failed" r))
      r)

    (method recv-bytes (self (param session LIST "A (Tls connect) session")
                             (param maxlen INT "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a byte list (the lossless carrier); nil at an orderly TLS close; raises kind-'io on transport failure."
        (returns ANY "Byte list, or nil at orderly close"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (def region (%make-str maxlen))
      (def buf (%str->ptr region))
      (def n (Tls %fold (%call (Tls %sym "SSL_read") (first session) buf maxlen)))
      (match
        ((> n 0)
          (let go ((i (- n 1)) (acc ()))
            (if (< i 0) acc
              (go (- i 1) (pair (& (%pref buf i 1) 255) acc)))))
        (#t
          ; 0/ZERO_RETURN(6) = orderly close; SYSCALL(5) with a clean EOF
          ; is how peers that skip close_notify look -- treat as EOF too
          (let ((code (%call (Tls %sym "SSL_get_error") (first session) n)))
            (match
              ((= code 6) ())
              ((= code 5) ())
              (#t (Err raise (lit io) "Tls: read failed (SSL_get_error in the payload)" code)))))))

    (method close (self (param session LIST "A (Tls connect) session"))
      (doc "Shut the session down and free everything: SSL_shutdown, SSL_free, SSL_CTX_free, and the fd."
        (returns ANY "nil"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (%call (Tls %sym "SSL_shutdown") (first session))
      (%call (Tls %sym "SSL_free") (first session))
      (%call (Tls %sym "SSL_CTX_free") (first (rest session)))
      (Socket close (first (rest (rest session))))
      ())))

(doc (provide x/net/tls Tls)
  (note "libssl over the dlopen FFI (plain functions only -- the variadic blocker was libcurl's). Verification + SNI + hostname checks ON by default; ('insecure) is the explicit dev override. Hosts are quads: (Socket resolve) turns names into them; Http wires the two together for https:// urls.")
  "TLS client sessions over Socket fds, homed on the Tls class.")
