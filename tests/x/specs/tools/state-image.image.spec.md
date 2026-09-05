# State image: the format's invariants, checked on a loaded image
# @weight 5
# @lib x.x

Each test here is one invariant of [docs/state-image-format.md](../../../../docs/state-image-format.md)
§6, checked by loading the x-core image and evaluating inside it. The image
is `$X_IMG_DIR/x-core.x.ximg`, written by `tools/dev/image-build.sh`; `make
test-x-img` builds it and sets `X_IMAGE_SPECS=1`, which is what makes the
runner pick this file up (the `.image` tag). It needs an engine carrying
`(image rebuild!)` -- `X_BIN` until the pin has one.

Every probe is a subprocess: `lib/img.x`, the loader, then the probe's forms,
so the forms evaluate inside the loaded image and this process's helium is
never in the picture. The last line the probe prints is the answer; a probe
that dies prints the shell's report instead, which is a wrong answer that
says why.

## the fixture

### the image is there

```x
(import x/sys/posix)
(import x/sys/file)
(def %dir (Sys getenv "X_IMG_DIR"))
(def %img (Str8 append %dir "/x-core.x.ximg"))
(def %tmp "/tmp/x-image-spec")
(if (File exists? %tmp) () (File mkdir %tmp))
(def %sh
  (fn (_ cmd)
    (def pid (Sys fork))
    (if (eq? pid 0) (Sys exec "/bin/sh" (list "-c" cmd)) (Sys wait pid))))
(def %write-file
  (fn (_ path s)
    (def fd (Sys open-write path))
    (Sys fd-write fd s)
    (Sys close fd)))
; Run FORMS inside the loaded image; answer everything the probe printed.
(def %probe
  (fn (_ forms)
    (%write-file (Str8 append %tmp "/pre.x") (Str8 append "(def %IMG-PATH \"" (Str8 append %img "\")\n")))
    (%write-file (Str8 append %tmp "/forms.x") forms)
    (%sh (Str8 append "{ cat " (Str8 append %tmp (Str8 append "/pre.x tools/dev/image-read.x " (Str8 append %tmp (Str8 append "/forms.x; } | sh x.sh -q -l img > " (Str8 append %tmp "/out.txt 2>&1")))))))
    (File read-all (Str8 append %tmp "/out.txt"))))
; Run FORMS on the bare img dialect, no loader.
(def %probe-raw
  (fn (_ forms)
    (%write-file (Str8 append %tmp "/forms.x") forms)
    (%sh (Str8 append "sh x.sh -q -l img -f " (Str8 append %tmp (Str8 append "/forms.x > " (Str8 append %tmp "/out.txt 2>&1")))))
    (File read-all (Str8 append %tmp "/out.txt"))))
(display (if (< 0 (Assoc get 'size (File stat %img))) "image present" "no image"))
```
---
    image present

## §6.1 header

### magic, version, word size, byte order, a count

```x
(display (%probe-raw (Str8 append "(def %rw (prim-ref (lit ptr) (lit ref-word))) (def buf ((prim-ref (lit ptr) (lit alloc)) 200)) (def fd ((prim-ref (lit sys) (lit open)) \"" (Str8 append %img "\" 0)) ((prim-ref (lit sys) (lit read)) fd buf 160) (def w (fn (_ i) (%rw buf (* i 8))))
(display (if (eq? (w 0) 1196247384) (if (eq? (w 1) 1) (if (eq? (w 2) %word-size) (if (eq? (w 3) 1) (if (< 0 (w 4)) \"header ok\" \"no objects\") \"byte order\") \"word size\") \"version\") \"magic\")) (newline)"))))
```
---
    header ok

## §6.2 objects

### a rebuilt pair is typed like a fresh one, and its contents read back

```x
(display (%probe "(write (list (first (first %type-shape-rows)) (eq? (%reflect-type-word (first %type-shape-rows)) (%reflect-type-word (pair 1 2))))) (newline)"))
```
---
    ("INTEGER" #t)

### strings, symbols, integers and characters survive

```x
(display (%probe "(write (list (< 0 (Str8 length x-machine)) (first (rest (first %type-shape-rows))) (first (first (rest (rest (first %type-shape-rows))))) %word-size)) (newline)"))
```
---
    (#t 1 'word 8)

## §6.3 closures

### a rebuilt closure is callable and resolves its environment

```x
(display (%probe "(write (list 1 2 3)) (newline)"))
```
---
    (1 2 3)

## §6.4 class instances

### new makes an instance; object?, class-of and dispatch agree

```x
(display (%probe "(write (list (Err err? (Err make (lit k) \"m\" ())) (Err kind-of (Err make (lit k) \"m\" ())) (Str8 length \"abcd\"))) (newline)"))
```
---
    (#t 'k 4)

## §6.5 type-word integers

### the boot-cached type words are this base's

```x
(display (%probe "(write (list (eq? %reflect-satom-tw (%reflect-type-word (Type of 0))) (eq? %reflect-spair-tw (%reflect-type-word (Type by-atom (Type of 0)))) (eq? %print-int-tw (%reflect-type-word 0)) (eq? %print-str-tw (%reflect-type-word \"\")))) (newline)"))
```
---
    (#t #t #t #t)

## §6.6 raised errors

### a primitive's type error arrives as an Err the class can read

```x
(display (%probe "(write (list (guard (e (Err kind-of e)) (+ \"a\" 1)) (guard (e (Err kind-of e)) (Err raise (lit k) \"m\" ())))) (newline)"))
```
---
    ('type 'k)

## §6.7 collect safety

### collects, top-level and tail-position defs, printing, and lookups

```x
(display (%probe "((prim-ref (lit heap) (lit collect))) ((prim-ref (lit heap) (lit collect))) (def q 1) (def f (fn (_) (def zz 9))) (f) (display \"x\") (newline) ((prim-ref (lit heap) (lit collect))) (write (list q zz)) (newline) ((prim-ref (lit heap) (lit collect))) (write (Str8 length \"abc\")) (newline)"))
```
---
    3

## §6.8 statics

### a static resolves to this base's own object, by identity

```x
(display (%probe "(write (list ((prim-ref (lit obj) (lit same?)) #t (first (%reflect-base-cell (lit true)))) ((prim-ref (lit obj) (lit same?)) %object (Type of (Err make (lit k) \"m\" ()))))) (newline)"))
```
---
    (#t #t)

## §6.9 every foreign entry and every static resolves

### the loader's own count

```x
(%write-file (Str8 append %tmp "/pre.x") (Str8 append "(def %IMG-PATH \"" (Str8 append %img "\") (def %IMG-VERBOSE #t)\n")))
(%write-file (Str8 append %tmp "/forms.x") "")
(%sh (Str8 append "{ cat " (Str8 append %tmp (Str8 append "/pre.x tools/dev/image-read.x " (Str8 append %tmp (Str8 append "/forms.x; } | sh x.sh -q -l img > " (Str8 append %tmp "/out.txt 2>&1")))))))
(def %out (File read-all (Str8 append %tmp "/out.txt")))
(display (Str8 sub (- (Str8 length %out) 13) 12 %out))
```
---
    unresolved=0

## §6.11 transients

A value an image cannot carry -- `num/float.x`'s libm handle -- is listed in
`%image-transients`, written as nil, and re-derived by the module's recache
hook.  Probed in the float test library's image, which is the smallest one
that loads float.

### a declared transient is re-derived, and the call-time path through it answers

```x
(def %probe-in
  (fn (_ name forms)
    (%write-file (Str8 append %tmp "/pre.x") (Str8 append "(def %IMG-PATH \"" (Str8 append %dir (Str8 append "/" (Str8 append name "\")\n")))))
    (%write-file (Str8 append %tmp "/forms.x") forms)
    (%sh (Str8 append "{ cat " (Str8 append %tmp (Str8 append "/pre.x tools/dev/image-read.x " (Str8 append %tmp (Str8 append "/forms.x; } | sh x.sh -q -l img > " (Str8 append %tmp "/out.txt 2>&1")))))))
    (File read-all (Str8 append %tmp "/out.txt"))))
(display (%probe-in "float.x.ximg" "(write (list (not (null? %libm)) (Float hypot 3.0 4.0))) (newline)"))
```
---
    (#t 5.0)

## §6.12 the interned `#t`

### a `#t` the reader produces after load is eq? to the evaluated one

```x
(display (%probe "(write (list (eq? (first (lit (#t))) #t) (eq? (first (lit (#f))) #f))) (newline)"))
```
---
    (#t #t)

## §6.10 the primitives

The three engine primitives, exercised in this process rather than through
the loader: a fresh type struct is flagged node by node, `(image write!)`
writes it with a naming callable that names nothing, `(image rebuild!)`
rebuilds it, and the rebuilt struct is a struct whose name reads back.
`(image save!)` alone saves an ordinary pair as its two references.

### save! saves a pair as two reference units

```x
(def %sbuf ((prim-ref (lit ptr) (lit alloc)) 80))
(def n ((prim-ref (lit image) (lit save!)) (pair 1 2) %sbuf))
(display (list n (Ptr ref-word %sbuf 8) (Ptr ref-word %sbuf 24)))
```
---
    (2 0 0)

### write! then rebuild! round-trips a flagged type struct

```x
(include "engine/tools/contract/obj-layout.x")
(def %FLAG 1024)
(def %flags-off (* %obj-slot-flags %word-size))
(def %type-off (* %obj-slot-type %word-size))
(def %data-off (* %obj-meta-len %word-size))
(def %alloc (prim-ref (lit ptr) (lit alloc)))
(def %psw (prim-ref (lit ptr) (lit set-word!)))
(def %p2o (prim-ref (lit ptr) (lit ->obj)))
(def %rw (fn (_ o off) (Ptr ref-word (Obj ->ptr o) off)))
(def %flag! (fn (_ o) (%psw (Obj ->ptr o) %flags-off (| (%rw o %flags-off) %FLAG))))
(def %spair? (fn (_ o) (eq? (%rw o %type-off) %reflect-spair-tw)))
; Flag every on-chain node of the struct tree: its spair nodes and the leaves they hold.
(def %flag-tree!
  (fn (self o)
    (if (null? o) ()
      (do (%flag! o)
          (if (%spair? o) (do (self (first o)) (self (rest o))) ())))))
(def h ((prim-ref (lit type) (lit make)) "IMGT" ()))
(def st ((prim-ref (lit type) (lit by-atom)) h))
(%flag-tree! st)
(def cursor (pair 1 2))
(def table (%alloc 8000)) (def blob (%alloc 800)) (def result (%alloc 40))
(%psw result 0 1000) (%psw result 8 800)
(def N ((prim-ref (lit image) (lit write!)) cursor %FLAG table blob (fn (_ w k o) ()) (list st) result))
(def IX (%alloc (* 8 (+ N 1))))
((prim-ref (lit image) (lit rebuild!)) table 0 N (pair () ()) 1 blob IX)
(def root (%p2o (Ptr from-int (Ptr ref-word IX (* 8 (Ptr ref-word result 32))))))
(def name-atom (first (first root)))
(display (list (< 0 N) (%spair? root) (Ptr ->str (Ptr from-int (%rw name-atom %data-off)))))
```
---
    (#t #t IMGT)
