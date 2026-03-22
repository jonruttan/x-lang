; token.x -- Composable tokenizer state builders
(import x/char)

(note "Terminators")

(doc (def token-accept
  (fn (_ (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character"))
    (buffer-unread buffer)
    (score-set score 1 buffer)))
  (returns ANY "Score object (signals match)")
  "Accept the current token, rewinding the last character. Standard terminator for states.")

(doc (def token-accept-inclusive
  (fn (_ (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character"))
    (score-set score 1 buffer)))
  (returns ANY "Score object (signals match)")
  "Accept the current token including the current character.")

(doc (def token-reject
  (fn (_ (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character"))
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
  (example "(make-pred-state char-alphabetic? token-accept)" "match letters")
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

(doc (provide x/token
  token-accept token-accept-inclusive token-reject
  make-digit-state make-xdigit-state make-char-state
  make-pred-state make-range-state)
  (note "States receive (self buffer score chr). Return self to loop, another state to transition, score to accept, nil to reject.")
  (example "(make-digit-state (make-char-state 46 (make-digit-state token-accept) ()))" "integer.fractional")
  "Composable tokenizer state machine builders.")
