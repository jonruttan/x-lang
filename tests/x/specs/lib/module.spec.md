# @weight 1

The module registry as data. `(modules)` and `(help x/some/module)` print
the same facts; these cases read them.

## names

### every known module, the boot modules included

```x
(list (List includes? 'x/core/fn (Module names))
      (List includes? 'x/type/module (Module names))
      (List includes? 'x/boot/module (Module names)))
```
---
    (#t #t #t)

### sorted by name, each name once

```x
(let ((n (Module names)))
  (list (Str8 <? (symbol->str (first n)) (symbol->str (first (rest n))))
        (= (List length n) (List length (List distinct n)))))
```
---
    (#t #t)

## loaded?

### a loaded module, and one the session does not know

```x
(list (Module loaded? 'x/core/fn) (Module loaded? 'x/no/such))
```
---
    (#t #f)

## exports

### what a module provides, as symbols, a (global NAME) export as NAME

```x
(list (List includes? 'Fn (Module exports 'x/core/fn))
      (List includes? 'apply (Module exports 'x/core/fn)))
```
---
    (#t #t)

### () for a module that is not loaded

```x
(null? (Module exports 'x/no/such))
```
---
    #t

## owner

### the module that provided a name

```x
(list (Module owner 'Fn) (Module owner 'Env))
```
---
    ('x/core/fn 'x/type/env)

### () for a name no module provided

```x
(null? (Module owner 'no-such-name-zz))
```
---
    #t

## env

### a scoped module's environment holds its private names

```x
(list (Env has? (Module env 'x/core/fn) '%apply-label)
      (Env has? (Env root) '%apply-label)
      (same? (Env parent (Module env 'x/core/fn)) (Env root)))
```
---
    (#t #f #t)

### a module loaded by include answers the root

```x
(same? (Module env 'x/boot/module) (Env root))
```
---
    #t

### () for a module that is not loaded

```x
(null? (Module env 'x/no/such))
```
---
    #t
