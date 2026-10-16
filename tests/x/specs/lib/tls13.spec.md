# Tls13
# @weight 15
# @timeout-scale 4

The TLS 1.3 client written in x, against `openssl s_server` on a
certificate made for the run: the handshake, application data both ways,
and the server's close.  The server's certificate is self-signed RSA, so
the exchanges ask for ('insecure), and one without it is refused: its
CertificateVerify, RSA-PSS (scheme 2052), holds, and then the
certificate, made with a common name alone, names no host.  connect
builds every engine it uses before it dials (ready!), so the file
carries the weight and the timeout of engine builds.

## connecting

### a GET over TLS 1.3, the reply read to the server's close

`s_server -www` answers a GET with a page about the session, which names
the protocol and the cipher suite it agreed; a second connection without
('insecure) is refused by the certificate check.

```x
(do (import x/net/tls13) (import x/sys/socket) (import x/sys/posix) (import x/sys/proc)
  (def %t13-dir (Str8 append "/tmp/x-lang-tls13-" (%number->str (Sys getpid))))
  (def %t13-probe (Socket tcp-listen 0))
  (def %t13-port (Socket local-port %t13-probe))
  (Socket close %t13-probe)
  (Proc run! (list "/bin/sh" "-c"
    (Str8 append "mkdir -p " %t13-dir " && cd " %t13-dir
      " && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1"
      " && { openssl s_server -quiet -www -tls1_3 -accept " (%number->str %t13-port)
      " -cert cert.pem -key key.pem >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))
  (def %t13-read
    (fn (self s acc)
      (let ((r (Tls13 recv-run s 4096)))
        (if (null? r) acc (self s (Str8 append acc (Str8 slice 0 (rest r) (first r))))))))
  (def %t13-result
    (guard (e (list 'raised (Err label e) (e msg)))
      (let ((s (Tls13 connect "127.0.0.1" %t13-port (list (pair 'host "localhost") (list 'insecure)))))
        (do (Tls13 send s "GET / HTTP/1.0\r\n\r\n")
            (def page (%t13-read s ""))
            (Tls13 close s)
            (list (Str8 starts? "HTTP/1.0 200" page)
                  (Str8 includes? "TLSv1.3" page)
                  (Str8 includes? "CHACHA20" page)
                  (List length (Tls13 certificates s))
                  (guard (e (list (Err label e) (e msg)))
                    (Tls13 connect "127.0.0.1" %t13-port (list (pair 'host "localhost")))))))))
  (Proc run! (list "/bin/sh" "-c" (Str8 append "kill $(cat " %t13-dir "/pid) 2>/dev/null; rm -rf " %t13-dir)))
  (write %t13-result))
```
---
    (#t #t #t 1 ('io "Tls13: X509: the server's certificate does not name localhost"))

### over: the same session on descriptors the caller opened

`over` runs the handshake on a pair of descriptors already open: here the
socket a TCP connect made, read and written both, then a pair of pipes to
`nc`, which carries the bytes to the server -- a program between, as
busybox's `ssl_client -e` has it.  Each gets the page, and close leaves the
caller's descriptors open.

```x
(do (import x/net/tls13) (import x/sys/socket) (import x/sys/posix) (import x/sys/proc)
  (def %t13o-dir (Str8 append "/tmp/x-lang-tls13o-" (%number->str (Sys getpid))))
  (def %t13o-probe (Socket tcp-listen 0))
  (def %t13o-port (Socket local-port %t13o-probe))
  (Socket close %t13o-probe)
  (Proc run! (list "/bin/sh" "-c"
    (Str8 append "mkdir -p " %t13o-dir " && cd " %t13o-dir
      " && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1"
      " && { openssl s_server -quiet -www -tls1_3 -accept " (%number->str %t13o-port)
      " -cert cert.pem -key key.pem >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))
  (def %t13o-read
    (fn (self s acc)
      (let ((r (Tls13 recv-run s 4096)))
        (if (null? r) acc (self s (Str8 append acc (Str8 slice 0 (rest r) (first r))))))))
  (def %t13o-page
    (fn (_ in out)
      (let ((s (Tls13 over in out (list (pair 'host "localhost") (list 'insecure)))))
        (do (Tls13 send s "GET / HTTP/1.0\r\n\r\n")
            (def page (%t13o-read s ""))
            (Tls13 close s)
            (list (Str8 starts? "HTTP/1.0 200" page) (Str8 includes? "TLSv1.3" page))))))
  (def %t13o-socket
    (guard (e (list 'raised (Err label e) (e msg)))
      (let ((fd (Socket tcp-connect "127.0.0.1" %t13o-port)))
        (let ((r (%t13o-page fd fd)))
          ; still open: close answers 0
          (list r (Sys close fd))))))
  (def %t13o-pipes
    (guard (e (list 'raised (Err label e) (e msg)))
      (let ((to (Sys pipe)) (from (Sys pipe)))
        (let ((pid (Sys fork)))
          (when (= pid 0)
            (do (Sys close (rest to)) (Sys close (first from))
                (Sys dup2 (first to) 0) (Sys dup2 (rest from) 1)
                (Sys exec "/usr/bin/nc" (list "127.0.0.1" (%number->str %t13o-port)))
                (Sys exit 127)))
          (Sys close (first to))
          (Sys close (rest from))
          (let ((r (%t13o-page (first from) (rest to))))
            (do (Sys close (rest to)) (Sys close (first from)) (Sys wait pid) r))))))
  (Proc run! (list "/bin/sh" "-c" (Str8 append "kill $(cat " %t13o-dir "/pid) 2>/dev/null; rm -rf " %t13o-dir)))
  (write (list %t13o-socket %t13o-pipes)))
```
---
    (((#t #t) 0) (#t #t))

### a reply of many records, NULs and all, every byte in order

`s_server -WWW` serves a file of 100000 bytes, every value 0-255 in
turn, so it crosses six full 16384-byte records and a part, and its digest is
checked; the reader collects between records, as a caller of Tls13 does.

```x
(do (import x/net/tls13) (import x/sys/socket) (import x/sys/posix) (import x/sys/proc) (import x/codec/bytes) (import x/codec/sha256)
  (def %t13b-dir (Str8 append "/tmp/x-lang-tls13b-" (%number->str (Sys getpid))))
  (def %t13b-probe (Socket tcp-listen 0))
  (def %t13b-port (Socket local-port %t13b-probe))
  (Socket close %t13b-probe)
  (Proc run! (list "/bin/sh" "-c"
    (Str8 append "mkdir -p " %t13b-dir " && cd " %t13b-dir
      " && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1"
      " && LC_ALL=C awk 'BEGIN { for (i = 0; i < 100000; i++) printf \"%c\", i % 256 }' > big"
      " && { openssl s_server -quiet -WWW -tls1_3 -accept " (%number->str %t13b-port)
      " -cert cert.pem -key key.pem >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))
  (def %t13b-result
    (guard (e (list 'raised (Err label e) (e msg)))
      (let ((s (Tls13 connect "127.0.0.1" %t13b-port (list (pair 'host "localhost") (list 'insecure)))))
        (do (Tls13 send s "GET /big HTTP/1.0\r\n\r\n")
            (def w (Bytes writer))
            ((fn (self)
               (let ((r (Tls13 recv-run s 16384)))
                 (unless (null? r)
                   (do (Bytes put w (list (first r) 0 (rest r))) (Heap collect) (self))))))
            (Tls13 close s)
            (def all (Bytes written w))
            ; the body follows the head's blank line
            (def body-at ((fn (self i) (if (and (= (Bytes ref all i) 13) (= (Bytes ref all (+ i 1)) 10)
                                                (= (Bytes ref all (+ i 2)) 13) (= (Bytes ref all (+ i 3)) 10))
                                          (+ i 4) (self (+ i 1)))) 0))
            (def body (Bytes copy (Bytes sub all body-at (- (Bytes length all) body-at))))
            ; the file's digest, as shasum -a 256 gives it
            (list (Bytes length body) (Sha256 hex-n (first body) (Bytes length body)))))))
  (Proc run! (list "/bin/sh" "-c" (Str8 append "kill $(cat " %t13b-dir "/pid) 2>/dev/null; rm -rf " %t13b-dir)))
  (write %t13b-result))
```
---
    (100000 "db8f1d69251d95e2c88268d3c540533cc5182e0e33065a6f3f322f606a574489")

## the engines

### ready! builds every engine a connect uses, and is idempotent

```x
(do (import x/net/tls13)
  (write (list (Tls13 ready!) (Tls13 ready!))))
```
---
    (#t #t)
