; net/tls13.x -- Tls13: a TLS 1.3 client written in x (RFC 8446).
;
; The handshake and the record layer, over Socket: a ClientHello offering
; TLS 1.3 alone, TLS_CHACHA20_POLY1305_SHA256 and an X25519 key share; the
; ServerHello's share; the key schedule (x/net/tls-keys); the server's
; encrypted flight -- EncryptedExtensions, Certificate, CertificateVerify,
; Finished -- with its Finished checked; then the client's Finished and
; application data both ways.  The interface is x/net/tls's: connect,
; send, recv-run, recv-bytes, close, so Http can take either.
;
; THE SERVER IS NOT YET AUTHENTICATED.  Checking the certificate chain and
; the CertificateVerify signature needs ECDSA, RSA and X.509, which are
; still to be written, so connect refuses unless asked for ('insecure); the
; certificates and the signature are kept on the session for that check.
;
; Bytes are regions (BUF START LEN), as x/codec/bytes has them.  The
; session is a vector of slots, written as the handshake and the records
; move it on.
(module x/net/tls13)

(import x/type/vector)
(import x/sys/socket)
(import x/codec/bytes)
(import x/codec/hmac)
(import x/codec/x25519)
(import x/codec/chacha20-poly1305)
(import x/codec/sha256)
(import x/codec/chacha20)
(import x/codec/poly1305)
(import x/net/tls-keys)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))

(def %hash (lit sha256))
(def %key-len 32)
(def %max-plaintext 16384)

; Content types (5.1) and handshake types (4).
(def %ct-ccs 20)
(def %ct-alert 21)
(def %ct-handshake 22)
(def %ct-data 23)
(def %hs-client-hello 1)
(def %hs-server-hello 2)
(def %hs-new-session-ticket 4)
(def %hs-encrypted-extensions 8)
(def %hs-certificate 11)
(def %hs-certificate-request 13)
(def %hs-certificate-verify 15)
(def %hs-finished 20)
(def %hs-key-update 24)

; A ServerHello whose random is this is a HelloRetryRequest (4.1.3).
(def %hrr-random "cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")

; --- the session's slots --------------------------------------------------

(def %fd 1)
(def %in-buf 2)
(def %in-pos 3)
(def %in-end 4)
(def %read-key 5)
(def %read-iv 6)
(def %read-seq 7)
(def %write-key 8)
(def %write-iv 9)
(def %write-seq 10)
(def %hs-pending 11)
(def %app-pending 12)
(def %read-secret 13)
(def %write-secret 14)
(def %closed 15)
(def %certs 16)
(def %verify 17)
(def %host 18)
(def %slots 18)

(def %get (fn (_ s i) (%oref s i)))
(def %set! (fn (_ s i v) (%oset! s i v)))

(def %fail (fn (_ what payload) (Err raise (lit io) (Str8 append "Tls13: " what) payload)))

; --- reading the wire -----------------------------------------------------

; More bytes from the socket after what is unread; #f at the peer's close.
(def %recv-more!
  (fn (_ s)
    (def run (Socket recv-run (%get s %fd) 65536))
    (if (null? run) #f
      (do (def left (list (%get s %in-buf) (%get s %in-pos) (%sub (%get s %in-end) (%get s %in-pos))))
          (def joined (Bytes join left (list (first run) 0 (rest run))))
          (%set! s %in-buf (first joined))
          (%set! s %in-pos 0)
          (%set! s %in-end (Bytes length joined))
          #t))))

; At least n unread bytes, or #f when the peer closed first.
(def %have!
  (fn (self s n)
    (if (>= (%sub (%get s %in-end) (%get s %in-pos)) n) #t
      (if (%recv-more! s) (self s n) #f))))

; The next record as (TYPE HEADER BODY), header and body regions of the
; input; nil when the peer closed between records.
(def %read-record
  (fn (_ s)
    (if (not (%have! s 5)) ()
      (do (def pos (%get s %in-pos))
          (def rd (Bytes reader (list (%get s %in-buf) pos 5)))
          (def type (Bytes get-u8 rd))
          (Bytes get-u16 rd)
          (def len (Bytes get-u16 rd))
          (when (> len (%add %max-plaintext 256)) (%fail "a record longer than the protocol allows" len))
          (unless (%have! s (%add 5 len)) (%fail "the connection closed inside a record" len))
          ; the buffer may have moved
          (def at (%get s %in-pos))
          (def buf (%get s %in-buf))
          (%set! s %in-pos (%add at (%add 5 len)))
          (list type (Bytes copy (list buf at 5)) (Bytes copy (list buf (%add at 5) len)))))))

; The per-record nonce (5.3): the IV with the sequence number, big-endian,
; XORed into its last eight bytes.
(def %nonce
  (fn (_ iv seq)
    (Bytes of-list
      ((fn (self i acc)
         (if (< i 0) acc
           (self (%sub i 1)
                 (pair (^ (Bytes ref iv i) (if (< i 4) 0 (& (>> seq (<< (%sub 11 i) 3)) 255))) acc))))
       11 ()))))

; A protected record opened: (TYPE CONTENT), the inner type and content
; once the zero padding is stripped (5.4).  A plaintext record is itself.
(def %open
  (fn (_ s rec)
    (def type (first rec))
    (if (or (null? (%get s %read-key)) (not (= type %ct-data)))
      (list type (first (rest (rest rec))))
      (do (def seq (%get s %read-seq))
          (def inner (guard (e (%fail "a record did not authenticate" seq))
                       (ChaCha20Poly1305 open (%get s %read-key) (%nonce (%get s %read-iv) seq)
                                          (first (rest rec)) (first (rest (rest rec))))))
          (%set! s %read-seq (%add seq 1))
          (def end ((fn (self i) (if (< i 0) -1 (if (= (Bytes ref inner i) 0) (self (%sub i 1)) i)))
                    (%sub (Bytes length inner) 1)))
          (when (< end 0) (%fail "a record with no content type" ()))
          (list (Bytes ref inner end) (Bytes sub inner 0 end))))))

; --- writing the wire -----------------------------------------------------

(def %send-region
  (fn (_ s r)
    (def flat (Bytes copy r))
    (Socket send-run (%get s %fd) (first flat) (Bytes length flat))))

(def %plain-record
  (fn (_ type legacy body)
    (def w (Bytes writer))
    (Bytes put-u8 w type)
    (Bytes put-u16 w legacy)
    (Bytes put-u16 w (Bytes length body))
    (Bytes put w body)
    (Bytes written w)))

; content sealed as one record of the given inner type (5.2).
(def %send-sealed
  (fn (_ s type content)
    (def inner (Bytes join content (Bytes of-list (list type))))
    (def hw (Bytes writer))
    (Bytes put-u8 hw %ct-data)
    (Bytes put-u16 hw 771)
    (Bytes put-u16 hw (%add (Bytes length inner) 16))
    (def aad (Bytes written hw))
    (def seq (%get s %write-seq))
    (def sealed (ChaCha20Poly1305 seal (%get s %write-key) (%nonce (%get s %write-iv) seq) aad inner))
    (%set! s %write-seq (%add seq 1))
    (%send-region s (Bytes join aad sealed))))

; --- handshake messages ---------------------------------------------------

; The next handshake message as (TYPE BODY WHOLE): whole is the message
; with its four-byte header, what the transcript takes.
(def %next-handshake
  (fn (self s)
    (def pending (%get s %hs-pending))
    (if (>= (Bytes length pending) 4)
      (do (def rd (Bytes reader pending))
          (def type (Bytes get-u8 rd))
          (def len (Bytes get-u24 rd))
          (if (>= (Bytes length pending) (%add 4 len))
            (do (%set! s %hs-pending (Bytes copy (Bytes sub pending (%add 4 len) (%sub (Bytes length pending) (%add 4 len)))))
                (list type (Bytes copy (Bytes sub pending 4 len)) (Bytes copy (Bytes sub pending 0 (%add 4 len)))))
            (do (%pull-handshake! s) (self s))))
      (do (%pull-handshake! s) (self s)))))

; Another record's worth of handshake bytes onto what is pending.
(def %pull-handshake!
  (fn (self s)
    (def rec (%read-record s))
    (when (null? rec) (%fail "the connection closed during the handshake" ()))
    (def opened (%open s rec))
    (def type (first opened))
    (match
      ((= type %ct-ccs) (self s))
      ((= type %ct-alert) (%alert! s (first (rest opened))))
      ((= type %ct-handshake)
        (%set! s %hs-pending (Bytes join (%get s %hs-pending) (first (rest opened)))))
      (#t (%fail "an unexpected record during the handshake" type)))))

(def %alert!
  (fn (_ s body)
    (def desc (if (>= (Bytes length body) 2) (Bytes ref body 1) -1))
    (if (= desc 0)
      (do (%set! s %closed #t) ())
      (%fail (Str8 append "the server sent alert " (Str8 str desc)) desc))))

(def %handshake-message
  (fn (_ type body)
    (def w (Bytes writer))
    (Bytes put-u8 w type)
    (Bytes put-u24 w (Bytes length body))
    (Bytes put w body)
    (Bytes written w)))

; An extension: its type, then its data with a u16 length.
(def %put-extension
  (fn (_ w type data)
    (Bytes put-u16 w type)
    (Bytes put-u16 w (Bytes length data))
    (Bytes put w data)))

(def %extension-data
  (fn (_ fill)
    (def w (Bytes writer))
    (fill w)
    (Bytes written w)))

(def %client-hello
  (fn (_ host public)
    (def w (Bytes writer))
    (Bytes put-u16 w 771)
    (Bytes put w (Bytes random 32))
    ; a legacy session id, which middleboxes expect (D.4)
    (Bytes put-u8 w 32)
    (Bytes put w (Bytes random 32))
    (Bytes put-u16 w 2)
    (Bytes put-u16 w 4867)
    (Bytes put-u8 w 1)
    (Bytes put-u8 w 0)
    (def ext (Bytes writer))
    (unless (null? host)
      (%put-extension ext 0
        (%extension-data (fn (_ e)
          (Bytes put-u16 e (%add (Str8 length host) 3))
          (Bytes put-u8 e 0)
          (Bytes put-u16 e (Str8 length host))
          (Bytes put e host)))))
    ; supported_groups: x25519
    (%put-extension ext 10 (%extension-data (fn (_ e) (Bytes put-u16 e 2) (Bytes put-u16 e 29))))
    ; signature_algorithms: ECDSA P-256 and P-384, RSA-PSS, RSA PKCS#1
    (%put-extension ext 13
      (%extension-data (fn (_ e)
        (def algs (list 1027 1283 2052 2053 2054 1025 1281 1537))
        (Bytes put-u16 e (* 2 (List length algs)))
        ((fn (self l) (unless (null? l) (do (Bytes put-u16 e (first l)) (self (rest l))))) algs))))
    ; supported_versions: TLS 1.3
    (%put-extension ext 43 (%extension-data (fn (_ e) (Bytes put-u8 e 2) (Bytes put-u16 e 772))))
    ; key_share: one X25519 share
    (%put-extension ext 51
      (%extension-data (fn (_ e)
        (Bytes put-u16 e 36)
        (Bytes put-u16 e 29)
        (Bytes put-u16 e 32)
        (Bytes put e public))))
    (Bytes put-u16 w (Bytes size ext))
    (Bytes put w (Bytes written ext))
    (%handshake-message %hs-client-hello (Bytes written w))))

; The ServerHello's X25519 share, once it is checked to be TLS 1.3 with
; the suite and group offered.
(def %server-share
  (fn (_ body)
    (def rd (Bytes reader body))
    (Bytes get-u16 rd)
    (when (Bytes same? (Bytes get rd 32) (Bytes of-hex %hrr-random))
      (%fail "the server asked to retry the hello (HelloRetryRequest), which this client does not do" ()))
    (Bytes get rd (Bytes get-u8 rd))
    (def suite (Bytes get-u16 rd))
    (unless (= suite 4867) (%fail "the server chose a cipher suite not offered" suite))
    (Bytes get-u8 rd)
    (def ext (Bytes reader (Bytes get rd (Bytes get-u16 rd))))
    ((fn (self version share)
       (if (= (Bytes left ext) 0)
         (do (unless (= version 772) (%fail "the server did not choose TLS 1.3" version))
             (when (null? share) (%fail "the server sent no key share" ()))
             share)
         (do (def type (Bytes get-u16 ext))
             (def data (Bytes reader (Bytes get ext (Bytes get-u16 ext))))
             (match
               ((= type 43) (self (Bytes get-u16 data) share))
               ((= type 51)
                 (do (def group (Bytes get-u16 data))
                     (unless (= group 29) (%fail "the server chose a group not offered" group))
                     (def key (Bytes get data (Bytes get-u16 data)))
                     (unless (= (Bytes length key) 32) (%fail "an X25519 share of the wrong length" (Bytes length key)))
                     (self version (Bytes copy key))))
               (#t (self version share))))))
     0 ())))

; The Certificate message's certificates, leaf first (4.4.2).
(def %certificates
  (fn (_ body)
    (def rd (Bytes reader body))
    (Bytes get rd (Bytes get-u8 rd))
    (def list-rd (Bytes reader (Bytes get rd (Bytes get-u24 rd))))
    ((fn (self acc)
       (if (= (Bytes left list-rd) 0) (List reverse acc)
         (do (def cert (Bytes copy (Bytes get list-rd (Bytes get-u24 list-rd))))
             (Bytes get list-rd (Bytes get-u16 list-rd))
             (self (pair cert acc)))))
     ())))

(def %set-keys!
  (fn (_ s key-slot iv-slot seq-slot secret)
    (def kv (TlsKeys traffic-keys %hash secret %key-len))
    (%set! s key-slot (Bytes copy (first kv)))
    (%set! s iv-slot (Bytes copy (first (rest kv))))
    (%set! s seq-slot 0)))

(def %transcript-hash (fn (_ tw) (TlsKeys transcript-hash %hash (Bytes written tw))))

; The handshake, from the TCP connection to application keys both ways.
(def %handshake!
  (fn (_ s priv public)
    (def hello (%client-hello (%get s %host) public))
    (%send-region s (%plain-record %ct-handshake 769 hello))
    (def tw (Bytes writer))
    (Bytes put tw hello)
    (def sh (%next-handshake s))
    (unless (= (first sh) %hs-server-hello) (%fail "the server did not answer with a ServerHello" (first sh)))
    (def share (%server-share (first (rest sh))))
    (Bytes put tw (first (rest (rest sh))))
    (def shared (list (X25519 scalarmult (first priv) (first share)) 0 32))
    (when (Bytes same? shared (Bytes of-list (List repeat 32 0)))
      (%fail "the X25519 shared secret is zero" ()))
    (def hs (TlsKeys handshake-secret %hash shared))
    (def hello-hash (%transcript-hash tw))
    (def c-hs (TlsKeys derive-secret %hash hs "c hs traffic" hello-hash))
    (def s-hs (TlsKeys derive-secret %hash hs "s hs traffic" hello-hash))
    (%set-keys! s %read-key %read-iv %read-seq s-hs)
    ; the server's encrypted flight, through its Finished
    ((fn (self)
       (def m (%next-handshake s))
       (def type (first m))
       (match
         ((= type %hs-finished)
           (do (def want (TlsKeys finished %hash s-hs (%transcript-hash tw)))
               (unless (Bytes same? want (first (rest m)))
                 (%fail "the server's Finished does not match the handshake" ()))
               (Bytes put tw (first (rest (rest m))))))
         ((= type %hs-encrypted-extensions) (do (Bytes put tw (first (rest (rest m)))) (self)))
         ((= type %hs-certificate)
           (do (%set! s %certs (%certificates (first (rest m))))
               (Bytes put tw (first (rest (rest m))))
               (self)))
         ((= type %hs-certificate-verify)
           (do (def rd (Bytes reader (first (rest m))))
               (def alg (Bytes get-u16 rd))
               (def sig (Bytes copy (Bytes get rd (Bytes get-u16 rd))))
               ; what the signature covers: the transcript before it (4.4.3)
               (%set! s %verify (list alg sig (Bytes copy (%transcript-hash tw))))
               (Bytes put tw (first (rest (rest m))))
               (self)))
         ((= type %hs-certificate-request)
           (%fail "the server asked for a client certificate, which this client does not send" ()))
         (#t (%fail "an unexpected handshake message" type)))))
    (def to-server-finished (%transcript-hash tw))
    (def master (TlsKeys master-secret %hash hs))
    (def c-ap (TlsKeys derive-secret %hash master "c ap traffic" to-server-finished))
    (def s-ap (TlsKeys derive-secret %hash master "s ap traffic" to-server-finished))
    ; a ChangeCipherSpec for middleboxes (D.4), then the client's Finished
    (%send-region s (%plain-record %ct-ccs 771 (Bytes of-list (list 1))))
    (%set-keys! s %write-key %write-iv %write-seq c-hs)
    (%send-sealed s %ct-handshake
      (%handshake-message %hs-finished (TlsKeys finished %hash c-hs to-server-finished)))
    (%set! s %read-secret s-ap)
    (%set! s %write-secret c-ap)
    (%set-keys! s %read-key %read-iv %read-seq s-ap)
    (%set-keys! s %write-key %write-iv %write-seq c-ap)))

; A post-handshake message (4.6): session tickets are not kept; a
; KeyUpdate moves the read keys on, and answers in kind when asked.
(def %post-handshake!
  (fn (self s)
    (unless (< (Bytes length (%get s %hs-pending)) 4)
      (do (def rd (Bytes reader (%get s %hs-pending)))
          (def type (Bytes get-u8 rd))
          (def len (Bytes get-u24 rd))
          (when (>= (Bytes left rd) len)
            (do (def body (Bytes get rd len))
                (%set! s %hs-pending (Bytes copy (Bytes rest rd)))
                (when (= type %hs-key-update)
                  (do (def next (TlsKeys next-traffic-secret %hash (%get s %read-secret)))
                      (%set! s %read-secret next)
                      (%set-keys! s %read-key %read-iv %read-seq next)
                      (when (= (Bytes ref body 0) 1)
                        (do (%send-sealed s %ct-handshake (%handshake-message %hs-key-update (Bytes of-list (list 0))))
                            (def wnext (TlsKeys next-traffic-secret %hash (%get s %write-secret)))
                            (%set! s %write-secret wnext)
                            (%set-keys! s %write-key %write-iv %write-seq wnext)))))
                (self s)))))))

; The next application data as a region; nil at the peer's close.
(def %next-data
  (fn (self s)
    (if (%get s %closed) ()
      (do (def rec (%read-record s))
          (if (null? rec) (do (%set! s %closed #t) ())
            (do (def opened (%open s rec))
                (def type (first opened))
                (match
                  ((= type %ct-data) (first (rest opened)))
                  ((= type %ct-handshake)
                    (do (%set! s %hs-pending (Bytes join (%get s %hs-pending) (first (rest opened))))
                        (%post-handshake! s)
                        (self s)))
                  ((= type %ct-alert) (%alert! s (first (rest opened))))
                  (#t (self s)))))))))

(def-class Tls13 ()
  (static
    (method connect (self (param quad STRING "Dotted-quad IPv4 address (resolve names via (Socket resolve))")
                          (param port INTEGER "Port, usually 443")
                          . (param opts ALIST "Options: (host . NAME) for the server name sent (SNI); ('insecure), REQUIRED until certificates are checked"))
      (doc "Open a TLS 1.3 session: TCP connect, then the handshake (X25519, ChaCha20-Poly1305), the server's Finished checked. The server's certificate is NOT yet checked, so ('insecure) must be given; without it connect raises a label 'value and connects to nothing. A failed handshake raises a label 'io naming what failed."
        (returns OBJECT "The session")
        (sample "(Tls13 connect \"127.0.0.1\" 4433 (list (pair 'host \"localhost\") (list 'insecure)))" "a session"))
      (def o (if (null? opts) () (first opts)))
      (def host (let ((e (Assoc entry (lit host) o))) (if (null? e) () (rest e))))
      (when (null? (Assoc entry (lit insecure) o))
        (Err raise (lit value) "Tls13: the server's certificate cannot be checked yet; pass ('insecure) to connect without checking it" ()))
      ; Everything slow happens before the server is dialled: pure x, an
      ; X25519 multiplication is about five seconds and a server gives up
      ; on a handshake that takes ten.  The compiled engines are built and
      ; proven once a process (about five seconds together, measured
      ; 2026-10-09 on arm64), and the key pair is made with them; after that
      ; the handshake's work is milliseconds.  An engine that cannot be
      ; built leaves its codec pure x, correct and slow.
      (X25519 jit!)
      (Sha256 jit!)
      (ChaCha20 jit!)
      (Poly1305 jit!)
      (def priv (Bytes random 32))
      (def public (list (X25519 base (first priv)) 0 32))
      (def s (Vector make %slots ()))
      (%set! s %fd (Socket tcp-connect quad port))
      (%set! s %in-buf (first (Bytes of-list ())))
      (%set! s %in-pos 0)
      (%set! s %in-end 0)
      (%set! s %hs-pending (Bytes of-list ()))
      (%set! s %app-pending (Bytes of-list ()))
      (%set! s %closed #f)
      (%set! s %host host)
      (guard (e (do (Socket close (%get s %fd)) (Err raise (Err label e) (e msg) ())))
        (%handshake! s priv public))
      s)
    (method send (self (param session OBJECT "A (Tls13 connect) session")
                       (param data ANY "The bytes: a region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "Send the bytes as application data, in records of at most 16384 bytes each."
        (returns INTEGER "Bytes sent"))
      (def r (Bytes of data))
      ((fn (self at)
         (unless (>= at (Bytes length r))
           (do (def n (if (> (%sub (Bytes length r) at) %max-plaintext) %max-plaintext (%sub (Bytes length r) at)))
               (%send-sealed session %ct-data (Bytes sub r at n))
               (self (%add at n)))))
       0)
      (Bytes length r))
    (method recv-run (self (param session OBJECT "A (Tls13 connect) session")
                           (param maxlen INTEGER "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes of application data as a RUN: (STRING . COUNT), NUL bytes included. nil at the server's close; raises a label 'io on a record that does not authenticate or an alert."
        (returns ANY "(STRING . COUNT), or nil at close"))
      (def pending (%get session %app-pending))
      (def r (if (> (Bytes length pending) 0) pending (%next-data session)))
      (if (null? r) ()
        (do (def n (if (> (Bytes length r) maxlen) maxlen (Bytes length r)))
            (%set! session %app-pending (Bytes sub r n (%sub (Bytes length r) n)))
            (def out (Bytes copy (Bytes sub r 0 n)))
            (if (= n 0) (Tls13 recv-run session maxlen) (pair (first out) n)))))
    (method recv-bytes (self (param session OBJECT "A (Tls13 connect) session")
                             (param maxlen INTEGER "Maximum bytes to receive"))
      (doc "Receive up to maxlen bytes as a byte list; nil at the server's close."
        (returns ANY "Byte list, or nil at close"))
      (def run (Tls13 recv-run session maxlen))
      (if (null? run) ()
        ((fn (self i acc) (if (< i 0) acc (self (%sub i 1) (pair (Bytes ref (list (first run) 0 (rest run)) i) acc))))
         (%sub (rest run) 1) ())))
    (method close (self (param session OBJECT "A (Tls13 connect) session"))
      (doc "Send close_notify, unless the server closed first, and close the socket."
        (returns ANY "nil"))
      (unless (%get session %closed)
        (guard (e ()) (%send-sealed session %ct-alert (Bytes of-list (list 1 0)))))
      (%set! session %closed #t)
      (Socket close (%get session %fd))
      ())
    (method certificates (self (param session OBJECT "A (Tls13 connect) session"))
      (doc "The server's certificates as it sent them, leaf first, each a region of DER bytes -- what a chain check reads."
        (returns LIST "Regions"))
      (%get session %certs))
    (method signature (self (param session OBJECT "A (Tls13 connect) session"))
      (doc "The server's CertificateVerify: (ALGORITHM SIGNATURE TRANSCRIPT-HASH), what it signed over being the context string and that hash (RFC 8446 4.4.3)."
        (returns LIST "(INTEGER region region)"))
      (%get session %verify))))

(doc (provide x/net/tls13 Tls13)
  (note "TLS 1.3 written in x: X25519, ChaCha20-Poly1305, SHA-256. The server's certificate is not yet checked; ('insecure) is required until it is.")
  "A TLS 1.3 client in x (RFC 8446): connect, send, recv-run, recv-bytes, close, as x/net/tls has them.")
