# Buffer reading and predicate (Buf) -- PENDING

These cover `Buf read`/`Buf tok` behaviour (read advances, end-of-input -> `()`,
`tok` returns the consumed text) and the `Buf buffer?` predicate -- methods that
still exist. They are **pending** because a buffer can't yet be *constructed*
from x-lang: a buffer is non-owning cursors into a memory vector, and that
backing type doesn't exist yet. When it lands, re-point the construction line in
each case (currently the removed `Buf make`) at the new constructor and add the
`---` + expected block back to activate it.

(A test with no `---` separator is counted *pending*, not run -- see
tests/spec-format.md.)

## Buf construction & reading

### construction yields a BUFFER

```scheme
(Type name (Type of (Buf make "hello")))
```

### read advances; tok returns the consumed bytes

```scheme
(do (def b (Buf make "hi")) (Buf read b) (Buf read b) (Buf tok b))
```

### reads the whole input in order

```scheme
(do (def b (Buf make "abc")) (Buf read b) (Buf read b) (Buf read b) (Buf tok b))
```

### a read-only view returns () at end of input

```scheme
(null? (do (def b (Buf make "x")) (Buf read b) (Buf read b)))
```

### empty input is an immediately-exhausted buffer

```scheme
(null? (do (def b (Buf make "")) (Buf read b)))
```

## Buf buffer?

### true for a buffer

```scheme
(Buf buffer? (Buf make "x"))
```

### false for a string

```scheme
(if (Buf buffer? "x") "yes" "no")
```

### false for an integer

```scheme
(if (Buf buffer? 42) "yes" "no")
```
