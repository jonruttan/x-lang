; token.x -- Token: composable tokenizer state-machine builders.
;
; The builders run at type-build (setup) time, so they are Token methods. The
; three TERMINATORS (accept/accept-inclusive/reject), however, are invoked
; per-character INSIDE reader/analyse lambdas, where class dispatch would
; allocate and risk a GC mid-C-reader-callback. So their logic lives in
; %-private functions, registered in the catalog under ns `token`; reader-hot
; callers (logo/types.x) fetch-and-cache them and call the cached refs directly
; -- no dispatch on the hot path. The Token class methods are the cold-call API.
(import x/type/char)
(import x/type/object)
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))

; --- Terminators: %-private logic + catalog registration ---
; States call these to finish: accept (rewind last char), accept-inclusive
; (keep it), reject (no match). Registered so reader-context consumers fetch
; raw refs rather than dispatching (Token accept ...) per character.
(def %tok-accept
  (fn (_ buffer score chr)
    (buffer-unread buffer)
    (score-set score 1 buffer)))
(def %tok-accept-inclusive
  (fn (_ buffer score chr)
    (score-set score 1 buffer)))
(def %tok-reject
  (fn (_ buffer score chr) ()))

(prim-reg! (lit token) (lit accept)           %tok-accept)
(prim-reg! (lit token) (lit accept-inclusive) %tok-accept-inclusive)
(prim-reg! (lit token) (lit reject)           %tok-reject)

; --- State builders: %-private logic (cross-reference each other directly) ---
(def %make-digit-state
  (fn (_ done)
    (fn (self buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        self
        (done buffer score chr)))))

(def %make-xdigit-state
  (fn (_ done)
    (fn (self buffer score chr)
      (if (or (and (>= chr 48) (<= chr 57))
              (and (>= chr 65) (<= chr 70))
              (and (>= chr 97) (<= chr 102)))
        self
        (done buffer score chr)))))

(def %make-char-state
  (fn (_ ch next fail)
    (fn (_ buffer score chr)
      (if (= chr ch)
        next
        (if (null? fail) () (fail buffer score chr))))))

(def %make-pred-state
  (fn (_ pred done)
    (fn (self buffer score chr)
      (if (pred chr)
        self
        (done buffer score chr)))))

(def %make-range-state
  (fn (_ lo hi done)
    (fn (self buffer score chr)
      (if (and (>= chr lo) (<= chr hi))
        self
        (done buffer score chr)))))

(def %make-alt-state
  (fn (_ state-a state-b)
    (fn (_ buffer score chr)
      (def result (state-a buffer score chr))
      (if (null? result)
        (state-b buffer score chr)
        result))))

(def %make-str-state
  (fn (_ s next fail)
    ; byte-level literal match: str-ref is the byte accessor (immune to any
    ; pushed code-point handler), so this is safe inside the tokenizer.
    (def len (str-length s))
    (def %build
      (fn (self i)
        (if (= i len) next
          (%make-char-state (%char->integer (str-ref s i))
            (self (+ i 1))
            fail))))
    (%build 0)))

(def %make-count-state
  (fn (_ n pred done)
    (def %build
      (fn (self remaining)
        (if (= remaining 0) done
          (fn (_ buffer score chr)
            (if (pred chr)
              (self (- remaining 1))
              ())))))
    (%build n)))

(def %make-min-state
  (fn (_ n pred done)
    (%make-count-state n pred (%make-pred-state pred done))))

(def %make-optional-char
  (fn (_ ch next)
    (%make-char-state ch next next)))

; --- The Token class: the API over the builders + terminators ---
(def-class Token ()
  (doc "Composable tokenizer state-machine builders. A state is (fn (self buffer score chr) ...) returning self to loop, another state to transition, a score to accept, or nil to reject."
    (note "Terminators (accept/accept-inclusive/reject) run per-character in reader lambdas. Reader-context callers must fetch them raw -- (prim-ref 'token 'accept) -- and call the cached ref, NOT (Token accept ...) (class dispatch allocates, hazardous mid-reader-callback). The class methods are for cold call sites.")
    (sample "(Token make-digit-state (Token make-char-state 46 (Token make-digit-state acc) ()))" "an integer.fractional matcher (acc = an accept terminator)"))
  (static
    ; --- terminators ---
    (method accept (self (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character (ignored)"))
      (doc "Accept the current token, rewinding the last character. The standard state terminator."
        (returns ANY "Score object (signals match)"))
      (%tok-accept buffer score chr))
    (method accept-inclusive (self (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character (ignored)"))
      (doc "Accept the current token INCLUDING the current character."
        (returns ANY "Score object (signals match)"))
      (%tok-accept-inclusive buffer score chr))
    (method reject (self (param buffer ANY "Token buffer") (param score ANY "Score atom") (param chr ANY "Current character (ignored)"))
      (doc "Reject the current token. Returns nil to signal no match."
        (returns NIL "Nil (signals no match)"))
      (%tok-reject buffer score chr))

    ; --- state builders ---
    (method make-digit-state (self (param done CALLABLE "Called on non-digit: (done buffer score chr)"))
      (doc "A state that loops while reading digits [0-9], then calls done on a non-digit."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-digit-state done)" "consumes digits then calls done"))
      (%make-digit-state done))

    (method make-xdigit-state (self (param done CALLABLE "Called on non-xdigit"))
      (doc "A state that loops while reading hex digits [0-9a-fA-F], then calls done."
        (returns CALLABLE "Analyzer state"))
      (%make-xdigit-state done))

    (method make-char-state (self (param ch INT "Character code to match")
                                  (param next CALLABLE "Reached on match")
                                  (param fail CALLABLE "Reached on non-match (or nil to reject)"))
      (doc "A state matching a single character, transitioning to next or fail."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-char-state 46 frac-state ())" "match '.' then frac-state"))
      (%make-char-state ch next fail))

    (method make-pred-state (self (param pred CALLABLE "Predicate: (pred chr) -> bool")
                                  (param done CALLABLE "Called when pred fails"))
      (doc "A state that loops while pred returns truthy, then calls done."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-pred-state (fn (_ c) (Char alphabetic? c)) done)" "match letters"))
      (%make-pred-state pred done))

    (method make-range-state (self (param lo INT "Lowest accepted character code")
                                   (param hi INT "Highest accepted character code")
                                   (param done CALLABLE "Called on out-of-range character"))
      (doc "A state that loops while the character is in the inclusive range [lo, hi]."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-range-state 65 90 done)" "match uppercase A-Z"))
      (%make-range-state lo hi done))

    (method make-alt-state (self (param state-a CALLABLE "First alternative")
                                 (param state-b CALLABLE "Second alternative"))
      (doc "Try state-a on the current character; if it rejects (nil), try state-b."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-alt-state (Token make-char-state 43 next ()) (Token make-char-state 45 next ()))" "match + or -"))
      (%make-alt-state state-a state-b))

    (method make-str-state (self (param s STRING "Literal string to match")
                                 (param next CALLABLE "Reached after full match")
                                 (param fail CALLABLE "Reached on mismatch (or nil to reject)"))
      (doc "A chain of char-states matching each byte of a literal string in sequence."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-str-state \"0x\" hex-digits ())" "match '0x' prefix"))
      (%make-str-state s next fail))

    (method make-count-state (self (param n INT "Exact number of characters to match")
                                   (param pred CALLABLE "Predicate: (pred chr) -> bool")
                                   (param done CALLABLE "Called after exactly n matches"))
      (doc "Match exactly n characters satisfying pred, then call done. Rejects if fewer match. With n=0, returns done directly."
        (returns CALLABLE "Analyzer state (or done when n=0)")
        (sample "(Token make-count-state 4 (fn (_ c) (Char numeric? c)) done)" "exactly 4 digits"))
      (%make-count-state n pred done))

    (method make-min-state (self (param n INT "Minimum number of characters to match")
                                 (param pred CALLABLE "Predicate: (pred chr) -> bool")
                                 (param done CALLABLE "Called after n+ matches on a non-matching char"))
      (doc "Match at least n characters satisfying pred, then loop more, calling done when pred fails."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-min-state 1 (fn (_ c) (Char numeric? c)) done)" "1+ digits"))
      (%make-min-state n pred done))

    (method make-optional-char (self (param ch INT "Character code to optionally match")
                                     (param next CALLABLE "Next state (reached whether or not ch matched)"))
      (doc "Match a character if present, skip it if not; either way continue to next."
        (returns CALLABLE "Analyzer state")
        (sample "(Token make-optional-char 43 digits)" "optionally match '+' then digits"))
      (%make-optional-char ch next))))

(doc (provide x/sys/token Token)
  (note "States receive (self buffer score chr): return self to loop, another state to transition, a score to accept, nil to reject.")
  (note "Terminators registered under catalog ns `token` (accept/accept-inclusive/reject) -- reader-context callers fetch-and-cache them; never dispatch (Token accept ...) per character.")
  "Composable tokenizer state-machine builders on the Token class.")
