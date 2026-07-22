## selective imports

### valid selective import succeeds

```scheme
(import x/core/list else str-copy)
```
---

### empty selector works (no validation)

```scheme
(import x/core/list)
```
---

### invalid symbol raises error

```scheme
(guard (e (display e)) (import x/core/list else nonexistent str-copy))
```
---
    import: symbol not exported by x/core/list: nonexistent

### all listed symbols are valid

```scheme
(import x/core/list else str-copy)
```
---

### unregistered module selector is ignored

```scheme
(import x/core/predicates null? pair? atom?)
```
---
