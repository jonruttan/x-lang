# Midi: a MIDI keyboard's messages
# @weight 1

The decoder runs on bytes in hand, so it is tested with no device. The
CoreMIDI read callback is a native stub; it is called here with a packet
list built in memory, as CoreMIDI would call it, and what it wrote to the
pipe is read back.

## decoding

### notes on and off, and a note-on of velocity 0 as a note-off

```x
(do (import x/sys/midi)
    (Midi decode (list 144 60 100 128 60 64 145 62 90 145 62 0)))
```
---
    (('note-on 1 60 100) ('note-off 1 60 64) ('note-on 2 62 90) ('note-off 2 62 0))

### running status: the status byte sent once for many messages

```x
(do (import x/sys/midi)
    (Midi decode (list 144 60 100 64 90 67 80)))
```
---
    (('note-on 1 60 100) ('note-on 1 64 90) ('note-on 1 67 80))

### controllers, programs, pressure and the bend

```x
(do (import x/sys/midi)
    (Midi decode (list 176 7 100 192 5 208 40 160 60 30 224 0 64 224 127 127 224 0 0)))
```
---
    (('cc 1 7 100) ('program 1 5) ('pressure 1 40) ('poly-pressure 1 60 30) ('bend 1 0) ('bend 1 8191) ('bend 1 -8192))

### real-time bytes between a message's bytes, and a system exclusive, are passed over

```x
(do (import x/sys/midi)
    (Midi decode (list 144 248 60 254 100 240 1 2 3 247 128 60 0)))
```
---
    (('note-on 1 60 100) ('note-off 1 60 0))

### a message split between reads is finished by the next

```x
(do (import x/sys/midi)
    (def fds (Sys pipe))
    (Sys nonblock! (first fds))
    (def m (new Midi fd (first fds)))
    (Sys fd-write (rest fds) (bytes->str (list 144 60)))
    (def one (m messages))
    (Sys fd-write (rest fds) (bytes->str (list 100 62 90)))
    (def two (m messages))
    (def three (m messages))
    (m close!)
    (Sys close (rest fds))
    (list one two three))
```
---
    (() (('note-on 1 60 100) ('note-on 1 62 90)) ())

## the devices

### devices answers a list of names

```x
(do (import x/sys/midi)
    (List all? str? (Midi devices)))
```
---
    #t

### a device there is not is refused

```x
(do (import x/sys/midi)
    (guard (e (Err label e)) (Midi open "/no/such/midi")))
```
---
    'io

## the read callback

### the stub writes each packet's bytes to the pipe, the packets placed as CoreMIDI places them

```x
(do (import x/sys/midi)
    (import x/tool/asm)
    (import x/core/doors ptr-call ptr-set! ptr->int str->ptr str-make)
    (def fds (Sys pipe))
    (Sys nonblock! (first fds))
    (def list-buf (str-make 64))
    (def p (str->ptr list-buf))
    (ptr-set! p 0 2 4)
    (ptr-set! p 12 3 2)
    (List for-each (fn (_ b) (ptr-set! p (+ 14 (first b)) (rest b) 1)) (list (pair 0 144) (pair 1 60) (pair 2 100)))
    (def second (if arch-arm64? 20 17))
    (ptr-set! p (+ second 8) 3 2)
    (List for-each (fn (_ b) (ptr-set! p (+ second (+ 10 (first b))) (rest b) 1)) (list (pair 0 128) (pair 1 60) (pair 2 0)))
    (def stub (Midi %write-stub))
    (ptr-call (asm-finalize! stub) list-buf (rest fds) 0)
    (def got (Sys fd-read (first fds) 64))
    (asm-free! stub)
    (Sys close (first fds)) (Sys close (rest fds))
    (list got (Midi decode got)))
```
---
    ((144 60 100 128 60 0) (('note-on 1 60 100) ('note-off 1 60 0)))
