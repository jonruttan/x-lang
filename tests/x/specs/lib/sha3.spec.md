# Sha3
# @weight 4

The SHA-3 digest (FIPS 202), pure x-lang on the engine's 64-bit words.
The vectors are the standard's widths and the padding's boundaries; every
digest here is also what the system `openssl dgst -sha3-WIDTH` answers.  A
block costs about a hundred milliseconds pure-x, so the file carries some
weight.

## sha3: the four widths

### abc at 224, 256, 384 and 512

```x
(do
  (import x/codec/sha3)
  (display (Sha3 hex 224 "abc"))(newline)
  (display (Sha3 hex 256 "abc"))(newline)
  (display (Sha3 hex 384 "abc"))(newline)
  (display (Sha3 hex 512 "abc")))
```
---
```output
e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25
b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
```

### the empty string, through hex-n's explicit length too

```x
(do
  (import x/codec/sha3)
  (display (Sha3 hex 512 ""))(newline)
  (display (Sha3 hex-n 224 "abc" 0)))
```
---
```output
a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26
6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7
```

## the padding's boundaries, at SHA3-256's 136-byte rate

### 135 bytes: 0x06 and 0x80 meet in the block's last byte

```x
(do
  (import x/codec/sha3)
  (display (Sha3 hex 256 (Str8 pad-right 135 #\z ""))))
```
---
    42793503c1b01806dc99fc04d80db0dd244013e3ce66b6fab9b9d542e6c867e4

### 136 bytes: the padding is a block of its own

```x
(do
  (import x/codec/sha3)
  (display (Sha3 hex 256 (Str8 pad-right 136 #\y "x"))))
```
---
    d64acb4b7ff9bcd79db07d858c4b9b18a4ae1911b873995c4a1649b1c7320366

### 200 bytes: two blocks

```x
(do
  (import x/codec/sha3)
  (display (Sha3 hex 256 (Str8 pad-right 200 #\a ""))))
```
---
    cce34485baf2bf2aca99b94833892a4f52896d3d153f7b840cc4f9fe695f1387

## binary input and widths

### 300 bytes 0 to 255 and on, NULs among them, through hex-n

```x
(do
  (import x/codec/sha3)
  (def s3-r ((prim-ref (lit str) (lit make)) 300))
  (def s3-p ((prim-ref (lit str) (lit ->ptr)) s3-r))
  ((fn (self i) (unless (= i 300) (do ((prim-ref (lit ptr) (lit set!)) s3-p i (& i 255) 1) (self (+ i 1))))) 0)
  (display (Sha3 hex-n 512 s3-r 300)))
```
---
    fa288fe9f54b8301e3012051fb1b275fd3f278a281ef149bb878fd322a647d3f51dc24908905550ed4883870c94f8d297f0690f8661b14d8222e9a46eebcbdf6

### a width that is no multiple of 8, or past 792, is refused

```x
(do
  (import x/codec/sha3)
  (display (list (guard (e (Err label e)) (Sha3 hex 250 "abc"))
                 (guard (e (Err label e)) (Sha3 hex 800 "abc"))
                 (Str8 length (Sha3 hex 32 "abc")))))
```
---
    (value value 8)
