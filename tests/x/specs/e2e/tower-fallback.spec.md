# @lib x-base.x
# @weight 3

The tower's fallback (`lib/x/boot/tower-compiled.x`). Where the probe is
closed, an entry on the full ladder takes the cc rung if the engine ships its C
headers, and every other entry keeps its interpreted twin; the tower that
results must read source as the compiled one does. No boot reaches that path
while the lane compiles, so this file takes the path a state image takes on a
host whose lane refuses: every entry is switched to its twin, the probe closes,
and every entry is compiled again. The probe then reopens and the
compiled tower is remade.

## a closed probe leaves a tower that reads what the compiled one reads

### every literal the tower adds, read both ways

The sample holds one literal of each tower type, and symbols against each quote
character the delimiter hook ends a token at. The two reads are compared as
written text, since two reads of one bigint are not `equal?` even from the same
tower. On a disagreement the case prints what the closed tower read.

```x
(do
  (import x/codec/xon)
  (def %text (prim-ref 'io 'write-to-str))
  (def %sample "(a 1 -2 3.5 1/2 1+2i 0.25d 18446744073709551616 'b `c ,d e'f \"g\" (h i))")
  (def %compiled (Xon parse %sample))
  (Compiled interpret-all!)
  (set! %tower-jit? #f)
  (Compiled compile-all!)
  (def %closed (guard (e (list (lit raised) (e msg))) (Xon parse %sample)))
  (Compiled interpret-all!)
  (%tower-probe!)
  (Compiled compile-all!)
  (write (if (str=? (%text %closed) (%text %compiled)) #t %closed)))
```
---
    #t
