# Err: structured errors (kind + message + data)

The Err class (boot-loaded) is the structured-error convention over the
untyped C error prim (#20). Kinds are blessed but open: 'type 'value
'index 'io 'state 'user.

## construction

### make carries kind, msg, data

```scheme
(let ((e (Err make 'io "boom" '((fd . 3)))))
  (list (e kind) (e msg) (assoc-get 'fd (e data))))
```
---
    ('io "boom" 3)

### instances inspect as #<err:KIND MESSAGE>

```scheme
(Err make 'value "bad input" ())
```
---
    #<err:value bad input>

## predicates and discrimination

### err? accepts only Err instances

```scheme
(list (Err err? (Err make 'io "x" ())) (Err err? "x") (Err err? 42))
```
---
    (#t #f #f)

### kind? tests the instance kind

```scheme
(list ((Err make 'io "x" ()) kind? 'io) ((Err make 'io "x" ()) kind? 'type))
```
---
    (#t #f)

### kind-of is total: Err answers its kind

```scheme
(Err kind-of (Err make 'index "oops" ()))
```
---
    'index

### kind-of is total: legacy bare strings answer 'user

```scheme
(Err kind-of "opt store: expected an alist or plist")
```
---
    'user

### kind-of is total: any non-Err value answers 'user

```scheme
(list (Err kind-of 42) (Err kind-of ()) (Err kind-of '(a b)))
```
---
    ('user 'user 'user)

## raising and the guard idiom

### raise throws the constructed Err

```scheme
(guard (e (list (Err kind-of e) (e msg))) (Err raise 'state "already closed" ()))
```
---
    ('state "already closed")

### one match discriminates structured and legacy errors

```scheme
(let ((classify (fn (_ thunk)
                  (guard (e (match
                              ((eq? (Err kind-of e) 'io) "io-handled")
                              ((eq? (Err kind-of e) 'user) "legacy-handled")
                              (#t "other")))
                    (thunk)))))
  (list (classify (fn (_) (Err raise 'io "fd gone" ())))
        (classify (fn (_) (error "plain old string")))))
```
---
    ("io-handled" "legacy-handled")

### unhandled kinds re-raise through nested guards

```scheme
(guard (outer (list 'outer-saw (Err kind-of outer)))
  (guard (e (if (eq? (Err kind-of e) 'io) "handled" (error e)))
    (Err raise 'type "not mine" ())))
```
---
    ('outer-saw 'type)

## errno translation

### from-errno builds a kind-'io Err with a strerror message

```scheme
(let ((e (Err from-errno 2 'open "/nope")))
  (list (e kind) (e msg)))
```
---
    ('io "open: No such file or directory")

### the syscall layer's negative -errno normalizes

```scheme
(assoc-get 'errno ((Err from-errno -13 'write ()) data))
```
---
    13

### data carries errno, sym, op, detail

```scheme
(let ((d ((Err from-errno 2 'open "/nope") data)))
  (list (assoc-get 'sym d) (assoc-get 'op d) (assoc-get 'detail d)))
```
---
    ('enoent 'open "/nope")

### shared-range entries are OS-independent

```scheme
(list (assoc-get 'sym ((Err from-errno 9 'read ()) data))
      (assoc-get 'sym ((Err from-errno 17 'mkdir ()) data))
      (assoc-get 'sym ((Err from-errno 28 'write ()) data)))
```
---
    ('ebadf 'eexist 'enospc)

### unknown numbers degrade gracefully

```scheme
(let ((e (Err from-errno 9999 'op ())))
  (list (assoc-get 'sym (e data)) (e msg)))
```
---
    ('unknown "op: Unknown error")
