; token.x -- Composable tokenizer state builders
(import x/type/char)
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))


(note "Terminators")

(doc (def token-accept
  (fn (_ (param buffer ANY "Token buffer") (param score ANY "Score atom") _)
    (buffer-unread buffer)
    (score-set score 1 buffer)))
  (returns ANY "Score object (signals match)")
  "Accept the current token, rewinding the last character. Standard terminator for states.")

(doc (def token-accept-inclusive
  (fn (_ (param buffer ANY "Token buffer") (param score ANY "Score atom") _)
    (score-set score 1 buffer)))
  (returns ANY "Score object (signals match)")
  "Accept the current token including the current character.")

(doc (def token-reject
  (fn (_ _ _ _)
    ()))
  (returns NIL "Nil (signals no match)")
  "Reject the current token. Returns nil to signal no match.")

(note "State Builders")

(doc (def make-digit-state
  (fn (_ (param done CALLABLE "Called on non-digit: (done buffer score chr)"))
    (fn (self buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        self
        (done buffer score chr)))))
  (returns CALLABLE "Analyzer state that loops on digits [0-9]")
  (example "(make-digit-state token-accept)" "state that consumes digits then accepts")
  "Create a state that loops while reading digits, then calls done on non-digit.")

(doc (def make-xdigit-state
  (fn (_ (param done CALLABLE "Called on non-xdigit"))
    (fn (self buffer score chr)
      (if (or (and (>= chr 48) (<= chr 57))
              (and (>= chr 65) (<= chr 70))
              (and (>= chr 97) (<= chr 102)))
        self
        (done buffer score chr)))))
  (returns CALLABLE "Analyzer state that loops on hex digits [0-9a-fA-F]")
  "Create a state that loops while reading hex digits, then calls done.")

(doc (def make-char-state
  (fn (_ (param ch INTEGER "Character code to match")
       (param next CALLABLE "Called on match")
       (param fail CALLABLE "Called on non-match (or nil to reject)"))
    (fn (_ buffer score chr)
      (if (= chr ch)
        next
        (if (null? fail) () (fail buffer score chr))))))
  (returns CALLABLE "Analyzer state that matches a specific character")
  (example "(make-char-state 46 frac-state ())" "match '.' then go to frac-state")
  "Create a state that matches a single character, transitioning to next or fail.")

(doc (def make-pred-state
  (fn (_ (param pred CALLABLE "Predicate: (pred chr) -> bool")
       (param done CALLABLE "Called when pred fails"))
    (fn (self buffer score chr)
      (if (pred chr)
        self
        (done buffer score chr)))))
  (returns CALLABLE "Analyzer state that loops while predicate holds")
  (example "(make-pred-state (fn (_ c) (Char alphabetic? c)) token-accept)" "match letters")
  "Create a state that loops while pred returns truthy, then calls done.")

(doc (def make-range-state
  (fn (_ (param lo INTEGER "Lowest accepted character code")
       (param hi INTEGER "Highest accepted character code")
       (param done CALLABLE "Called on out-of-range character"))
    (fn (self buffer score chr)
      (if (and (>= chr lo) (<= chr hi))
        self
        (done buffer score chr)))))
  (returns CALLABLE "Analyzer state that loops while character is in [lo, hi]")
  (example "(make-range-state 65 90 token-accept)" "match uppercase A-Z")
  "Create a state that loops while character code is in the inclusive range.")

(note "Combinators")

(doc (def make-alt-state
  (fn (_ (param state-a CALLABLE "First alternative")
       (param state-b CALLABLE "Second alternative"))
    (fn (_ buffer score chr)
      (def result (state-a buffer score chr))
      (if (null? result)
        (state-b buffer score chr)
        result))))
  (returns CALLABLE "State that tries a then b")
  (example "(make-alt-state (make-char-state 43 next ()) (make-char-state 45 next ()))" "match + or -")
  "Try state-a on the current character. If it rejects, try state-b.")

(doc (def make-str-state
  (fn (_ (param s STRING "Literal string to match")
       (param next CALLABLE "Called after full match")
       (param fail CALLABLE "Called on mismatch (or nil to reject)"))
    ; byte-level literal match: str-ref is the byte accessor (immune to any
    ; pushed code-point handler), so this is safe inside the tokenizer.
    (def len (str-length s))
    (def %build
      (fn (self i)
        (if (= i len) next
          (make-char-state (%char->integer (str-ref s i))
            (self (+ i 1))
            fail))))
    (%build 0)))
  (returns CALLABLE "Chain of char-states matching a literal string")
  (example "(make-str-state \"0x\" hex-digits ())" "match '0x' prefix")
  "Create a state chain that matches each character of a string in sequence.")

(doc (def make-count-state
  (fn (_ (param n INTEGER "Exact number of characters to match")
       (param pred CALLABLE "Predicate: (pred chr) -> bool")
       (param done CALLABLE "Called after exactly n matches"))
    (def %build
      (fn (self remaining)
        (if (= remaining 0) done
          (fn (_ buffer score chr)
            (if (pred chr)
              (self (- remaining 1))
              ())))))
    (%build n)))
  (returns CALLABLE "State that matches exactly n characters satisfying pred")
  (example "(make-count-state 4 (fn (_ c) (Char numeric? c)) token-accept)" "match exactly 4 digits")
  "Match exactly n characters satisfying pred, then call done. Rejects if fewer match.")

(doc (def make-min-state
  (fn (_ (param n INTEGER "Minimum number of characters to match")
       (param pred CALLABLE "Predicate: (pred chr) -> bool")
       (param done CALLABLE "Called after n+ matches on non-matching char"))
    (make-count-state n pred (make-pred-state pred done))))
  (returns CALLABLE "State that matches n or more characters satisfying pred")
  (example "(make-min-state 1 (fn (_ c) (Char numeric? c)) token-accept)" "match 1+ digits")
  "Match at least n characters satisfying pred, then loop more, calling done when pred fails.")

(doc (def make-optional-char
  (fn (_ (param ch INTEGER "Character code to optionally match")
       (param next CALLABLE "Next state (reached whether char matched or not)"))
    (make-char-state ch next next)))
  (returns CALLABLE "State that optionally matches a character then continues")
  (example "(make-optional-char 43 digits)" "optionally match '+' then digits")
  "Match a character if present, skip if not. Either way, continue to next.")

(doc (provide x/sys/token
  token-accept token-accept-inclusive token-reject
  make-digit-state make-xdigit-state make-char-state
  make-pred-state make-range-state
  make-alt-state make-str-state make-count-state
  make-min-state make-optional-char)
  (note "States receive (self buffer score chr). Return self to loop, another state to transition, score to accept, nil to reject.")
  (example "(make-digit-state (make-char-state 46 (make-digit-state token-accept) ()))" "integer.fractional")
  "Composable tokenizer state machine builders.")
