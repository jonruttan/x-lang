# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @requires tok/variant
# @weight 1

The variant channel through the assembler lane: `%score-variant!` compiles to the
`jit_score_variant` trampoline, so a native state declares what it accepted the
way an interpreted one does (lib/reader-variant.spec.md is the interpreted twin).
## the variant a state declares reaches the reader

An analyser knows which of its states accepted -- whether a literal ran
through a fraction -- and `(%score-variant! score K)` is how it says so: the
engine hangs a variant cell off the score, records the winning handler's variant,
and hands it to the type's reader as its second argument.  Nil when no
state declared one, so every reader written before the channel existed
reads what it always read.

### a compiled state declares its variant, and the reader reads it

Digits alone are variant 1; a dot promotes the literal to variant 2.  The two
accepting states differ only in the variant they declare.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %frac
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 48) (<= chr 57))
          me
          (%seq (%buffer-unread buffer) (%seq (%score-variant! score 2) (%score-set score 1 buffer)))))
      (list (pair 'u 1))))
  (def %body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 48) (<= chr 57))
          me
          (if (= chr 46)
            frac
            (%seq (%buffer-unread buffer) (%seq (%score-variant! score 1) (%score-set score 1 buffer))))))
      (list (pair 'frac %frac))))
  (def %start
    (compile-asm
      '(fn (_ buffer score chr)
        (if (and (>= chr 48) (<= chr 57)) body ()))
      (list (pair 'body %body))))
  (Base make-type %b "V-NUM"
    (list (pair 'analyse %start)
      (pair 'read (fn (_ . args) (list (%buf-tok (first args)) (%read-variant args))))))
  (Base make-type %b "V-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "12 3.5 7 "))
  (newline))
```
---
    (("12" 1) ("3.5" 2) ("7" 1))

### a state that declares no variant hands the reader nil

The same reader on a type whose states never call `%score-variant!`: the
second argument is nil, as it was before the channel existed.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 97) (<= chr 122))
          me
          (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
      (list (pair 'u 1))))
  (def %start
    (compile-asm
      '(fn (_ buffer score chr)
        (if (and (>= chr 97) (<= chr 122)) body ()))
      (list (pair 'body %body))))
  (Base make-type %b "V-NAME"
    (list (pair 'analyse %start)
      (pair 'read (fn (_ . args) (list (%buf-tok (first args)) (%read-variant args))))))
  (Base make-type %b "V-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "ab c "))
  (newline))
```
---
    (("ab" ()) ("c" ()))
