; regex.x -- Regex type with #/pattern/ reader syntax
;
; Supports: literal chars, . * + ? \ escape,
;   [abc] [a-z] [^abc] character classes,
;   \d \w \s \D \W \S shorthand classes,
;   ^ $ anchors, {n} {n,} {n,m} counted repetition,
;   (group) and | alternation.

; --- Matcher ---
; Forward-declare for mutual recursion

(def regex-exec ())
(def regex-parse ())

; Word character check: [0-9A-Za-z_]
(def %regex-is-word-char
  (fn (_ c)
    (if (and (>= c 48) (<= c 57)) #t
      (if (and (>= c 65) (<= c 90)) #t
        (if (and (>= c 97) (<= c 122)) #t
          (= c 95))))))

; Character class membership: check if chr (char) matches any entry (int codes)
(def %regex-class-match
  (fn (_ entries chr)
    (def c (char->integer chr))
    (if (null? entries) #f
      (let ((e (first entries)))
        (if (pair? e)
          ; range: (lo . hi) — integer codes
          (if (and (>= c (first e)) (<= c (rest e)))
            #t (%regex-class-match (rest entries) chr))
          ; literal char code
          (if (= c e)
            #t (%regex-class-match (rest entries) chr)))))))

; Match a single AST node at position, return new position or ()
(def regex-exec-one
  (fn (_ node str pos end)
    (def tag (first node))
    (match
      ((eq? tag (lit lit))
        (if (and (< pos end)
              (= (str-ref str pos) (first (rest node))))
          (+ pos 1) ()))
      ((eq? tag (lit any))
        (if (< pos end) (+ pos 1) ()))
      ((eq? tag (lit class))
        (if (< pos end)
          (if (%regex-class-match (rest node) (str-ref str pos))
            (+ pos 1) ())
          ()))
      ((eq? tag (lit nclass))
        (if (< pos end)
          (if (%regex-class-match (rest node) (str-ref str pos))
            () (+ pos 1))
          ()))
      ; Nested quantifiers: delegate to full exec
      (#t (regex-exec (list node) str pos end)))))

; Greedy star: collect all reachable positions, try rest from farthest first
(def regex-exec-star
  (fn (_ inner rest-nodes str pos end)
    (def collect
      (fn (_ p)
        (def next (regex-exec-one inner str p end))
        (if (null? next) (list p) (pair p (collect next)))))
    (def try-from
      (fn (_ ps)
        (if (null? ps) ()
          (let ((r (regex-exec rest-nodes str (first ps) end)))
            (if r r (try-from (rest ps)))))))
    (try-from (reverse (collect pos)))))

; Plus: match inner once, then star
(def regex-exec-plus
  (fn (_ inner rest-nodes str pos end)
    (def first-match (regex-exec-one inner str pos end))
    (if (null? first-match) ()
      (regex-exec-star inner rest-nodes str first-match end))))

; Optional: try with inner (greedy), backtrack to without
(def regex-exec-opt
  (fn (_ inner rest-nodes str pos end)
    (def with-inner (regex-exec-one inner str pos end))
    (if (not (null? with-inner))
      (let ((result (regex-exec rest-nodes str with-inner end)))
        (if result result (regex-exec rest-nodes str pos end)))
      (regex-exec rest-nodes str pos end))))

; Lazy star: try shortest match first (don't reverse)
(def regex-exec-lazy-star
  (fn (_ inner rest-nodes str pos end)
    (def collect
      (fn (_ p)
        (def next (regex-exec-one inner str p end))
        (if (null? next) (list p) (pair p (collect next)))))
    (def try-from
      (fn (_ ps)
        (if (null? ps) ()
          (let ((r (regex-exec rest-nodes str (first ps) end)))
            (if r r (try-from (rest ps)))))))
    (try-from (collect pos))))

; Lazy plus: match once, then lazy star
(def regex-exec-lazy-plus
  (fn (_ inner rest-nodes str pos end)
    (def first-match (regex-exec-one inner str pos end))
    (if (null? first-match) ()
      (regex-exec-lazy-star inner rest-nodes str first-match end))))

; Lazy optional: try WITHOUT inner first, then with
(def regex-exec-lazy-opt
  (fn (_ inner rest-nodes str pos end)
    (let ((without (regex-exec rest-nodes str pos end)))
      (if without without
        (let ((with-inner (regex-exec-one inner str pos end)))
          (if (null? with-inner) ()
            (regex-exec rest-nodes str with-inner end)))))))

; Counted repetition: match inner between min and max times
(def regex-exec-repeat
  (fn (_ inner min max rest-nodes str pos end)
    ; Match inner exactly n times from pos
    (def match-n
      (fn (_ n p)
        (if (= n 0) p
          (let ((next (regex-exec-one inner str p end)))
            (if (null? next) () (match-n (- n 1) next))))))
    ; Collect positions from min to max matches (greedy)
    (def collect-from
      (fn (_ count p)
        (if (> count max) ()
          (if (< count min)
            (let ((next (regex-exec-one inner str p end)))
              (if (null? next) () (collect-from (+ count 1) next)))
            (let ((next (regex-exec-one inner str p end)))
              (if (null? next) (list p)
                (pair p (collect-from (+ count 1) next))))))))
    (def positions (collect-from 0 pos))
    (def try-from
      (fn (_ ps)
        (if (null? ps) ()
          (let ((r (regex-exec rest-nodes str (first ps) end)))
            (if r r (try-from (rest ps)))))))
    (try-from (reverse positions))))

; Walk AST node list against string
(set! regex-exec
  (fn (_ nodes str pos end)
    (if (null? nodes) pos
      (let ((node (first nodes))
            (rest-nodes (rest nodes))
            (tag (first (first nodes))))
        (match
          ((eq? tag (lit lit))
            (if (and (< pos end)
                  (= (str-ref str pos) (first (rest node))))
              (regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit any))
            (if (< pos end)
              (regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit class))
            (if (and (< pos end)
                  (%regex-class-match (rest node) (str-ref str pos)))
              (regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit nclass))
            (if (and (< pos end)
                  (not (%regex-class-match (rest node) (str-ref str pos))))
              (regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit star))
            (regex-exec-star (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit plus))
            (regex-exec-plus (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit opt))
            (regex-exec-opt (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-star))
            (regex-exec-lazy-star (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-plus))
            (regex-exec-lazy-plus (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-opt))
            (regex-exec-lazy-opt (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit repeat))
            (regex-exec-repeat (first (rest node))
              (first (rest (rest node)))
              (first (rest (rest (rest node))))
              rest-nodes str pos end))
          ((eq? tag (lit group))
            (regex-exec (append (first (rest node)) rest-nodes) str pos end))
          ((eq? tag (lit alt))
            (let ((left (regex-exec (append (first (rest node)) rest-nodes) str pos end)))
              (if left left
                (regex-exec (append (first (rest (rest node))) rest-nodes) str pos end))))
          ((eq? tag (lit anchor-start))
            (if (= pos 0) (regex-exec rest-nodes str pos end) ()))
          ((eq? tag (lit anchor-word-boundary))
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (char->integer (str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (char->integer (str-ref str pos))))))
              (if (eq? left-word right-word) ()
                (regex-exec rest-nodes str pos end))))
          ((eq? tag (lit anchor-not-word-boundary))
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (char->integer (str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (char->integer (str-ref str pos))))))
              (if (eq? left-word right-word)
                (regex-exec rest-nodes str pos end) ())))
          ((eq? tag (lit anchor-end))
            (if (= pos end) (regex-exec rest-nodes str pos end) ()))
          (#t ()))))))

; --- Write: reconstruct pattern from AST ---

(def %regex-write-node
  (fn (_ node)
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
            ((= ch #\[) (do (display "\\") (display "[")))
            ((= ch #\() (do (display "\\") (display "(")))
            ((= ch #\|) (do (display "\\") (display "|")))
            ((= ch #\{) (do (display "\\") (display "{")))
            ((= ch #\^) (do (display "\\") (display "^")))
            ((= ch #\$) (do (display "\\") (display "$")))
            (#t (display (convert ch %char))))))
      ((eq? tag (lit any)) (display "."))
      ((eq? tag (lit star))
        (do (%regex-write-node (first (rest node))) (display "*")))
      ((eq? tag (lit plus))
        (do (%regex-write-node (first (rest node))) (display "+")))
      ((eq? tag (lit opt))
        (do (%regex-write-node (first (rest node))) (display "?")))
      ((eq? tag (lit class))
        (do (display "[") (%regex-write-class (rest node)) (display "]")))
      ((eq? tag (lit nclass))
        (do (display "[^") (%regex-write-class (rest node)) (display "]")))
      ((eq? tag (lit group))
        (do (display "(") (%regex-write (first (rest node))) (display ")")))
      ((eq? tag (lit alt))
        (do (%regex-write (first (rest node)))
            (display "|")
            (%regex-write (first (rest (rest node))))))
      ((eq? tag (lit anchor-start)) (display "^"))
      ((eq? tag (lit anchor-end)) (display "$"))
      ((eq? tag (lit anchor-word-boundary)) (display "\\b"))
      ((eq? tag (lit anchor-not-word-boundary)) (display "\\B"))
      ((eq? tag (lit lazy-star))
        (do (%regex-write-node (first (rest node))) (display "*?")))
      ((eq? tag (lit lazy-plus))
        (do (%regex-write-node (first (rest node))) (display "+?")))
      ((eq? tag (lit lazy-opt))
        (do (%regex-write-node (first (rest node))) (display "??")))
      ((eq? tag (lit repeat))
        (do (%regex-write-node (first (rest node)))
            (display "{")
            (display (first (rest (rest node))))
            (def mx (first (rest (rest (rest node)))))
            (if (= mx 999999999)
              (display ",")
              (if (not (= mx (first (rest (rest node)))))
                (do (display ",") (display mx))))
            (display "}"))))))

(def %regex-write-class
  (fn (_ entries)
    (if (not (null? entries))
      (do
        (def e (first entries))
        (if (pair? e)
          (do (display (convert (first e) %char))
              (display "-")
              (display (convert (rest e) %char)))
          (display (convert e %char)))
        (%regex-write-class (rest entries))))))

(def %regex-write
  (fn (_ nodes)
    (if (not (null? nodes))
      (do (%regex-write-node (first nodes))
          (%regex-write (rest nodes))))))

; --- Parser: compile pattern string to AST ---

; Parse {n}, {n,}, {n,m} and wrap node
(def %regex-parse-repeat-wrap
  (fn (_ s pos end node)
    ; Parse integer
    (def %parse-int
      (fn (_ i acc)
        (if (>= i end) (pair acc i)
          (let ((ch (str-ref s i)))
            (if (and (>= ch 48) (<= ch 57))
              (%parse-int (+ i 1) (+ (* acc 10) (- ch 48)))
              (pair acc i))))))
    (def min-r (%parse-int pos 0))
    (def min-val (first min-r))
    (def after-min (rest min-r))
    (if (>= after-min end) (pair node pos)
      (let ((ch (str-ref s after-min)))
        (match
          ; {n}
          ((= ch #\})
            (pair (list (lit repeat) node min-val min-val) (+ after-min 1)))
          ; {n,} or {n,m}
          ((= ch #\,)
            (if (and (< (+ after-min 1) end) (= (str-ref s (+ after-min 1)) #\}))
              ; {n,} — unbounded
              (pair (list (lit repeat) node min-val 999999999) (+ after-min 2))
              ; {n,m}
              (let ((max-r (%parse-int (+ after-min 1) 0)))
                (def max-val (first max-r))
                (def after-max (rest max-r))
                (if (and (< after-max end) (= (str-ref s after-max) #\}))
                  (pair (list (lit repeat) node min-val max-val) (+ after-max 1))
                  (pair node pos)))))
          (#t (pair node pos)))))))

; Wrap node with quantifier if present: * + ? {n,m}
(def %regex-wrap-quantifier
  (fn (_ s pos end node)
    (if (>= pos end) (pair node pos)
      (let ((ch (str-ref s pos)))
        (def lazy (and (< (+ pos 1) end) (= (str-ref s (+ pos 1)) #\?)))
        (match
          ((= ch #\*)
            (if lazy (pair (list (lit lazy-star) node) (+ pos 2))
              (pair (list (lit star) node) (+ pos 1))))
          ((= ch #\+)
            (if lazy (pair (list (lit lazy-plus) node) (+ pos 2))
              (pair (list (lit plus) node) (+ pos 1))))
          ((= ch #\?)
            (if lazy (pair (list (lit lazy-opt) node) (+ pos 2))
              (pair (list (lit opt) node) (+ pos 1))))
          ((= ch #\{) (%regex-parse-repeat-wrap s (+ pos 1) end node))
          (#t (pair node pos)))))))

; Parse escape sequence
(def %regex-parse-escape
  (fn (_ s pos)
    (def ch (str-ref s pos))
    (match
      ((= ch #\d) (pair (list (lit class) (pair 48 57)) (+ pos 1)))
      ((= ch #\D) (pair (list (lit nclass) (pair 48 57)) (+ pos 1)))
      ((= ch #\w) (pair (list (lit class) (pair 48 57) (pair 65 90) (pair 97 122) 95) (+ pos 1)))
      ((= ch #\W) (pair (list (lit nclass) (pair 48 57) (pair 65 90) (pair 97 122) 95) (+ pos 1)))
      ((= ch #\s) (pair (list (lit class) 32 9 10 13) (+ pos 1)))
      ((= ch #\S) (pair (list (lit nclass) 32 9 10 13) (+ pos 1)))
      ((= ch #\b) (pair (list (lit anchor-word-boundary)) (+ pos 1)))
      ((= ch #\B) (pair (list (lit anchor-not-word-boundary)) (+ pos 1)))
      (#t (pair (list (lit lit) ch) (+ pos 1))))))

; Parse character class [...] or [^...]
(def %regex-parse-class
  (fn (_ s pos end)
    (def negated (and (< pos end) (= (str-ref s pos) #\^)))
    (def start (if negated (+ pos 1) pos))
    (def tag (if negated (lit nclass) (lit class)))
    (def %go
      (fn (_ i acc)
        (if (>= i end) (pair (pair tag (reverse acc)) i)
          (let ((ch (char->integer (str-ref s i))))
            (match
              ((= ch #\])
                (pair (pair tag (reverse acc)) (+ i 1)))
              ; Escape inside class: \d \w \s etc. expand to ranges/literals
              ((= ch #\\)
                (if (>= (+ i 1) end) (%go (+ i 1) (pair ch acc))
                  (let ((esc (char->integer (str-ref s (+ i 1)))))
                    (match
                      ((= esc #\d) (%go (+ i 2) (pair (pair 48 57) acc)))
                      ((= esc #\w) (%go (+ i 2) (pair 95 (pair (pair 97 122) (pair (pair 65 90) (pair (pair 48 57) acc))))))
                      ((= esc #\s) (%go (+ i 2) (pair 13 (pair 10 (pair 9 (pair 32 acc))))))
                      (#t (%go (+ i 2) (pair esc acc)))))))
              ; Range: a-z
              ((and (< (+ i 2) end) (= (char->integer (str-ref s (+ i 1))) #\-))
                (let ((hi (char->integer (str-ref s (+ i 2)))))
                  (%go (+ i 3) (pair (pair ch hi) acc))))
              (#t (%go (+ i 1) (pair ch acc))))))))
    (%go start ())))

; Forward-declare mutually recursive parse functions
(def %regex-parse-atom ())
(def %regex-parse-group ())
(def %regex-parse-alt-full ())
(def %regex-parse-seq ())

; --- Set parse functions (mutually recursive) ---

(set! %regex-parse-atom
  (fn (_ s i end)
    (let ((ch (str-ref s i)))
      (match
        ((= ch #\.)
          (pair (list (lit any)) (+ i 1)))
        ((= ch #\\)
          (if (>= (+ i 1) end) (pair (list (lit lit) ch) (+ i 1))
            (%regex-parse-escape s (+ i 1))))
        ((= ch #\[)
          (%regex-parse-class s (+ i 1) end))
        ((= ch #\()
          (let ((inner (%regex-parse-group s (+ i 1) end)))
            (pair (list (lit group) (first inner)) (rest inner))))
        (#t
          (pair (list (lit lit) ch) (+ i 1)))))))

(set! %regex-parse-group
  (fn (_ s pos end)
    (def content (%regex-parse-alt-full s pos end 1))
    (def nodes (first content))
    (def close-pos (rest content))
    (pair nodes (if (and (< close-pos end) (= (str-ref s close-pos) #\)))
                  (+ close-pos 1) close-pos))))

(set! %regex-parse-alt-full
  (fn (_ s pos end depth)
    (def left (%regex-parse-seq s pos end depth))
    (def left-nodes (first left))
    (def left-pos (rest left))
    (if (and (< left-pos end) (= (str-ref s left-pos) #\|))
      (let ((right (%regex-parse-alt-full s (+ left-pos 1) end depth)))
        (pair (list (list (lit alt) left-nodes (first right))) (rest right)))
      left)))

(set! %regex-parse-seq
  (fn (_ s pos end depth)
    (def %go
      (fn (_ i acc)
        (if (>= i end) (pair (reverse acc) i)
          (let ((ch (str-ref s i)))
            (match
              ((and (= ch #\)) (> depth 0)) (pair (reverse acc) i))
              ((= ch #\|) (pair (reverse acc) i))
              ((= ch #\^) (%go (+ i 1) (pair (list (lit anchor-start)) acc)))
              ((= ch #\$) (%go (+ i 1) (pair (list (lit anchor-end)) acc)))
              (#t
                (let ((atom (%regex-parse-atom s i end)))
                  (def node (first atom))
                  (def next-i (rest atom))
                  (let ((q (%regex-wrap-quantifier s next-i end node)))
                    (%go (rest q) (pair (first q) acc))))))))))
    (%go pos ())))

; Top-level parse: pattern string to AST node list
(set! regex-parse
  (fn (_ pattern)
    (def len (str-length pattern))
    (def result (%regex-parse-alt-full pattern 0 len 0))
    (first result)))

; --- Analyser: just match #/ ... / (handle \/ escapes) ---

(def %regex ())
(def %regex-read ())

; Simple analyser: after seeing #, check for /, then scan until unescaped /
(def %regex-scan-escape ())

(def %regex-scan-body
  (fn (self buffer score chr)
    (match
      ((= chr #\/) (score-set score 1 buffer))
      ((= chr #\\) %regex-scan-escape)
      (#t self))))

(set! %regex-scan-escape
  (fn (_ buffer score chr)
    %regex-scan-body))

; --- Type definition ---

(set! %regex
  (make-type
    "REGEX"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          (def input (first args))
          (def end (str-length input))
          (def result (regex-exec (first self) input 0 end))
          (if (and result (= result end)) #t #f)))
      (pair
        (lit write)
        (fn (_ self)
          (display "#/")
          (%regex-write (first self))
          (display "/")))
      (pair (lit first-chars) "#")
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (= chr #\#)
            (fn (_ buffer score chr)
              (if (= chr #\/) %regex-scan-body ()))
            ())))
      (pair (lit read)
        (fn (_ . args)
          (def tok (buffer-token (first args)))
          ; Strip #/ prefix and / suffix
          (def pattern (substring tok 2 (- (str-length tok) 1)))
          (make-instance %regex (regex-parse pattern)))))))

(set! %regex-read
  (fn (_ . args) (make-instance %regex (first args))))

(doc (def regex?
  (fn (_ (param x ANY "Value to test"))
    (type? x %regex)))
  (returns BOOLEAN "True if x is a regex")
  "Test whether a value is a regex.")

(doc (def regex-match
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def end (str-length str))
    (def result (regex-exec (first rx) str 0 end))
    (if (and result (= result end)) #t #f)))
  (returns BOOLEAN "True if regex matches the entire string")
  "Test whether a regex matches an entire string.")

(doc (def regex-search
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def end (str-length str))
    (def %try
      (fn (_ i)
        (if (> i end) ()
          (let ((result (regex-exec (first rx) str i end)))
            (if result (list i result)
              (%try (+ i 1)))))))
    (%try 0)))
  (returns LIST "Pair (start end) of first match, or nil if not found")
  "Search for the first occurrence of a regex pattern in a string.")

; --- Search with offset ---

(doc (def regex-find-at
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string") (param pos INTEGER "Start position"))
    (def end (str-length str))
    (def %try
      (fn (_ i)
        (if (> i end) ()
          (let ((result (regex-exec (first rx) str i end)))
            (if result (list i result)
              (%try (+ i 1)))))))
    (%try pos)))
  (returns LIST "Pair (start end) of match, or nil")
  "Search for regex starting from position pos.")

; --- Extract matched substring ---

(doc (def regex-find
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def m (regex-search rx str))
    (if (null? m) ()
      (substring str (first m) (first (rest m))))))
  (returns STRING "Matched substring, or nil")
  (example "(regex-find #/[0-9]+/ \"abc123def\")" "\"123\"")
  "Find first match and return the matched substring.")

; --- Find all matches ---

(doc (def regex-find-all
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def %go
      (fn (_ pos acc)
        (def m (regex-find-at rx str pos))
        (if (null? m) (reverse acc)
          (do
            (def start (first m))
            (def end (first (rest m)))
            ; Advance by at least 1 to avoid infinite loop on zero-width matches
            (def next (if (= start end) (+ end 1) end))
            (%go next (pair (substring str start end) acc))))))
    (%go 0 ())))
  (returns LIST "List of matched substrings")
  (example "(regex-find-all #/[0-9]+/ \"a1b22c333\")" "(\"1\" \"22\" \"333\")")
  "Find all non-overlapping matches as a list of substrings.")

; --- Find all positions ---

(doc (def regex-find-all-pos
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def %go
      (fn (_ pos acc)
        (def m (regex-find-at rx str pos))
        (if (null? m) (reverse acc)
          (do
            (def start (first m))
            (def end (first (rest m)))
            (def next (if (= start end) (+ end 1) end))
            (%go next (pair m acc))))))
    (%go 0 ())))
  (returns LIST "List of (start end) pairs")
  "Find all non-overlapping match positions.")

; --- Count ---

(doc (def regex-count
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (length (regex-find-all-pos rx str))))
  (returns INTEGER "Number of non-overlapping matches")
  (example "(regex-count #/[0-9]+/ \"a1b22c333\")" "3")
  "Count the number of non-overlapping matches.")

; --- Replace ---

(def %regex-get-replacement
  (fn (_ rep matched)
    (if (procedure? rep) (rep matched) rep)))

(doc (def regex-replace
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string") (param rep ANY "Replacement string or function"))
    (def m (regex-search rx str))
    (if (null? m) str
      (do
        (def matched (substring str (first m) (first (rest m))))
        (str-append
          (substring str 0 (first m))
          (str-append (%regex-get-replacement rep matched)
            (substring str (first (rest m)) (str-length str))))))))
  (returns STRING "String with first match replaced")
  (example "(regex-replace #/[0-9]+/ \"abc123def\" \"N\")" "\"abcNdef\"")
  "Replace the first match. rep can be a string or a function that receives the matched text.")

(doc (def regex-replace-all
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string") (param rep ANY "Replacement string or function"))
    (def len (str-length str))
    (def %go
      (fn (_ pos acc)
        (def m (regex-find-at rx str pos))
        (if (null? m)
          (str-append acc (substring str pos len))
          (do
            (def start (first m))
            (def end (first (rest m)))
            (def matched (substring str start end))
            (def next (if (= start end) (+ end 1) end))
            (%go next
              (str-append acc
                (str-append (substring str pos start)
                  (%regex-get-replacement rep matched))))))))
    (%go 0 "")))
  (returns STRING "String with all matches replaced")
  (example "(regex-replace-all #/[0-9]+/ \"a1b22c333\" \"N\")" "\"aNbNcN\"")
  "Replace all matches. rep can be a string or a function that receives each matched text.")

; --- Split ---

(doc (def regex-split
  (fn (_ (param rx REGEX "Compiled regex") (param str STRING "Input string"))
    (def len (str-length str))
    (def %go
      (fn (_ pos acc)
        (def m (regex-find-at rx str pos))
        (if (null? m)
          (reverse (pair (substring str pos len) acc))
          (do
            (def start (first m))
            (def end (first (rest m)))
            (def next (if (= start end) (+ end 1) end))
            (%go next (pair (substring str pos start) acc))))))
    (%go 0 ())))
  (returns LIST "List of substrings between matches")
  (example "(regex-split #/,/ \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "Split a string at regex matches.")

; --- Internal docs ---

(doc regex-exec
  (param nodes LIST "List of AST nodes from a compiled regex")
  (param str STRING "Input string to match against")
  (param pos INTEGER "Starting position in the string")
  (param end INTEGER "End position (string length)")
  (returns INTEGER "Final position after match, or nil on failure")
  "Execute a regex AST against a string from the given position.")

(doc regex-parse
  (param pattern STRING "Regex pattern string")
  (returns LIST "AST node list")
  "Parse a regex pattern string into an executable AST.")

(doc (provide x/sys/regex
  regex? regex-match regex-search regex-find-at
  regex-find regex-find-all regex-find-all-pos regex-count
  regex-replace regex-replace-all regex-split
  regex-exec regex-parse)
  (note "Syntax: #/pattern/. Supports: . * + ? \\ [class] [^neg] (group) | alternation ^ $ anchors {n,m} repetition \\d \\w \\s.")
  (example "(regex-find #/[0-9]+/ \"abc123def\")" "\"123\"")
  (example "(regex-find-all #/\\w+/ \"hello world\")" "(\"hello\" \"world\")")
  (example "(regex-replace-all #/[0-9]+/ \"a1b2\" \"N\")" "\"aNbN\"")
  (example "(regex-split #/,/ \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "Regular expressions with literal syntax.")
