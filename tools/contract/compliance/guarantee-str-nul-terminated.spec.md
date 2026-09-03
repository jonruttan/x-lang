# Compliance: `(guarantee str/nul-terminated)`

A str value IS a C string: bytes past the first NUL are unobservable. This is a
ruling, not an accident -- x-lib's stated contract is exact libc semantics, and
the codecs are written to it.

An engine holding strings as a pointer and a length would answer differently here
while behaving identically everywhere else in the suite, which is exactly the kind
of difference a guarantee exists to pin.

The bytes below are `a`, NUL, `b`. A C string sees one byte; a counted string sees
three.

### bytes past an embedded NUL are unobservable

```x
(def %b2s (%coord (lit bytes) (lit ->str)))
(def %blen (%coord (lit str) (lit byte-len)))
(%ok (= (%blen (%b2s (pair 97 (pair 0 (pair 98 ()))))) 1))
```
---
    *** ERROR: ok

### and the truncation survives a round trip through append

An engine could terminate on construction yet carry the hidden bytes along in
concatenation. Appending to a string whose NUL is interior must not resurrect what
follows it: `"a\0b"` + `"c"` is `"ac"`, length 2.

```x
(def %b2s (%coord (lit bytes) (lit ->str)))
(def %blen (%coord (lit str) (lit byte-len)))
(def %app (%coord (lit str) (lit append)))
(%ok (= (%blen (%app (%b2s (pair 97 (pair 0 (pair 98 ())))) "c")) 2))
```
---
    *** ERROR: ok
