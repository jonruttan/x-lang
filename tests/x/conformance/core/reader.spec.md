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

The buffer is never the subject here. It is the tape the analysers run over, and
its marks are moved by the tokenizer in an order only the tokenizer knows — which
is why the remaining `buf/*` rows stay undefined (see `core/io-and-reader.spec.md`).

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
