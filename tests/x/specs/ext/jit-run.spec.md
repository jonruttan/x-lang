# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

A routine for a slot of the base's slot vector, compiled in run mode, and
the slot door on the Base class that puts it there.  The engine calls a
slot's routine with its one signature, (base args), and args is a run of
words, one an argument, typed by the slot's row in
engine/tools/contract/base-slots.x.  `compile-asm` declares that world as
`(run TYPE ...)`.  The cases call a routine the way the engine does: a run
in malloc'd memory, the base, and a call through the routine's address.

## the routine's address and the call the engine makes

### the helpers the cases share

`%jr-addr` is the address of a callable's code; `%jr-call` writes a run
and calls through an address the way a slot is called.

```x
(do
  (import x/core/doors ptr-call ptr-ref-word ptr-set-word! int->ptr ptr->int ptr->obj obj->ptr obj-ref ffi-dlopen ffi-dlsym)
  (def %jr-malloc (ffi-dlsym (ffi-dlopen () 1) "malloc"))
  (def %jr-addr (fn (_ c) (ptr->int (obj->ptr (obj-ref c 0)))))
  (def %jr-call
    (fn (_ c words)
      (def run (ptr-call %jr-malloc 64))
      ((fn (self ws i)
         (unless (null? ws)
           (do (ptr-set-word! run (* %word-size i) (first ws))
               (self (rest ws) (+ i 1)))))
       words 0)
      (ptr-call (int->ptr (%jr-addr c)) (obj->ptr (%base)) run)))
  (display "ok"))
```
---
    ok

## parameters are the words of the run

### integer words are read as they are

```x
(display (%jr-call (compile-asm '(fn (self a b) (- a b)) () '(run integer integer)) (list 10 3)))
```
---
    7

### an object word stays the pointer, and first reads through it

```x
(do
  (def %jr-p (pair 5 6))
  (def %jr-r (%jr-call (compile-asm '(fn (self p) (first p)) () '(run object)) (list (ptr->int (obj->ptr %jr-p)))))
  (display (ptr->obj (int->ptr %jr-r))))
```
---
    5

### a tail self-call is a loop over the slots

```x
(display (%jr-call (compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n)))) () '(run integer integer)) (list 100 0)))
```
---
    5050

## what run mode refuses

### arithmetic on an object-typed parameter

```x
(display (guard (e (e msg)) (compile-asm '(fn (self p) (+ p 1)) () '(run object))))
```
---
    asm-compile: + cannot take the object parameter p as an operand: this compile is in run mode, where that parameter is an x_obj_t* and not a number.  Pass #f as compile-asm's third argument for an ordinary integer function.

### a declaration that does not give one type a parameter

```x
(display (guard (e (e msg)) (compile-asm '(fn (self a b) (+ a b)) () '(run integer))))
```
---
    asm-compile: run mode declares one TYPE a parameter, and this function takes 2 parameters where the declaration gives 1 types.

### a self-call that returns

```x
(display (guard (e (e msg)) (compile-asm '(fn (self n) (+ 1 (self (- n 1)))) () '(run integer))))
```
---
    asm-compile: a routine compiled in run mode takes its arguments as a run of words, and a self-call that returns would pass them as a list; only a self-call in tail position compiles here.

### a type the contract does not have

```x
(display (guard (e (e msg)) (compile-asm '(fn (self a) a) () '(run float))))
```
---
    compile-asm: the third argument names the calling world: #t for an analyse callback, #f for an integer function, the symbol object for an object function, the symbol operative for an object function given its argument list unevaluated, or (run TYPE ...) for a routine the engine calls through a slot, one TYPE a parameter, each object, integer or string.

## the slot door

### the contract's rows, read at boot

```x
(do (import x/type/base)
  (display (list (List length (Base slots)) (List ref 18 (Base slots)))))
```
---
    (19 (18 obj-alloc (type flags units) (object integer integer)))

### a slot holds the engine's routine, and storing it back changes nothing

```x
(do
  (def %jr-sweep (Base slot (%base) (lit heap-sweep)))
  (display (list (> %jr-sweep 0)
                 (= (Base slot! (%base) (lit heap-sweep) %jr-sweep) %jr-sweep)
                 (= (Base slot (%base) (lit heap-sweep)) %jr-sweep))))
```
---
    (#t #t #t)

### a name the contract does not list refuses

```x
(display (guard (e (e msg)) (Base slot (%base) (lit heap-sweeper))))
```
---
    Base slot: no such slot: heap-sweeper

### the engine calls a compiled routine through the slot

The routine counts its calls in a word of its own and calls the engine's
sweep, held as a callable.  Two collects through it count two; once the
engine's routine is stored back, a third collect counts nothing.

```x
(do
  (def %jr-count (ptr-call %jr-malloc 8))
  (ptr-set-word! %jr-count 0 0)
  (def %jr-at (ptr->int %jr-count))
  (def %jr-engine-sweep ((prim-ref (lit obj) (lit make-callable)) (int->ptr %jr-sweep)))
  (def %jr-routine
    (compile-asm
      (list (lit fn) (lit (self))
        (list (lit do)
          (list (lit %mem-set!) %jr-at 0 (list (lit +) (list (lit %mem-ref) %jr-at 0) 1))
          (lit (sweep))))
      (list (pair (lit sweep) %jr-engine-sweep))
      (lit (run))))
  (Base slot! (%base) (lit heap-sweep) %jr-routine)
  (Heap collect)
  (Heap collect)
  (Base slot! (%base) (lit heap-sweep) %jr-sweep)
  (Heap collect)
  (display (ptr-ref-word %jr-count 0)))
```
---
    2
