# @weight 1

An environment is one pair `(bindings . parent)`. A frame's bindings are an
alist of `(name . value)`; the root's are a tree with no parent. `Env`
reads them by name, answering fresh pairs the List and Assoc walkers accept.

## current

### answers the environment the form is evaluated in

```x
(eval 'k ((fn (_ k) (Env current)) 7))
```
---
    7

### a frame's newest binding comes first

```x
(first (Env bindings ((fn (_ k) (Env current)) 7)))
```
---
    ('k . 7)

## bindings

### a frame answers its own names and values

```x
(let ((e ((fn (_ a b) (Env current)) 1 2)))
  (list (Assoc get 'a (Env bindings e)) (Assoc get 'b (Env bindings e))))
```
---
    (1 2)

### a definition in the body joins the frame

```x
(Assoc get 'local (Env bindings ((fn (_ a) (def local (* a 2)) (Env current)) 21)))
```
---
    42

### the frame alone, not the enclosing ones

```x
(null? (Assoc entry 'first (Env bindings ((fn (_ a) (Env current)) 1))))
```
---
    #t

### the root's tree is flattened to an alist holding the library's names

```x
(let ((b (Env bindings (Env root))))
  (list (null? (Assoc entry 'first b)) (null? (Assoc entry 'List b)) (< 100 (List length b))))
```
---
    (#f #f #t)

## names

### a frame's names

```x
(let ((n (Env names ((fn (_ a b) (Env current)) 1 2))))
  (list (List includes? 'a n) (List includes? 'b n) (List length n)))
```
---
    (#t #t 3)

## parent

### a frame's parent is the environment its closure was made in

```x
((fn (_ k) ((fn (_ x) (eval 'k (Env parent (Env current)))) 1)) 7)
```
---
    7

### the root has no parent

```x
(null? (Env parent (Env root)))
```
---
    #t

## has?

### answers for the chain, as lookup does

```x
((fn (_ k) (list (Env has? (Env current) 'k)
                 (Env has? (Env current) 'first)
                 (Env has? (Env current) 'no-such-name-zz)))
 7)
```
---
    (#t #t #f)

### a name that is not a symbol is a type error

```x
(guard (e (Err label e)) (Env has? (Env root) 42))
```
---
    'type

## root

### holds the library and is every frame's outermost parent

```x
((fn (_ k) (list (Env has? (Env root) 'List)
                 (Env has? (Env root) 'k)
                 (same? (Env parent (Env current)) (Env root))))
 7)
```
---
    (#t #f #t)

## with Fn env

### the environment a closure was made in is readable by name

```x
(let ((f ((fn (_ k) (fn (_) k)) 7)))
  (list (Env has? (Fn env f) 'k) (Assoc get 'k (Env bindings (Fn env f)))))
```
---
    (#t 7)
