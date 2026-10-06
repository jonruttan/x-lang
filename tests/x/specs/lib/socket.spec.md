# Socket: blocking IPv4 TCP over libc FFI (#29)
# @weight 2

Deterministic, non-blocking coverage only: listen/bind/connect failure
paths and address validation. The full accept/recv/send loop cannot run
single-threaded under the batch harness (accept blocks; fork tears the
shared stdin script) -- it is exercised live by x-logo's serve.x, the
class's first consumer, and was verified end-to-end against nc.

## address validation

### a non-quad host raises a label 'value before any syscall

```x
(do (import x/sys/socket)
  (guard (e (Err label e)) (Socket tcp-connect "not.an.ip" 1)))
```
---
    'value

### octets out of range raise too

```x
(do (import x/sys/socket)
  (guard (e (Err label e)) (Socket tcp-connect "127.0.0.999" 1)))
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
  (def second (guard (e (list (Err label e) (Assoc get 'sym (e data)))) (Socket tcp-listen port)))
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

### tcp-listen-on the loopback takes a connection to it

```x
(do (import x/sys/socket)
  (def lfd (Socket tcp-listen-on "127.0.0.1" 0))
  (def port (Socket local-port lfd))
  (def c (Socket tcp-connect "127.0.0.1" port))
  (def s (Socket accept lfd))
  (Socket send c "hi")
  (def got (Socket recv s 16))
  (Socket close c) (Socket close s) (Socket close lfd)
  (list (> port 0) got))
```
---
    (#t "hi")

### tcp-listen-on an address no interface holds is a structured bind failure

192.0.2.1 is TEST-NET-1 (RFC 5737): assigned to no host.

```x
(do (import x/sys/socket)
  (guard (e (list (Err label e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
    (Socket tcp-listen-on "192.0.2.1" 0)))
```
---
    ('io 'eaddrnotavail 'bind)

### tcp-listen-on a host that is not a dotted quad raises 'value

```x
(do (import x/sys/socket)
  (guard (e (Err label e)) (Socket tcp-listen-on "localhost" 0)))
```
---
    'value

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
  (guard (e (list (Err label e) (Assoc get 'op (e data)))) (Socket local-port l)))
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
  (guard (e (list (Err label e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
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
  (def tmp (File temp "/tmp/x-364-spec-sock-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def up (rest tmp))
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
  (list (guard (e (Err label e))
    (Socket unix-connect (Str8 repeat 25 "aaaa")))))
```
---
    ('value)


## recv-bytes (#374): the lossless door

### a NUL-bearing payload survives the byte-list door where recv's string truncates

```x
(do (import x/sys/socket) (import x/sys/file)
  (def tmp (File temp "/tmp/x-374-rb-sock-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def up (rest tmp))
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

## shutdown and peer

A loopback connection in one process: connect completes against the
listener's backlog, and accept takes it after.

### shutdown write: the peer reads what was sent, then end of input; poll says so

```x
(do (import x/sys/socket) (import x/sys/posix)
  (def lfd (Socket tcp-listen 0))
  (def c (Socket tcp-connect "127.0.0.1" (Socket local-port lfd)))
  (def s (Socket accept lfd))
  (Socket send c "hi")
  (Socket shutdown c)
  ; macOS adds hup once the peer has shut down its side; Linux need not
  (def ready (first (rest (first (Sys poll (list (pair s (list 'in))) 1000)))))
  (def got (Socket recv s 16))
  (def eof (Socket recv-run s 16))
  (Socket send s "back")
  (def reply (Socket recv c 16))
  (Socket close c) (Socket close s) (Socket close lfd)
  (list ready got eof reply))
```
---
    ('in "hi" () "back")

### peer names the other end, from either side

```x
(do (import x/sys/socket)
  (def lfd (Socket tcp-listen 0))
  (def port (Socket local-port lfd))
  (def c (Socket tcp-connect "127.0.0.1" port))
  (def s (Socket accept lfd))
  (def from-server (Socket peer s))
  (def from-client (Socket peer c))
  (def r (list (first from-server) (= (rest from-server) (Socket local-port c))
               from-client (= (rest from-client) port)))
  (Socket close c) (Socket close s) (Socket close lfd)
  (list (first r) (first (rest r)) (first (first (rest (rest r)))) (first (rest (rest (rest r))))))
```
---
    ("127.0.0.1" #t "127.0.0.1" #t)

### shutdown takes read, write or both, and nothing else

```x
(do (import x/sys/socket)
  (guard (e (Err label e)) (Socket shutdown 0 'sideways)))
```
---
    'value

## binary datagrams

### send-to-run and recv-from-run carry NUL bytes, and the sender to answer

```x
(do (import x/sys/socket)
  (def srv (Socket udp-bind 0))
  (def cli (Socket udp-bind 0))
  (def sp (Socket local-port srv))
  (def packet (bytes->str (list 18 52 0 1 0 0 104 105)))
  (Socket send-to-run cli (pair packet 8) "127.0.0.1" sp)
  (def got (Socket recv-from-run srv 512))
  (def bytes (let go ((i (- (rest (first got)) 1)) (acc ()))
               (if (< i 0) acc (go (- i 1) (pair (& (Char ->int ((prim-ref (lit str) (lit byte-ref)) (first (first got)) i)) 255) acc)))))
  (Socket send-to-run srv (pair (bytes->str (list 0 7 0)) 3) (first (rest got)) (rest (rest got)))
  (def back (Socket recv-from-run cli 512))
  (def r (list bytes (= (rest (rest got)) (Socket local-port cli)) (rest (first back)) (rest (rest back))))
  (Socket close srv) (Socket close cli)
  (list (first r) (first (rest r)) (first (rest (rest r))) (= (first (rest (rest (rest r)))) sp)))
```
---
    ((18 52 0 1 0 0 104 105) #t 3 #t)
