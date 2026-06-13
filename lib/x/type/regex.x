; regex.x -- Regex type with #/pattern/ reader syntax; operations on the Regex class.
;
; Supports: literal chars, . * + ? \ escape,
;   [abc] [a-z] [^abc] character classes,
;   \d \w \s \D \W \S shorthand classes,
;   ^ $ anchors, {n} {n,} {n,m} counted repetition,
;   (group) and | alternation.
;
; The %regex-exec/%regex-parse engine and the type machinery (the #/.../ reader,
; call/write slots) stay module-level %-privates -- the reader runs in tokenizer
; context and must not go through class dispatch. The Regex class wraps them.

(import x/type/object)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref (lit buf) (lit tok)))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))



; --- Matcher ---
; Forward-declare for mutual recursion

(def %regex-exec ())
(def %regex-parse ())

; Word character check: [0-9A-Za-z_]
(def %regex-is-word-char
  (fn (_ c)
    (if (and (>= c 48) (<= c 57)) #t
      (if (and (>= c 65) (<= c 90)) #t
        (if (and (>= c 97) (<= c 122)) #t
          (= c 95))))))

; Character class membership: check if chr (char) matches any entry (int codes)
(def %regex-class-match
  (fn (self entries chr)
    (def c (char->integer chr))
    (if (null? entries) #f
      (let ((e (first entries)))
        (if (pair? e)
          ; range: (lo . hi) — integer codes
          (if (and (>= c (first e)) (<= c (rest e)))
            #t (self (rest entries) chr))
          ; literal char code
          (if (= c e)
            #t (self (rest entries) chr)))))))

; Match a single AST node at position, return new position or ()
(def %regex-exec-one
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
      (#t (%regex-exec (list node) str pos end)))))

; Greedy star: collect all reachable positions, try rest from farthest first
(def %regex-exec-star
  (fn (_ inner rest-nodes str pos end)
    (def collect
      (fn (self p)
        (def next (%regex-exec-one inner str p end))
        (if (null? next) (list p) (pair p (self next)))))
    (def try-from
      (fn (self ps)
        (if (null? ps) ()
          (let ((r (%regex-exec rest-nodes str (first ps) end)))
            (if r r (self (rest ps)))))))
    (try-from (reverse (collect pos)))))

; Plus: match inner once, then star
(def %regex-exec-plus
  (fn (_ inner rest-nodes str pos end)
    (def first-match (%regex-exec-one inner str pos end))
    (if (null? first-match) ()
      (%regex-exec-star inner rest-nodes str first-match end))))

; Optional: try with inner (greedy), backtrack to without
(def %regex-exec-opt
  (fn (_ inner rest-nodes str pos end)
    (def with-inner (%regex-exec-one inner str pos end))
    (if (not (null? with-inner))
      (let ((result (%regex-exec rest-nodes str with-inner end)))
        (if result result (%regex-exec rest-nodes str pos end)))
      (%regex-exec rest-nodes str pos end))))

; Lazy star: try shortest match first (don't reverse)
(def %regex-exec-lazy-star
  (fn (_ inner rest-nodes str pos end)
    (def collect
      (fn (self p)
        (def next (%regex-exec-one inner str p end))
        (if (null? next) (list p) (pair p (self next)))))
    (def try-from
      (fn (self ps)
        (if (null? ps) ()
          (let ((r (%regex-exec rest-nodes str (first ps) end)))
            (if r r (self (rest ps)))))))
    (try-from (collect pos))))

; Lazy plus: match once, then lazy star
(def %regex-exec-lazy-plus
  (fn (_ inner rest-nodes str pos end)
    (def first-match (%regex-exec-one inner str pos end))
    (if (null? first-match) ()
      (%regex-exec-lazy-star inner rest-nodes str first-match end))))

; Lazy optional: try WITHOUT inner first, then with
(def %regex-exec-lazy-opt
  (fn (_ inner rest-nodes str pos end)
    (let ((without (%regex-exec rest-nodes str pos end)))
      (if without without
        (let ((with-inner (%regex-exec-one inner str pos end)))
          (if (null? with-inner) ()
            (%regex-exec rest-nodes str with-inner end)))))))

; Counted repetition: match inner between min and max times
(def %regex-exec-repeat
  (fn (_ inner min max rest-nodes str pos end)
    ; Collect positions from min to max matches (greedy)
    (def collect-from
      (fn (self count p)
        (if (> count max) ()
          (if (< count min)
            (let ((next (%regex-exec-one inner str p end)))
              (if (null? next) () (self (+ count 1) next)))
            (let ((next (%regex-exec-one inner str p end)))
              (if (null? next) (list p)
                (pair p (self (+ count 1) next))))))))
    (def positions (collect-from 0 pos))
    (def try-from
      (fn (self ps)
        (if (null? ps) ()
          (let ((r (%regex-exec rest-nodes str (first ps) end)))
            (if r r (self (rest ps)))))))
    (try-from (reverse positions))))

; Walk AST node list against string
(set! %regex-exec
  (fn (_ nodes str pos end)
    (if (null? nodes) pos
      (let ((node (first nodes))
            (rest-nodes (rest nodes))
            (tag (first (first nodes))))
        (match
          ((eq? tag (lit lit))
            (if (and (< pos end)
                  (= (str-ref str pos) (first (rest node))))
              (%regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit any))
            (if (< pos end)
              (%regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit class))
            (if (and (< pos end)
                  (%regex-class-match (rest node) (str-ref str pos)))
              (%regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit nclass))
            (if (and (< pos end)
                  (not (%regex-class-match (rest node) (str-ref str pos))))
              (%regex-exec rest-nodes str (+ pos 1) end) ()))
          ((eq? tag (lit star))
            (%regex-exec-star (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit plus))
            (%regex-exec-plus (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit opt))
            (%regex-exec-opt (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-star))
            (%regex-exec-lazy-star (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-plus))
            (%regex-exec-lazy-plus (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit lazy-opt))
            (%regex-exec-lazy-opt (first (rest node)) rest-nodes str pos end))
          ((eq? tag (lit repeat))
            (%regex-exec-repeat (first (rest node))
              (first (rest (rest node)))
              (first (rest (rest (rest node))))
              rest-nodes str pos end))
          ((eq? tag (lit group))
            (%regex-exec (append (first (rest node)) rest-nodes) str pos end))
          ((eq? tag (lit alt))
            (let ((left (%regex-exec (append (first (rest node)) rest-nodes) str pos end)))
              (if left left
                (%regex-exec (append (first (rest (rest node))) rest-nodes) str pos end))))
          ((eq? tag (lit anchor-start))
            (if (= pos 0) (%regex-exec rest-nodes str pos end) ()))
          ((eq? tag (lit anchor-word-boundary))
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (char->integer (str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (char->integer (str-ref str pos))))))
              (if (eq? left-word right-word) ()
                (%regex-exec rest-nodes str pos end))))
          ((eq? tag (lit anchor-not-word-boundary))
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (char->integer (str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (char->integer (str-ref str pos))))))
              (if (eq? left-word right-word)
                (%regex-exec rest-nodes str pos end) ())))
          ((eq? tag (lit anchor-end))
            (if (= pos end) (%regex-exec rest-nodes str pos end) ()))
          (#t ()))))))

; --- Write: reconstruct pattern from AST ---

(def %regex-write-node
  (fn (self node)
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
            (#t (display (%cvt ch %char))))))
      ((eq? tag (lit any)) (display "."))
      ((eq? tag (lit star))
        (do (self (first (rest node))) (display "*")))
      ((eq? tag (lit plus))
        (do (self (first (rest node))) (display "+")))
      ((eq? tag (lit opt))
        (do (self (first (rest node))) (display "?")))
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
        (do (self (first (rest node))) (display "*?")))
      ((eq? tag (lit lazy-plus))
        (do (self (first (rest node))) (display "+?")))
      ((eq? tag (lit lazy-opt))
        (do (self (first (rest node))) (display "??")))
      ((eq? tag (lit repeat))
        (let ((mx (first (rest (rest (rest node))))))
            (self (first (rest node)))
            (display "{")
            (display (first (rest (rest node))))
            (if (= mx 999999999)
              (display ",")
              (if (not (= mx (first (rest (rest node)))))
                (do (display ",") (display mx))))
            (display "}"))))))

(def %regex-write-class
  (fn (self entries)
    (if (not (null? entries))
      (let ((e (first entries)))
        (if (pair? e)
          (do (display (%cvt (first e) %char))
              (display "-")
              (display (%cvt (rest e) %char)))
          (display (%cvt e %char)))
        (self (rest entries))))))

(def %regex-write
  (fn (self nodes)
    (if (not (null? nodes))
      (do (%regex-write-node (first nodes))
          (self (rest nodes))))))

; --- Parser: compile pattern string to AST ---

; Parse {n}, {n,}, {n,m} and wrap node
(def %regex-parse-repeat-wrap
  (fn (_ s pos end node)
    ; Parse integer
    (def %parse-int
      (fn (self i acc)
        (if (>= i end) (pair acc i)
          (let ((ch (str-ref s i)))
            (if (and (>= ch 48) (<= ch 57))
              (self (+ i 1) (+ (* acc 10) (- ch 48)))
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
      (fn (self i acc)
        (if (>= i end) (pair (pair tag (reverse acc)) i)
          (let ((ch (char->integer (str-ref s i))))
            (match
              ((= ch #\])
                (pair (pair tag (reverse acc)) (+ i 1)))
              ; Escape inside class: \d \w \s etc. expand to ranges/literals
              ((= ch #\\)
                (if (>= (+ i 1) end) (self (+ i 1) (pair ch acc))
                  (let ((esc (char->integer (str-ref s (+ i 1)))))
                    (match
                      ((= esc #\d) (self (+ i 2) (pair (pair 48 57) acc)))
                      ((= esc #\w) (self (+ i 2) (pair 95 (pair (pair 97 122) (pair (pair 65 90) (pair (pair 48 57) acc))))))
                      ((= esc #\s) (self (+ i 2) (pair 13 (pair 10 (pair 9 (pair 32 acc))))))
                      (#t (self (+ i 2) (pair esc acc)))))))
              ; Range: a-z
              ((and (< (+ i 2) end) (= (char->integer (str-ref s (+ i 1))) #\-))
                (let ((hi (char->integer (str-ref s (+ i 2)))))
                  (self (+ i 3) (pair (pair ch hi) acc))))
              (#t (self (+ i 1) (pair ch acc))))))))
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
      (fn (self i acc)
        (if (>= i end) (pair (reverse acc) i)
          (let ((ch (str-ref s i)))
            (match
              ((and (= ch #\)) (> depth 0)) (pair (reverse acc) i))
              ((= ch #\|) (pair (reverse acc) i))
              ((= ch #\^) (self (+ i 1) (pair (list (lit anchor-start)) acc)))
              ((= ch #\$) (self (+ i 1) (pair (list (lit anchor-end)) acc)))
              (#t
                (let ((atom (%regex-parse-atom s i end)))
                  (def node (first atom))
                  (def next-i (rest atom))
                  (let ((q (%regex-wrap-quantifier s next-i end node)))
                    (self (rest q) (pair (first q) acc))))))))))
    (%go pos ())))

; Top-level parse: pattern string to AST node list
(set! %regex-parse
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
  (fn (_ _ _ _)
    %regex-scan-body))

; --- Type definition ---

(set! %regex
  (%make-type
    "REGEX"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          (def input (first args))
          (def end (str-length input))
          (def result (%regex-exec (first self) input 0 end))
          (if (and result (= result end)) #t #f)))
      (pair
        (lit write)
        (fn (_ self)
          (display "#/")
          (%regex-write (first self))
          (display "/")))
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (= chr #\#)
            (fn (_ buf sc c0)
              (if (= c0 #\/) %regex-scan-body ()))
            ())))
      (pair (lit read)
        (fn (_ . args)
          (def tok (%buffer-token (first args)))
          ; Strip #/ prefix and / suffix
          (def pattern (substring tok 2 (- (str-length tok) 1)))
          (%make-instance %regex (%regex-parse pattern)))))))

(set! %regex-read
  (fn (_ . args) (%make-instance %regex (first args))))

(def %regex-get-replacement
  (fn (_ rep matched)
    (if (procedure? rep) (rep matched) rep)))

(def-class Regex ()
  (static
    (method regex? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a regex." (returns BOOLEAN "True if x is a regex"))
      (%type? x %regex))
    (method match (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Test whether a regex matches an entire string." (returns BOOLEAN "True if regex matches the entire string"))
      (def end (str-length str))
      (def result (%regex-exec (first rx) str 0 end))
      (if (and result (= result end)) #t #f))
    (method search (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Search for the first occurrence of a regex pattern in a string." (returns LIST "Pair (start end) of first match, or nil if not found"))
      (def end (str-length str))
      (def %try
        (fn (self i)
          (if (> i end) ()
            (let ((result (%regex-exec (first rx) str i end)))
              (if result (list i result)
                (self (+ i 1)))))))
      (%try 0))
    (method find-at (self (param rx REGEX "Compiled regex") (param str STRING "Input string") (param pos INTEGER "Start position"))
      (doc "Search for regex starting from position pos." (returns LIST "Pair (start end) of match, or nil"))
      (def end (str-length str))
      (def %try
        (fn (self i)
          (if (> i end) ()
            (let ((result (%regex-exec (first rx) str i end)))
              (if result (list i result)
                (self (+ i 1)))))))
      (%try pos))
    (method find (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Find first match and return the matched substring." (returns STRING "Matched substring, or nil")
        (example "(Regex find #/[0-9]+/ \"abc123def\")" "\"123\""))
      (def m (Regex search rx str))
      (if (null? m) ()
        (substring str (first m) (first (rest m)))))
    (method find-all (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Find all non-overlapping matches as a list of substrings." (returns LIST "List of matched substrings")
        (example "(Regex find-all #/[0-9]+/ \"a1b22c333\")" "(\"1\" \"22\" \"333\")"))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at rx str pos))
          (if (null? m) (reverse acc)
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair (substring str start end) acc))))))
      (%go 0 ()))
    (method find-all-pos (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Find all non-overlapping match positions." (returns LIST "List of (start end) pairs"))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at rx str pos))
          (if (null? m) (reverse acc)
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair m acc))))))
      (%go 0 ()))
    (method count (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Count the number of non-overlapping matches." (returns INTEGER "Number of non-overlapping matches")
        (example "(Regex count #/[0-9]+/ \"a1b22c333\")" "3"))
      (length (Regex find-all-pos rx str)))
    (method replace (self (param rx REGEX "Compiled regex") (param str STRING "Input string") (param rep ANY "Replacement string or function"))
      (doc "Replace the first match. rep can be a string or a function that receives the matched text." (returns STRING "String with first match replaced")
        (example "(Regex replace #/[0-9]+/ \"abc123def\" \"N\")" "\"abcNdef\""))
      (def m (Regex search rx str))
      (if (null? m) str
        (let ((matched (substring str (first m) (first (rest m)))))
          (%str-append
            (substring str 0 (first m))
            (%str-append (%regex-get-replacement rep matched)
              (substring str (first (rest m)) (str-length str)))))))
    (method replace-all (self (param rx REGEX "Compiled regex") (param str STRING "Input string") (param rep ANY "Replacement string or function"))
      (doc "Replace all matches. rep can be a string or a function that receives each matched text." (returns STRING "String with all matches replaced")
        (example "(Regex replace-all #/[0-9]+/ \"a1b22c333\" \"N\")" "\"aNbNcN\""))
      (def len (str-length str))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at rx str pos))
          (if (null? m)
            (%str-append acc (substring str pos len))
            (let ((start (first m)))
              (def end (first (rest m)))
              (def matched (substring str start end))
              (def next (if (= start end) (+ end 1) end))
              (self next
                (%str-append acc
                  (%str-append (substring str pos start)
                    (%regex-get-replacement rep matched))))))))
      (%go 0 ""))
    (method split (self (param rx REGEX "Compiled regex") (param str STRING "Input string"))
      (doc "Split a string at regex matches." (returns LIST "List of substrings between matches")
        (example "(Regex split #/,/ \"a,b,c\")" "(\"a\" \"b\" \"c\")"))
      (def len (str-length str))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at rx str pos))
          (if (null? m)
            (reverse (pair (substring str pos len) acc))
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair (substring str pos start) acc))))))
      (%go 0 ()))
    (method exec (self (param nodes LIST "List of AST nodes from a compiled regex")
                       (param str STRING "Input string to match against")
                       (param pos INTEGER "Starting position in the string")
                       (param end INTEGER "End position (string length)"))
      (doc "Execute a regex AST against a string from the given position."
        (returns INTEGER "Final position after match, or nil on failure"))
      (%regex-exec nodes str pos end))
    (method parse (self (param pattern STRING "Regex pattern string"))
      (doc "Parse a regex pattern string into an executable AST." (returns LIST "AST node list"))
      (%regex-parse pattern))))

(doc (provide x/type/regex Regex)
  (note "Syntax: #/pattern/. Supports: . * + ? \\ [class] [^neg] (group) | alternation ^ $ anchors {n,m} repetition \\d \\w \\s.")
  (example "(Regex find #/[0-9]+/ \"abc123def\")" "\"123\"")
  (example "(Regex replace-all #/[0-9]+/ \"a1b2\" \"N\")" "\"aNbN\"")
  (example "(Regex split #/,/ \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "Regular expressions with literal syntax; operations homed on the Regex class.")
