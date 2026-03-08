; regex.x -- Regex type with rudimentary pattern matching
;
; Supports: literal chars, . (any), * (zero+), + (one+), ? (optional), \ (escape)
; Full-string match semantics: pattern must match entire input.
;
; Usage:
;   (def rx (regex "ab*c"))
;   (rx "abbc")              ; → t
;   (rx "abd")               ; → ()
;   (write rx)               ; → #/ab*c/

; --- Compiler: pattern string → AST ---
;
; AST nodes: (lit "a"), (any), (star <node>), (plus <node>), (opt <node>)
;
; Note: x-lang strings have no escape processing, so we extract a single
; backslash character via string-ref from a 2-char "\\" literal.
(def %regex-bs (string-ref "\\" 0))

(def regex-compile (fn (pattern)
  (def len (string-length pattern))
  (def go (fn (i acc)
    (if (>= i len)
      (reverse acc)
      (let ((ch (string-ref pattern i)))
        (match
          ; Escape: next char is literal
          ((string=? ch %regex-bs)
            (if (>= (+ i 1) len)
              (go (+ i 1) (pair (list (lit lit) %regex-bs) acc))
              (go (+ i 2)
                (pair (list (lit lit) (string-ref pattern (+ i 1))) acc))))
          ; Dot: any single character
          ((string=? ch ".")
            (go (+ i 1) (pair (list (lit any)) acc)))
          ; Star: zero or more (postfix, wraps previous node)
          ((string=? ch "*")
            (if (null? acc)
              (go (+ i 1) (pair (list (lit lit) "*") acc))
              (go (+ i 1)
                (pair (list (lit star) (first acc)) (rest acc)))))
          ; Plus: one or more (postfix)
          ((string=? ch "+")
            (if (null? acc)
              (go (+ i 1) (pair (list (lit lit) "+") acc))
              (go (+ i 1)
                (pair (list (lit plus) (first acc)) (rest acc)))))
          ; Question: optional (postfix)
          ((string=? ch "?")
            (if (null? acc)
              (go (+ i 1) (pair (list (lit lit) "?") acc))
              (go (+ i 1)
                (pair (list (lit opt) (first acc)) (rest acc)))))
          ; Literal character
          (t (go (+ i 1)
               (pair (list (lit lit) ch) acc))))))))
  (go 0 ())))

; --- Matcher ---

; Forward-declare for mutual recursion
(def regex-exec ())

; Match a single AST node at position, return new position or ()
(def regex-exec-one (fn (node str pos end)
  (def tag (first node))
  (match
    ((eq? tag (lit lit))
      (if (and (< pos end)
               (string=? (string-ref str pos) (first (rest node))))
        (+ pos 1)
        ()))
    ((eq? tag (lit any))
      (if (< pos end) (+ pos 1) ()))
    ; Nested quantifiers: delegate to full exec
    (t (regex-exec (list node) str pos end)))))

; Greedy star: collect all reachable positions, try rest from farthest first
(def regex-exec-star (fn (inner rest-nodes str pos end)
  (def collect (fn (p)
    (def next (regex-exec-one inner str p end))
    (if (null? next)
      (list p)
      (pair p (collect next)))))
  (def try-from (fn (ps)
    (if (null? ps)
      ()
      (let ((r (regex-exec rest-nodes str (first ps) end)))
        (if r r (try-from (rest ps)))))))
  (try-from (reverse (collect pos)))))

; Plus: match inner once, then star
(def regex-exec-plus (fn (inner rest-nodes str pos end)
  (def first-match (regex-exec-one inner str pos end))
  (if (null? first-match)
    ()
    (regex-exec-star inner rest-nodes str first-match end))))

; Optional: try with inner (greedy), backtrack to without
(def regex-exec-opt (fn (inner rest-nodes str pos end)
  (def with-inner (regex-exec-one inner str pos end))
  (if (not (null? with-inner))
    (let ((result (regex-exec rest-nodes str with-inner end)))
      (if result result
        (regex-exec rest-nodes str pos end)))
    (regex-exec rest-nodes str pos end))))

; Walk AST node list against string
(set regex-exec (fn (nodes str pos end)
  (if (null? nodes)
    pos
    (let ((node (first nodes))
          (rest-nodes (rest nodes))
          (tag (first (first nodes))))
      (match
        ((eq? tag (lit lit))
          (if (and (< pos end)
                   (string=? (string-ref str pos) (first (rest node))))
            (regex-exec rest-nodes str (+ pos 1) end)
            ()))
        ((eq? tag (lit any))
          (if (< pos end)
            (regex-exec rest-nodes str (+ pos 1) end)
            ()))
        ((eq? tag (lit star))
          (regex-exec-star (first (rest node)) rest-nodes str pos end))
        ((eq? tag (lit plus))
          (regex-exec-plus (first (rest node)) rest-nodes str pos end))
        ((eq? tag (lit opt))
          (regex-exec-opt (first (rest node)) rest-nodes str pos end))
        (t ()))))))

; --- Type definition ---

(def %regex (make-type "REGEX"
  (list
    (pair (lit call) (fn (self . args)
      (def data (first self))
      (def input (first args))
      (def end (string-length input))
      (def result (regex-exec (first data) input 0 end))
      (if (and result (= result end)) t ())))
    (pair (lit write) (fn (self)
      (display "#/")
      (display (rest (first self)))
      (display "/"))))))

(def regex (fn (pattern)
  (make-instance %regex (pair (regex-compile pattern) pattern))))

(def regex? (fn (x) (type? x %regex)))
