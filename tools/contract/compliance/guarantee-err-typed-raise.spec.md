# Compliance: `(guarantee err/typed-raise)`

The language words errors and the engine does not. A raise delivers the two
facts apart -- the code (the raise site's message) and the subject (the name it
was about) -- on a REGISTERED type, and the base's `err` row holds a value of
that same type.

An engine that flattens them into one English string passes every capability
check and every other spec in this suite, and then leaves a lang nothing to
reword: the structure is gone before x-lang sees it, and a type-less value has
no dispatch stacks to push a handler onto. That is exactly the kind of
difference a guarantee exists to pin.

**Identity is not claimed.** The reference engine reuses one base-resident
instance so a raise allocates nothing -- which is why a caught error must be
read before the next raise overwrites it -- but an engine that allocates per
raise satisfies this guarantee. Nothing below compares two raises with `eq?`.

### a raise delivers a typed value, not a bare atom

```x
(def %tof (%coord (lit type) (lit of)))
(%ok (match ((eq? (%tof (guard (e e) no-such-binding)) ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### the code and the subject are separate slots

The engine must not pre-join them. Interning is the bare-engine string
comparison: equal names are the same symbol, so `eq?` on `->sym` is equality.

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

### the base's err row holds a value of the raised type

This is the coupling `lib/x/type/err-io.x` depends on: it reaches the type
through the row in order to push handlers onto it. An engine may allocate the
raised value fresh, but if its type differs from the row's, the handlers the
language pushed are never consulted and the default wording never appears.

```x
(def %tof (%coord (lit type) (lit of)))
(def %rowv (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(%ok (eq? (%tof (guard (e e) no-such-binding))
          (%tof (first (%rowv (lit err))))))
```
---
    *** ERROR: ok
