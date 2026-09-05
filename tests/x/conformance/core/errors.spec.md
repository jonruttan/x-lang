# Conformance: a raise carries its facts (profile `core`)

What an engine hands a `guard` is part of the contract, because the
LANGUAGE words errors and the engine does not. A raise delivers a value
of a registered type carrying two slots, `(code . subject)`: the raise
site's message and what it was about. x-lang's `x/type/err-io.x` reaches
that type through the base's `err` row and pushes the prose onto its
write/display stacks; a lang pushes its own over that. None of it works
if the engine flattens the two into one string, or delivers a value with
no type for the stacks to hang off.

That is the whole of the obligation. The engine names no kinds, spells no
prose, and is not asked to: the codes it raises are its own vocabulary,
and what they should say in a given language is not its business.

**Not covered here: the empty subject.** A raise that names nothing writes
the empty string rather than nil — the slot holds an atom whose string
pointer the raise repoints, and there is no nil to spell in one. It is a
real obligation and a second engine must match it, but every raise
reachable from the BARE harness names a subject: `list` is a library
function, so a dotted call to it is just an unbound symbol, and the one
subject-less reader raise (`read: unknown character name`) crashes a bare
engine — on the reference engine too, so that is a pre-existing
fragility and not a thing to pin a contract to. The convention is
exercised in the library suite instead, `specs/meta/printer.spec.md`.

**Not required: identity.** The reference engine reuses ONE base-resident
instance so that a raise allocates nothing — which is why a caught error
must be read before the next raise overwrites it. An engine that
allocates a fresh value per raise conforms equally; nothing below tests
`eq?` between two raises, deliberately.

### the err row resolves

covers: eval

The row `x/type/err-io.x` reaches the type through. Its steps are the
engine's own business (decision L1); the NAME is not.

```x
(def %rowv (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(match ((eq? (%assoc (lit err) %base-paths) ()) (error "NO-ERR-ROW"))
       ((eq? (%rowv (lit err)) ()) (error "ERR-ROW-EMPTY"))
       (#t (error "ERR-ROW-RESOLVES")))
```
---
    *** ERROR: ERR-ROW-RESOLVES

### a caught engine raise is a TYPED value

covers: guard type/of

The failure this rules out: a type-less atom has no dispatch stacks, so
no handler can be pushed and no lang can reword what it says.

```x
(def %tof (%coord (lit type) (lit of)))
(%ok (match ((eq? (%tof (guard (e e) no-such-binding)) ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### it is the type the base's err row holds

covers: guard type/of

What `err-io.x` depends on: the type reached through the base row is the
type a raise actually delivers. An engine may allocate the raised value
fresh, but it must be of that same type, or the handlers the language
pushed are never consulted.

```x
(def %tof (%coord (lit type) (lit of)))
(def %rowv (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(%ok (eq? (%tof (guard (e e) no-such-binding))
          (%tof (first (%rowv (lit err))))))
```
---
    *** ERROR: ok

### the code and the subject arrive APART

covers: guard str/append str/->sym

The engine must not pre-join them into a sentence. `first` is the code —
the raise site's message — and `rest` is what it was about. Both are
string atoms; appending to `""` lifts one to a STRING.

No `str=?` here: this suite runs on a BARE engine, with the prelude and
nothing else. Interning is the bare-engine string comparison — equal
names are the same symbol, so `eq?` on `->sym` is string equality.

```x
(def %app (%coord (lit str) (lit append)))
(def %sym (%coord (lit str) (lit ->sym)))
(def %same? (fn (_ a b) (eq? (%sym a) (%sym b))))
(def e (guard (er er) no-such-binding))
(%ok (match ((%same? (%app "" (first e)) "Unbound SYMBOL")
              (%same? (%app "" (rest e)) "no-such-binding"))
             (#t ())))
```
---
    *** ERROR: ok
