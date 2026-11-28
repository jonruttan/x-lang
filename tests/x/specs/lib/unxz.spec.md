# Unxz: .xz in pure x-lang
# @weight 3

The decoder is checked against streams xz 5.8.4 wrote, carried here in
hex, and one built by hand from xz's raw LZMA2 output.  Each case answers
the output's length and CRC32 and the input bytes used; the length and
CRC32 are the plain file's, as gzip's trailer gives them, and the bytes
used are the .xz file's size.

## whole streams

### five bytes, under each check: CRC32 verified, CRC64 and SHA-256 skipped by their size, and none

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (list (%xz-sum "fd377a585a0000016922de3604c00905210116000000000000000000bf792567010004616263640a00000000aca48a5800012105475473dc9042990d010000000001595a") (%xz-sum "fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a") (%xz-sum "fd377a585a00000ae1fb0ca104c00905210116000000000000000000bf792567010004616263640a00000000fc4b5fd6816f75a7c81fc8eaa9499d6a299bd803397166e8c4cf9280b801d62c00013d051a09043a189b4b9a01000000000a595a") (%xz-sum "fd377a585a000000ff12d94104c00905210116000000000000000000bf792567010004616263640a0000000000011d05b82d80af06729e7a010000000000595a")))
```
---
    ((5 1485481132 68) (5 1485481132 72) (5 1485481132 96) (5 1485481132 64))

### an empty input's stream: no blocks, an empty index

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de36000000001cdf44219042990d010000000001595a"))
```
---
    (0 0 32)

### lp 4 and pb 0, then lc 4 and pb 4

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (list (%xz-sum "fd377a585a0000016922de3604c0bc09fdfd02210116000000000000a1969df8e0befc04b4240018884be74744a6b31e9ac72082d0e1da270f5b751584f506576d8d33a92268131cb38e2b38ba86c3cfbf2aba079cb800fde0d45bc6d865414ca3000756f0492603bb6a7f557d23b98e16142c77b396823c05d256d2129a304cdd549699a32b6cf7b241b34787083cf881c3cb56e73ad7cdac06831cb2d3882a5e4177bf7a4fa92e541cb12f9d7931a47af60ae05e3aa32ce961eba6bcd52a47bc8c4be2a50f20020212d0168eb3775e7166f97990d105c91ad07fe6056ec06bf43efa634da4cdea1af68e7f64b31c0bc74c020ef65296a8604cf49da17a72ae6d83f2b28386dc290d0f90eadcbd29cf30dd51159bdf1b1433cfd9c54fa0e5b5ba5d17cb4abf76c0ea6c3952f1b51f5875ecc4837ee628777ceaf7b681c01747cbb0550cf29804e881f3121f9489d0ff4afce6c69f5806be1cc07b29606f23ee41fe90739dc1dacbf084e05baa080a117d3520a850e8511bead118249747aad6bb56d4499f58a4c594918415d1a1669ccc56b005fba6e982c2c98c4442e4dc0c85a7d6c97b672a42f6f2ca281c7ffbc8017802f41cab2e59d1bf0bc15282d35f021e079ce63c82a2addf409cfc833035975a02811ca09611b4ef054798fb512c373beede2313bdcd3db48133969e5d03acdc2d73113f10f0bd927bbf84a2226be5af79d5a67b0c7034606830bfc0ff47d12e618894f07b508fe1e4f09b78c7c4c3f15144af140985aa81baffa53425e26fa1b9a2161d593f4427fd58a316b2c5fe109288cbf87fd44d67e46c05635ee6ae8968753a11ece9b1a8f3cbb82678c861aca3a322a9dd9b6d227a2e3a7605784d2b55437e2344e978d076746e7b475243872a9aef240a14dd3ae8a529a9cb3d23c4a67f094c8e0563add2dfd40cc82a3b50a495eb6301e5231bdb9c7a9babdc77652d6e73de409a2f341d63f1510f92f089cf4b65cdf377f519a1490cfa1758be4b314cd4bc6968b996e8aa6cad8ba5c144cd46849370bc7effdb1d488eb42e545ecd731b23f3487a890bb8c173b54952b9ad42ec4fb56746e6d360ed2570380d91689aec841e5bdba7d9c1f1e52e91a1a0eaec4572157b432a1faae22cc0e55de70821d06defb997cd5d182dc49370cc48481e4a7e70e2dcac916bfa824ac3830309f74486b0d2b4f6037501fed7a683dacc6fc8a8bebc6a7ebe7d16ecf6b5249720bdf07970d4337e00981c4dd39a0edb82b9ab9d819232455f4264e0e8a531e4c78c4a69c68b9e918a0b7494d169a7baeba17806b3711c058620b5feb5df5d19904dabd2b480f0dde7431177a4e9e40c806d2e1fd6a851382f5b15e5f300c226100a4ac7d9ca7ea56b910f8985f64e4bd2a13e97cf47c34324f7ef566129e763c59efa0b04a81724b41742410f800c5eb8ead60fb5b93714528f2fdf6b71710a5cea1b642ea36be93b69c67048999bb36487613453e7ab9111285d71670a25d9be05667fca87a2e883daba46768a95cb0ca81b3c26fb1d26991177bfbc7c7f9988cc512fa0f594ef2368e38624290ee16b5f9c89885424a5433eda48cce1988f9307e37189c3452e315a5a216311cbfa941e08bbb5ee6d37c5d54e6541292f57a9b884de81c40fce046840f1938f854029f4b34729a349f7b549ca88afdd8487946564f9702fd51f5700878925544d90e811f0f90e1f9a8975189c28f7ad4dbc50a26b0ceab5708d4f00bb25ca8b0001d409fdfd0200eea4ccbc3e300d8b020000000001595a") (%xz-sum "fd377a585a0000016922de3604c0d80afdfd022101160000000000005dfa26d0e0befc0550b80018880a86832880c65f4a8412b36463f8dcca96deba6cda616c34cf8cf7e66951b4cb84ab6afbd6e167d8fb273b16bf6a0169a866783c35b0f0d774cfe75170c2c08cea7e1fec6f3d6e24082fb2b1ba3417fea20b6b60d75d6100a870750ab1d43dd537869f559541ae4eafc98bad5e40af381cce1fb8dec25b9ee19bf002b318c11e9697bcf0e15332d3371f473331595c42877078013a58d92b715349d3130c3e56f9b85e7739a6c77d0ad7bdfb57c4858e272a3d583b3fa982622d233e7b95e8696cf4109defe6127f072dea10130ce707e5f03f8ec7223cf535d6151a0c3b74f8e4955ec5a814baf58c9cb0130e8f37a9f84c96af2e23711c3068216604a73e278efa83013fee724fdd678eb627ad7465d0abeb9683e8fe3423b93ae836addffb0478690bf5f9632d8322ff466c3f8eb8de9fd200984ad378d6be256f34fdb8e1a8b24b3ebc6f3e75ddfcda25a48091201b46a15c34f336e4e6e41cb2e0577a9da9f262abdf0b2971776c2b18477f749115ec7d5202057a8c0fc0daa2c7f5e21671e0d3df89c20558c6d3c08a99f67abb7df26dda106ef3a2127aef72e07111c3bfd3766e811b60a9128abd73752f0093143dcbd54d7cb798006161ebe14014bf315b62222ea6915007b780f13af1ba4c444b6340feb4a115df819a1d5ce7b79be32c419adbae46d5fc41661e07b9fe968cebef94d81276e51c4ac550509f179fd8e13424c4bcd497be846faa228baf36f08a53f277d4a16a3f028f3cf31207c0d7a1bd990dfc3411902cec53ffc99404e0f1be0fabf70a5cbfe50d48d2da6f2eb6b2558203995ffd456f1518edbedb00cbe3c76173485f52f5bbaba9a8405e28432f215104d0f02d0ee1dfe2a44fad552bf9f93cc77e3698a447b0c12d2823fd82f47c2112866f3827b5741117f8bfe98a7e488d9c64a989469b65cfd3972375365f0f692dbb7be7bbe268d19793f454af0f5e2f4843c4d7d39885e999889cbc104481fdfa3baa5975fe6ae5797d55a05aa6584018b753393226669ffdfaad90234240ed03e2498eb8b965c415b1cf2cf25af18fc027be22d98bd586a07a80afb53c7a6771dac7cd91fbbccfdc738d1fe149569b013b4e9dc1db789d34e70dafe0ced09d8b24186f2516e1b53f3df2814b383eed10d44e548dab489f190a525bda1e744b7bed3ed9e2af1e4d5aabe6038fa05dc67ec88cd51ed5f19b056aa04b5072c92f6e10e8a370b16eba9bf4b017cc272a8e806f182cbba9216a9e100aceac164044a514de000b5da56464f8cd2194c24aa8c5cd7dbe88e0aa9f10035977593cf36f9dadd3575b250293e91e3cde904b1b5e9c5318d6f9641db796a029e61ed74105729d5e97d9e5a9a675ffa7cf7bb098d38a82cc598b41245677dc5fa43f0709c2b7a04c1c3f9bca35e9b99b73d4d8a99b1f2ba274aff7d63d2f7350dded31845eb4df0f1e3eb249efe2f9dde75ab5a2c23dd2f33249e8c95de9636fa1c0bef05a0b3979cb96043b27d30aa555bdeee8be86143cf1beb6262019cdede9e32ec92deeaf1937a1fad5e01fc0331db95cd8ef736d2f6dcbd2d13d51aa02d334c55981a3e0b09510726e3712d8f2c1ecd43d4b6eea5c27f9fb60ffe55da7a2d6332bb7a0a26f9c5c66877baefb6fa2c3b23ae09661140158095babd6421cb9f13369ff63570f40fa4c90dcc3a1972c2fcee857c87dd9835ec5f73f44032eb1a4d440e7784267dc6860c2ce543660cca2f8c7f8def0eca3945b850290c2877d3e391e1f9161e5111bc372a8411e90dc0c063b32cdd8f2b4fa4c54f4bfebd7870c282cfb9186098feeb95cb9159181618c2f1e9b1896a32abf7f6afa7d9c20760583d6db7cecc503ec603702e09b9ef8ac7a77fd03128d6ae33b9d3ae5c1f1a751a4b61a608f7873d90fdbeadd9200bb25ca8b0001f00afdfd02001e9951673e300d8b020000000001595a")))
```
---
    ((48893 2345280955 1272) (48893 2345280955 1428))

### a 4KB window under 48KB, so distances wrap

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de3603c0b609fdfd02210100000092efbbeae0befc04ae5d0018880b06e1ac68b91bffbf315819d54ad6135425aad119bb8547c9842e9cabe463379039d63d66c278f44616096ec62d4ce0152705446bb778e85397df8afea67b3ba7374b7a9da45a0411f1da093ff383acbe904148e8789e25486c330b13018b715573a09cb6d06065c8524f88f8c33b9d4d93f27d7e8296c564c3a3cc1f3b6d206e5f044d4e15a77fb5dc38cf82a29a98b18ef493a16dc29aae652c36495746dd225259ce00f3b4945c6332b8efc33e1a8ee30609c494774dc278a2ea8d140518c98718b83569aacae8ffbde2c777dfb83cd9e99656d5fb6ead4438eb076158ca19df60988fbb00e88c779c684d28541dd06a899a99f5c1d4322e1892bdc6c4c940824153f25b5b996e3828a95170a73c530cbb9fc502431cd51ad5df77678b79250359ac81c28ba993c9a1f99b089815feea38b09d68e698cd9b04c639a41d6a76cc7f21ab41c6174c114236bb11b4f7b7ef9823ef4e47d53988c83b419d2a498378f145b807efcc8f70c50623ce82d4f8032eefeaf5aa166b8e27b7403d6cc85b65636e1390f67f1b1a25a5f8dbfdb47a707ca9c06a9a7a35a98163ba7e40ff717ffdfb1fb9805b4865295b64d622f18962e946a35225af014b3f28fa577ab57466dffa1cf556154a7f49d6984f828c4f3a08cc6371b74a4bd422108a5a07c4ca4363af38b71a016f7b2bd18c2e9d84eaa1c50a41c984fa4974a1a99130e60a9caf8a6d31ea5c69d9ace61b84007b28ba2268d9f18630240972f09426a529160f6d38b86acce2c0c8f241487405c8c519afc6fccc6c3a95168069f5c4008416c35a4602d4f29427e89fbe86a3fd4d57b51b393dd3b34efa2151642b74de6e2fd31d2e8d61b3b4f3683303f21f8e5eb63105fae70062d11b41a13c58027973179ec8d273dc1b8f30b7fb01fee7d18fd526b7990c4a3277f6d92e6d609be760aee0b53a66fe875999eca1d199ec7db3fc549ed3542f27ac61e8e13a51b92c26ba24ce2f589352a41d02cb572f686cc0bf29f3da4598e92a3f46c1c524f8a267fbb1289ea5d1e9f2ed161fd77746e32ce374bf445d09a7e6de9cc42a1f707251c3882376c89373be08d69569229af211c4bb295bf9d4d76d8583fa1589c58180ab39d0e1c771325ad3152997c76b1d32e4dc19cf29bcebbc02574a2de9add414182980bc9ef796797c7e238c06e75be86e9bbfd994b59b084039b64b36539dc4a1ec9caef52ec0283d2fdde63fd099d4bdd2130d2b64c3558b65f9407d7ba9c02c17ea2a4695e755285f54709f24c479fe685957229d9af912e7cbb51e568816dfc7f17f30aea71e276fb746e74d76fac55677a44b6c74ffbc18ca56900a41deca6f93a43312bd91dc327ef78255489c0768bf04be7772e9cb1724a5a516d28fb31a45d954bf2a7658e685eac0deae6e7059f7b0743fec0db6c45067b02a0dd94f338b6ec146acda8246bfe98b763f1d1c8d4c5358b381472f4e67eaabe4d016575c14fb8123d506fc01dd70d523eb092497debdf737a91fc3e50ee022e188490b7e81d6b9702f58bc939f61ea0091583770a9dd098478b54c7eb52626fd4ea74bdf45ac5de204423149f7cd88da0e3928c275952215d1051b6fab3be599a9ef91524f4642a32c98dc81da8c73cb430b4902bba42853ecf967866456b19848b082628fda3b80974c1ff54f49e3000000bb25ca8b0001ca09fdfd020005c710853e300d8b020000000001595a"))
```
---
    (48893 2345280955 1264)

### bytes that do not compress: a chunk copied as it is

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de3604c0b002ac02210116000000000000005096afdc01012b2adb293c7ad6403e0c31f93aa8dd25ee68b273fc5e0909ef1e7ca7d2ded09013ece6018791f7e76fe8ac825f601fa18fb60d22553d7b415bfcfee933df54dcef435b910c737ca51cc24c06d297c0995ad2209e387dcaff081573be0fd31a40fb3196ab1482193aa433cc13cc258d799a562f83a8b836727faa983f2326e904a0c4a458be173610657cd75d8bdf566532788cedbc3cdfae226e68879bcc3c32894f8c68c926d21b9149d01b80324f88b7b646d93e5eb527f1188cc07d81104dd5cdda1ff3c859f3dfce70900c5f5dd39d8656a5da8a5f4d90e47903afc1ae177165efc3882e4f7f72ee9324f88f0eaad6d19cbd69b020d63b9b20da01e9ac315b31c54938f04744dd931e5f5aec04d90c04c87c568231b1b4787b3980870c00e8ff289874236360cd24b78ac60051fdad860001c802ac020000b76917403e300d8b020000000001595a"))
```
---
    (300 2259549521 364)

### a copied chunk, then an LZMA chunk that sets properties without a window reset

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de360200210116000000742fe5a301012feaff953a4f1676843805bf580678c324a34a08fd70e65f75e40f76a62ccf0e4247d9e5fedfaa2dd9d33986d3bb3e748308fa397f71ded8ed1de3213732ae55d2823852f6b952d7fc2607fbf9251b9aac0a8214332ef881fed77d22eed9552bf429480c29ee9634d33fa1ab9e155978d1b74dce440e0f48a167594aa01eb1c238887bd1d70fd2bba36238f380f1bec73bf47dcc2f957f0dc54b97e3c2a93bc00bea047f0eb89f45be402ce46dd7bbf4c265ef08d1c6a81c29ca444117db74991d04b26db0acb27649ac39f38c3200c7c56a3d24aaf1e4ae189168ff5bcee3b7845071c9a174da9f949b00c6c8812900101b81098eb0ed45f9f077f423078602701c72885ee93e2c6061f6c7aa16f186380ff06e7472c3aa903da831b322612e82108ded806aa08f8cbaa6155d3efe8f9ec007cf0099000018888dec31f30c9851fdfc5cf078fb4a349fcc2688cf6668da72321a95d152ca21171449e407b55ddc4e0ed2c633cd910a01edaeaff066487dec2550dd4473f80120b912166589c28edc6dbdf1086cf96304d0fa7098693c0d7d33cfb67562a30a65d462956644638b6e9e7144235c41d178278acf64643c45f2618a55816915fd8197a3928927180ba3e52089f531b579a4e49b78ec0385fa00ef8011090001e40380120000bc36dbfb3e300d8b020000000001595a"))
```
---
    (2304 152142063 520)

### three blocks, each its header's sizes

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de3603c08101e807210116000000a9b92ea2e003e700795d0018880b06e1ac68b91bffbf315819d54ad6135425aad119bb8547c9842e9cabe463379039d63d66c278f44616096ec62d4ce0152705446bb778e85397df8afea67b3ba7374bac99017db715288f93c95d93201e4a2a01fe197abf7fbeb1c36541290f3bcb08a8e98e6573795e40e09d35eef00badacecb47000000000000cb71ebd03c08001e80721011600000097d2ec4de003e700785d00379dfd42f0150118d96d79b3f55d3df1674aae1fda8ec2a217a43985457906d1ed30dcd40c826d250c7d5c8356bad925cb032d9643f932e8ebf6f88cff6d15c028bc2bdb6b140278e4d0e44c1a4d3f8ee5a16c67560b62d432ee5c2271ecd289fbcf507d38d60885c1f0acea4ae8aeb7828323f91dac95aa00376220e303c07de80721011600000000829f4868e003e700755d003a9a488dccfa75ab2c13c3fb049465a995dc14c455086686fc423c51873e5629af35a3f55499675e6a6976aa3de6578a36f5254d2386d872c141c7c0c98502d5185c36090e8fbadc174766fddf706f5819fdae50a0cfa945403b1a7aecbbc4dab83a2c75595acb2df327ea0b828d8486276c951500000000008c10319d00039501e8079401e8079101e8070000518ae79123d3545d040000000001595a"))
```
---
    (3000 1546884033 492)

### 3MB in two LZMA chunks, the second carrying the first's window

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de3604c08a04c08db70121011600000000008a7faffcffff1b01785d00309888983ecbe26f34b348e2e7e860978e8df32b881c6cb354a323f97adcb7f753a44fbc3c7002e0b51e50f9f872b37f8c4179084484609af27fdf4ed931691d058274cf91e61ed6ca5e7b441e75e50c06603140b4f10f893c9dd1ae6b79b66936065973dfe1c8fe7921b5a8338f62847d5a51629274495cc46db292e7a0c8ce0704ee9fdea542cb883f5c008fd04eaf262894711f3d8f24e1709ea7235fec28cb85d195988a7e2a91f22775f719c006984d98fdd8afd5900fc42553f8f591363105a5b0ee6fc1704d470cd19111aaad601dbaceb127185c5986e9665258bee976ac59e4e55b0508f9c7daadfcfb522b74cd1e5b2042f9dd533df82964093b80cb2a6cdfb53bf0c4bd2e5faa0f3e4b664290130eff1093f8717859f80bcdff9528460fa9fc7cdefb9a302e56c08f85f38381c065c42553f8f591363105a5b0ee6fc1704d470cd19111aaad601dbaceb127185c5986e9665258bee976ac59e4e55b0508f9c7daadfcfb522b74cd1e5b2042f9dd533105b4868dc7a3008400ec7353a7fdbeae7c311a9fb78d316e709ea7235fec28cb85d195988a7e2a91f22775f719c006984d98fdd8afd5900fc42553f8f591363105a5b0ee6fc1704d470cd19111aaad601dbaceb127185c5986e9665258bee976ac59e4e55b0508f9c7daadfcfb522b74cd1e5b2042f9dd533df82964093b80cb2a6cdfb53bf0c4bd11b93539000000008feaef5e0001a204c08db701c4ac22213e300d8b020000000001595a"))
```
---
    (3000000 1592781455 584)

### two streams, four zero bytes between, then a byte that cannot start one

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-sum "fd377a585a0000016922de3604c00905210116000000000000000000bf792567010004616263640a00000000aca48a5800012105475473dc9042990d010000000001595a00000000fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a58595a"))
```
---
    (10 2979271011 144)

## a stream fed a piece at a time

### 7 bytes at a time, and 4093, as decode answers it

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (list (%xz-fed "fd377a585a0000016922de3604c0bc09fdfd02210116000000000000a1969df8e0befc04b4240018884be74744a6b31e9ac72082d0e1da270f5b751584f506576d8d33a92268131cb38e2b38ba86c3cfbf2aba079cb800fde0d45bc6d865414ca3000756f0492603bb6a7f557d23b98e16142c77b396823c05d256d2129a304cdd549699a32b6cf7b241b34787083cf881c3cb56e73ad7cdac06831cb2d3882a5e4177bf7a4fa92e541cb12f9d7931a47af60ae05e3aa32ce961eba6bcd52a47bc8c4be2a50f20020212d0168eb3775e7166f97990d105c91ad07fe6056ec06bf43efa634da4cdea1af68e7f64b31c0bc74c020ef65296a8604cf49da17a72ae6d83f2b28386dc290d0f90eadcbd29cf30dd51159bdf1b1433cfd9c54fa0e5b5ba5d17cb4abf76c0ea6c3952f1b51f5875ecc4837ee628777ceaf7b681c01747cbb0550cf29804e881f3121f9489d0ff4afce6c69f5806be1cc07b29606f23ee41fe90739dc1dacbf084e05baa080a117d3520a850e8511bead118249747aad6bb56d4499f58a4c594918415d1a1669ccc56b005fba6e982c2c98c4442e4dc0c85a7d6c97b672a42f6f2ca281c7ffbc8017802f41cab2e59d1bf0bc15282d35f021e079ce63c82a2addf409cfc833035975a02811ca09611b4ef054798fb512c373beede2313bdcd3db48133969e5d03acdc2d73113f10f0bd927bbf84a2226be5af79d5a67b0c7034606830bfc0ff47d12e618894f07b508fe1e4f09b78c7c4c3f15144af140985aa81baffa53425e26fa1b9a2161d593f4427fd58a316b2c5fe109288cbf87fd44d67e46c05635ee6ae8968753a11ece9b1a8f3cbb82678c861aca3a322a9dd9b6d227a2e3a7605784d2b55437e2344e978d076746e7b475243872a9aef240a14dd3ae8a529a9cb3d23c4a67f094c8e0563add2dfd40cc82a3b50a495eb6301e5231bdb9c7a9babdc77652d6e73de409a2f341d63f1510f92f089cf4b65cdf377f519a1490cfa1758be4b314cd4bc6968b996e8aa6cad8ba5c144cd46849370bc7effdb1d488eb42e545ecd731b23f3487a890bb8c173b54952b9ad42ec4fb56746e6d360ed2570380d91689aec841e5bdba7d9c1f1e52e91a1a0eaec4572157b432a1faae22cc0e55de70821d06defb997cd5d182dc49370cc48481e4a7e70e2dcac916bfa824ac3830309f74486b0d2b4f6037501fed7a683dacc6fc8a8bebc6a7ebe7d16ecf6b5249720bdf07970d4337e00981c4dd39a0edb82b9ab9d819232455f4264e0e8a531e4c78c4a69c68b9e918a0b7494d169a7baeba17806b3711c058620b5feb5df5d19904dabd2b480f0dde7431177a4e9e40c806d2e1fd6a851382f5b15e5f300c226100a4ac7d9ca7ea56b910f8985f64e4bd2a13e97cf47c34324f7ef566129e763c59efa0b04a81724b41742410f800c5eb8ead60fb5b93714528f2fdf6b71710a5cea1b642ea36be93b69c67048999bb36487613453e7ab9111285d71670a25d9be05667fca87a2e883daba46768a95cb0ca81b3c26fb1d26991177bfbc7c7f9988cc512fa0f594ef2368e38624290ee16b5f9c89885424a5433eda48cce1988f9307e37189c3452e315a5a216311cbfa941e08bbb5ee6d37c5d54e6541292f57a9b884de81c40fce046840f1938f854029f4b34729a349f7b549ca88afdd8487946564f9702fd51f5700878925544d90e811f0f90e1f9a8975189c28f7ad4dbc50a26b0ceab5708d4f00bb25ca8b0001d409fdfd0200eea4ccbc3e300d8b020000000001595a" 7) (%xz-fed "fd377a585a0000016922de3604c0bc09fdfd02210116000000000000a1969df8e0befc04b4240018884be74744a6b31e9ac72082d0e1da270f5b751584f506576d8d33a92268131cb38e2b38ba86c3cfbf2aba079cb800fde0d45bc6d865414ca3000756f0492603bb6a7f557d23b98e16142c77b396823c05d256d2129a304cdd549699a32b6cf7b241b34787083cf881c3cb56e73ad7cdac06831cb2d3882a5e4177bf7a4fa92e541cb12f9d7931a47af60ae05e3aa32ce961eba6bcd52a47bc8c4be2a50f20020212d0168eb3775e7166f97990d105c91ad07fe6056ec06bf43efa634da4cdea1af68e7f64b31c0bc74c020ef65296a8604cf49da17a72ae6d83f2b28386dc290d0f90eadcbd29cf30dd51159bdf1b1433cfd9c54fa0e5b5ba5d17cb4abf76c0ea6c3952f1b51f5875ecc4837ee628777ceaf7b681c01747cbb0550cf29804e881f3121f9489d0ff4afce6c69f5806be1cc07b29606f23ee41fe90739dc1dacbf084e05baa080a117d3520a850e8511bead118249747aad6bb56d4499f58a4c594918415d1a1669ccc56b005fba6e982c2c98c4442e4dc0c85a7d6c97b672a42f6f2ca281c7ffbc8017802f41cab2e59d1bf0bc15282d35f021e079ce63c82a2addf409cfc833035975a02811ca09611b4ef054798fb512c373beede2313bdcd3db48133969e5d03acdc2d73113f10f0bd927bbf84a2226be5af79d5a67b0c7034606830bfc0ff47d12e618894f07b508fe1e4f09b78c7c4c3f15144af140985aa81baffa53425e26fa1b9a2161d593f4427fd58a316b2c5fe109288cbf87fd44d67e46c05635ee6ae8968753a11ece9b1a8f3cbb82678c861aca3a322a9dd9b6d227a2e3a7605784d2b55437e2344e978d076746e7b475243872a9aef240a14dd3ae8a529a9cb3d23c4a67f094c8e0563add2dfd40cc82a3b50a495eb6301e5231bdb9c7a9babdc77652d6e73de409a2f341d63f1510f92f089cf4b65cdf377f519a1490cfa1758be4b314cd4bc6968b996e8aa6cad8ba5c144cd46849370bc7effdb1d488eb42e545ecd731b23f3487a890bb8c173b54952b9ad42ec4fb56746e6d360ed2570380d91689aec841e5bdba7d9c1f1e52e91a1a0eaec4572157b432a1faae22cc0e55de70821d06defb997cd5d182dc49370cc48481e4a7e70e2dcac916bfa824ac3830309f74486b0d2b4f6037501fed7a683dacc6fc8a8bebc6a7ebe7d16ecf6b5249720bdf07970d4337e00981c4dd39a0edb82b9ab9d819232455f4264e0e8a531e4c78c4a69c68b9e918a0b7494d169a7baeba17806b3711c058620b5feb5df5d19904dabd2b480f0dde7431177a4e9e40c806d2e1fd6a851382f5b15e5f300c226100a4ac7d9ca7ea56b910f8985f64e4bd2a13e97cf47c34324f7ef566129e763c59efa0b04a81724b41742410f800c5eb8ead60fb5b93714528f2fdf6b71710a5cea1b642ea36be93b69c67048999bb36487613453e7ab9111285d71670a25d9be05667fca87a2e883daba46768a95cb0ca81b3c26fb1d26991177bfbc7c7f9988cc512fa0f594ef2368e38624290ee16b5f9c89885424a5433eda48cce1988f9307e37189c3452e315a5a216311cbfa941e08bbb5ee6d37c5d54e6541292f57a9b884de81c40fce046840f1938f854029f4b34729a349f7b549ca88afdd8487946564f9702fd51f5700878925544d90e811f0f90e1f9a8975189c28f7ad4dbc50a26b0ceab5708d4f00bb25ca8b0001d409fdfd0200eea4ccbc3e300d8b020000000001595a" 4093)))
```
---
    ((48893 2345280955) (48893 2345280955))

### a byte at a time, across a copied chunk and an LZMA one

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-fed "fd377a585a0000016922de360200210116000000742fe5a301012feaff953a4f1676843805bf580678c324a34a08fd70e65f75e40f76a62ccf0e4247d9e5fedfaa2dd9d33986d3bb3e748308fa397f71ded8ed1de3213732ae55d2823852f6b952d7fc2607fbf9251b9aac0a8214332ef881fed77d22eed9552bf429480c29ee9634d33fa1ab9e155978d1b74dce440e0f48a167594aa01eb1c238887bd1d70fd2bba36238f380f1bec73bf47dcc2f957f0dc54b97e3c2a93bc00bea047f0eb89f45be402ce46dd7bbf4c265ef08d1c6a81c29ca444117db74991d04b26db0acb27649ac39f38c3200c7c56a3d24aaf1e4ae189168ff5bcee3b7845071c9a174da9f949b00c6c8812900101b81098eb0ed45f9f077f423078602701c72885ee93e2c6061f6c7aa16f186380ff06e7472c3aa903da831b322612e82108ded806aa08f8cbaa6155d3efe8f9ec007cf0099000018888dec31f30c9851fdfc5cf078fb4a349fcc2688cf6668da72321a95d152ca21171449e407b55ddc4e0ed2c633cd910a01edaeaff066487dec2550dd4473f80120b912166589c28edc6dbdf1086cf96304d0fa7098693c0d7d33cfb67562a30a65d462956644638b6e9e7144235c41d178278acf64643c45f2618a55816915fd8197a3928927180ba3e52089f531b579a4e49b78ec0385fa00ef8011090001e40380120000bc36dbfb3e300d8b020000000001595a" 1))
```
---
    (2304 152142063)

## refused

Each answers the raise's kind and how many bytes it says came out before
it.

### not .xz: its magic is wrong

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused "00377a585a0000016922de3604c00905210116000000000000000000bf792567010004616263640a00000000aca48a5800012105475473dc9042990d010000000001595a"))
```
---
    ('format 0)

### the stream header's CRC32 does not match

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused "fd377a585a0000010022de3604c00905210116000000000000000000bf792567010004616263640a00000000aca48a5800012105475473dc9042990d010000000001595a"))
```
---
    ('data 0)

### a BCJ filter, which busybox does not build

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused "fd377a585a0000016922de3604c10905040021010c0000000000000032493955010004616263640a00000000aca48a5800012105475473dc9042990d010000000001595a"))
```
---
    ('options 0)

### a block's data changed: its CRC32 catches it, after its bytes are out

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused "fd377a585a0000016922de3604c00905210116000000000000000000bf792567010004610063640a00000000aca48a5800012105475473dc9042990d010000000001595a"))
```
---
    ('data 5)

### the input ends inside an LZMA chunk: what of it decodes comes out before the raise

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (let ((r (%xz-refused "fd377a585a0000016922de3604c0bc09fdfd02210116000000000000a1969df8e0befc04b4240018884be74744a6b31e9ac72082d0e1da270f5b751584f506576d8d33a92268131cb38e2b38ba86c3cfbf2aba079cb800fde0d45bc6d865414ca3000756f0492603bb6a7f557d23b98e16142c77b396823c05d256d2129a304cdd549699a32b6cf7b241b34787083cf881c3cb56e73ad7cdac06831cb2d3882a5e4177bf7a4fa92e541cb12f9d7931a47af60ae05e3aa32ce961eba6bcd52a47bc8c4be2a50f20020212d0168eb3775e7166f97990d105c91ad07fe6056ec06bf43efa634da4cdea1af68e7f64b31c0bc74c020ef65296a8604cf49da17a72ae6d83f2b28386dc290d0f90eadcbd29cf30dd51159bdf1b1433cfd9c54fa0e5b5ba5d17cb4abf76c0ea6c3952f1b51f5875ecc4837ee628777ceaf7b681c01747cbb0550cf29804e881f3121f9489d0ff4afce6c69f5806be1cc07b29606f23ee41fe90739dc1dacbf084e05baa080a117d3520a850e8511bead118249747aad6bb56d4499f58a4c594918415d1a1669ccc56b005fba6e982c2c98c4442e4dc0c85a7d6c97b672a42f6f2ca281c7ffbc8017802f41cab2e59d1bf0bc15282d35f021e079ce63c82a2addf409cfc833035975a02811ca09611b4ef054798fb512c373beede2313bdcd3db48133969e5d03acdc2d73113f10f0bd927bbf84a2226be5af79d5a67b0c7034606830bfc0ff47d12e618894f07b508fe1e4f09b78c7c4c3f15144af140985aa81baffa53425e26fa1b9a2161d593f4427fd58a316b2c5fe109288cbf87fd44d67e46c05635ee6ae8968753a11ece9"))) (list (first r) (< 0 (first (rest r))) (< (first (rest r)) 48893))))
```
---
    ('short #t #t)

### the input ends inside the stream header

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused "fd377a585a0000"))
```
---
    ('short 0)

### nothing at all

```x
(do (import x/codec/unxz) (import x/codec/bytes) (import x/codec/crc32)
  (def %xz-region (fn (_ hex) (Bytes of-hex hex)))
  (def %xz-out-sum (fn (_ out n) (list n (Crc32 of out 0 n))))
  (def %xz-sum (fn (_ hex) (let ((b (%xz-region hex))) (let ((r (Unxz decode (first b) 0 (Bytes length b))))
    (List append (%xz-out-sum (first r) (first (rest r))) (list (first (rest (rest r)))))))))
  (def %xz-add (fn (_ acc r) (list (+ (first acc) (first (rest r))) (Crc32 update (first (rest acc)) (first r) 0 (first (rest r))))))
  (def %xz-fed (fn (_ hex step) (let ((b (%xz-region hex)))
    (let ((z (Unxz stream)) (n (Bytes length b)))
      (let ((acc ((fn (self off acc) (if (< off n)
                    (let ((k (if (< (- n off) step) (- n off) step)))
                      (self (+ off k) (%xz-add acc (Unxz feed z (first b) off k))))
                    acc))
                  0 (list 0 0))))
        (%xz-add acc (Unxz finish z)))))))
  (def %xz-refused (fn (_ hex) (let ((b (%xz-region hex)))
    (guard (e (list (rest (Assoc entry (lit xz) (e data))) (first (rest (rest (Assoc entry (lit out) (e data)))))))
      (do (Unxz decode (first b) 0 (Bytes length b)) (lit decoded))))))
  (%xz-refused ""))
```
---
    ('short 0)

