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

## floating point

A floating-point file's fmt chunk has tag 3 (WAVE_FORMAT_IEEE_FLOAT), or
tag 0xFFFE with the sub-format GUID 00000003-0000-0010-8000-00aa00389b71
(WAVE_FORMAT_EXTENSIBLE, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT), as Microsoft's
WAVEFORMATEX and WAVEFORMATEXTENSIBLE documents lay them out. Its samples
are IEEE 754 singles or doubles, little-endian, full scale -1 to 1.

### 32-bit samples times 32768, rounded down, held to full scale, a NaN 0

The frames are 0.5, -0.5, 1, -1, a NaN and -2^-16.

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex (Str8 append "524946463c00000057415645666d74201000000003000100401f0000007d0000040020006461746118000000"
                                    "0000003f000000bf0000803f000080bf0000c07f000080b7")))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (Wav format (first r) 0 (List ref 2 r)) (List ref 1 d) (Bytes hex (list (List ref 2 d) 0 12))))
```
---
    ((8000 1 32 6) 6 "004000c0ff7f00800000ffff")

### 64-bit stereo in the extensible form, each frame its channels' mean

The frames are (0.25 -0.75) and (1 1).

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def r (Bytes of-hex (Str8 append "524946465c00000057415645666d742028000000feff0200401f000000f40100100040001600400003000000"
                                    "0300000000001000800000aa00389b71" "6461746120000000"
                                    "000000000000d03f000000000000e8bf000000000000f03f000000000000f03f")))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (Wav format (first r) 0 (List ref 2 r)) (Bytes hex (list (List ref 2 d) 0 4))))
```
---
    ((8000 2 64 2) "00e0ff7f")

### a long file reads as a short one does

8192 frames, alternately 0.5 and -0.5: long enough that the kernel is
compiled where the toolchain has a backend.

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def w (Bytes writer))
  (Bytes put w (Bytes of-hex "524946462480000057415645666d74201000000003000100401f0000007d0000040020006461746100800000"))
  (def e (Bytes writer))
  ((fn (self i) (when (< i 4096) (Bytes put-u32 w 63) (Bytes put-u32 w 191) (Bytes put-u16 e 64) (Bytes put-u16 e 192) (self (+ i 1)))) 0)
  (def r (Bytes written w))
  (def d (Wav decode (first r) 0 (List ref 2 r)))
  (list (List ref 1 d) (Bytes same? (list (List ref 2 d) 0 16384) (Bytes written e))))
```
---
    (8192 #t)

## what it refuses

### bytes that are not WAV, 16-bit floating point, and a file that ends early raise

```x
(do (import x/codec/wav) (import x/codec/bytes)
  (def try (fn (_ hex) (guard (e (Err text e)) ((fn (_ r) (Wav decode (first r) 0 (List ref 2 r))) (Bytes of-hex hex)))))
  (list (try "524946462800000057415645")
        (try "00000000000000000000000000000000")
        (try "524946462800000057415645666d74201000000003000100401f0000803e0000020010006461746104000000ff7f0080")
        (try "524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746110000000ff7f0080")))
```
---
    ("Wav: no fmt chunk" "Wav: not a WAV file: no RIFF WAVE header" "Wav: floating-point bits a sample other than 32 or 64" "Wav: the file ends early")
