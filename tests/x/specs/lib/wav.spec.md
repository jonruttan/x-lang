# Wav: WAV files read as one channel of signed 16-bit samples
# @weight 1

Each file is written out in hex, chunk by chunk: the RIFF header with its
size, a fmt chunk, the frames, and in one case a sampler's smpl chunk.

## format

### a 16-bit mono file's rate, channels, bits and frames

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex "524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080"))
  (Wav format (first r) 0 (List ref 2 r)))
```
---
    (8000 1 16 2)

## decode

### 16-bit samples come out as they are

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex "524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080"))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Bytes hex (list (List ref 2 d) 0 4)) (List ref 3 d) (List ref 4 d)))
```
---
    (8000 2 "ff7f0080" () ())

### 8-bit stereo is centred, raised to 16 bits, and each frame its channels' mean

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex "524946462800000057415645666d74201000000001000200401f0000803e0000020008006461746104000000ffff0080"))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (List ref 1 d) (Bytes hex (list (List ref 2 d) 0 4))))
```
---
    (2 "007f00c0")

### a 24-bit sample is its top 16 bits, and an odd chunk's pad byte is passed over

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex "524946462800000057415645666d74201000000001000100401f0000c05d000003001800646174610300000000341200"))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (List ref 1 d) (Bytes hex (list (List ref 2 d) 0 2))))
```
---
    (1 "3412")

### a sampler chunk gives the loop, its end past its last frame, and the root note

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex (Str8 append "524946467000000057415645666d74201000000001000100401f0000803e00000200100064617461080000000100020003000400"
                                    "736d706c3c000000000000000000000000000000" "3c000000000000000000000000000000" "0100000000000000"
                                    "000000000000000001000000020000000000000000000000")))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (List ref 1 d) (List ref 3 d) (List ref 4 d)))
```
---
    (4 (1 3) 60)

## what it refuses

### bytes that are not WAV, floating-point samples, and a file that ends early raise

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def try (fn (_ hex) (guard (e (Err text e)) ((fn (_ r) (Wav decode (first r) 0 (List ref 2 r))) (Bytes of-hex hex)))))
  (list (try "524946462800000057415645")
        (try "00000000000000000000000000000000")
        (try "524946462800000057415645666d74201000000003000100401f0000007d0000040020006461746104000000000080bf")
        (try "524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746110000000ff7f0080")))
```
---
    ("Wav: no fmt chunk" "Wav: not a WAV file: no RIFF WAVE header" "Wav: floating-point samples are not read: only integer PCM" "Wav: the file ends early")
