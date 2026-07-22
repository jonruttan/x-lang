# @lib ../tests/x/lib/isa.x

# The C ISA ratchet

The C layer is the interpreter's instruction set: unchecked, minimal, FIXED.
`tools/isa.x` is the committed manifest of every C function reachable from x-lang.
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
  (List map (fn (_ dom)
         (List map (fn (_ e)
                (if (eq? (Type of (rest e)) %prim-type)
                    (set! %live (pair (pair (first dom) (first e)) %live))
                    ()))
              (rest dom)))
       (prims))
  (def %man ())
  (List map (fn (_ e) (set! %man (pair (pair (first e) (first (rest e))) %man)))
       %isa-catalog)
  (def %report (fn (self label a b)
    (List map (fn (_ p)
           (if (List member p b)
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
  (List map (fn (_ e) (eval (first e))) %isa-bare)
  (display "ok"))
```
---
```output
ok
```

### every C-bound value in the manifest is live

```scheme
(do
  (List map (fn (_ e) (eval (first e))) %isa-values)
  (display "ok"))
```
---
```output
ok
```

### every live PRIMITIVE-typed global is catalog-filed or manifested

The reverse direction the liveness checks above cannot see: walk the env
global BST and demand that every PRIMITIVE-typed binding is either (a) a
value alias of a catalog-filed prim (module `%`-caches -- already-gated
surface), or (b) named in `%isa-bare`/`%isa-keep`.  A NEW bare C binding
-- however it is spelled in the source, across however many lines --
exists in the live env and fails here.  (Keep-list names the lib shadows
with X wrappers, like `+`, simply don't appear as PRIMITIVE; this
direction is live-to-manifest only.)

```scheme
(do
  (def %walk
    (fn (self node acc)
      (if (null? node) acc
          (let ((kids (rest node)))
            (self (first kids) (self (rest kids) (pair (first node) acc)))))))
  (def %prim-t (Type of first))
  (def %cat-vals ())
  (List map (fn (_ dom)
         (List map (fn (_ e)
                (if (eq? (Type of (rest e)) %prim-t)
                    (set! %cat-vals (pair (rest e) %cat-vals))
                    ()))
              (rest dom)))
       (prims))
  (def %man-names ())
  (List map (fn (_ e) (set! %man-names (pair (first e) %man-names))) %isa-bare)
  (List map (fn (_ e) (set! %man-names (pair (first e) %man-names))) %isa-keep)
  (List map (fn (_ e) (set! %man-names (pair (first e) %man-names))) %isa-aliases)
  (def %bad ())
  (List map (fn (_ e)
         (match
           ((not (eq? (Type of (rest e)) %prim-t)) ())
           ((List memq (rest e) %cat-vals) ())
           ((List memq (first e) %man-names) ())
           (#t (set! %bad (pair (first e) %bad)))))
       (%walk (%reflect-base-cell 'env-global-tree) ()))
  (if (null? %bad) "ok" %bad))
```
---
    "ok"
