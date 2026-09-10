# @no-seam-collect
<!-- A child tokenizer base, like core/sandbox.spec.md: objects reachable only
     through it are invisible to the parent's mark, so this file runs with no
     seam collects. -->
# @weight 1
# @requires tok/variant

The variant channel (`lib/x/reader/intrinsics.x`, x-token.h): an analyser state
declares what it accepted with `(%score-variant! score K)`, the engine records the
winning handler's variant, and the type's reader recovers it with
`(%read-variant args)` -- an integer, or nil when no state declared one.  The
analyser already knows which of its states ran; this is how it says so
instead of the reader rescanning the text.

## a declared variant reaches the reader

### lowercase words are variant 1, uppercase words variant 2

Two accepting states that differ only in the variant they declare.  `%seq` is
binary, so the declaration nests inside the accept.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %lo ())
  (def %up ())
  (set! %lo (fn (_ buffer score chr)
    (if (if (>= chr 97) (<= chr 122) #f) %lo
      (%seq (%buffer-unread buffer) (%seq (%score-variant! score 1) (%score-set score 1 buffer))))))
  (set! %up (fn (_ buffer score chr)
    (if (if (>= chr 65) (<= chr 90) #f) %up
      (%seq (%buffer-unread buffer) (%seq (%score-variant! score 2) (%score-set score 1 buffer))))))
  (Base make-type %b "V-WORD"
    (list (pair 'analyse (fn (_ buffer score chr)
            (if (if (>= chr 97) (<= chr 122) #f) %lo (if (if (>= chr 65) (<= chr 90) #f) %up ()))))
      (pair 'read (fn (_ . args) (list (%buf-tok (first args)) (%read-variant args))))))
  (Base make-type %b "V-WS"
    (list (pair 'analyse (fn (_ buffer score chr) (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "ab CD e "))
  (newline))
```
---
    (("ab" 1) ("CD" 2) ("e" 1))

### a state that declares no variant hands the reader nil

The same reader on a type whose state never calls `%score-variant!`: the second
argument is nil, as it was before the channel existed.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %lo ())
  (set! %lo (fn (_ buffer score chr)
    (if (if (>= chr 97) (<= chr 122) #f) %lo
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
  (Base make-type %b "V-WORD"
    (list (pair 'analyse (fn (_ buffer score chr) (if (if (>= chr 97) (<= chr 122) #f) %lo ())))
      (pair 'read (fn (_ . args) (list (%buf-tok (first args)) (%read-variant args))))))
  (Base make-type %b "V-WS"
    (list (pair 'analyse (fn (_ buffer score chr) (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "ab c "))
  (newline))
```
---
    (("ab" ()) ("c" ()))
