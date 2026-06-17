# Relative includes and the import search path

`include` / `include-once` / `require-once` / `import` resolve a path that
begins with `./` or `../` against the directory of the file currently loading.
`import` resolves a module name against a search path that is **conservative**
(only `lib` by default) and **configurable** (add roots with `import-path!`).
Plain and absolute paths keep their cwd-relative meaning, so existing
call-sites are unaffected.

These tests stay self-contained: they exercise the resolution logic and use
files already under `lib/`, so nothing depends on paths outside the repo.

## Path resolution

### ./ resolves against the including file's directory

```scheme
(str=? (%resolve-include-path "./cell.x" "app/maze") "app/maze/cell.x")
```
---
    #t

### ../ is kept for the OS to collapse

```scheme
(str=? (%resolve-include-path "../shared/x.x" "app/maze") "app/maze/../shared/x.x")
```
---
    #t

### a plain path is unchanged (cwd-relative, as before)

```scheme
(str=? (%resolve-include-path "lib/x/type/list.x" "app/maze") "lib/x/type/list.x")
```
---
    #t

### an absolute path is unchanged

```scheme
(str=? (%resolve-include-path "/etc/hosts" "app/maze") "/etc/hosts")
```
---
    #t

### a directory is everything before the last slash

```scheme
(list (str=? (%path-dir "app/maze/cell.x") "app/maze") (str=? (%path-dir "cell.x") "."))
```
---
    (#t #t)

### the top-level current directory is "." after boot

```scheme
(str=? (%include-curdir) ".")
```
---
    #t

### the dir-stack feeds the current directory into resolution

```scheme
(%include-dir-push! "lib/x/core")
(let ((%r (%resolve-include-path "./list.x" (%include-curdir))))
  (%include-dir-pop!)
  (str=? %r "lib/x/core/list.x"))
```
---
    #t

## Import search path

### conservative: the only default root is lib

```scheme
(str=? (%module-resolve 'x/num/random) "lib/x/num/random.x")
```
---
    #t

### configurable: import-path! adds a root, falling back to the lib default

```scheme
(import-path! "lib/x")
(list (str=? (%module-resolve 'core/list) "lib/x/core/list.x")
      (str=? (%module-resolve 'x/num/random) "lib/x/num/random.x"))
```
---
    (#t #t)
