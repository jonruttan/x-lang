# Conformance: the reader protocol (profile `core`)

x-lang's reader is extensible: a type registered on a tokenizer base can claim
text and turn it into a value, which is how `lib/x/num/bigint.x` makes `12345678901234567890`
read as a BIGINT with no change to the engine. That extensibility is an engine
contract, and this is it.

**The protocol.** A bare tokenizer base is made, reader types are registered on
it, and text is read through it:

1. `(base make-tok)` makes a base with NO types registered — deliberately bare,
   for exactly this purpose.
2. `(base make-type TOKBASE "NAME" handlers)` registers a reader type. The
   handler alist carries `analyse` and `read`.
3. `analyse` is `(fn (_ buffer score chr))` and it is a **state machine whose
   states are functions**: return the analyser for the next character to
   continue, `()` to reject, or record a match through the score object to
   accept.
4. `(tok read-str TOKBASE text)` drives every registered type's analyser over the
   text, scores them against each other, calls the winner's `read`, and answers
   the LIST of tokens it produced.

The buffer is the tape the analysers run over, and its marks are moved by the
tokenizer in an order only the tokenizer knows. That does not put it out of reach
— it puts it out of reach FROM OUTSIDE. The `read` handler runs inside that order,
so the mark discipline is asserted there; see the second half of this file. The
`buf/*` rows that remain undefined are the ones no case here requires
(`core/io-and-reader.spec.md` says which, and why).

**A token must be DELIMITED to be accepted.** The accept branch of an analyser
runs when a character arrives that the state rejects, so text ending mid-token is
never scored: `"42"` produces nothing where `"42 "` produces a token. That is a
real part of the contract and it cost an hour of "the protocol does not work"
before the space was added.

### a registered reader type claims text and produces its value

covers: base/make-tok base/make-type tok/read-str buf/read

The scoring helpers are rebuilt from primitives here, because in the library they
are x-level (`lib/x/reader/intrinsics.x`): a buffer's marks are two integer cells
reachable through `obj ->ptr` + `ptr ref-word`, the token's length is the distance
between them, and accepting means writing that distance into the score object.

`buf/read` is claimed because the tokenizer must pull each character out of the
buffer to feed the analyser: break it and nothing ever reaches this type.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %analyse (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %readfn (fn (_ . args) 7))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def tb (%mktok))
(%mktype tb "TEST" (pair (pair (lit analyse) %analyse) (pair (pair (lit read) %readfn) ())))
(%ok (= (first (%readstr tb "42 ")) 7))
```
---
    *** ERROR: ok

### an undelimited token is not accepted

covers: tok/read-str

The same registration over `"42"` -- no trailing delimiter -- yields no tokens at
all. An engine that accepted at end-of-input instead would read one, and every
reader type in the library is written to the behaviour asserted here.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %analyse (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %readfn (fn (_ . args) 7))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def tb (%mktok))
(%mktype tb "TEST" (pair (pair (lit analyse) %analyse) (pair (pair (lit read) %readfn) ())))
(%ok (eq? (%readstr tb "42") ()))
```
---
    *** ERROR: ok

### a type that rejects every character claims nothing

covers: base/make-type

The other half of `analyse`: returning `()` declines the text, and a base whose
only type declines produces no tokens. Without this an engine could pass the
first case by accepting unconditionally.

```scheme
(def %analyse (fn (_ buffer score chr) ()))
(def %readfn (fn (_ . args) 7))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def tb (%mktok))
(%mktype tb "TEST" (pair (pair (lit analyse) %analyse) (pair (pair (lit read) %readfn) ())))
(%ok (eq? (%readstr tb "42 ") ()))
```
---
    *** ERROR: ok

## The mark discipline

A buffer carries three marks -- a retain mark, a read cursor, and a write mark --
and the primitives that expose them are only meaningful WHERE THE TOKENIZER HAS
PUT THEM. The `read` handler is that place: it runs once, on accept, with the
buffer positioned over the text its analyser just claimed. Its first argument IS
the buffer.

Driven anywhere else they answer nonsense -- see `core/io-and-reader.spec.md` for
the demonstration that cost two green cases.

### inside the read handler, tok is the text the analyser claimed

covers: buf/tok

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-d (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def %btok (%coord (lit buf) (lit tok)))
(def %blen (%coord (lit str) (lit byte-len)))
(def %readfn (fn (_ . args) (%blen (%btok (first args)))))
(def tb (%mktok))
(%mktype tb "NUM" (pair (pair (lit analyse) %an-d) (pair (pair (lit read) %readfn) ())))
(%ok (= (first (%readstr tb "42 ")) 2))
```
---
    *** ERROR: ok

### the claimed text and the mark distance agree

covers: buf/tok

`tok` is not a separate accounting of the token: its length is exactly the
distance between the retain mark and the read cursor, which is what an analyser
measures when it scores. An engine where the two could disagree would score one
length and hand the reader another.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-d (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def %btok (%coord (lit buf) (lit tok)))
(def %blen (%coord (lit str) (lit byte-len)))
(def %readfn (fn (_ . args) (- (%blen (%btok (first args))) (%buflen (first args)))))
(def tb (%mktok))
(%mktype tb "NUM" (pair (pair (lit analyse) %an-d) (pair (pair (lit read) %readfn) ())))
(%ok (= (first (%readstr tb "42 ")) 0))
```
---
    *** ERROR: ok

### last-char is the character most recently read

covers: buf/last-char

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-d (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def %blast (%coord (lit buf) (lit last-char)))
(def %c2i (%coord (lit char) (lit ->int)))
(def %readfn (fn (_ . args) (%c2i (%blast (first args)))))
(def tb (%mktok))
(%mktype tb "NUM" (pair (pair (lit analyse) %an-d) (pair (pair (lit read) %readfn) ())))
(%ok (= (first (%readstr tb "42 ")) 50))
```
---
    *** ERROR: ok

### each token's text is its OWN -- the retain mark advances between tokens

covers: buf/retain buf/tok base/make-type

Two types now compete: one claims digits, one claims spaces. Reading `"42 43 "`
yields three tokens whose texts are 2, 1 and 2 bytes long.

That third number is the whole point. If the retain mark did not advance past a
finished token, the next token's span would still start at the beginning of the
input and `"43"` would measure 5 rather than 2. The case also shows the scorer
choosing between two candidate types per position rather than taking the first
registered.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-d (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def %btok (%coord (lit buf) (lit tok)))
(def %blen (%coord (lit str) (lit byte-len)))
(def %spaces ())
(set! %spaces
  (fn (_ buffer score chr)
    (match ((= chr 32) %spaces)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-s (fn (_ buffer score chr) (match ((= chr 32) %spaces) (#t ()))))
(def %readfn (fn (_ . args) (%blen (%btok (first args)))))
(def tb (%mktok))
(%mktype tb "NUM" (pair (pair (lit analyse) %an-d) (pair (pair (lit read) %readfn) ())))
(%mktype tb "WS" (pair (pair (lit analyse) %an-s) (pair (pair (lit read) %readfn) ())))
(def %r (%readstr tb "42 43 "))
(%ok (match ((= (first %r) 2) (match ((= (first (rest %r)) 1) (= (first (rest (rest %r))) 2)) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### a base with no type for a character stops there

covers: tok/read-str

The corollary, and it is why the case above needs a space-claiming type: with only
a digit type registered, `"42 43 "` yields ONE token. Nothing claims the space, so
tokenising stops rather than skipping it. An engine that silently skipped
unclaimable input would read two.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %setw (%coord (lit ptr) (lit set-word!)))
(def %doff (* %param-word-size %obj-meta-len))
(def %cellint (fn (_ x) (%refw (%o2p x) %doff)))
(def %setcell (fn (_ p v) (%setw (%o2p p) %doff v) p))
(def %buflen (fn (_ b) (- (%cellint (rest b)) (%cellint b))))
(def %unread (fn (_ b) (%setcell (rest b) (- (%cellint (rest b)) 1))))
(def %scoreset (fn (_ s sign b) (%setcell s (* sign (%buflen b)))))
(def %digit? (fn (_ c) (match ((< c 48) ()) ((< 57 c) ()) (#t 1))))
(def %digits ())
(set! %digits
  (fn (_ buffer score chr)
    (match ((%digit? chr) %digits)
           (#t (%seq (%unread buffer) (%scoreset score 1 buffer))))))
(def %an-d (fn (_ buffer score chr) (match ((%digit? chr) %digits) (#t ()))))
(def %mktok (%coord (lit base) (lit make-tok)))
(def %mktype (%coord (lit base) (lit make-type)))
(def %readstr (%coord (lit tok) (lit read-str)))
(def %btok (%coord (lit buf) (lit tok)))
(def %blen (%coord (lit str) (lit byte-len)))
(def %readfn (fn (_ . args) (%blen (%btok (first args)))))
(def tb (%mktok))
(%mktype tb "NUM" (pair (pair (lit analyse) %an-d) (pair (pair (lit read) %readfn) ())))
(def %r (%readstr tb "42 43 "))
(%ok (eq? (rest %r) ()))
```
---
    *** ERROR: ok
