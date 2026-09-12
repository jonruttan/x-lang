# Socket: blocking IPv4 TCP over libc FFI (#29)
# @weight 2

Deterministic, non-blocking coverage only: listen/bind/connect failure
paths and address validation. The full accept/recv/send loop cannot run
single-threaded under the batch harness (accept blocks; fork tears the
shared stdin script) -- it is exercised live by x-logo's serve.x, the
class's first consumer, and was verified end-to-end against nc.

## address validation

### a non-quad host raises tag 'value before any syscall

```x
(do (import x/sys/socket)
  (guard (e (Err tag e)) (Socket tcp-connect "not.an.ip" 1)))
```
---
    'value

### octets out of range raise too

```x
(do (import x/sys/socket)
  (guard (e (Err tag e)) (Socket tcp-connect "127.0.0.999" 1)))
```
---
    'value

## listen and structured failure

No case here names a port. A fixed one is a bet that nothing else on the
box holds it, and the bet lost: 49364 sat inside the ephemeral range
macOS hands to any process that asks, and Spotify had it when the release
tag's pre-push suite ran (2026-09-12). Each case binds port 0, lets the
kernel choose, and reads the choice back with local-port.

### tcp-listen answers a real fd; rebinding the port is a structured eaddrinuse

```x
(do (import x/sys/socket)
  (def lfd (Socket tcp-listen 0))
  (def port (Socket local-port lfd))
  (def second (guard (e (list (Err tag e) (Assoc get 'sym (e data)))) (Socket tcp-listen port)))
  (Socket close lfd)
  (list (> lfd 2) (> port 0) second))
```
---
    (#t #t ('io 'eaddrinuse))

### the port frees on close

```x
(do (import x/sys/socket)
  (def a (Socket tcp-listen 0))
  (def port (Socket local-port a))
  (Socket close a)
  (def b (Socket tcp-listen port))
  (def again (Socket local-port b))
  (Socket close b)
  (list (> b 2) (= again port)))
```
---
    (#t #t)

### local-port answers the kernel's choice for a listener and a datagram socket alike

```x
(do (import x/sys/socket)
  (def l (Socket tcp-listen 0))
  (def u (Socket udp-bind 0))
  (def lp (Socket local-port l))
  (def up (Socket local-port u))
  (Socket close l) (Socket close u)
  (list (and (> lp 0) (< lp 65536)) (and (> up 0) (< up 65536)) (not (= lp up))))
```
---
    (#t #t #t)

### local-port on a closed fd is a structured io failure

```x
(do (import x/sys/socket)
  (def l (Socket tcp-listen 0))
  (Socket close l)
  (guard (e (list (Err tag e) (Assoc get 'op (e data)))) (Socket local-port l)))
```
---
    ('io 'getsockname)

### connecting where nothing listens is a structured econnrefused

"Nothing listens" is made true by construction -- bind a port, close
it, then connect: a bare fixed port turned out to be LISTENED ON by
something on the ubuntu CI runner (connect returned an fd; the pin got
"5").

```x
(do (import x/sys/socket)
  (def l (Socket tcp-listen 0))
  (def port (Socket local-port l))
  (Socket close l)
  (guard (e (list (Err tag e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
    (Socket tcp-connect "127.0.0.1" port)))
```
---
    ('io 'econnrefused 'connect)

## UDP and unix-domain loopback (#364)

These ARE deterministic under the batch harness, unlike the TCP accept
loop the preamble rules out: a datagram queues before recv-from runs,
and a unix/TCP connect completes against the listen backlog before
accept is called -- no step blocks.

### connected-UDP request, recv-from identifies the sender, send-to replies

```x
(do (import x/sys/socket)
  (def sfd (Socket udp-bind 0))
  (def port (Socket local-port sfd))
  (def cfd (Socket udp-connect "127.0.0.1" port))
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

```x
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

```x
(do (import x/sys/socket)
  (list (guard (e (Err tag e))
    (Socket unix-connect (Str8 repeat 25 "aaaa")))))
```
---
    ('value)


## recv-bytes (#374): the lossless door

### a NUL-bearing payload survives the byte-list door where recv's string truncates

```x
(do (import x/sys/socket) (import x/sys/file)
  (def up "/tmp/x-374-rb.sock")
  (guard (_ ()) (File unlink up))
  (def lfd (Socket unix-listen up))
  (def c (Socket unix-connect up))
  (def a (Socket accept lfd))
  (Socket send c (bytes->str (list 104 105)))
  (def first-half (Socket recv-bytes a 16))
  (Socket close c) (Socket close a) (Socket close lfd)
  (File unlink up)
  first-half)
```
---
    (104 105)
