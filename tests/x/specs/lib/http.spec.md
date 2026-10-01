# Http: a plain-http/1.1 client over Socket (#374)
# @weight 2

The ruled strategy, as amended by #412: pure x; https rides the Tls
class (libssl over the dlopen FFI) and names resolve through
(Socket resolve). These specs pin the protocol layer --
url splitting, request rendering, response parsing under both framings
-- through the %-private doors, which need no live socket. The wire
section holds both ends of each exchange: a forked child serves http,
and `openssl s_server` serves https.

## urls

### host/port/path split; defaults; strict refusals

```x
(do (import x/net/http)
  (list (Http %parse-url "http://127.0.0.1:8080/a/b?q=1")
        (Http %parse-url "http://10.0.0.5")
        (guard (e (Err label e)) (Http %parse-url "https://x.test/"))
        (guard (e (Err label e)) (Http %parse-url "ftp://x/"))))
```
---
    ((('host . "127.0.0.1") ('port . 8080) ('path . "/a/b?q=1") ('tls . #f)) (('host . "10.0.0.5") ('port . 80) ('path . "/") ('tls . #f)) (('host . "x.test") ('port . 443) ('path . "/") ('tls . #t)) 'value)

## requests

### verb, Host, Connection: close, Content-Length, user headers, CRLF framing

```x
(do (import x/net/http)
  (Http %build-request "POST" (Http %parse-url "http://h:9/p")
        (list (pair "X-A" "1")) "hi"))
```
---
    "POST /p HTTP/1.1\r\nHost: h:9\r\nConnection: close\r\nContent-Length: 2\r\nX-A: 1\r\n\r\nhi"

### Host carries the port only when it is not the scheme's own

```x
(do (import x/net/http)
  (List map (fn (_ url) (Str8 sub 0 (Str8 index-of "\r\nConnection" (Http %build-request "GET" (Http %parse-url url) () ())) (Http %build-request "GET" (Http %parse-url url) () ())))
    (list "http://h:80/" "http://h/" "https://h/" "https://h:80/" "http://h:443/")))
```
---
    ("GET / HTTP/1.1\r\nHost: h" "GET / HTTP/1.1\r\nHost: h" "GET / HTTP/1.1\r\nHost: h" "GET / HTTP/1.1\r\nHost: h:80" "GET / HTTP/1.1\r\nHost: h:443")

## responses

### content-length framing trims trailing bytes; headers lowercase

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def r (Http %parse-response (%s->b "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhelloJUNK")))
  (list (rest (Assoc find 'status r))
        (bytes->str (rest (Assoc find 'body r)))
        (rest (Assoc find "content-type" (rest (Assoc find 'headers r))))))
```
---
    (200 "hello" "text/plain")

### chunked framing reassembles across chunks

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (bytes->str (rest (Assoc find 'body
    (Http %parse-response (%s->b "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n"))))))
```
---
    "Wikipedia"

### garbage responses and bad chunk framing raise 'value

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (list (guard (e (Err label e)) (Http %parse-response (%s->b "garbage")))
        (guard (e (Err label e)) (Http %dechunk (%s->b "zz\r\n")))))
```
---
    ('value 'value)


## the REST layer (#412)

### url-encode passes unreserved bytes, encodes the rest uppercase

```x
(do (import x/net/http)
  (list (Http url-encode "a b&c=d")
        (Http url-encode "A-z_0.~")))
```
---
    ("a%20b%26c%3Dd" "A-z_0.~")

### with-query: ? on a bare url, & after; both sides encoded

```x
(do (import x/net/http)
  (Http with-query (Http with-query "http://h/p" (list (pair "q" "a b")))
                   (list (pair "n" "2"))))
```
---
    "http://h/p?q=a%20b&n=2"

### quad detection routes names to resolve

```x
(do (import x/net/http)
  (list (Http %quad? "127.0.0.1") (Http %quad? "github.com") (Http %quad? "")))
```
---
    (#t #f #f)

### HEAD framing: content-length describes the body a GET would carry

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def r (Http %parse-response (%s->b "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n") #t))
  (list (rest (Assoc find 'status r)) (rest (Assoc find 'body r))))
```
---
    (200 ())

### resolve turns localhost into the loopback quad (no network needed)

```x
(do (import x/sys/socket)
  (Socket resolve "localhost"))
```
---
    "127.0.0.1"


## redirect following (#412)

### the method rules: 303 -> GET; 301/302 flip only POST; 307/308 preserve

```x
(do (import x/net/http)
  (list (Http %redirect-method 303 "POST")
        (Http %redirect-method 302 "POST")
        (Http %redirect-method 302 "DELETE")
        (Http %redirect-method 307 "POST")))
```
---
    (("GET" . #f) ("GET" . #f) ("DELETE" . #t) ("POST" . #t))

### location resolution: absolute, path-absolute (port kept), relative

```x
(do (import x/net/http)
  (list (Http %resolve-location (Http %parse-url "https://h/x") "http://elsewhere/y")
        (Http %resolve-location (Http %parse-url "https://h:8443/a/b") "/c")
        (Http %resolve-location (Http %parse-url "http://h/a/b") "c/d")))
```
---
    ("http://elsewhere/y" "https://h:8443/c" "http://h/a/c/d")


## auth headers (#412)

### basic (the RFC 7617 vector), bearer (RFC 6750); the cross-host strip covers both

```x
(do (import x/net/http)
  (list (Http basic-auth "Aladdin" "open sesame")
        (Http bearer-auth "abc123")
        (Http %sans-auth (list (pair "authorization" "Basic x")
                               (pair "Authorization" "Bearer y")
                               (pair "X-Keep" "1")))))
```
---
    (("Authorization" . "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==") ("Authorization" . "Bearer abc123") (("X-Keep" . "1")))


## streams: the body a piece at a time

A stream over byte-list pieces is the wire's shape with no socket: each
transport read answers the next piece, so a piece boundary can fall
anywhere -- in a size line, between CR and LF, inside a chunk.

### a byte per read: head, chunk sizes, extensions and trailers all split

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def s (Http %over (List map (fn (_ c) (list c))
                       (%s->b "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-A: 1\r\n\r\n4\r\nWiki\r\n5;ext\r\npedia\r\n0\r\nX-T: t\r\n\r\n"))
                     #f))
  (def got (let go ((acc ())) (let ((b (Http read s 3))) (if (null? b) (List reverse acc) (go (pair b acc))))))
  (list (s status) (s head) (bytes->str (List flat-map (fn (_ c) c) got)) (Http read s 3)))
```
---
    (200 ("HTTP/1.1 200 OK" "Transfer-Encoding: chunked" "X-A: 1") "Wikipedia" ())

### a read hands out at most n bytes, and never crosses a chunk

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def s (Http %over (list (%s->b "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n")) #f))
  (let go ((acc ())) (let ((b (Http read s 3))) (if (null? b) (List reverse acc) (go (pair (List length b) acc))))))
```
---
    (3 1 3 2)

### Content-Length counts down; a peer that closes early ends the body there

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def %all (fn (_ s) (let go ((acc ())) (let ((b (Http read s 2))) (if (null? b) (bytes->str (List flat-map (fn (_ c) c) (List reverse acc))) (go (pair b acc)))))))
  (list (%all (Http %over (list (%s->b "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhe") (%s->b "lloJUNK")) #f))
        (%all (Http %over (list (%s->b "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc")) #f))
        (%all (Http %over (list (%s->b "HTTP/1.0 200 OK\r\n\r\nto ") (%s->b "the end")) #f))))
```
---
    ("hello" "abc" "to the end")

### a chunk cut short, and a chunk with no CRLF after it, raise 'value

```x
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (list (guard (e (Err label e)) (Http %dechunk (%s->b "9\r\nshort")))
        (guard (e (Err label e)) (Http %dechunk (%s->b "2\r\nabXY\r\n0\r\n\r\n")))
        (bytes->str (Http %dechunk (%s->b "2\r\nab\r\n0\r\n")))))
```
---
    ('value 'value "ab")


## the wire

A forked child serves canned responses on an ephemeral port while the
spec reads them through Http; the child never returns to the runner --
it execs a shell that exits, whatever happened.

### a body read 4096 bytes at a time arrives in pieces, every byte counted

```x
(do (import x/net/http) (import x/sys/posix)
  (def %hw-lfd (Socket tcp-listen 0))
  (def %hw-port (Socket local-port %hw-lfd))
  (def %hw-body (Str8 repeat 1638 "0123456789"))
  (def %hw-pid (Sys fork))
  (when (= %hw-pid 0)
    (do (guard (e ())
          (let ((c (Socket accept %hw-lfd)))
            (do (Socket recv c 65536)
                (Socket send c (Str8 append "HTTP/1.1 200 OK\r\nContent-Length: "
                                 (%number->str (Str8 length %hw-body)) "\r\n\r\n" %hw-body))
                (Socket close c))))
        (Sys exec "/bin/sh" (list "-c" "exit 0"))))
  (Socket close %hw-lfd)
  ; the child is stopped whatever the exchange does
  (def %hw-result
    (guard (e e)
      (let ((s (Http open "GET" (Str8 append "http://127.0.0.1:" (%number->str %hw-port) "/f") () ())))
        (let ((got (let go ((total 0) (reads 0))
                     (let ((b (Http read s 4096)))
                       (if (null? b) (list total reads) (go (+ total (List length b)) (+ reads 1)))))))
          (do (Http close s)
              (list (s status) (first got) (> (first (rest got)) 1)))))))
  (Sys kill %hw-pid 9)
  (Sys wait %hw-pid)
  %hw-result)
```
---
    (200 16380 #t)

### open follows a redirect, request drains the final body, (redirects . 0) stops at the 3xx

```x
(do (import x/net/http) (import x/sys/posix)
  (def %hr-lfd (Socket tcp-listen 0))
  (def %hr-port (Socket local-port %hr-lfd))
  (def %hr-replies (list "HTTP/1.1 302 Found\r\nLocation: /b\r\nContent-Length: 0\r\n\r\n"
                         "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nb\r\n0\r\n\r\n"
                         "HTTP/1.1 302 Found\r\nLocation: /b\r\nContent-Length: 0\r\n\r\n"))
  (def %hr-pid (Sys fork))
  (when (= %hr-pid 0)
    (do (guard (e ())
          (List for-each
            (fn (_ reply)
              (let ((c (Socket accept %hr-lfd)))
                (do (Socket recv c 65536) (Socket send c reply) (Socket close c))))
            %hr-replies))
        (Sys exec "/bin/sh" (list "-c" "exit 0"))))
  (Socket close %hr-lfd)
  (def url (Str8 append "http://127.0.0.1:" (%number->str %hr-port) "/a"))
  ; the child is stopped whatever the exchanges do
  (def %hr-result
    (guard (e e)
      (let ((r (Http request "GET" url () ())))
        (let ((s (Http open "GET" url () () (list (pair 'redirects 0)))))
          (do (Http close s)
              (list (rest (Assoc find 'status r)) (bytes->str (rest (Assoc find 'body r)))
                    (s status) (rest (Assoc find "location" (s headers)))))))))
  (Sys kill %hr-pid 9)
  (Sys wait %hr-pid)
  %hr-result)
```
---
    (200 "b" 302 "/b")

### https: (insecure) reads from a self-signed server; verification refuses it

`openssl s_server` with a certificate made for the run; the session
the handshake makes is the TlsSession record, built by keyword.

```x
(do (import x/net/http) (import x/sys/posix) (import x/sys/proc)
  (def %ht-dir (Str8 append "/tmp/x-lang-http-tls-" (%number->str (Sys getpid))))
  (def %ht-probe (Socket tcp-listen 0))
  (def %ht-port (Socket local-port %ht-probe))
  (Socket close %ht-probe)
  (Proc run! (list "/bin/sh" "-c"
    (Str8 append "mkdir -p " %ht-dir " && cd " %ht-dir
      " && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1"
      " && { openssl s_server -quiet -www -accept " (%number->str %ht-port)
      " -cert cert.pem -key key.pem >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))
  (def url (Str8 append "https://127.0.0.1:" (%number->str %ht-port) "/"))
  ; the server is stopped whatever the exchange does
  (def %ht-result
    (guard (e e)
      (let ((s (Http open "GET" url () () (list (list 'insecure)))))
        (let ((body (bytes->str (Http %drain s))))
          (do (Http close s)
              (list (s status) (Str8 includes? "s_server" body)
                    (guard (e (Err label e)) (Http open "GET" url () ()))))))))
  (Proc run! (list "/bin/sh" "-c" (Str8 append "kill $(cat " %ht-dir "/pid); rm -rf " %ht-dir)))
  %ht-result)
```
---
    (200 #t 'io)
