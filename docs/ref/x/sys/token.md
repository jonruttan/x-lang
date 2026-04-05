[← Index](../../index.md)

# x/sys/token

Composable tokenizer state machine builders.

> States receive (self buffer score chr). Return self to loop, another state to transition, score to accept, nil to reject.

## Terminators

### `token-accept`

Accept the current token, rewinding the last character. Standard terminator for states.

**Parameters:**

- **buffer** : `ANY` — Token buffer
- **score** : `ANY` — Score atom
- **chr** : `ANY` — Current character

**Returns:** `ANY` — Score object (signals match)

### `token-accept-inclusive`

Accept the current token including the current character.

**Parameters:**

- **buffer** : `ANY` — Token buffer
- **score** : `ANY` — Score atom
- **chr** : `ANY` — Current character

**Returns:** `ANY` — Score object (signals match)

### `token-reject`

Reject the current token. Returns nil to signal no match.

**Parameters:**

- **buffer** : `ANY` — Token buffer
- **score** : `ANY` — Score atom
- **chr** : `ANY` — Current character

**Returns:** `NIL` — Nil (signals no match)

## State Builders

### `make-digit-state`

Create a state that loops while reading digits, then calls done on non-digit.

**Parameters:**

- **done** : `CALLABLE` — Called on non-digit: (done buffer score chr)

**Returns:** `CALLABLE` — Analyzer state that loops on digits [0-9]

**Examples:**

```
(make-digit-state token-accept) => state that consumes digits then accepts
```

### `make-xdigit-state`

Create a state that loops while reading hex digits, then calls done.

**Parameters:**

- **done** : `CALLABLE` — Called on non-xdigit

**Returns:** `CALLABLE` — Analyzer state that loops on hex digits [0-9a-fA-F]

### `make-char-state`

Create a state that matches a single character, transitioning to next or fail.

**Parameters:**

- **ch** : `INTEGER` — Character code to match
- **next** : `CALLABLE` — Called on match
- **fail** : `CALLABLE` — Called on non-match (or nil to reject)

**Returns:** `CALLABLE` — Analyzer state that matches a specific character

**Examples:**

```
(make-char-state 46 frac-state ()) => match '.' then go to frac-state
```

### `make-pred-state`

Create a state that loops while pred returns truthy, then calls done.

**Parameters:**

- **pred** : `CALLABLE` — Predicate: (pred chr) -> bool
- **done** : `CALLABLE` — Called when pred fails

**Returns:** `CALLABLE` — Analyzer state that loops while predicate holds

**Examples:**

```
(make-pred-state char-alphabetic? token-accept) => match letters
```

### `make-range-state`

Create a state that loops while character code is in the inclusive range.

**Parameters:**

- **lo** : `INTEGER` — Lowest accepted character code
- **hi** : `INTEGER` — Highest accepted character code
- **done** : `CALLABLE` — Called on out-of-range character

**Returns:** `CALLABLE` — Analyzer state that loops while character is in [lo, hi]

**Examples:**

```
(make-range-state 65 90 token-accept) => match uppercase A-Z
```

## Combinators

### `make-alt-state`

Try state-a on the current character. If it rejects, try state-b.

**Parameters:**

- **state-a** : `CALLABLE` — First alternative
- **state-b** : `CALLABLE` — Second alternative

**Returns:** `CALLABLE` — State that tries a then b

**Examples:**

```
(make-alt-state (make-char-state 43 next ()) (make-char-state 45 next ())) => match + or -
```

### `make-str-state`

Create a state chain that matches each character of a string in sequence.

**Parameters:**

- **s** : `STRING` — Literal string to match
- **next** : `CALLABLE` — Called after full match
- **fail** : `CALLABLE` — Called on mismatch (or nil to reject)

**Returns:** `CALLABLE` — Chain of char-states matching a literal string

**Examples:**

```
(make-str-state "0x" hex-digits ()) => match '0x' prefix
```

### `make-count-state`

Match exactly n characters satisfying pred, then call done. Rejects if fewer match.

**Parameters:**

- **n** : `INTEGER` — Exact number of characters to match
- **pred** : `CALLABLE` — Predicate: (pred chr) -> bool
- **done** : `CALLABLE` — Called after exactly n matches

**Returns:** `CALLABLE` — State that matches exactly n characters satisfying pred

**Examples:**

```
(make-count-state 4 char-numeric? token-accept) => match exactly 4 digits
```

### `make-min-state`

Match at least n characters satisfying pred, then loop more, calling done when pred fails.

**Parameters:**

- **n** : `INTEGER` — Minimum number of characters to match
- **pred** : `CALLABLE` — Predicate: (pred chr) -> bool
- **done** : `CALLABLE` — Called after n+ matches on non-matching char

**Returns:** `CALLABLE` — State that matches n or more characters satisfying pred

**Examples:**

```
(make-min-state 1 char-numeric? token-accept) => match 1+ digits
```

### `make-optional-char`

Match a character if present, skip if not. Either way, continue to next.

**Parameters:**

- **ch** : `INTEGER` — Character code to optionally match
- **next** : `CALLABLE` — Next state (reached whether char matched or not)

**Returns:** `CALLABLE` — State that optionally matches a character then continues

**Examples:**

```
(make-optional-char 43 digits) => optionally match '+' then digits
```

