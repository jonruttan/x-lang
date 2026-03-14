; regex.x -- Regex type with #/pattern/ reader syntax
;
; Supports: literal chars, . (any), * (zero+), + (one+), ? (optional), \ (escape)
; Full-string match semantics: pattern must match entire input.
;
; Usage:
;   (def rx #/ab*c/)
;   (rx "abbc")              ; -> t
;   (rx "abd")               ; -> ()
;   (write rx)               ; -> #/ab*c/

; --- Matcher ---

; Forward-declare for mutual recursion
(def regex-exec ())

; Match a single AST node at position, return new position or ()
(def regex-exec-one (fn (node str pos end)
  (def tag (first node))
  (match
    ((eq? tag (lit lit))
      (if (and (< pos end)
               (= (string-ref str pos) (first (rest node))))
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
                   (= (string-ref str pos) (first (rest node))))
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

; --- Write: reconstruct pattern from AST ---

(def %regex-write-node (fn (node)
  (def tag (first node))
  (match
    ((eq? tag (lit lit))
      (let ((ch (first (rest node))))
        (match
          ((= ch #\.) (do (display "\\") (display ".")))
          ((= ch #\*) (do (display "\\") (display "*")))
          ((= ch #\+) (do (display "\\") (display "+")))
          ((= ch #\?) (do (display "\\") (display "?")))
          ((= ch #\\) (do (display "\\") (display "\\")))
          (t (display (integer->char ch))))))
    ((eq? tag (lit any)) (display "."))
    ((eq? tag (lit star))
      (do (%regex-write-node (first (rest node)))
          (display "*")))
    ((eq? tag (lit plus))
      (do (%regex-write-node (first (rest node)))
          (display "+")))
    ((eq? tag (lit opt))
      (do (%regex-write-node (first (rest node)))
          (display "?"))))))

(def %regex-write (fn (nodes)
  (if (not (null? nodes))
    (do (%regex-write-node (first nodes))
        (%regex-write (rest nodes))))))

; --- Analyser: state machine that compiles regex at read time ---

; Forward-declare for mutual recursion
(def %regex ())
(def %regex-escape ())

; Shared data cell for dynamic reader: analyser writes, reader reads
(def %regex-read-data ())

; Static reader: creates regex instance from shared data
(def %regex-read (fn args
  (make-instance %regex %regex-read-data)))

; Create a reader closure that captures the compiled AST
(def %regex-make-reader (fn (ast)
  (fn args
    (make-instance %regex ast))))

; Body state: accumulate AST nodes one char at a time
; Note: chr is a stack atom from the tokenizer; (+ chr 0) copies to a heap int
(def %regex-body (fn (acc)
  (fn (buffer score chr)
    (match
      ; End of pattern
      ((= chr #\/)
        (do (set %regex-read-data (reverse acc))
            (score-set score 1 buffer)))
      ; Escape: next char is literal
      ((= chr #\\)
        (%regex-escape acc))
      ; Dot: any single character
      ((= chr #\.)
        (%regex-body (pair (list (lit any)) acc)))
      ; Star: zero or more (postfix, wraps previous node)
      ((= chr #\*)
        (if (null? acc)
          (%regex-body (pair (list (lit lit) (+ chr 0)) acc))
          (%regex-body (pair (list (lit star) (first acc)) (rest acc)))))
      ; Plus: one or more (postfix)
      ((= chr #\+)
        (if (null? acc)
          (%regex-body (pair (list (lit lit) (+ chr 0)) acc))
          (%regex-body (pair (list (lit plus) (first acc)) (rest acc)))))
      ; Question: optional (postfix)
      ((= chr #\?)
        (if (null? acc)
          (%regex-body (pair (list (lit lit) (+ chr 0)) acc))
          (%regex-body (pair (list (lit opt) (first acc)) (rest acc)))))
      ; Literal character
      (t
        (%regex-body (pair (list (lit lit) (+ chr 0)) acc)))))))

; Escape state: next char is literal regardless
(set %regex-escape (fn (acc)
  (fn (buffer score chr)
    (%regex-body (pair (list (lit lit) (+ chr 0)) acc)))))

; --- Type definition ---

(set %regex (make-type "REGEX"
  (list
    (pair (lit call) (fn (self . args)
      (def input (first args))
      (def end (string-length input))
      (def result (regex-exec (first self) input 0 end))
      (if (and result (= result end)) t ())))
    (pair (lit write) (fn (self)
      (display "#/")
      (%regex-write (first self))
      (display "/")))
    (pair (lit read) %regex-read)
    (pair (lit analyse) (fn (buffer score chr)
      (if (= chr #\#)
        (fn (buffer score chr)
          (if (= chr #\/)
            (%regex-body ())
            ()))
        ()))))))

(def regex? (fn (x) (type? x %regex)))
