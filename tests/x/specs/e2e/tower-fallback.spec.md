# @lib x-base.x
# @weight 3

The tower's fallback (`lib/x/boot/tower-compiled.x`). Where the probe is
closed, a site on the full ladder takes the cc rung if the engine ships its C
headers, and every other site keeps its interpreted twin; the tower that
results must read source as the compiled one does. No boot reaches that path
while the lane compiles, so this file takes the path a state image takes on a
host whose lane refuses: every site goes down to its twin, the probe closes, and
every site comes back up through its maker. The probe then reopens and the
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
  (%tower-unjit!)
  (set! %tower-jit? #f)
  ((fn (self l) (if (null? l) () (do (%tower-site-up! (first l)) (self (rest l)))))
   ((fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc)))) %tower-sites ()))
  (def %closed (guard (e (list (lit raised) (e msg))) (Xon parse %sample)))
  (%tower-unjit!)
  (%tower-rejit!)
  (write (if (str=? (%text %closed) (%text %compiled)) #t %closed)))
```
---
    #t
