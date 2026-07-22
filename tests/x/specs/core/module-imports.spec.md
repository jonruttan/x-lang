## selective imports

### valid selective import succeeds

```scheme
(import x/core/predicates null? pair?)
```
---

### empty selector works (no validation)

```scheme
(import x/core/list)
```
---

### invalid symbol raises error

```scheme
(guard (e (display e)) (import x/core/predicates null? nonexistent pair?))
```
---
    import: symbol not exported by x/core/predicates: nonexistent

### all listed symbols are valid

```scheme
(import x/core/predicates null? pair?)
```
---

### unregistered module selector is ignored

```scheme
(import x/core/predicates null? pair? atom?)
```
---
