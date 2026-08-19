# Socket: blocking IPv4 TCP over libc FFI (#29)

Deterministic, non-blocking coverage only: listen/bind/connect failure
paths and address validation. The full accept/recv/send loop cannot run
single-threaded under the batch harness (accept blocks; fork tears the
shared stdin script) -- it is exercised live by x/logo/serve.x, the
class's first consumer, and was verified end-to-end against nc.

## address validation

### a non-quad host raises kind-'value before any syscall

```scheme
(do (import x/sys/socket)
  (guard (e (Err kind-of e)) (Socket tcp-connect "not.an.ip" 1)))
```
---
    'value

### octets out of range raise too

```scheme
(do (import x/sys/socket)
  (guard (e (Err kind-of e)) (Socket tcp-connect "127.0.0.999" 1)))
```
---
    'value

## listen and structured failure

### tcp-listen answers a real fd; rebinding the port is a structured eaddrinuse

```scheme
(do (import x/sys/socket)
  (def lfd (Socket tcp-listen 47913))
  (def second (guard (e (list (Err kind-of e) (Assoc get 'sym (e data)))) (Socket tcp-listen 47913)))
  (Socket close lfd)
  (list (> lfd 2) second))
```
---
    (#t ('io 'eaddrinuse))

### the port frees on close

```scheme
(do (import x/sys/socket)
  (def a (Socket tcp-listen 47914))
  (Socket close a)
  (def b (Socket tcp-listen 47914))
  (Socket close b)
  (> b 2))
```
---
    #t

### connecting where nothing listens is a structured econnrefused

"Nothing listens" is made true by construction -- bind the port, close
it, then connect: a bare fixed port turned out to be LISTENED ON by
something on the ubuntu CI runner (connect returned an fd; the pin got
"5").

```scheme
(do (import x/sys/socket)
  (def l (Socket tcp-listen 49877))
  (Socket close l)
  (guard (e (list (Err kind-of e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
    (Socket tcp-connect "127.0.0.1" 49877)))
```
---
    ('io 'econnrefused 'connect)

## UDP and unix-domain loopback (#364)

These ARE deterministic under the batch harness, unlike the TCP accept
loop the preamble rules out: a datagram queues before recv-from runs,
and a unix/TCP connect completes against the listen backlog before
accept is called -- no step blocks.

### connected-UDP request, recv-from identifies the sender, send-to replies

```scheme
(do (import x/sys/socket)
  (def sfd (Socket udp-bind 49364))
  (def cfd (Socket udp-connect "127.0.0.1" 49364))
  (Socket send cfd "ping")
  (def got (Socket recv-from sfd 64))
  (Socket send-to sfd "pong" (first (rest got)) (rest (rest got)))
  (def reply (Socket recv cfd 64))
  (Socket close cfd) (Socket close sfd)
  (list (first got) (first (rest got)) reply))
```
---
    ("ping" "127.0.0.1" "pong")

### unix-domain round trip through listen/connect/accept

```scheme
(do (import x/sys/socket) (import x/sys/file)
  (def up "/tmp/x-364-spec.sock")
  (guard (_ ()) (File unlink up))
  (def lfd (Socket unix-listen up))
  (def c (Socket unix-connect up))
  (def a (Socket accept lfd))
  (Socket send c "hello-unix")
  (def got (Socket recv a 64))
  (Socket close c) (Socket close a) (Socket close lfd)
  (File unlink up)
  got)
```
---
    "hello-unix"

### a unix path past sockaddr_un capacity raises 'value

```scheme
(do (import x/sys/socket)
  (list (guard (e (Err kind-of e))
    (Socket unix-connect (Str8 repeat 25 "aaaa")))))
```
---
    ('value)
