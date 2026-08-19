# Http: a plain-http/1.1 client over Socket (#374)

The ruled strategy, as amended by #412: pure x; https rides the Tls
class (libssl over the dlopen FFI) and names resolve through
(Socket resolve). These specs pin the protocol tier --
url splitting, request rendering, response parsing under both framings
-- through the %-private doors, which need no live socket. The wire
path (request/get/post over tcp-connect + recv-bytes) was proven live
at build time against python3 -m http.server (200 + body, 501 status)
and an nc-served chunked response; a single-threaded spec cannot hold
both ends of a blocking exchange, so the wire stays out of the suite.

## urls

### host/port/path split; defaults; strict refusals

```scheme
(do (import x/net/http)
  (list (Http %parse-url "http://127.0.0.1:8080/a/b?q=1")
        (Http %parse-url "http://10.0.0.5")
        (guard (e (Err kind-of e)) (Http %parse-url "https://x.test/"))
        (guard (e (Err kind-of e)) (Http %parse-url "ftp://x/"))))
```
---
    ((('host . "127.0.0.1") ('port . 8080) ('path . "/a/b?q=1") ('tls . #f)) (('host . "10.0.0.5") ('port . 80) ('path . "/") ('tls . #f)) (('host . "x.test") ('port . 443) ('path . "/") ('tls . #t)) 'value)

## requests

### verb, Host, Connection: close, Content-Length, user headers, CRLF framing

```scheme
(do (import x/net/http)
  (Http %build-request "POST" (Http %parse-url "http://h:9/p")
        (list (pair "X-A" "1")) "hi"))
```
---
    "POST /p HTTP/1.1\r\nHost: h\r\nConnection: close\r\nContent-Length: 2\r\nX-A: 1\r\n\r\nhi"

## responses

### content-length framing trims trailing bytes; headers lowercase

```scheme
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

```scheme
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (bytes->str (rest (Assoc find 'body
    (Http %parse-response (%s->b "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n"))))))
```
---
    "Wikipedia"

### garbage responses and bad chunk framing raise 'value

```scheme
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (list (guard (e (Err kind-of e)) (Http %parse-response (%s->b "garbage")))
        (guard (e (Err kind-of e)) (Http %dechunk (%s->b "zz\r\n")))))
```
---
    ('value 'value)


## the REST tier (#412)

### url-encode passes unreserved bytes, encodes the rest uppercase

```scheme
(do (import x/net/http)
  (list (Http url-encode "a b&c=d")
        (Http url-encode "A-z_0.~")))
```
---
    ("a%20b%26c%3Dd" "A-z_0.~")

### with-query: ? on a bare url, & after; both sides encoded

```scheme
(do (import x/net/http)
  (Http with-query (Http with-query "http://h/p" (list (pair "q" "a b")))
                   (list (pair "n" "2"))))
```
---
    "http://h/p?q=a%20b&n=2"

### quad detection routes names to resolve

```scheme
(do (import x/net/http)
  (list (Http %quad? "127.0.0.1") (Http %quad? "github.com") (Http %quad? "")))
```
---
    (#t #f #f)

### HEAD framing: content-length describes the body a GET would carry

```scheme
(do (import x/net/http)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def r (Http %parse-response (%s->b "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n") #t))
  (list (rest (Assoc find 'status r)) (rest (Assoc find 'body r))))
```
---
    (200 ())

### resolve turns localhost into the loopback quad (no network needed)

```scheme
(do (import x/sys/socket)
  (Socket resolve "localhost"))
```
---
    "127.0.0.1"


## redirect following (#412)

### the method rules: 303 -> GET; 301/302 flip only POST; 307/308 preserve

```scheme
(do (import x/net/http)
  (list (Http %redirect-method 303 "POST")
        (Http %redirect-method 302 "POST")
        (Http %redirect-method 302 "DELETE")
        (Http %redirect-method 307 "POST")))
```
---
    (("GET" . #f) ("GET" . #f) ("DELETE" . #t) ("POST" . #t))

### location resolution: absolute, path-absolute (port kept), relative

```scheme
(do (import x/net/http)
  (list (Http %resolve-location (Http %parse-url "https://h/x") "http://elsewhere/y")
        (Http %resolve-location (Http %parse-url "https://h:8443/a/b") "/c")
        (Http %resolve-location (Http %parse-url "http://h/a/b") "c/d")))
```
---
    ("http://elsewhere/y" "https://h:8443/c" "http://h/a/c/d")
