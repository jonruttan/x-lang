# @weight 2
# Module scope: a scoped module is an environment of its own

A file whose first form, after its comment banner, is `(module NAME)` is
evaluated in a child of the root: its top-level definitions are private to it, `provide` is the only
door out, and a selective `import` is the door in. The rules for every
name conflict the doors can meet are in
[docs/namespaces.md](../../../../docs/namespaces.md). The fixtures live
under `tests/x/fixtures/modscope`.

## a scoped module keeps its private names

### an export is bound in the root, a private name is not

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (list (alpha-twice 1) (guard (_ 'hidden) %helper)))
```
---
    (3 'hidden)

### a private name is reached by the exports that close over it

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (list (alpha-bump) (alpha-bump) (guard (_ 'hidden) %state)))
```
---
    (1 2 'hidden)

### a class defined in the module is an export like any other

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (Alpha twice 5))
```
---
    7

### a doc form inside the module documents the export

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (%doc-commit!)
    (not (null? (%doc-lookup 'alpha-twice))))
```
---
    #t

## private against private is not a conflict

### two scoped modules define the same private name and each keeps its own

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (import scoped/beta)
    (list (alpha-twice 1) (beta-tenfold 3)))
```
---
    (3 30)

## export against export: one owner per name

### a second module providing a name another owns is refused, naming both

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (guard (e e) (import scoped/gamma)))
```
---
    "provide: scoped/gamma exports alpha-twice, owned by scoped/alpha"

### the refused module leaves the owner's binding as it was

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (guard (e ()) (import scoped/gamma))
    (alpha-twice 1))
```
---
    3

## the header names the module

### a file headed with another module's name is refused

```x
(do (import-path! "tests/x/fixtures/modscope")
    (guard (e e) (import scoped/delta)))
```
---
    "import: scoped/delta is headed (module scoped/epsilon)"

### a file with no header loads in the root as before

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/plain)
    (list (plain-seven) %plain-helper))
```
---
    (7 7)

### the header may follow the file's comment banner, however long

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/banner)
    (list (banner-five) (guard (_ 'hidden) %secret)))
```
---
    (5 'hidden)

### a file with no header may provide ahead of its definitions

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/early)
    (early-nine))
```
---
    9

### a scoped module that provides a name it does not define is refused

```x
(do (import-path! "tests/x/fixtures/modscope")
    (guard (e e) (import scoped/zeta)))
```
---
    "provide: scoped/zeta exports zeta-two, which it does not define"

## the module form denotes the module's environment

### a scoped module can name its own environment

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (eq? (alpha-self) (module scoped/alpha)))
```
---
    #t

### the environment is a pair whose parent is the root

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/alpha)
    (null? (rest (rest (module scoped/alpha)))))
```
---
    #t

### a module that is not loaded is an error

```x
(guard (e e) (module scoped/nowhere))
```
---
    "module: not loaded: scoped/nowhere"

## a selective import copies an export into the importer's environment

### the import binds the name where it is evaluated

```x
(do (import-path! "tests/x/fixtures/modscope")
    ((fn (_) (import scoped/beta beta-tenfold) (beta-tenfold 4))))
```
---
    40

### an alias binds the export under another name

```x
(do (import-path! "tests/x/fixtures/modscope")
    ((fn (_) (import scoped/beta (beta-tenfold tenfold)) (tenfold 5))))
```
---
    50

### the copy is the importer's: a later rebinding of the global does not reach it

The global rebind is restored so the case leaves the shared binding as it
found it -- the file's cases share one session.

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/beta)
    (def %orig beta-tenfold)
    (def %held ((fn (_) (import scoped/beta (beta-tenfold t10)) (fn (_ n) (t10 n)))))
    (set! beta-tenfold (fn (_ n) 0))
    (def %r (%held 6))
    (set! beta-tenfold %orig)
    %r)
```
---
    60

### importing the same export twice into one environment is a repeat

```x
(do (import-path! "tests/x/fixtures/modscope")
    ((fn (_) (import scoped/beta beta-tenfold) (import scoped/beta beta-tenfold) (beta-tenfold 1))))
```
---
    10

### a name already bound to something else in the importer is refused

```x
(do (import-path! "tests/x/fixtures/modscope")
    (import scoped/beta)
    ((fn (_) (def beta-tenfold 5) (guard (e e) (import scoped/beta beta-tenfold)))))
```
---
    "import: beta-tenfold from scoped/beta is already bound here by scoped/beta"

### a name that is not exported is refused

```x
(do (import-path! "tests/x/fixtures/modscope")
    (guard (e e) (import scoped/beta %helper)))
```
---
    "import: symbol not exported by scoped/beta: %helper"
