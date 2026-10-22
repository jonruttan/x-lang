# Rsa
# @weight 15
# @timeout-scale 4

RSA signature verification (RFC 8017), PKCS#1 v1.5 and PSS over SHA-256,
under keys of 2048 and 4096 bits.  Every key and signature here is
OpenSSL's: a key made with `openssl genrsa`, the message "x-lang
verifies RSA" signed with `openssl dgst -sha256 -sign`, once plain and
once with `-sigopt rsa_padding_mode:pss`, and each signature verified by
`openssl dgst -verify` before it was written down.  Each case then
breaks one thing -- the padding mode, a digest bit, a signature bit, the
hash, the length -- and must answer #f.  The first verification builds
the looping Montgomery engine (x/codec/mont-jit) and checks it against
the pure-x arithmetic, so the file carries an engine's weight.  Last,
PSS signatures this code makes.

## OpenSSL's signatures

### a 2048-bit key, PKCS#1 v1.5 and PSS, and what breaks them

```x
(do
  (import x/codec/rsa)
  (import x/codec/bytes)
  (def %rs-n (Bytes of-hex "aa54ba0b4cb8044c63065f6d657dd178ccc247acff7c095803e784b5fd8fee2eb0fd26f5cfbf5c072a8662b5fa2d53f1fa9d266060c6b4b4d461ed0af452390c9a36ef6e7df3b47644118c906216f5bd091549f8683e00112847c7e15a4e815695002deb15c1569984970865fa99c30743c6f8303e24834d4cc91713f5c16fbb0c84029dbcebcd6e95f175eb997f413185a0a681643e0b6646ca4711a21f59e6b87d157ed56866c70aff35908b234f66dc2aee57e6ef0f9e4b85363323d32bbf37b77f85feaf9bcefe0ba3bad005c7beea5949169d0b161cb65e777d9ec6ade3b0cb382b4c8b847b9ec4df0d991cfc69c189f43e5f9f0bf9a6345e772ee37331"))
  (def %rs-e (Bytes of-hex "010001"))
  (def %rs-h (Bytes of-hex "647b29271b96d1c1183c25f88b2b6a4667576d6872fcff0bff65b7bece3e9288"))
  (def %rs-v15 (Bytes of-hex "764a0551fc1dadeef3cc06a50f5461ddd390f5d3921938cf602d7352d43b4866a159a111f0bef93b6e74e8723001546e3b18cb44af1e01ac67ad9e66f981cebdd75574b61b5f691a60b0a71300febcef599ef88b08f167f63841f0b4a6010f31109ab10acf512aabf70376f8e6ff9468d5855fe0928efb942a89bf2b094215bfea28feb1751cd0752f56954421adf069a600736a2f0226acc7b5f2dc91444cc38e0737f605c646c05413cefba7f652758aa6fe5e3e1652488fddc0ea033730580c5e05f74dfbfe86c0bfdd4c58ffdbc0bf6d88f635dd4add9ffa3df2f512a418824951f9ac141a47586fa3a2d1fdf30da28e1474be78317604cd10d52e4d514d"))
  (def %rs-pss (Bytes of-hex "09fd04244680c0b5e0f2bd097087c38f8ffb59a47851c8eb2c44923955e6144b0257a8e442c5b1a9c45b91e952fbdf062b290fb10bf981763dd4a4e3707969fddefda16857a47c835a6a66744ba76296cadb876f0a29092b286c2a80f0a828569fce71710caac8feb926bea4f54d339be9d7d2968bbdff9165146c41f381ce776627f929d2d33a8d94ee245e202db78f3f0853d8546edbe47f820a8c5108724b178a4038b39b7fd8838558dd010e771a4997c30c0ba64274386f9a4cc5f33feac4e8386602f00d7d1725b521f6e10aa63c774c0b1bb6036ef946d5e5a469d7555e091ee0a90003e6ef6d9a5f42a7b65847085f1c9e4d0b73ff35d0420c9221c8"))
  ; a copy of r with the low bit of byte i flipped
  (def %rs-flip
    (fn (_ r i)
      (Bytes of-list ((fn (self k acc) (if (< k 0) acc (self (- k 1) (pair (if (= k i) (^ (Bytes ref r k) 1) (Bytes ref r k)) acc))))
                      (- (Bytes length r) 1) ()))))
  (write (list (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) %rs-h %rs-v15)
               (Rsa verify-pss %rs-n %rs-e (lit sha256) %rs-h %rs-pss)
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) %rs-h %rs-pss)
               (Rsa verify-pss %rs-n %rs-e (lit sha256) %rs-h %rs-v15)
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) (%rs-flip %rs-h 31) %rs-v15)
               (Rsa verify-pss %rs-n %rs-e (lit sha256) (%rs-flip %rs-h 0) %rs-pss)
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) %rs-h (%rs-flip %rs-v15 100))
               (Rsa verify-pss %rs-n %rs-e (lit sha256) %rs-h (%rs-flip %rs-pss 255))
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha384) %rs-h %rs-v15)
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) %rs-h (Bytes sub %rs-v15 1 255))
               (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) %rs-h %rs-n)
               (Rsa verify-pkcs1 (Bytes of-hex "00ff00") %rs-e (lit sha256) %rs-h (Bytes of-hex "0102")))))
```
---
    (#t #t #f #f #f #f #f #f #f #f #f #f)

### a 4096-bit key

```x
(do
  (import x/codec/rsa)
  (import x/codec/bytes)
  (def %rs4-n (Bytes of-hex "e73abd38e09acca82795b15a53590cc1e50ccba2776830958298f5da60c0153ff3d1106f44eb52a7755617c5a2074cec3a763273b1d26ab2ea1b9668ee942cee2f6f18d08ebb65b739734853c0de90c79f1408baf18b2b3c106d5e3caaf4fd85432b02fc8e69ecdc5e3da563c6fad1974f2ed3501d79c78388287bde6f9c31953bf5e434f1becec9396ab3208df5cd4ef29c3a859fe38fc45f15c51ca1d1af2875e0ae82e9923f7080e98fa4704c226d7b011058309588d47e623c6325bdba59b39befbb7ca5f8524ef550fde6cc1f8b2dd59ee284bc475c5be395e623d25363d82983b2a53988226a1854e2c7f1f783e15e67f879af656bb93d3b0ef75972e50de81c59cdd7461042cadedbcc3ce2c56d5315b71c30fcdf7eabec6f25602ab9cac50da3d465b569171f435e8410c1e5e0237f8bd232637e2035bc9bfb545e3d1c8d1016c7a8c369c1392a60db6f5041d1d89621f4283b01e1507ed12d987081e64cde87e3afb2326e8ac79a04f8d7c1be7286ac251e29ed20aaf9a18ff681a5bb654e571acbc51e5d01b6135daa3b0caba32a6654cd0d7129f8e60d8651c230d8c92607ceb913d60b10d4c7f109fc8ef1a214236a47361ed8c7f5f7f4830cfbd4a27dbe310ecb7a3164b2963359ea9b88acab86822c4c0fc5d0ea05241dfa0243106bf3533e8bbf7b0f83bec5d189f587b69eb917f47ffc2c8d02c3c5e1a6d9"))
  (def %rs4-e (Bytes of-hex "010001"))
  (def %rs4-h (Bytes of-hex "647b29271b96d1c1183c25f88b2b6a4667576d6872fcff0bff65b7bece3e9288"))
  (def %rs4-v15 (Bytes of-hex "bea165e0bc9b789f78d2d9d9d18603385ac07224a8e63c3ba7631468ffec64d5e0c0d33212f52e0650a685a50d1d858617c50a0d5e6abaf6b659a9eafdded4fc3ef71c8c80126e350a515c2ff302200f2936ec70df2581c5f7de81f0943509a62eb9da1bf42147b8e18c1da5a275acb4a90bca604d8204a6d5d32cab7c7c6429ebd7f56901ea02a65a9183a4de4328eca2504595c40a641f8cf01e7ffe676c22ccb13290d51e27f3e78bf4e794846f711519e9ce05e130fcc908c48f86431e8905b73cb09944007e7ab239c83ae48547e4c6f5ae790103aa3b5a6d9b5010e1f1fed16bbafe2dcb6455439f66c671529e081820bb79bfcfb38c211dfeae5dff36a73e26bef0fd6532b4b3f5ff8f616383dc777f0d3c3e99cdb78b805708a6b5dc3ac5afd8d131e24039b46157fc7e0c9902685f98e4071bc0bc1b37dedcebdaed4b2a4cb898ecf5c31eccfdcdd480a3c1081738e53ab1d1db6f6e03cea8c1d68defd99269a926976128247281b4dbb7d56584e5e0ad0f1f76b9ceeb3191cef5b408dc31aea2506a5cec306837566e6fa64ffd6558f8d9a29021bbbe0f4d610bd182f41504376b8b415f56da83ec543211a067d93ff4daabfc957fd34426a69999b25ea2d5a46ff51ea8a90f984e2ab90261352a29f8797ab3359de6bdd1e52ee795e1201abebb6490e09f90654f5d5788e031779e5522324c5357beae7220f83a"))
  (def %rs4-pss (Bytes of-hex "1b78d9d528eb1b86a67d1b406940c7846fb7a807d6608c3a3c91dca675d4156e7e7f820b011becf8f40e7fb736e5bf3dc2fb1999c2f08d9779048ea684cb5683f1a6c079935242777a9eb4a4f4a8155126c0fa36c3b3ad2d1022b3796eff3c96e47caad163d45f3768b41cb97363f957ce3fe3ec1c81b689999e4f10707855b1f19d7a2faaf8f77f8d9dba6765bc64b96a423d9538398dd923a7dc5c6c2995752bb2f60b5b72b1db9754c9b68597427f6db3ccf17d15e13ffed7fa4df05f1c4a6e49efb36210861b5c0083c616116593f1e2274bdb9b943c9b17b8f1b9f98f2714fbb62f378c573a2b52191726ce1ffea0cd6f63796eb70e57130dba1e19237cac3aa56bbcb36cc4aad5e052f9835fa38ca0d05f6dc14dbe301031d63e8062533aa2450ac81d8c827b4e443af79a307eec6d12baf409a2f959283c460ee67bf14520fc1dd8ea3c1020a29e469b1e00b0701e98ae735942761b75d991ba5c930ce10c9451473edeb9e9fbb4fa533729ed129603b1e0e24b20fefbbd16318ee251fb903f932b579ad7ee2d96bf0a9cd30b50a1dd471fe90607867cc30601db1c424246253eff0579c7e28d004efdfe710989de3d7f48f2a210a9be0e26380bdac2985ca1751ef4440cb706ef6b8c2935e978445692903efc1b412ad18a4a35663dd273a245d069a97808e87f2ab8acd6841bbcf11b4d9c0962185cc306265e983e"))
  (write (list (Rsa verify-pkcs1 %rs4-n %rs4-e (lit sha256) %rs4-h %rs4-v15)
               (Rsa verify-pss %rs4-n %rs4-e (lit sha256) %rs4-h %rs4-pss)
               (Rsa verify-pss %rs4-n %rs4-e (lit sha256) %rs4-h %rs4-v15))))
```
---
    (#t #t #f)

## signing

### a PSS signature made with a 2048-bit key: it verifies, a broken one does not, and two differ by their salts

The key is OpenSSL's (`openssl genpkey -algorithm RSA`), (n, e) and d as
its PKCS#1 form holds them; the digest is SHA-256 of "x-lang signs RSA".
A signature made this way was checked by `openssl pkeyutl -verify` with
`rsa_padding_mode:pss` and `rsa_pss_saltlen:32`.  Each signature has a
fresh salt, so two are not the same bytes.  A signature costs about 1.3
seconds: d is two thousand bits where e is seventeen.

```x
(do
  (import x/codec/rsa)
  (import x/codec/bytes)
  (def %rss-n (Bytes of-hex "88abf0be8db1b0f6222824bf309319582db9942997f7dfbbe0625b0b42cf038031be79551bf366754d43cebf694cada865cfce8e137e4a000f1a6783be854abb8e4ce1e717ef29e289586a91602ac523067438ce45df7e5534522e1892db6a79adac07b27acf727c56d5dcc7fa71cab54b35d8e16b28d9e2c3c3ba6cc3b1a76bc34df5aebaadd3e28d8fd5bd2641fab5e1c805b1e10023769fcdbb235f1441c20f66dd97063f265b1e2df3510a6dbbb0ca598cb8c67d63e991a0a72ea1d01e9f0f0d5fc6f13ca1e049b9f631adbf87f39e23844984c9bb846df48a4f5e608072b5c6ea9325d47d3cc32a3d40e8510e6410f4a9b78b0f72ba549c24afc37369cb"))
  (def %rss-e (Bytes of-hex "010001"))
  (def %rss-d (Bytes of-hex "43913da3f74931c37d7f7b2b4a486eef392bd623fa0d817ed09fcf82f1b486768a2130baf2e69270cb920a54772a81700f657d28a05a7f1b285c5570bc700952503792373d8def971f6fa6bfd85b4cbad426012f793bd4a92b04b5e55035499e7e4dde404e96e072b83b62bb3b05a6c19a3d34cbbcbea579866eed6b78140c40717412a64eba4ea4c85ca3fd5b97df03631d45f482964d600f8e836150ed7a27c07c1203cf0fd3c21d7cbcb8caa15a283f992e3a1a41103140cc582084f20fce3e9c2ce38344877ecec78a2bbd7b045397b0c471217a6576a295863ad130e7332f75f00ff47bf209d06297856719cd8134cff16674c117cbc75950094976cf01"))
  (def %rss-h (Bytes of-hex "f8195934168616f8a1bee229c8009dc0c69edfc72a405806af7b6af41526ddb0"))
  (def %rss-a (Rsa sign-pss %rss-n %rss-d (lit sha256) %rss-h))
  (def %rss-b (Rsa sign-pss %rss-n %rss-d (lit sha256) %rss-h))
  (write (list (Bytes length %rss-a)
               (Rsa verify-pss %rss-n %rss-e (lit sha256) %rss-h %rss-a)
               (Rsa verify-pss %rss-n %rss-e (lit sha256) %rss-h %rss-b)
               (Bytes same? %rss-a %rss-b)
               (Rsa verify-pss %rss-n %rss-e (lit sha256) (%rs-flip %rss-h 0) %rss-a)
               (Rsa verify-pss %rss-n %rss-e (lit sha256) %rss-h (%rs-flip %rss-a 200))
               (guard (e (Err label e)) (Rsa sign-pss (Bytes of-hex "0f") %rss-d (lit sha256) %rss-h)))))
```
---
    (256 #t #t #f #f #f 'value)

## Signing, PKCS#1 v1.5

The key is one `openssl genrsa 2048` made; the signatures are what
`openssl dgst -sha256 -sign` and `-sha512 -sign` made over "sample".
PKCS#1 v1.5 has no randomness, so they are byte for byte the same.

### sign-pkcs1 is openssl's signature, SHA-256 and SHA-512, and verify-pkcs1 takes it

```x
(do (import x/codec/bytes)
    (import x/codec/rsa)
    (def %rs-n (Bytes of-hex "00a4b1e88e6909214ef263b666781145197fbd128700f260ed4cb7f55d6636243d9c0b8faccce3cc75ad0c1511f68f99cb560a343c0904e29e694e550e7a00e708f029af91892d643641d01815ecc45b41e99152f54ef2d36675e0ea8a119b98f01f4d7830ac9cb3e8f8e5e6ea1cba3e257cea41935d15cb0e8969b3370b616e4d7c60ab3b104ae47ee755f57273514610a5fd56b23e4dafbd7f98fbf3ded033333f6a66c688bf89966827e13eb90b72b551aa4fdedef7f08a0b1dab68ffd8b48b3116c6d66657b2184b275128a828e9b6ee8bc2b382f1a813cbe79fbe9867ad724fb9a842539346863510c535aa4d0163e2b9542d327f58372ede6c1b7ee87981"))
    (def %rs-d (Bytes of-hex "41d97e65de5a4fae8c9cd0b3b4c316f1449138e4b0bcb88378debea4aaf6efd3905e510262e39bfedb034f3360f576a505d04ba54b67e0223d719bf18f576808bb59b78085ac17fad7a297d6c0559c3544e99d95468d3178309e8eb848a50167d4e4392fa0fc80b4a03beff1602e19260d056ed5b86cbbc522ad180264b2fe92296edded67337c7a43ecf0fc508afce388866a9f1c480b7ab65b9e5f45a20e14b9d27f94eafca7e33b25b37186e20d324594c8f5d19aeba3c1e732bd0554924546bd7dbdc3cc1721a3782ae0629b1a8aead590ca39e4f3078e87d9fe2116555461ed5df635588ae1792526f5879fdb072c5898e4b18d71edcfaaf670fcb63007"))
    (def %rs-e (Bytes of-hex "010001"))
    (def %rs-256 (Rsa sign-pkcs1 %rs-n %rs-d (lit sha256) (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf")))
    (def %rs-512 (Rsa sign-pkcs1 %rs-n %rs-d (lit sha512) (Bytes of-hex "39a5e04aaff7455d9850c605364f514c11324ce64016960d23d5dc57d3ffd8f49a739468ab8049bf18eef820cdb1ad6c9015f838556bc7fad4138b23fdf986c7")))
    (list (str=? (Bytes hex %rs-256) "2865b740aa9c7fd0b87bd42cfc91dc0e1c9488bbbb5b14c92f62ece17f81b5b7798fc8b86cae108fccc63e1ca6a56388ded26c97ddbb6035de0b89a6f59d86fbd8321934584d46fdc09b2d0af20bb320d4b3f66b143514a4294201e1a92d666953becbf96993b61eadfc701a87862dedd4f806a248d45c17a21bfa58b5b040f04f0b766659503f73df405fecd6c389f8c3ffc7d743b87d66ef3fecd47e52934feacbd956ee2749c6a3cf7667f55d113d56a079d4926d433a7b08b8e5d9dee47555b14093493d6d22946bbc26ec34b3e235ec2f678065289c976464f08b6133bd011e88dd31ef3dc12e79be1f5f97ff2b551540e7278bb53f6d9e48603f5e9929")
          (str=? (Bytes hex %rs-512) "3930c217d547aacc30067e6c06ecc67faa9a90eddd423f7437e07f6277ba37c25a0190b367908eaab0220e51e8369998e71a7e0f938fa9cde629b72420eefe946e5efcb98c65458af2a27ecb820cfbb60b0cf2cfa8be20da539b31352adc6e94a7e0942f35aa75101686c4ed80b99fa28b42b98e2e1cf99edfc4dcc507055e123b0f94d594d07134ae3df654968a3631c182da3e7cd8eaffd40398cd248ddc9a7f4b5b24d9ce50c5400510ba5c65d24780c65c43d43a119f4140b39ab5a7aedad4b8409d79cee0bbe2a80cce8bbbfa4debb8137136c486c5335849947d324c459c908c8219ec8859f993d5efdf3eaeb7893109454669c871978052dad1c86f24")
          (Rsa verify-pkcs1 %rs-n %rs-e (lit sha256) (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf") %rs-256)))
```
---
    (#t #t #t)

## Making a key

### generate makes a key of the size asked: its primes p q, d inverting e, iqmp inverting q, and it signs

```x
(do (import x/codec/bytes)
    (import x/codec/rsa)
    (def %rg (Rsa generate 1024))
    (def %rg-n (first %rg)) (def %rg-e (List ref 1 %rg)) (def %rg-d (List ref 2 %rg))
    (def %rg-h (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf"))
    (def %rg-sig (Rsa sign-pkcs1 %rg-n %rg-d (lit sha256) %rg-h))
    (list (Bytes length %rg-n) (>= (Bytes ref %rg-n 0) 128) (Bytes hex %rg-e)
          (List map (fn (_ r) (Bytes length r)) (List drop 3 %rg))
          (Rsa verify-pkcs1 %rg-n %rg-e (lit sha256) %rg-h %rg-sig)
          (guard (e (e msg)) (Rsa generate 512))))
```
---
    (128 #t "010001" (64 64 64) #t "Rsa generate: a size outside 1024..16384")
