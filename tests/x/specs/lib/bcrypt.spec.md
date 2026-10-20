# bcrypt-pbkdf
# @weight 4
# @timeout-scale 4

OpenBSD's bcrypt-pbkdf over Blowfish.  The vectors are Go's
(x/crypto/ssh/internal/bcrypt_pbkdf): its bcrypt_hash case and its three
bcrypt_pbkdf cases, one with NUL bytes in both regions, one with UTF-8
and an 88-byte key.  The pure-x Blowfish is checked on the classic
zero-key vector (Eric Young's set); the hashes run on the compiled
engine, which is adopted only after it answers Go's bcrypt_hash vector.
Output is binary, so every case reads it back by its length, through
`Hex encode-bytes`.

## Blowfish, pure-x

### the zero key's schedule encrypts the zero block to 4ef997456198dd78

```x
(do
  (import x/type/vector)
  (import x/codec/hex)
  (import x/codec/bcrypt)
  (def %bf-in (fn (_ n) (eval n (module x/codec/bcrypt))))
  (def %bf-st (Vector make 1042 0))
  ((fn (self i) (unless (= i 1043) (do ((prim-ref (lit obj) (lit set!)) %bf-st i ((prim-ref (lit obj) (lit ref)) (%bf-in (lit %init)) i)) (self (+ i 1))))) 1)
  ((%bf-in (lit %expand!)) %bf-st ((%bf-in (lit %stream)) (Hex decode "0000000000000000") 8 18) ())
  (def %bf-e ((%bf-in (lit %encrypt)) %bf-st 0 0))
  (write (list (first %bf-e) (rest %bf-e))))
```
---
    (1324980037 1637408120)

## bcrypt_hash

### Go's vector: the passphrase digest bytes 0..63, the salt's 64..127

```x
(do
  (import x/codec/hex)
  (import x/codec/bcrypt)
  (def %bc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %bc-c->i (prim-ref (lit char) (lit ->int)))
  (def %bc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%bc-c->i (%bc-bref s i)) acc))))
         (- n 1) ()))))
  (def %bc-ramp
    (fn (_ from)
      (def r ((prim-ref (lit str) (lit make)) 65))
      (def p ((prim-ref (lit str) (lit ->ptr)) r))
      ((fn (self i) (unless (= i 64) (do ((prim-ref (lit ptr) (lit set!)) p i (+ from i) 1) (self (+ i 1))))) 0)
      r))
  (display (%bc-hex (Bcrypt hash (%bc-ramp 0) (%bc-ramp 64)) 32)))
```
---
    87904870eef9deddf8e7611a140106e6aaf1a363d9a2c504db356443721eb555

## bcrypt_pbkdf

### "password" and "salt", 12 rounds, 32 bytes

```x
(do
  (import x/codec/hex)
  (import x/codec/bcrypt)
  (def %bc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %bc-c->i (prim-ref (lit char) (lit ->int)))
  (def %bc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%bc-c->i (%bc-bref s i)) acc))))
         (- n 1) ()))))
  (display (%bc-hex (Bcrypt pbkdf "password" 8 "salt" 4 12 32) 32)))
```
---
    1ae42c05d487bc02f64921a4ebe4ea93bcacfe135fda99974c06b7b01fae149a

### NUL bytes in both regions, 3 rounds

```x
(do
  (import x/codec/hex)
  (import x/codec/bcrypt)
  (def %bc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %bc-c->i (prim-ref (lit char) (lit ->int)))
  (def %bc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%bc-c->i (%bc-bref s i)) acc))))
         (- n 1) ()))))
  ; Hex decode is a C string, so the regions are written from decode-bytes
  (def %bc-buf
    (fn (_ hex)
      (def bs (Hex decode-bytes hex))
      (def r ((prim-ref (lit str) (lit make)) (+ (List length bs) 1)))
      (def p ((prim-ref (lit str) (lit ->ptr)) r))
      ((fn (self i bs) (unless (null? bs) (do ((prim-ref (lit ptr) (lit set!)) p i (first bs) 1) (self (+ i 1) (rest bs))))) 0 bs)
      r))
  (display (%bc-hex (Bcrypt pbkdf (%bc-buf "70617373776f7264790050415353574f524400") 19
                                  (%bc-buf "73616c74790053414c5400") 11 3 32) 32)))
```
---
    7f310bd3e78c3280c59ce4595211a2928e8d4ec744c1ed2efc9f764e3388e0ad

### UTF-8, 8 rounds, an 88-byte key: three blocks interleaved

```x
(do
  (import x/codec/hex)
  (import x/codec/bcrypt)
  (def %bc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %bc-c->i (prim-ref (lit char) (lit ->int)))
  (def %bc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%bc-c->i (%bc-bref s i)) acc))))
         (- n 1) ()))))
  (display (%bc-hex (Bcrypt pbkdf (Hex decode "d181d0b5d0bad180d0b5d182d0bdd0bed0b520d181d0bbd0bed0b2d0be") 29
                                  (Hex decode "d0bfd0bed181d0bed0bbd0b8d182d18c20d0bdd0b5d0bcd0bdd0bed0b6d0bad0be") 33 8 88) 88)))
```
---
    8df43fc6fe131fc47f0c9e39224bd94c70b6fcc8ee8135faddf61156e6cb2733ea765f315a3e1e4afc35bf8687d189254c1e05a6fe80c0617f9183d67260d6a115c6c94e3603e2303fbb43a76a64523ffda686b1d4518543

### what OpenBSD refuses is refused

```x
(do
  (import x/codec/bcrypt)
  (write (List map (fn (_ args) (guard (e (e msg)) (Bcrypt pbkdf (List ref 0 args) (List ref 1 args) (List ref 2 args) (List ref 3 args) (List ref 4 args) (List ref 5 args))))
    (list (list "pw" 2 "salt" 4 0 32) (list "" 0 "salt" 4 1 32) (list "pw" 2 "" 0 1 32) (list "pw" 2 "salt" 4 1 2000)))))
```
---
    ("Bcrypt: rounds must be 1 or more" "Bcrypt: an empty password" "Bcrypt: a bad salt length" "Bcrypt: key-len must be 1 to 1024")

## OpenSSH's key files

### a key ssh-keygen sealed under a passphrase opens: the check ints agree, the type and comment read (as hex)

`ssh-keygen -t ed25519 -N x-lang -C fixture -a 2`: aes256-ctr under
bcrypt-pbkdf, a 16-byte salt at byte 47, rounds at 63, the sealed
private section's 144 bytes from 130.  The 48 bytes derived are the
cipher's key and counter block.

```x
(do
  (import x/codec/base64)
  (import x/codec/hex)
  (import x/codec/aes)
  (import x/codec/bcrypt)
  (def %ok-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ok-c->i (prim-ref (lit char) (lit ->int)))
  (def %ok-byte (fn (_ s i) (%ok-c->i (%ok-bref s i))))
  (def %ok-region
    (fn (_ bs)
      (def r ((prim-ref (lit str) (lit make)) (+ (List length bs) 1)))
      (def p ((prim-ref (lit str) (lit ->ptr)) r))
      ((fn (self i bs) (unless (null? bs) (do ((prim-ref (lit ptr) (lit set!)) p i (first bs) 1) (self (+ i 1) (rest bs))))) 0 bs)
      r))
  (def %ok-sub (fn (_ s from n) (%ok-region ((fn (self i) (if (= i n) () (pair (%ok-byte s (+ from i)) (self (+ i 1))))) 0))))
  (def %ok-file (%ok-region (Base64 decode-bytes "b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAbeE38VXSd5rblJ37aa2F1AAAAAgAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIBAKoKrwWrJ05sAb7Qoyb+viPW+BGOKDfVwFI1zq9tdBAAAAkHVV6BBz5oVOHQwrzLxLYv7fsplhCMDc1XHYa2LZHJJa4QbRs02lAEjhlhZZTUFe/7nJlOdIqVcmGNFEFu/k8m73D/4tkpsis6Vo4z7wa8OzCRE841D3vIPC01gL2DezsN/jci0U66CseZsCqmkdZmcgBbCvr4qWnbXpXCGknIoinnXzYVasvtpZQRpiTclZ5w==")))
  (def %ok-kiv (Bcrypt pbkdf "x-lang" 6 (%ok-sub %ok-file 47 16) 16 2 48))
  (def %ok-priv (Aes ctr %ok-kiv 32 (%ok-sub %ok-kiv 32 16) %ok-file 130 144))
  (def %ok-word (fn (_ s i) (+ (* 16777216 (%ok-byte s i)) (* 65536 (%ok-byte s (+ i 1))) (* 256 (%ok-byte s (+ i 2))) (%ok-byte s (+ i 3)))))
  (def %ok-hex (fn (_ s i n) (Hex encode-bytes ((fn (self k) (if (= k n) () (pair (%ok-byte s (+ i k)) (self (+ k 1))))) 0))))
  (write (list (= (%ok-word %ok-priv 0) (%ok-word %ok-priv 4))
               (%ok-word %ok-priv 8) (%ok-hex %ok-priv 12 11)
               (%ok-hex %ok-priv 131 7))))
```
---
    (#t 11 "7373682d65643235353139" "66697874757265")
