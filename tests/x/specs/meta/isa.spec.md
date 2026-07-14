# @lib ../tests/x/lib/isa.x

# The C ISA ratchet

The C layer is the interpreter's instruction set: unchecked, minimal, FIXED.
`tools/isa.x` is the committed manifest of every C function reachable from X.
These tests walk the LIVE primitives catalog and fail on drift in either
direction, so growing the C surface requires editing the manifest in the same
commit. The source-level companion (`make check-isa`) covers the bare binding
sites the runtime walk cannot enumerate; here the bare/value sections are
checked for liveness only.

## catalog surface

### every live C prim is in the manifest, and every manifest entry is live

```scheme
(do
  (def %prim-type (Type of first))
  (def %live ())
  (map (fn (_ dom)
         (map (fn (_ e)
                (if (eq? (Type of (rest e)) %prim-type)
                    (set! %live (pair (pair (first dom) (first e)) %live))
                    ()))
              (rest dom)))
       (prims))
  (def %man ())
  (map (fn (_ e) (set! %man (pair (pair (first e) (first (rest e))) %man)))
       %isa-catalog)
  (def %member? (fn (self p lst)
    (if (null? lst)
        #f
        (if (if (eq? (first p) (first (first lst)))
                (eq? (rest p) (rest (first lst)))
                #f)
            #t
            (self p (rest lst))))))
  (def %report (fn (self label a b)
    (map (fn (_ p)
           (if (%member? p b)
               ()
               (do (display label) (display " ")
                   (display (first p)) (display " ")
                   (display (rest p)) (newline))))
         a)))
  (%report "not-in-manifest:" %live %man)
  (%report "stale-in-manifest:" %man %live)
  (display "ok"))
```
---
```output
ok
```

## bare surface

### every bare-bound name in the manifest is live

```scheme
(do
  (map (fn (_ e) (eval (first e))) %isa-bare)
  (display "ok"))
```
---
```output
ok
```

### every C-bound value in the manifest is live

```scheme
(do
  (map (fn (_ e) (eval (first e))) %isa-values)
  (display "ok"))
```
---
```output
ok
```
