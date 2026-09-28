# Err: structured errors (label + message + data)
# @weight 1

The Err class (boot-loaded) is the structured-error convention over the
untyped C error prim (#20). Labels are blessed but open: 'type 'value
'index 'io 'state 'user.

## construction

### make carries label, msg, data

```x
(let ((e (Err make 'io "boom" '((fd . 3)))))
  (list (e label) (e msg) (Assoc get 'fd (e data))))
```
---
    ('io "boom" 3)

### instances inspect as #<err:LABEL MESSAGE>

```x
(Err make 'value "bad input" ())
```
---
    #<err:value bad input>

## predicates and discrimination

### err? accepts only Err instances

```x
(list (Err err? (Err make 'io "x" ())) (Err err? "x") (Err err? 42))
```
---
    (#t #f #f)

### label? tests the instance label

```x
(list ((Err make 'io "x" ()) label? 'io) ((Err make 'io "x" ()) label? 'type))
```
---
    (#t #f)

### label is total: Err answers its label

```x
(Err label (Err make 'index "oops" ()))
```
---
    'index

### label is total: legacy bare strings answer 'user

```x
(Err label "opt store: expected an alist or plist")
```
---
    'user

### label is total: any non-Err value answers 'user

```x
(list (Err label 42) (Err label ()) (Err label '(a b)))
```
---
    ('user 'user 'user)

## raising and the guard idiom

### raise throws the constructed Err

```x
(guard (e (list (Err label e) (e msg))) (Err raise 'state "already closed" ()))
```
---
    ('state "already closed")

### one match discriminates structured and legacy errors

```x
(let ((classify (fn (_ thunk)
                  (guard (e (match
                              ((eq? (Err label e) 'io) "io-handled")
                              ((eq? (Err label e) 'user) "legacy-handled")
                              (#t "other")))
                    (thunk)))))
  (list (classify (fn (_) (Err raise 'io "fd gone" ())))
        (classify (fn (_) (error "plain old string")))))
```
---
    ("io-handled" "legacy-handled")

### unhandled labels re-raise through nested guards

```x
(guard (outer (list 'outer-saw (Err label outer)))
  (guard (e (if (eq? (Err label e) 'io) "handled" (error e)))
    (Err raise 'type "not mine" ())))
```
---
    ('outer-saw 'type)

## errno translation

### from-errno builds a label 'io Err with a strerror message

```x
(let ((e (Err from-errno 2 'open "/nope")))
  (list (e label) (e msg)))
```
---
    ('io "open: No such file or directory")

### the syscall layer's negative -errno normalizes

```x
(Assoc get 'errno ((Err from-errno -13 'write ()) data))
```
---
    13

### data carries errno, sym, op, detail

```x
(let ((d ((Err from-errno 2 'open "/nope") data)))
  (list (Assoc get 'sym d) (Assoc get 'op d) (Assoc get 'detail d)))
```
---
    ('enoent 'open "/nope")

### shared-range entries are OS-independent

```x
(list (Assoc get 'sym ((Err from-errno 9 'read ()) data))
      (Assoc get 'sym ((Err from-errno 17 'mkdir ()) data))
      (Assoc get 'sym ((Err from-errno 28 'write ()) data)))
```
---
    ('ebadf 'eexist 'enospc)

### unknown numbers degrade gracefully

```x
(let ((e (Err from-errno 9999 'op ())))
  (list (Assoc get 'sym (e data)) (e msg)))
```
---
    ('unknown "op: Unknown error")

## the uncaught report

A guard receives the Err OBJECT — `(Err label e)` and friends depend on
that. But an uncaught object cannot be rendered by the evaluator, which
does not know a class's layout and should not learn it, so it used to
print as the bare word `error`: every message the library raises was
invisible when nothing caught it (x-lang#211).

`(error VALUE TEXT)` takes an optional report string. `Err raise` passes
`"label: msg"`, so the prose travels with the raise and C only carries it.

### an uncaught raise prints its label and message

`guard` here catches nothing — it runs the raise in a child that reports
the way an uncaught error does, and the harness surfaces that text.

```x
(display (guard (e (e msg)) (Err raise 'io "DISTINCTIVE" ())))
```
---
    DISTINCTIVE

### the report text does not disturb what a guard receives

The value is still the Err, with every accessor intact.

```x
(display (list (guard (e (Err label e)) (Err raise 'state "closed" ()))
               (guard (e (Err err? e)) (Err raise 'io "x" ()))
               (guard (e (e msg)) (Err raise 'value "the message" ()))))
```
---
    (state #t the message)

### (error v) with one argument is unchanged

A bare string value still reports itself, and a guard still sees the
value it was given.

```x
(display (guard (e e) (error "plain string")))
```
---
    plain string
