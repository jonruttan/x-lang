# Http: a plain-http/1.1 client over Socket (#374)

The ruled strategy: pure x, plain http only (https is the curl door;
no DNS -- the Socket contract). These specs pin the protocol tier --
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
    ((('host . "127.0.0.1") ('port . 8080) ('path . "/a/b?q=1")) (('host . "10.0.0.5") ('port . 80) ('path . "/")) 'value 'value)

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
