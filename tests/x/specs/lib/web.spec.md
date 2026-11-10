# Web: a window in a browser tab, over a WebSocket
# @weight 2

Each case plays the browser itself on the loopback: it connects before
the window serves, since connect finishes in the kernel's backlog, and
the window answers at its next poll.  No case names a port; each listens
on port 0 and reads the port back with local-port.

## the handshake's answer

### the key from RFC 6455's example gets the answer the RFC gives

```x
(do (import x/sys/web)
  (Web accept-key "dGhlIHNhbXBsZSBub25jZQ=="))
```
---
    "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

## messages from the page

### a message's words make an event, numbers read as numbers

```x
(do (import x/sys/web)
  (list (Web %event (list 107 101 121 45 100 111 119 110 32 57 55 32 49 32 48))
        (Web %event (list 112 97 100 45 117 112 32 115 111 117 116 104 32 48))))
```
---
    (('key-down 97 1 0) ('pad-up 'south 0))

### a mask comes off four bytes round

```x
(do (import x/sys/web)
  (Web %unmask (list 106 103 120 101 104 107) (list 1 2 3 4)))
```
---
    (107 101 123 97 105 105)

## serving the page

### a GET of / is the page, anything else not found

```x
(do (import x/sys/web) (import x/sys/socket)
  (Web listen! "127.0.0.1" 0)
  (def w-win (Web open "t" 2 1 1))
  (def w-port (Socket local-port (Web %ref w-win (lit listener))))
  (def w-ask (fn (_ path)
             (def w-c (Socket tcp-connect "127.0.0.1" w-port))
             (Socket send w-c (Str8 append "GET " path " HTTP/1.1\r\nHost: x\r\n\r\n"))
             (Web poll)
             (def got (Socket recv w-c 64))
             (Socket close w-c)
             (Str8 sub 0 15 got)))
  (def w-page (w-ask "/"))
  (def w-other (w-ask "/nothing"))
  (Web close w-win)
  (list w-page w-other (Web available?)))
```
---
    ("HTTP/1.1 200 OK" "HTTP/1.1 404 No" #t)

## the WebSocket

### the page's socket is told the window's state, its keys come back as events, and a frame goes to it

```x
(do (import x/sys/web) (import x/sys/socket) (import x/core/doors ptr-set! str->ptr str-make)
  (Web listen! "127.0.0.1" 0)
  (def w-win (Web open "Delve" 2 1 1))
  (def w-port (Socket local-port (Web %ref w-win (lit listener))))
  (def w-c (Socket tcp-connect "127.0.0.1" w-port))
  (Socket send w-c (Str8 append "GET /socket HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n"
                              "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                              "Sec-WebSocket-Version: 13\r\n\r\n"))
  (def w-first-poll (Web poll))
  (def w-told (Socket recv w-c 4096))
  ; "key-down 97 1 0" in a masked text frame, the mask 1 2 3 4
  (def w-text (list 107 101 121 45 100 111 119 110 32 57 55 32 49 32 48))
  (def w-frame (str-make 22))
  (def w-p (str->ptr w-frame))
  (ptr-set! w-p 0 129 1) (ptr-set! w-p 1 (+ 128 15) 1)
  (ptr-set! w-p 2 1 1) (ptr-set! w-p 3 2 1) (ptr-set! w-p 4 3 1) (ptr-set! w-p 5 4 1)
  (let put ((l w-text) (i 0))
    (unless (null? l)
      (do (ptr-set! w-p (+ 6 i) (- (| (first l) (+ 1 (& i 3))) (& (first l) (+ 1 (& i 3)))) 1)
          (put (rest l) (+ i 1)))))
  (Socket send-run w-c w-frame 21)
  (def w-event (Web poll))
  (def w-buf (Web canvas w-win))
  (ptr-set! (str->ptr w-buf) 0 200 1)
  (Web show! w-win w-buf)
  (def w-sent (let more ((got ())) (if (>= (List length got) 4) got (more (List append got (Socket recv-bytes w-c 16))))))
  (Web close w-win)
  (Socket close w-c)
  (list w-first-poll
        (not (null? (Str8 index-of "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" w-told)))
        (not (null? (Str8 index-of "size 2 1" w-told)))
        (not (null? (Str8 index-of "title Delve" w-told)))
        w-event
        (List take 4 w-sent)))
```
---
    (() #t #t #t ('key-down 97 1 0) (130 9 70 200))

### a frame of 126 bytes or more carries a two-byte length

```x
(do (import x/sys/web) (import x/sys/socket)
  (Web listen! "127.0.0.1" 0)
  (def w-win (Web open "t" 64 64 1))
  (def w-port (Socket local-port (Web %ref w-win (lit listener))))
  (def w-c (Socket tcp-connect "127.0.0.1" w-port))
  (Socket send w-c (Str8 append "GET /socket HTTP/1.1\r\nUpgrade: websocket\r\n"
                              "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"))
  (Web poll)
  (Socket recv w-c 4096)
  (Web show! w-win (Web canvas w-win))
  (def w-sent (let more ((got ())) (if (>= (List length got) 4) (List take 4 got) (more (List append got (Socket recv-bytes w-c 4))))))
  (Web close w-win)
  (Socket close w-c)
  w-sent)
```
---
    (130 126 64 1)

### a page that goes away is waited for again, and poll answers nil

```x
(do (import x/sys/web) (import x/sys/socket)
  (Web listen! "127.0.0.1" 0)
  (def w-win (Web open "t" 2 1 1))
  (def w-port (Socket local-port (Web %ref w-win (lit listener))))
  (def w-c (Socket tcp-connect "127.0.0.1" w-port))
  (Socket send w-c (Str8 append "GET /socket HTTP/1.1\r\nUpgrade: websocket\r\n"
                              "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"))
  (Web poll)
  (def w-had (not (null? (Web %ref w-win (lit page)))))
  (Socket close w-c)
  (def w-after (Web poll))
  (def w-gone (null? (Web %ref w-win (lit page))))
  (Web close w-win)
  (list w-had w-after w-gone))
```
---
    (#t () #t)

## sound

### audio-queued counts down from what was sent, by the clock

```x
(do (import x/sys/web)
  (Web listen! "127.0.0.1" 0)
  (def w-win (Web open "t" 2 1 1))
  (def w-s (Web audio-open 1000 1))
  (def w-buf (Str8 append "abcdefghij"))
  (Web audio-put! w-s w-buf 10)
  (def w-queued (Web audio-queued w-s))
  (Web audio-clear! w-s)
  (def w-cleared (Web audio-queued w-s))
  (Web audio-close w-s)
  (Web close w-win)
  (list (> w-queued 0) (<= w-queued 10) w-cleared))
```
---
    (#t #t 0)
