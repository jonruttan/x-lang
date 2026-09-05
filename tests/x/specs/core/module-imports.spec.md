# @weight 1
## selective imports

### valid selective import succeeds

```x
(import x/core/predicates null? pair?)
```
---

### empty selector works (no validation)

```x
(import x/core/list)
```
---

### invalid symbol raises error

```x
(guard (e (display e)) (import x/core/predicates null? nonexistent pair?))
```
---
    import: symbol not exported by x/core/predicates: nonexistent

### all listed symbols are valid

```x
(import x/core/predicates null? pair?)
```
---

### unregistered module selector is ignored

```x
(import x/core/predicates null? pair? atom?)
```
---
