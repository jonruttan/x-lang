# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

A compiled analyser state that loops must RETURN ITSELF — the
tokenizer's replace-analyser protocol continues a token by handing the
same handler back for the next character. An fvar can't carry that
value: the function's own pointer doesn't exist until its compile
finishes. But in the prim ABI the callee sits at slot 0 of its own
argument list, so the self param IS reachable — `compile-asm` now
resolves a reference to the self-param name (analyser mode only) as
firstobj of p_args: no eval, no unbox, exactly the object the protocol
wants back.

## the self param as a return value

### a compiled state loops itself across a multi-character token

`me` names the self param. Lowercase letters return `me` — stay in this
state, consume — and anything else unreads and accepts. The whole
name-token loop runs compiled, no interpreter re-entry per character.

```scheme
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %name-body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 97) (<= chr 122))
          me
          (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
      (list (pair 'u 1))))
  (def %name-start
    (compile-asm
      '(fn (_ buffer score chr)
        (if (and (>= chr 97) (<= chr 122)) body ()))
      (list (pair 'body %name-body))))
  (Base make-type %b "S-NAME"
    (list (pair 'analyse %name-start)
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "hello world xy z "))
  (newline))
```
---
    ("hello" "world" "xy" "z")

### a one-character token still accepts through the same state

The boundary case: the state is entered and immediately exited — the
self-return path is never taken, and the accept path must not be
disturbed by the slot-0 machinery.

```scheme
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %name-body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 97) (<= chr 122))
          me
          (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
      (list (pair 'u 1))))
  (def %name-start
    (compile-asm
      '(fn (_ buffer score chr)
        (if (and (>= chr 97) (<= chr 122)) body ()))
      (list (pair 'body %name-body))))
  (Base make-type %b "S-NAME"
    (list (pair 'analyse %name-start)
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "a b "))
  (newline))
```
---
    ("a" "b")

## the self param as a CALL target

A state may also CALL itself, and that path had never run for an
analyser. `%asm-compile-funcall` was written for integer recursion: it
marshalled every argument through `jit_mkint` and unboxed the result
with `atomint`. Both are wrong here — `buffer` and `score` are
`x_obj_t*`, and a handler returns an OBJECT (a state, the score, or
nil). Boxing the buffer handed the callee an integer atom whose value
happened to be a pointer; unboxing the result handed the tokenizer a
pointer built out of an object's first word. Either way: segfault on
the first self-call.

### a compiled state calls itself, passing the buffer and score through

`me` consumes letters by returning itself (the path above), and finishes
through a self-CALL that carries `buffer` and `score` across the call
before accepting. If either object were re-boxed on the way in, or the
returned score unboxed on the way out, this reads nothing at all.

```scheme
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 97) (<= chr 122))
          me
          (if (= chr 0)
            (%seq (%buffer-unread buffer) (%score-set score 1 buffer))
            (me buffer score 0))))
      (list (pair 'u 1))))
  (Base make-type %b "S-NAME"
    (list (pair 'analyse
        (compile-asm
          '(fn (_ buffer score chr)
            (if (and (>= chr 97) (<= chr 122)) body ()))
          (list (pair 'body %body))))
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "de b a "))
  (newline))
```
---
    ("de" "b" "a")
