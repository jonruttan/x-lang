# Png JIT engine
# @weight 4

The compiled row loops behind `(Png jit!)`.  They are adopted only after
undoing every filter at every pixel width and writing every layout's pixels
exactly as the pure-x loops do; these cases re-prove agreement through the
class, on the images png.spec.md decodes with the pure-x loops: the same
CRC-32 of the RGBA out.  A layout under 8 bits, and a grey or RGB image
with tRNS, take the compiled filters and the pure-x pixel loop.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/png) (list (Png jit!) (Png jit!)))
```
---
    (#t #t)

## colour types and bit depths

### RGBA, 8 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070806000000d370c71a0000000774494d4507ea0b04161e03d65a85a5000001244944415418d305c13f6f12710000d077e7712052a92d3f9a62631c2c3521c63f7191c4513f817e4a2727e3eca4b1894e9a8aa6d504ca49c5d2f62a39e07c2f7afd60d7481a6efc4ddaf3f5e721ac7d0e7fcacbd03b09ed9fd94108278dd0ec34436578dace5d09f56e2324fb9ff6c4368cc4ee77a606795fe728f26173a5b2fd48d2499dad3e3accba5a9b4bddd354f2ca0bbb8e2cddf27d7847556624b318ce34f2bafdbb3dc32f7de1eaa5f178ee99b792c2c257b745ce3d319269f967a5af69badcb17abfa3525e33ad1ecbc5de782a19b8eea6ae9ae09d0b6b0a05167a466735692b524c0ecde61b2e1cdbb627697b69861ace23eae5c0818766d689e7f24955e49ed458e6b1856fe22956986e519685a5542af74be17759059398a12d0bfcb0eb3fd5a2722e706ba0cc0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 4039302694)

### RGB, 8 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d0000000708020000005c12504d0000000774494d4507ea0b04161e03d65a85a5000000f84944415418d325c14d4f82701cc0f1ef0fe1af339c202066cd2ec96ad6ea4dd4c9d7d46be9dcad63efa14ba71e37b52d0d263d68888c840e7d3e727dda9fa1ec2f3db3cebdc6dd47990e62ef357af262b3d96d1ad3ef15957a60ca05438d568976d2d5dfccddee4462a7305a862f4a2f6ec78fbeeb6c02941c72d967b2a167b35f25f2897e5998563d3a184cef9557a4e1323be3a662318c713e49f628e6386be418333382c5a897ad3ba994cb8d3da22e70b54350c383a4419e131e31985153aee4f3f1023be17d1b256dca14daf023b4cb9707dc0e165ab62aaa028a30c2eff12c06a582aa8f1ee62eb3097a82571363ab24d6a0e0df1f6dd85d4514ab1cb10000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 3997290753)

### RGBA, 16 bits: the high byte of each sample

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d00000007100600000083e01b590000000774494d4507ea0b04161e03d65a85a5000002564944415428cf2d8e4d48930100869f4ff7397fa6d3b96fd9d426e4d4d2b4a44c3c842829048188dffcbd5807410821cac80e6591442086541644604450a3c80e82042112a162a61eca64337f6a6b4ba74dddd87f87757adee7f2f208efb28f961b3bc1568755ac91e4b4a4ed64715032f99ad48b35193a592a4951cfbf9564d7a3f0b8572fc945ddae11a940675acb74b42ed549b2b6d855a81a95e4d4057d55cab0248b9bb60fee3b3ad35e27c49e90e444837125a952921533637393f9418869044d17d853f923cc42c99cfeead67bb0b47a7e557c05bd77f58990035343daccb01ac47afde3520962854c75dc3aec84c391997e5879e3ecc94f036d9da636580d79cfff7e515e078579061ad6c0580cabc5101a8103afc0aab5f51b1f80d24ebf6310eccbe00c4150b0e1ae0655c0539ae886cfdbf9f6a29b609bfd16a86802a92721cbdb0b8e01679f4f86d3fb61ec13c4f89b21340f8b02e43483e52078af81e202d8b2c02940da0d583d07da8f6010e0800a62da823d257608d74f0d19fa402c70abf3da60abd17f4897059e1f60380ba3b7e1d43e505845488907fd0418ad10ef07a903268e8167019223e0ef82e0192002c174281c037bf66e43c27988bbac6da50a02dd1bac5482dbe29bd65c81dd61f83d0efa76c89b0085f4131a9661e7300024f8a2dc31f30220319d166b3c7c7f09a539e07e0dea45605698f48d82c7b451ae5403bd7004505e02a70c8e32386e8690092c65a0d8be1f3d8e6b8fd2754ff70c40bceb6c093c84502d881741790bf67261fd29249d04e51203ca2950fd0fdcec105cd115d1e8cc4046d49681dc69f807f278d5d5f362e5430000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 237651651)

### RGB, 16 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d0000000710020000000c828c0e0000000774494d4507ea0b04161e03d65a85a5000002034944415428cf45c64b48d3011cc0f1efbff977e5df39f7d67f4e7bb04c5c69923de8524a1666601218da690703893a1865044920a4541743283048c90e05d13c0462888445879092a834f3116ace748e998f6d6ebf0e1dba7cf8283deec2439efad94a7ea865162d6452db22e7ccdfca321c0569e64f2f830f12036bbaf76ad0efd8fd736ba076b4d2be37989ffa2a7d582f49eb541767fbc32d2bf560284ec9f14c6a47959b5fa0a26e5335587b251d94a1024d6f50fb666ab51b592dfaefa90e65dba2d3ae25cc6a957544ad72294a677273522251f4e1d4e48b91c3ae547ba5f5c4c6855d4f081a9b94bc2e787cd2d30b536adc0fd9e5163b78da8df51068738dc37c7c2317c2a5a9bef4a294f07c2877d05b3a3bf435a6763b2e49d6daad80637939b2743c137adf19cccfe0f44ad00fd686a518ac5ec9a98378de0260eb5b3f038a61cf34982a22f792ee7b6ac21d13afb3f747ea22c7322fae4595422958ee8fcf580e8e7781f6590178be5d7f031edfe6283856d907abc32681a86fa31c02e2b541beeb971bb65c4b3e6fafa5247667a17b723d3c0696c63fad3037a03741f2111cd320624a03919d461071f6f054c4fb16c68c491310ca75df0511778df27e3d64cb0011db4310d14d10386b9803911db7e17b316a2388689741c422ce2e11672b44dbf33ec2d475cd07338f0062078ca34ab588ad194440098ac0bffff72f19bdd3c6d7a149fe0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 3979991945)

### grey with alpha, 8 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d00000007080400000079790f91000000844944415408d705c1c14ac3401400c0d9740d5a0b22f8d243c11ff2fb7b2978100fbd887a6813d36c769d496f96f81b9e621b4bd4e11c53ece37ba8f11af9a84332f9b1f5a257cc9e8df2452ff9c4c6afab83771b1f1ee4e6a6e9adaa9de4a4c8b8ea66c99d5131997cb9777331233faa3a55b3187196342bba153b0dc9ac485645b3f8076648354b157c10a80000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 4033459354)

### grey, 8 bits: spread to red, green and blue

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070800000000f61b98c6000000624944415408d705c14b0a85300c00c0b4c953d48208823b2fe4f95dba16370ae2e7b5491a67dcc4ffb6e6bcbec39e479a3db8f7a8fb4262f72099de079f1c16bf3d586529d51a5ad92421fe8821f92b5c91113b2380647a6655f00ac1c045712ac61f5514369724d2a90c0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 4008360893)

### grey, 16 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000071000000000a68b4485000000c84944415408d701bd0042ff014b10fad2f98c0ffa0a6dfb8dfeade6baf8ac1732ed3afefb1e0d01207d0290ffef1e420488ef250b2c0e4806bdfbd3df0f1222086c04f4ef05f2027ce28200f00311f115f5bc1adfde80024fe1f1091302fe92fad4f8afff13fd83fbea08b10128db14f91cfae0001bf5db04fa5c086403caf74e0265fd0e048af37e10eef5f8fe3ffc0f06df011722fe1f04adfed702a2f9f8066401b9fd0e001c00bcfded04dc0113a401451295f063034af9d4002303f90186fd3bff9f00000000618559779edf3fcd0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 1266181890)

### grey, 4 bits: scaled to 0-255

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d00000007040000000033eb75c7000000324944415408d7637031090d36317660505276360901d28242409691029016323632126010141454321404d34000a40dc13400ee9a06d7b75e48150000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 212304305)

### grey, 2 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070200000000bcab8067000000204944415408d763080d0d75606004110c8c210c40c2054830383040000b10030050970309e506683d0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 2516327616)

### grey, 1 bit

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070100000000fb0bfab70000000b4944415408d76360c0020000150001321d39600000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 1711486020)

### palette, 8 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070803000000e4ae372800000060504c5445aa2f30a5212ba23075b9344ed6284cd100397e004c80005e7f0060ae1967992982ad0781980a739c1f8fd5185b2500994c00905306cb6304b07800906c38be5100b29500a6840dc26a01de5107ec0000aa1b00d02c00eb2e00d52900aa0d01fb884cde71000000504944415408d72dc5db1640201405c09d0a25ba09a9a3ffff4b2ce66500b08e433029a414e88751e9c9e8991bb5c03ae7438cf3ea4332b0d68614b6fdc8de279ca5125db966aa85d05a6dd45ecff8feddf3a506f8abf2f2390000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 1800273664)

### palette, 4 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070403000000215eda2900000021504c5445a8292ea31a66d52054d100397f00569d198c2100a55e06a75505da840dc21901f0d233ea3d000000374944415408d7636060645030325660707414140d14546048af282fad281760484b6f9fd9d151c090b56a5947c7aa06865560b000460300b2a51534125c9dd20000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 604313330)

### palette, 2 bits

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070203000000ae1e2f890000000c504c5445b41b4f9312864d04b61901f04f29285c0000002a4944415408d7636064000291501706865553573930ac5ab6aa81e1ffeaf74062ffff030cffffff3f0000bb380fa526f7a60f0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 1333938313)

### palette, 1 bit

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070103000000e9be555900000006504c5445aa185f2f02d7c78e6cd8000000144944415408d7636000831f1f18fefe60f80f450048f509c30a905b8b0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 388137733)

## transparency

### a palette's tRNS: an alpha for each entry

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070803000000e4ae37280000002d504c5445000000b2132cd10039d71d549d238bb4216097026d6a22bd4f07cd4e00af840dc25707e83800ea3100d20b00fc454840630000000174524e530040e6d866000000344944415408d755c75b1200100800c044891ef73fae3134c6fe2dc051b022d61b688d98debaf4c1b9a92a3272a66eeeb9d8fec5023025017c692fc01d0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 694930390)

### a grey image's tRNS: one grey value transparent

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070800000000f61b98c60000000274524e5300007693cd38000000234944415408d7630c6540028c0c0c0ca1283c06a8c86a0626b8f86a642d28fab1890200a53d030582b3b8090000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 3868222479)

### an RGB image's tRNS: one colour transparent

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d0000000708020000005c12504d0000000674524e5300b4001b004f7df1b9d5000000814944415418d363dc22edcf40046039fd941dc23295fef9f48f2bb29c34cbeed34fd94da57f32303030da331f96677e82a6db5af0edd1f7c20fffcac8333f79f857c6e1ef6426060686877f651efe9581309015c145eeb30532da331fbef54f17628c1ad365080322a2c674f9d63f5d8820a324e307b8751009acfe405187070000ea5133303ae5fc010000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 3182779919)

## interlacing

### Adam7, RGBA: the seven passes put back in place

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070806000001a477f78c0000000774494d4507ea0b04161e03d65a85a50000014a4944415418d305c1cf2f23611cc0e1cfb7dee9a03462fa4e2d5d113f63ded00a12d9c4650f7b100997d9ab83ffc261ff8e3d3a49f4c681bb9304e142918a56a2544c34d4cfa1e379642337847be4e4657bf68f3f5895bc409e1cc64fa57efae1fda52feb7d5933d232e0270a155fad94b6984271ce0732ca2afd44a68ba4e750342f33d35e78fc65c69f363db188684f63baaa57de093f8c83e50560004ffee78c6e65ce34b5ed7aed85073368f77861a56ed4d6d15f92fca6977e9a3b3e597d9ea0410d75c002cdb4724888539b442873838daa912541c82d092e24c99b8c4103e41ff3c4e8d4113137dbadf4755b46779745074ec3b53a2d9d96b8568d7d5d3a4bbb29e74b0f13d76a8d4562580875ca154d408a2401bf2a21774f19f6ea19826889c8bea5568d11a7807a649957c005b605dca8c82913ecd001cfefbc443602c4df23ee48d38bcd37f29d6b6c68cfe35a0000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 4039302694)

### Adam7, 2-bit grey: a pass's rows end mid-byte

```x
(do (import x/codec/png) (import x/codec/bytes) (import x/codec/crc32) (Png jit!)
  (def r (Bytes of-hex "89504e470d0a1a0a0000000d494844520000000d000000070200000001cbacb0f1000000274944415408d763086008606061086100820006010686d0000646070608600c0d0532195d203c0054bb036ff0cbdba60000000049454e44ae426082"))
  (def d (Png decode (first r) 0 (List ref 2 r)))
  (list (first d) (List ref 1 d) (Crc32 of (List ref 2 d) 0 (* 4 (* (first d) (List ref 1 d))))))
```
---
    (13 7 2516327616)

