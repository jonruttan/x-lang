; net/x509.x -- X509: certificates (RFC 5280) and the chain a TLS server sends.
;
; A certificate is read once into what checking it needs: the bytes its
; issuer signed (tbsCertificate) and the signature over them, its issuer
; and subject names as their DER bytes (two names match when their bytes
; do), its validity as Unix seconds, its public key, and the extensions a
; chain's check reads -- basicConstraints, keyUsage and the subject's
; alternative DNS names.  An extension marked critical that is none of
; those, extKeyUsage or certificatePolicies makes the certificate unusable,
; as RFC 5280 4.2 says.
;
; verify-chain checks a server's chain: the leaf names the host and is in
; date; each certificate is signed by the next one up, an intermediate
; being a CA in date whose path length allows what is below it; and the
; walk ends at a certificate signed by a trusted root.  It ends at the
; FIRST such certificate, so a cross-signature the server sends past it
; is never read.  Signatures are ECDSA over P-256 and P-384 (x/codec/ecdsa)
; and RSA PKCS#1 v1.5 (x/codec/rsa); an RSASSA-PSS signature on a
; certificate is one this code does not check.
(module x/net/x509)

(import x/codec/bytes)
(import x/codec/base64)
(import x/codec/hmac)
(import x/codec/der)
(import x/codec/ecdsa)
(import x/codec/rsa)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shl (prim-ref (lit int) (lit <<)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %isub (prim-ref 'int '-))
(def %xor (fn (_ a b) (%isub (%or a b) (%and a b))))


(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "X509: " what) ())))

(def %tag (fn (_ e) (first e)))
(def %body (fn (_ e) (first (rest e))))
(def %whole (fn (_ e) (first (rest (rest e)))))

; OIDs
(def %oid-ec-public-key "1.2.840.10045.2.1")
(def %oid-rsa "1.2.840.113549.1.1.1")
(def %pem-begin "-----BEGIN CERTIFICATE-----")
(def %pem-end "-----END CERTIFICATE-----")

; A name's bytes as lowercase ASCII text in a fresh buffer: what a DNS name
; in a certificate is, and Str8 downcase's generic walk is tens of
; thousands of objects for twenty characters.
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset (prim-ref (lit ptr) (lit set!)))
(def %ascii-lower
  (fn (_ r)
    (def s (first r))
    (def start (first (rest r)))
    (def n (first (rest (rest r))))
    (def out (%make-str (+ n 1)))
    (def p (%str->ptr out))
    ((fn (self i)
       (unless (= i n)
         (do (def c (%char->int (%byte-ref s (+ start i))))
             (%pset p i (if (and (>= c 65) (<= c 90)) (+ c 32) c) 1)
             (self (+ i 1)))))
     0)
    (%pset p n 0 1)
    out))
(def %oid-p256 "1.2.840.10045.3.1.7")
(def %oid-p384 "1.3.132.0.34")
(def %sig-algs
  (list (list "1.2.840.10045.4.3.2" (lit ecdsa) (lit sha256))
        (list "1.2.840.10045.4.3.3" (lit ecdsa) (lit sha384))
        (list "1.2.840.10045.4.3.4" (lit ecdsa) (lit sha512))
        (list "1.2.840.113549.1.1.11" (lit rsa) (lit sha256))
        (list "1.2.840.113549.1.1.12" (lit rsa) (lit sha384))
        (list "1.2.840.113549.1.1.13" (lit rsa) (lit sha512))
        (list "1.2.840.113549.1.1.10" (lit rsa-pss) ())))
(def %ext-basic "2.5.29.19")
(def %ext-key-usage "2.5.29.15")
(def %ext-san "2.5.29.17")
(def %ext-understood (list %ext-basic %ext-key-usage %ext-san "2.5.29.37" "2.5.29.32"))

(def %lookup (fn (self k l) (if (null? l) () (if (str=? (first (first l)) k) (first l) (self k (rest l))))))
(def %member? (fn (self k l) (if (null? l) #f (if (str=? (first l) k) #t (self k (rest l))))))

; --- a certificate ----------------------------------------------------------
;
; (TBS SIG-ALG SIG ISSUER SUBJECT NOT-BEFORE NOT-AFTER CURVE KEY CA PATHLEN
;  CERT-SIGN DNS-NAMES), TBS ISSUER SUBJECT KEY and SIG regions.

(def %c (fn (_ c i) (List ref i c)))

(def %extensions
  (fn (_ items)
    ; [3] EXPLICIT, when present, is the last of the optional fields
    (def tail ((fn (self l) (if (null? l) () (if (= (%tag (first l)) 163) (first l) (self (rest l))))) items))
    (if (null? tail) ()
      (do (def seq (Der items (%body tail)))
          (unless (and (= (List length seq) 1) (= (%tag (first seq)) 48)) (%fail "extensions that are not a SEQUENCE"))
          (List map
            (fn (_ ext)
              (def parts (Der items (%body ext)))
              (def id (Der oid (%body (first parts))))
              (def critical (and (= (List length parts) 3) (= (%tag (first (rest parts))) 1)
                                 (not (= (Bytes ref (%body (first (rest parts))) 0) 0))))
              (def value (%body (List ref (- (List length parts) 1) parts)))
              (list id critical value))
            (Der items (%body (first seq))))))))

(def %parse
  (fn (_ der)
    (def top (Der items (%body (Der read der))))
    (unless (= (List length top) 3) (%fail "a certificate that is not three parts"))
    (def tbs (first top))
    (def sig-alg (Der oid (%body (first (Der items (%body (first (rest top))))))))
    (def sig (Der bits (%body (List ref 2 top))))
    (def fields (Der items (%body tbs)))
    ; version [0], when present, comes first
    (def f (if (= (%tag (first fields)) 160) (rest fields) fields))
    (def issuer (%whole (List ref 2 f)))
    (def validity (Der items (%body (List ref 3 f))))
    (def not-before (Der time (%tag (first validity)) (%body (first validity))))
    (def not-after (Der time (%tag (first (rest validity))) (%body (first (rest validity)))))
    (def subject (%whole (List ref 4 f)))
    (def spki (Der items (%body (List ref 5 f))))
    (def alg (Der items (%body (first spki))))
    (def key-oid (Der oid (%body (first alg))))
    ; the key's kind: its curve, rsa, or nil for one this code does not use
    (def kind
      (match ((and (str=? key-oid %oid-ec-public-key) (= (List length alg) 2) (= (%tag (first (rest alg))) 6))
              (do (def c (Der oid (%body (first (rest alg)))))
                  (match ((str=? c %oid-p256) (lit p256)) ((str=? c %oid-p384) (lit p384)) (#t ()))))
             ((str=? key-oid %oid-rsa) (lit rsa))
             (#t ())))
    (def bits (Der bits (%body (first (rest spki)))))
    ; an RSA key's bits hold SEQUENCE { INTEGER n, INTEGER e }
    (def key
      (if (eq? kind (lit rsa))
        (do (def ints (Der items (%body (Der read bits))))
            (unless (and (= (List length ints) 2) (= (%tag (first ints)) 2) (= (%tag (first (rest ints))) 2))
              (%fail "an RSA key that is not two INTEGERs"))
            (list (%body (first ints)) (%body (first (rest ints)))))
        bits))
    (def exts (%extensions f))
    ((fn (self l)
       (unless (null? l)
         (do (when (and (first (rest (first l))) (not (%member? (first (first l)) %ext-understood)))
               (%fail (Str8 append "an unrecognized critical extension, " (first (first l)))))
             (self (rest l)))))
     exts)
    (def basic (%lookup %ext-basic exts))
    (def basic-items (if (null? basic) () (Der items (%body (Der read (List ref 2 basic))))))
    (def ca (and (not (null? basic-items)) (= (%tag (first basic-items)) 1) (not (= (Bytes ref (%body (first basic-items)) 0) 0))))
    (def pathlen ((fn (self l) (if (null? l) () (if (= (%tag (first l)) 2) (Der small (%body (first l))) (self (rest l))))) basic-items))
    (def ku (%lookup %ext-key-usage exts))
    ; keyCertSign is bit 5: 0x04 in the first byte; no keyUsage means no limit
    (def cert-sign
      (if (null? ku) #t
        (do (def bs (%body (Der read (List ref 2 ku))))
            (and (>= (Bytes length bs) 2) (not (= (%and (Bytes ref bs 1) 4) 0))))))
    (def san (%lookup %ext-san exts))
    (def dns
      (if (null? san) ()
        (List map (fn (_ e) (%ascii-lower (%body e)))
                  (List filter (fn (_ e) (= (%tag e) 130)) (Der items (%body (Der read (List ref 2 san))))))))
    (list (%whole tbs) sig-alg sig issuer subject not-before not-after kind key ca pathlen cert-sign dns)))

(def %tbs (fn (_ c) (%c c 0)))
(def %sig-alg (fn (_ c) (%c c 1)))
(def %sig (fn (_ c) (%c c 2)))
(def %issuer (fn (_ c) (%c c 3)))
(def %subject (fn (_ c) (%c c 4)))
(def %not-before (fn (_ c) (%c c 5)))
(def %not-after (fn (_ c) (%c c 6)))
(def %kind (fn (_ c) (%c c 7)))
(def %key (fn (_ c) (%c c 8)))
(def %ca? (fn (_ c) (%c c 9)))
(def %pathlen (fn (_ c) (%c c 10)))
(def %cert-sign? (fn (_ c) (%c c 11)))
(def %dns (fn (_ c) (%c c 12)))

; Did parent sign child?  #f for a signature this code cannot check (RSA,
; or a key on another curve) as well as for a wrong one.
; Did parent's key sign child?  The signature algorithm's kind must be
; the key's: ECDSA under a curve's key, PKCS#1 v1.5 under an RSA key.
(def %signed-by?
  (fn (_ child parent)
    (def alg (%lookup (%sig-alg child) %sig-algs))
    (if (or (null? alg) (null? (%kind parent))) #f
      (do (def hash (first (rest (rest alg))))
          (def digest (fn (_) (list (Hmac digest hash (%tbs child)) 0 (Hmac size hash))))
          (match ((and (eq? (first (rest alg)) (lit ecdsa)) (not (eq? (%kind parent) (lit rsa))))
                  (Ecdsa verify-der (%kind parent) (%key parent) (digest) (%sig child)))
                 ((and (eq? (first (rest alg)) (lit rsa)) (eq? (%kind parent) (lit rsa)))
                  (Rsa verify-pkcs1 (first (%key parent)) (first (rest (%key parent))) hash (digest) (%sig child)))
                 (#t #f))))))

(def %in-date? (fn (_ c now) (and (>= now (%not-before c)) (<= now (%not-after c)))))

; host against a DNS name: equal, or "*.rest" matching one more label on
; the left (RFC 6125 6.4.3: the wildcard is the whole leftmost label).
(def %first-dot
  (fn (_ s)
    ((fn (self i) (if (= i (Str8 length s)) -1 (if (str=? (Str8 slice i (+ i 1) s) ".") i (self (+ i 1))))) 0)))

(def %wildcard-matches?
  (fn (_ host name)
    (def dot (%first-dot host))
    (if (> dot 0)
      (str=? (Str8 slice dot (Str8 length host) host) (Str8 slice 1 (Str8 length name) name))
      #f)))

(def %name-matches?
  (fn (_ host name)
    (if (str=? host name) #t
      (if (Str8 starts? "*." name) (%wildcard-matches? host name) #f))))

(def %find-issuer
  (fn (self cur pool)
    (if (null? pool) ()
      (if (and (Bytes same? (%subject (first pool)) (%issuer cur)) (%signed-by? cur (first pool)))
        (first pool)
        (self cur (rest pool))))))

; roots is a list of parsed roots, or a function from a name's DER bytes
; to the roots with that subject (x/net/roots' Roots find).
(def %walk
  (fn (_ leaf pool roots now)
    ((fn (self cur below)
       (when (> below 8) (%fail "a chain longer than eight certificates"))
       (def root (%find-issuer cur (if (procedure? roots) (roots (%issuer cur)) roots)))
       (if (not (null? root))
         (do (unless (%in-date? root now) (%fail "the trusted root is out of date")) #t)
         (do (def up (%find-issuer cur pool))
             (when (null? up)
               (%fail (if (null? (%lookup (%sig-alg cur) %sig-algs))
                        "a signature algorithm this code does not know"
                        "no path to a trusted root")))
             (unless (%ca? up) (%fail "an intermediate that is not a CA"))
             (unless (%cert-sign? up) (%fail "an intermediate whose key may not sign certificates"))
             (unless (%in-date? up now) (%fail "an intermediate out of date"))
             (unless (or (null? (%pathlen up)) (<= below (%pathlen up))) (%fail "an intermediate's path length is exceeded"))
             (self up (+ below 1)))))
     leaf 0)))

(def-class X509 ()
  (static
    (method parse (self (param der ANY "A certificate's DER bytes, a region"))
      (doc "Read a certificate. Raises a label 'value when it does not parse, or names a critical extension this code does not understand."
        (returns LIST "The certificate, for the other methods")
        (sample "(X509 parse der)" "a certificate"))
      (%parse (Bytes of der)))
    (method from-pem (self (param text ANY "PEM text: one or more BEGIN CERTIFICATE blocks, a region or a STRING up to its first NUL"))
      (doc "The certificates' DER bytes from PEM text, in order, each a region: each block's text between its BEGIN and END lines decoded, line breaks and all."
        (returns LIST "Regions")
        (sample "(X509 from-pem (File read-all \"/etc/ssl/cert.pem\"))" "the bundle's certificates"))
      (def r (Bytes of text))
      ((fn (self at out)
         (def left (Bytes sub r at (- (Bytes length r) at)))
         (def b (Bytes find left %pem-begin))
         (if (null? b) (List reverse out)
           (do (def body (+ b (Str8 length %pem-begin)))
               (def e (Bytes find (Bytes sub left body (- (Bytes length left) body)) %pem-end))
               (when (null? e) (%fail "a PEM block with no end"))
               (self (+ at body e (Str8 length %pem-end))
                     (pair (Base64 decode-region (Bytes sub left body e)) out)))))
       0 ()))
    (method subject (self (param cert LIST "A parsed certificate"))
      (doc "The subject's name, as its DER bytes."
        (returns LIST "A region"))
      (%subject cert))
    (method issuer (self (param cert LIST "A parsed certificate"))
      (doc "The issuer's name, as its DER bytes."
        (returns LIST "A region"))
      (%issuer cert))
    (method validity (self (param cert LIST "A parsed certificate"))
      (doc "(NOT-BEFORE NOT-AFTER), Unix seconds."
        (returns LIST "Two integers"))
      (list (%not-before cert) (%not-after cert)))
    (method dns-names (self (param cert LIST "A parsed certificate"))
      (doc "The subject's alternative DNS names, lowercase."
        (returns LIST "Strings"))
      (%dns cert))
    (method public-key (self (param cert LIST "A parsed certificate"))
      (doc "(KIND KEY): p256 or p384 and the key's bytes as SEC 1 encodes them; rsa and (N E), the modulus and exponent as the big-endian regions DER holds; or nil and the key's bytes for a kind this code does not use."
        (returns LIST "(SYMBOL region) or (rsa (region region))"))
      (list (%kind cert) (%key cert)))
    (method signed-by? (self (param child LIST "A parsed certificate")
                             (param parent LIST "The certificate that may have signed it"))
      (doc "#t when parent's key signed child: ECDSA over P-256 or P-384, or RSA PKCS#1 v1.5 with SHA-256, SHA-384 or SHA-512. An RSASSA-PSS signature answers #f: it is not checked."
        (returns BOOL "#t when the signature holds"))
      (%signed-by? child parent))
    (method verify-chain (self (param certs LIST "The server's certificates, leaf first, each a region of DER bytes or a certificate X509 parse already read")
                               (param host STRING "The name the client asked for")
                               (param now INTEGER "Unix seconds")
                               (param roots ANY "The trusted roots: a list of parsed certificates, or a function from a name's DER bytes to the roots with that subject, as (fn (_ name) (Roots find name))"))
      (doc "Check a server's chain: the leaf names host and is in date, each certificate is signed by one above it -- a CA in date whose path length allows it -- and the walk reaches a certificate a trusted root signed. #t when it holds; raises a label 'value naming the first thing that fails."
        (returns BOOL "#t")
        (sample "(X509 verify-chain (Tls13 certificates s) \"github.com\" (Sys now) roots)" "#t"))
      (when (null? certs) (%fail "no certificate"))
      ; a region's first element is its buffer; a parsed certificate's is
      ; the region of its signed part
      (def parsed (List map (fn (_ c) (if (str? (first c)) (%parse c) c)) certs))
      (def leaf (first parsed))
      (unless (%in-date? leaf now) (%fail "the server's certificate is out of date"))
      (def h (%ascii-lower (Bytes of host)))
      (unless ((fn (self l) (if (null? l) #f (if (%name-matches? h (first l)) #t (self (rest l))))) (%dns leaf))
        (%fail (Str8 append "the server's certificate does not name " host)))
      (%walk leaf (rest parsed) roots now))))

(doc (provide x/net/x509 X509)
  "X.509 certificates (RFC 5280): parse, from-pem, and verify-chain -- a TLS server's chain checked for its host, dates, CA constraints and signatures (ECDSA and RSA) up to a trusted root.")
