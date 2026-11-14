# Unlzma JIT engine

# @weight 6
# @timeout-scale 4

The compiled decoder behind `(Unlzma jit!)`.  It is adopted only after
decoding two check streams exactly as the pure-x decoder does; these cases
re-prove agreement through the class, on streams written by xz 5.8.4.
`%uj-region` puts a byte list into a byte region.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/unlzma)
  (display (list (Unlzma jit!) (Unlzma jit!) ((Compiled named (lit unlzma)) state))))
```
---
    (#t #t compiled)

## agreement through the engine

### every decision the format has, and a window that wraps

The first check stream: literals plain and matched, distances from each
tier, all four repeated distances and lengths from each tier, through a
4096-byte window over 4652 bytes.  `gzip` gives the input's CRC-32.

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-z (Hex decode-bytes (Str8 append
    "5d00100000ffffffffffffffff00399948caebd3b5bc6180c1fad3fafc7972156fc13767639185bd015f88c195a2f4c4"
    "7140f803827086e65f855789c9412488723be50124b0ca6fb9b4d26be6cdfd8319d24179ba9c46c23fbb1e3cb7172b51"
    "8485a73ed2a40c39bb9abf714d3ae98273d60480cde321bbaa33a281b2379fd2a3e92a26eb2d1d0f68560014e515d3a0"
    "9f4cb995d7f1b1c79304d8067ea4e23b34dee7c1db0d2715e75138ced1310e2cc81ae77f8bb2d98226c9bcbdccc9f48f"
    "427e61e55508e4149932d8ca6ba54da2fba83a8649459ba1ecad3de60f0762e6d24904e3f240870cbf4761dac9db2fed"
    "a05fad8a5637565e7a10cd122aea43f424b4f83e463740d612fd6796e553ccb064eed37577ea3f7e379ccf579ad6e378"
    "46f4f8643e37866b6a0936d79e83a5ddd0d95bc6e207e5d5225c7eb54fee2a6ae542d0d6b6b75ccfc6d54a6c3a2b5a43"
    "b5ff1b9ae63615b7deca95a4882c8ccda80d72ec5d7db6559d9b58ead38452f80e094c101344c571a7bc4c5345c093f0"
    "d1340bbb36349f25567f2f523b268db64a9f585e95e0f87a60dd93b90dbf5503bffc157839b2742fb81378cb45e8ac6f"
    "f9c4da32d7b5ffb5a44d789b4d23a2cf78f59b790c641acc802d180fdcf7e2b2e00fbefddba98d4bc41736440615ac12"
    "a2157c4e1c58b7813c1934997ca3917ed538e97ee321609c5299597bd8cf267bed6c26c62d06d02d6fd5c01eb752aea1"
    "8c5e60d355c5a0d550499bb5a7336b9ec7117075399ada8c8382c2e5d3eab26bab66fd2538d915bccd2e51192b69643b"
    "bf5ffb4197245d5ed08b795bf7b89e9e4560f236feecf2fb2a99cb5c50a6160245c199aaa8ed0d7801c5e8433bc6fe14"
    "97e354a41008c573999c0df3d86cb2cc7aa60651eb42a6c025c4a53d5cc74fb7cfe05ec220fdf5ad4d709e40949f60b3"
    "0e976b193bf459f5e213b20b7f326919aa40359a19c30131dd924cd739b155a4f7e4f913dedeefd0a7459a820bc00075"
    "6f21b790600211554ee75de7cf66b92bcef0b812c2805e45fded04861771c1f004665e1487a48e38e255fd44542fa3de"
    "2042f108674ca552407ef7020574d870f649a27c89546d0aa161564ac799cbabd677e6a04e5e723ccc84849520ec0a9d"
    "b2fb9b0edb63cba450b7470691a1d2d93e13a69a8c8c6724d35c312ccb4582d3ec05d6e7e3b45994d1eb1d111c5e209a"
    "4b8569b945729c3f99eecfb8ad58009f95de46a54414407cb22cb744e8d5423cbe2120af994d8d3fac712e4a38107398"
    "d668d295681cb720330ee3f781fd4b56eb42411791fffd9eae8c")))
  (def %uj-r (Unlzma decode (%uj-region %uj-z) 0 (List length %uj-z)))
  (write (list (first (rest %uj-r)) (first (rest (rest %uj-r)))
               (Crc32 of (first %uj-r) 0 (first (rest %uj-r))))))
```
---
    (4652 938 977594949)

### an output that outgrows its region and its window many times over

The header declares a 64MB dictionary and no length, so the window starts
at 64KB and grows, and the output starts at 4KB: 100000 bytes cross both
many times.  The input is byte i = 97 + (i mod 7 + i mod 3 + i div 5000)
mod 26, and `gzip` gives its CRC-32.  It uses 296 of the stream's 297
bytes: the end marker comes before the coder's last flush byte.

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-z (Hex decode-bytes (Str8 append
    "5d00000004ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03"
    "b58c1c21a1fd665f7bc68e3a23b1a4baa0ebd46ff7df289b037d04abb1f53a247b10fa45369775500de590a1cff24842"
    "210f6c1b39c21f42f8a389284d8f8d3f24d84cda4d36472a77f2be194e751544fff50da539b8b8a3144ffcc1740161d8"
    "be7ddfefbab8997ad6fb2b5f1f2243c97b3842d5c7b66a2698032b7d16d418a758a0bad4f3a46e3f480b4fbcb1a9af6c"
    "dc219705819bbace15e7acdf8198614c2b40f02884a2c2e885dd49ce6cea1e2b9c1b7b04eaa9cb7250c48d4b5b8f8fa3"
    "c1267022ea550feb976ec9343d26df9e906275563de2c79f33cf73394e640ca097dad3028f84a23b93a33237a94ed0c4"
    "bef3bbffff120c0000")))
  (def %uj-r (Unlzma decode (%uj-region %uj-z) 0 (List length %uj-z)))
  (write (list (first (rest %uj-r)) (first (rest (rest %uj-r)))
               (Crc32 of (first %uj-r) 0 (first (rest %uj-r))))))
```
---
    (100000 296 881757662)

### a header that says how long the output is

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-z (Hex decode-bytes "5d000000040d0000000000000000341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (def %uj-r (Unlzma decode (%uj-region %uj-z) 0 (List length %uj-z)))
  (write (list (Str8 sub 0 13 (first %uj-r)) (first (rest %uj-r)))))
```
---
    ("hello, hello\n" 13)

### the end marker alone

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-z (Hex decode-bytes "5d00000004ffffffffffffffff0083fffbffffc0000000"))
  (rest (Unlzma decode (%uj-region %uj-z) 0 (List length %uj-z))))
```
---
    (0 23)

## a stream that is not one

### a stream cut short inside its decisions is refused through the engine too

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-z (Hex decode-bytes "5d00000004ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03b58c1c21a1fd665f7bc68e3a23b1a4baa0ebd46ff7df289b037d04abb1f53a247b10fa45369775500de590a1cff24842210f6c1b"))
  (guard (e (list (Err label e) (e msg) (e data)))
    (Unlzma decode (%uj-region %uj-z) 0 (List length %uj-z))))
```
---
    ('value "Unlzma: the stream ends inside a symbol" (('lzma . 'short)))

## a stream fed a piece at a time

### an output that outgrows its regions, fifty bytes at a time

The 100000-byte stream above, fed through the engine: each piece's decisions run until
fewer bytes are unread than one might need, and the bytes held carry to
the next.  The CRC-32 is carried across the pieces.  The byte the stream
leaves is the coder's last flush byte.

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-fed (fn (_ in n step)
    (let ((z (Unlzma stream))
          (sum (fn (_ acc p) (list (+ (first acc) (first (rest p))) (Crc32 update (first (rest acc)) (first p) 0 (first (rest p)))))))
      ((fn (self off acc)
         (if (< off n)
           (self (+ off step) (sum acc (Unlzma feed z in off (if (< (- n off) step) (- n off) step))))
           (let ((all (sum acc (Unlzma finish z))))
             (list (first all) (first (rest all)) (Unlzma done? z) (first (rest (Unlzma rest z)))))))
       0 (list 0 0)))))
  (def %uj-z (Hex decode-bytes (Str8 append
    "5d00000004ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03"
    "b58c1c21a1fd665f7bc68e3a23b1a4baa0ebd46ff7df289b037d04abb1f53a247b10fa45369775500de590a1cff24842"
    "210f6c1b39c21f42f8a389284d8f8d3f24d84cda4d36472a77f2be194e751544fff50da539b8b8a3144ffcc1740161d8"
    "be7ddfefbab8997ad6fb2b5f1f2243c97b3842d5c7b66a2698032b7d16d418a758a0bad4f3a46e3f480b4fbcb1a9af6c"
    "dc219705819bbace15e7acdf8198614c2b40f02884a2c2e885dd49ce6cea1e2b9c1b7b04eaa9cb7250c48d4b5b8f8fa3"
    "c1267022ea550feb976ec9343d26df9e906275563de2c79f33cf73394e640ca097dad3028f84a23b93a33237a94ed0c4"
    "bef3bbffff120c0000")))
  (write (%uj-fed (%uj-region %uj-z) (List length %uj-z) 50)))
```
---
    (100000 881757662 #t 1)

### a stream cut short keeps the windows it decoded

The engine runs on past the end of the input with zero bytes until it is
back at the top of a decision; the count it raises with is the one it held
at the top of the decision that failed.  The same cut stream and numbers as
unlzma.spec.md's: the 50007 bytes `xz -dc` decodes, gzip's CRC-32.

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (Unlzma jit!)
  (def %uj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %uj-at (fn (self k l) (if (eq? (first (first l)) k) (rest (first l)) (self k (rest l)))))
  (def %uj-z (Hex decode-bytes (Str8 append
    "5d00100000ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03"
    "b58c1c21a1fd665f7bc68e3a23b1a4baa0ebd46ff7df289b037d04abb1f53a247b10fa45369775500de590a1cff24842"
    "210f6c1b39c21f42f8a389284d8f8d3f24d84cda4d36472a77f2be194e751544fff50da539b8b8a3144ffcc1740161d8"
    "be7ddfefbab8997ad6fb2b5f1f2243c97b3842d5c7b66a2698032b7d16d418a758a0bad4f3a46e3f480b4fbcb1a9af6c"
    "dc21")))
  (def %uj-s (Unlzma stream))
  (def %uj-p (Unlzma feed %uj-s (%uj-region %uj-z) 0 (List length %uj-z)))
  (def %uj-c (Crc32 update 0 (first %uj-p) 0 (first (rest %uj-p))))
  (guard (e (let ((q (%uj-at (lit out) (e data))))
              (list (+ (first (rest %uj-p)) (first (rest q)))
                    (Crc32 update %uj-c (first q) 0 (first (rest q)))
                    (%uj-at (lit lzma) (e data)))))
    (Unlzma finish %uj-s)))
```
---
    (50007 3562979691 'short)
