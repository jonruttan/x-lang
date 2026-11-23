# @weight 4
# x/sys/bundle: the bundles a session can reach

A bundle is a directory with a `bundle.xon` and its modules under
`lib/NAME/`. `Bundle` answers where bundles are installed, which installed
ones carry a name, and where a loaded one is; `(Bundle arm! NAME)` makes one's
modules importable, and a missed import asks it for the bundle the module's
first segment names.

Each case builds a bundles directory of its own under /tmp and names it with
`(Bundle dir! ...)`.

## fixture

### the bundles directory is built

Three official bundles sit directly under it: `bsone`, a second directory
that also calls itself `bsdup`, and its twin. Two authors, `ann` and `bob`,
each carry a `bsmany`; `ann` alone carries `bssolo`.

```x
(do (import x/sys/file) (import x/sys/bundle)
  (def tmp (File temp "/tmp/x-spec-bundles-"))
  (File close (first tmp))
  (def bsdir (rest tmp))
  (File unlink bsdir)
  (def mk
    (fn (_ rel name)
      (def d (Str8 append bsdir rel))
      (List for-each (fn (_ s) (File mkdir (Str8 append d s)))
        (list "" "/lib" (Str8 append "/lib/" name)))
      (File write-all (Str8 append d "/bundle.xon")
        (Str8 append "(name \"" (Str8 append name "\")\n")))
      (File write-all (Str8 append d (Str8 append "/lib/" (Str8 append name "/m.x")))
        (Str8 append "(def " (Str8 append name (Str8 append "-from \"" (Str8 append rel "\")\n")))))))
  (List for-each (fn (_ s) (File mkdir (Str8 append bsdir s))) (list "" "/ann" "/bob"))
  (mk "/bsone" "bsone")
  (mk "/dup-a" "bsdup")
  (mk "/dup-b" "bsdup")
  (mk "/ann/bsmany" "bsmany")
  (mk "/bob/bsmany" "bsmany")
  (mk "/ann/bssolo" "bssolo")
  (Bundle dir! bsdir)
  (display (str=? (Bundle dir) bsdir)))
```
---
    #t

## installed

### an official bundle is the whole answer

```x
(write (List map (fn (_ d) (Str8 ends? "/bsone" d)) (Bundle installed "bsone")))
```
---
    (#t)

### with none official, every author's bundle of the name is answered

```x
(write (List length (Bundle installed "bsmany")))
```
---
    2

### a name nothing declares is no bundle

```x
(write (Bundle installed "bsnone"))
```
---
    ()

## root and arm!

### a bundle that is not loaded has no root

```x
(write (Bundle root "bsone"))
```
---
    ()

### arm! makes the bundle's lib an import root, and root answers its directory

```x
(do
  (def armed (Bundle arm! "bsone"))
  (write (list (Str8 ends? "/bsone" armed)
               (str=? armed (Bundle root "bsone"))
               (Str8 ends? "/bsone/lib/bsone/m.x" (%module-resolve 'bsone/m)))))
```
---
    (#t #t #t)

### the one third-party bundle of a name is armed

```x
(write (Str8 ends? "/ann/bssolo" (Bundle arm! "bssolo")))
```
---
    #t

### several of a name and none official is refused

```x
(write (guard (e (Err label e)) (Bundle arm! "bsmany")))
```
---
    'value

### two official bundles of one name is refused the same way

```x
(write (guard (e (Err label e)) (Bundle arm! "bsdup")))
```
---
    'value

### no bundle of the name arms nothing

```x
(write (Bundle arm! "bsnone"))
```
---
    ()

## a missed import

### the platform's own modules belong to no bundle

```x
(write (Bundle arm-module! "x/no/such"))
```
---
    ()

### an import no root holds arms the bundle its first segment names

`bssolo` was armed above; `bsone` too. A fresh name shows the miss doing it.

```x
(do
  (File mkdir (Str8 append bsdir "/bsmiss"))
  (File mkdir (Str8 append bsdir "/bsmiss/lib"))
  (File mkdir (Str8 append bsdir "/bsmiss/lib/bsmiss"))
  (File write-all (Str8 append bsdir "/bsmiss/bundle.xon") "(name \"bsmiss\")\n")
  (File write-all (Str8 append bsdir "/bsmiss/lib/bsmiss/m.x") "(def bsmiss-loaded \"by a miss\")\n")
  (import bsmiss/m)
  (write (list bsmiss-loaded (Str8 ends? "/bsmiss" (Bundle root "bsmiss")))))
```
---
    ("by a miss" #t)

### a module no installed bundle holds is still refused by name

```x
(write (guard (e 'refused) (import bsnone/m)))
```
---
    'refused

## a bundle booted from its state image

### its modules read %image-writing as nil

The image writer binds `%image-writing` to `#t` in its child while the
bundle loads, and clears it before the walk. A module of the bundle must read
the cleared binding after the boot, or a guard on it skips, on every boot,
what it skips while being imaged. The image is written into the fixture.

```x
(do
  (import x/sys/proc)
  (def d (Str8 append bsdir "/imaged/bsimg"))
  (List for-each (fn (_ s) (File mkdir (Str8 append bsdir s)))
    (list "/imaged" "/imaged/bsimg" "/imaged/bsimg/lib" "/imaged/bsimg/lib/bsimg" "/cache"))
  (File write-all (Str8 append d "/bundle.xon") "(name \"bsimg\")\n(dialect he)\n(entry run)\n")
  (File write-all (Str8 append d "/lib/bsimg/run.x")
    "(module bsimg/run)\n(import x/sys/posix)\n(def bsimg-writing (fn (_) (guard (_ (lit unbound)) %image-writing)))\n(def main (fn (_) (write (bsimg-writing)) (Sys exit 0)))\n(provide bsimg/run main)\n")
  (def out (Str8 append bsdir "/imaged/out.txt"))
  (Proc run! (list "sh" "-c"
    (Str8 append "X_BUNDLE_DIR=" (Str8 append bsdir (Str8 append "/imaged/ XDG_CACHE_HOME=" (Str8 append bsdir (Str8 append "/cache sh x.sh -q -l bsimg </dev/null >" out)))))))
  (display (File read-all out)))
```
---
    ()

## teardown

### the fixture is removed

```x
(do
  (import x/sys/proc)
  (Proc run! (list "rm" "-rf" bsdir))
  (write (File exists? bsdir)))
```
---
    #f
