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

(import x/type/class)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref 'type 'make))
(def %make-instance (prim-ref 'type 'make-instance))
(def %type? (prim-ref 'type '?))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref 'char '->int))




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
    (def c (%char->integer chr))
    (if (null? entries) #f
      (let ((e (first entries)))
        (if (pair? e)
          ; range: (lo . hi) — integer codes
          (if (and (>= c (first e)) (<= c (rest e)))
            #t (self (rest entries) chr))
          ; literal char code
          (if (= c e)
            #t (self (rest entries) chr)))))))

; --- Capture threading (#23) ---
; Every walker takes a `caps` list and returns a STATE (pos . caps) on
; success, () on failure. Backtracking is capture-safe for free: each
; tried alternative carries the caps it accumulated, and abandoning it
; abandons its captures. Group boundaries ride the node stream as
; spliced (g-open N) / (g-close N) markers (see %regex-exec's group
; case); an open marker records (g-open N start) in caps, the close
; converts the most recent one to a finished (N start end) entry --
; so a group inside a star keeps only its LAST iteration, the usual
; regex semantics.

; Match a single AST node at position: STATE (pos . caps) or ()
(def %regex-exec-one
  (fn (_ node str pos end caps)
    (def tag (first node))
    (match
      ((eq? tag 'lit)
        (if (and (< pos end)
              (= (%str-ref str pos) (first (rest node))))
          (pair (+ pos 1) caps) ()))
      ((eq? tag 'any)
        (if (< pos end) (pair (+ pos 1) caps) ()))
      ((eq? tag 'class)
        (if (< pos end)
          (if (%regex-class-match (rest node) (%str-ref str pos))
            (pair (+ pos 1) caps) ())
          ()))
      ((eq? tag 'nclass)
        (if (< pos end)
          (if (%regex-class-match (rest node) (%str-ref str pos))
            () (pair (+ pos 1) caps))
          ()))
      ; Nested quantifiers/groups: delegate to full exec
      (#t (%regex-exec (list node) str pos end caps)))))

; Greedy star: collect all reachable STATES, try rest from farthest first
(def %regex-exec-star
  (fn (_ inner rest-nodes str pos end caps)
    (def collect
      (fn (self st)
        (def next (%regex-exec-one inner str (first st) end (rest st)))
        (if (null? next) (list st) (pair st (self next)))))
    (def try-from
      (fn (self sts)
        (if (null? sts) ()
          (let ((r (%regex-exec rest-nodes str (first (first sts)) end (rest (first sts)))))
            (if r r (self (rest sts)))))))
    (try-from (%reverse (collect (pair pos caps))))))

; Plus: match inner once, then star
(def %regex-exec-plus
  (fn (_ inner rest-nodes str pos end caps)
    (def first-match (%regex-exec-one inner str pos end caps))
    (if (null? first-match) ()
      (%regex-exec-star inner rest-nodes str (first first-match) end (rest first-match)))))

; Optional: try with inner (greedy), backtrack to without
(def %regex-exec-opt
  (fn (_ inner rest-nodes str pos end caps)
    (def with-inner (%regex-exec-one inner str pos end caps))
    (if (not (null? with-inner))
      (let ((result (%regex-exec rest-nodes str (first with-inner) end (rest with-inner))))
        (if result result (%regex-exec rest-nodes str pos end caps)))
      (%regex-exec rest-nodes str pos end caps))))

; Lazy star: try shortest match first (don't reverse)
(def %regex-exec-lazy-star
  (fn (_ inner rest-nodes str pos end caps)
    (def collect
      (fn (self st)
        (def next (%regex-exec-one inner str (first st) end (rest st)))
        (if (null? next) (list st) (pair st (self next)))))
    (def try-from
      (fn (self sts)
        (if (null? sts) ()
          (let ((r (%regex-exec rest-nodes str (first (first sts)) end (rest (first sts)))))
            (if r r (self (rest sts)))))))
    (try-from (collect (pair pos caps)))))

; Lazy plus: match once, then lazy star
(def %regex-exec-lazy-plus
  (fn (_ inner rest-nodes str pos end caps)
    (def first-match (%regex-exec-one inner str pos end caps))
    (if (null? first-match) ()
      (%regex-exec-lazy-star inner rest-nodes str (first first-match) end (rest first-match)))))

; Lazy optional: try WITHOUT inner first, then with
(def %regex-exec-lazy-opt
  (fn (_ inner rest-nodes str pos end caps)
    (let ((without (%regex-exec rest-nodes str pos end caps)))
      (if without without
        (let ((with-inner (%regex-exec-one inner str pos end caps)))
          (if (null? with-inner) ()
            (%regex-exec rest-nodes str (first with-inner) end (rest with-inner))))))))

; Counted repetition: match inner between min and max times
(def %regex-exec-repeat
  (fn (_ inner min max rest-nodes str pos end caps)
    ; Collect states from min to max matches (greedy)
    (def collect-from
      (fn (self count st)
        (if (> count max) ()
          (if (< count min)
            (let ((next (%regex-exec-one inner str (first st) end (rest st))))
              (if (null? next) () (self (+ count 1) next)))
            (let ((next (%regex-exec-one inner str (first st) end (rest st))))
              (if (null? next) (list st)
                (pair st (self (+ count 1) next))))))))
    (def states (collect-from 0 (pair pos caps)))
    (def try-from
      (fn (self sts)
        (if (null? sts) ()
          (let ((r (%regex-exec rest-nodes str (first (first sts)) end (rest (first sts)))))
            (if r r (self (rest sts)))))))
    (try-from (%reverse states))))

; Walk AST node list against string: STATE (pos . caps) or ()
(set! %regex-exec
  (fn (_ nodes str pos end caps)
    (if (null? nodes) (pair pos caps)
      (let ((node (first nodes))
            (rest-nodes (rest nodes))
            (tag (first (first nodes))))
        (match
          ((eq? tag 'lit)
            (if (and (< pos end)
                  (= (%str-ref str pos) (first (rest node))))
              (%regex-exec rest-nodes str (+ pos 1) end caps) ()))
          ((eq? tag 'any)
            (if (< pos end)
              (%regex-exec rest-nodes str (+ pos 1) end caps) ()))
          ((eq? tag 'class)
            (if (and (< pos end)
                  (%regex-class-match (rest node) (%str-ref str pos)))
              (%regex-exec rest-nodes str (+ pos 1) end caps) ()))
          ((eq? tag 'nclass)
            (if (and (< pos end)
                  (not (%regex-class-match (rest node) (%str-ref str pos))))
              (%regex-exec rest-nodes str (+ pos 1) end caps) ()))
          ((eq? tag 'star)
            (%regex-exec-star (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'plus)
            (%regex-exec-plus (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'opt)
            (%regex-exec-opt (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'lazy-star)
            (%regex-exec-lazy-star (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'lazy-plus)
            (%regex-exec-lazy-plus (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'lazy-opt)
            (%regex-exec-lazy-opt (first (rest node)) rest-nodes str pos end caps))
          ((eq? tag 'repeat)
            (%regex-exec-repeat (first (rest node))
              (first (rest (rest node)))
              (first (rest (rest (rest node))))
              rest-nodes str pos end caps))
          ; Numbered group (group N nodes): splice open/close markers
          ; around the content so captures record on the way through --
          ; the group itself is transparent to matching (#23).
          ((eq? tag 'group)
            (%regex-exec
              (pair (list 'g-open (first (rest node)))
                (%append (first (rest (rest node)))
                  (pair (list 'g-close (first (rest node))) rest-nodes)))
              str pos end caps))
          ((eq? tag 'g-open)
            (%regex-exec rest-nodes str pos end
              (pair (list 'g-open (first (rest node)) pos) caps)))
          ((eq? tag 'g-close)
            (%regex-exec rest-nodes str pos end
              (%regex-close-group caps (first (rest node)) pos)))
          ((eq? tag 'alt)
            (let ((left (%regex-exec (%append (first (rest node)) rest-nodes) str pos end caps)))
              (if left left
                (%regex-exec (%append (first (rest (rest node))) rest-nodes) str pos end caps))))
          ((eq? tag 'anchor-start)
            (if (= pos 0) (%regex-exec rest-nodes str pos end caps) ()))
          ((eq? tag 'anchor-word-boundary)
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (%char->integer (%str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (%char->integer (%str-ref str pos))))))
              (if (eq? left-word right-word) ()
                (%regex-exec rest-nodes str pos end caps))))
          ((eq? tag 'anchor-not-word-boundary)
            (let ((left-word (if (= pos 0) #f
                    (%regex-is-word-char (%char->integer (%str-ref str (- pos 1))))))
                  (right-word (if (= pos end) #f
                    (%regex-is-word-char (%char->integer (%str-ref str pos))))))
              (if (eq? left-word right-word)
                (%regex-exec rest-nodes str pos end caps) ())))
          ((eq? tag 'anchor-end)
            (if (= pos end) (%regex-exec rest-nodes str pos end caps) ()))
          (#t ()))))))

; Convert the most recent (g-open N start) in caps to a finished
; (N start end) capture -- pure prefix rebuild, so abandoned backtrack
; branches never see it.
(def %regex-close-group
  (fn (_ caps n endpos)
    (def go (fn (self cs)
      (if (null? cs) ()
        (let ((c (first cs)))
          (if (if (eq? (first c) 'g-open) (= (first (rest c)) n) #f)
            (pair (list n (first (rest (rest c))) endpos) (rest cs))
            (pair c (self (rest cs))))))))
    (go caps)))

; --- Write: reconstruct pattern from AST ---

(def %regex-write-node
  (fn (self node)
    (def tag (first node))
    (match
      ((eq? tag 'lit)
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
      ((eq? tag 'any) (display "."))
      ((eq? tag 'star)
        (do (self (first (rest node))) (display "*")))
      ((eq? tag 'plus)
        (do (self (first (rest node))) (display "+")))
      ((eq? tag 'opt)
        (do (self (first (rest node))) (display "?")))
      ((eq? tag 'class)
        (do (display "[") (%regex-write-class (rest node)) (display "]")))
      ((eq? tag 'nclass)
        (do (display "[^") (%regex-write-class (rest node)) (display "]")))
      ((eq? tag 'group)
        ; numbered shape (group N nodes) -- the nodes are the third element
        (do (display "(") (%regex-write (first (rest (rest node)))) (display ")")))
      ((eq? tag 'alt)
        (do (%regex-write (first (rest node)))
            (display "|")
            (%regex-write (first (rest (rest node))))))
      ((eq? tag 'anchor-start) (display "^"))
      ((eq? tag 'anchor-end) (display "$"))
      ((eq? tag 'anchor-word-boundary) (display "\\b"))
      ((eq? tag 'anchor-not-word-boundary) (display "\\B"))
      ((eq? tag 'lazy-star)
        (do (self (first (rest node))) (display "*?")))
      ((eq? tag 'lazy-plus)
        (do (self (first (rest node))) (display "+?")))
      ((eq? tag 'lazy-opt)
        (do (self (first (rest node))) (display "??")))
      ((eq? tag 'repeat)
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
          (let ((ch (%str-ref s i)))
            (if (and (>= ch 48) (<= ch 57))
              (self (+ i 1) (+ (* acc 10) (- ch 48)))
              (pair acc i))))))
    (def min-r (%parse-int pos 0))
    (def min-val (first min-r))
    (def after-min (rest min-r))
    (if (>= after-min end) (pair node pos)
      (let ((ch (%str-ref s after-min)))
        (match
          ; {n}
          ((= ch #\})
            (pair (list 'repeat node min-val min-val) (+ after-min 1)))
          ; {n,} or {n,m}
          ((= ch #\,)
            (if (and (< (+ after-min 1) end) (= (%str-ref s (+ after-min 1)) #\}))
              ; {n,} — unbounded
              (pair (list 'repeat node min-val 999999999) (+ after-min 2))
              ; {n,m}
              (let ((max-r (%parse-int (+ after-min 1) 0)))
                (def max-val (first max-r))
                (def after-max (rest max-r))
                (if (and (< after-max end) (= (%str-ref s after-max) #\}))
                  (pair (list 'repeat node min-val max-val) (+ after-max 1))
                  (pair node pos)))))
          (#t (pair node pos)))))))

; Wrap node with quantifier if present: * + ? {n,m}
(def %regex-wrap-quantifier
  (fn (_ s pos end node)
    (if (>= pos end) (pair node pos)
      (let ((ch (%str-ref s pos)))
        (def lazy (and (< (+ pos 1) end) (= (%str-ref s (+ pos 1)) #\?)))
        (match
          ((= ch #\*)
            (if lazy (pair (list 'lazy-star node) (+ pos 2))
              (pair (list 'star node) (+ pos 1))))
          ((= ch #\+)
            (if lazy (pair (list 'lazy-plus node) (+ pos 2))
              (pair (list 'plus node) (+ pos 1))))
          ((= ch #\?)
            (if lazy (pair (list 'lazy-opt node) (+ pos 2))
              (pair (list 'opt node) (+ pos 1))))
          ((= ch #\{) (%regex-parse-repeat-wrap s (+ pos 1) end node))
          (#t (pair node pos)))))))

; Parse escape sequence
(def %regex-parse-escape
  (fn (_ s pos)
    (def ch (%str-ref s pos))
    (match
      ((= ch #\d) (pair (list 'class (pair 48 57)) (+ pos 1)))
      ((= ch #\D) (pair (list 'nclass (pair 48 57)) (+ pos 1)))
      ((= ch #\w) (pair (list 'class (pair 48 57) (pair 65 90) (pair 97 122) 95) (+ pos 1)))
      ((= ch #\W) (pair (list 'nclass (pair 48 57) (pair 65 90) (pair 97 122) 95) (+ pos 1)))
      ((= ch #\s) (pair (list 'class 32 9 10 13) (+ pos 1)))
      ((= ch #\S) (pair (list 'nclass 32 9 10 13) (+ pos 1)))
      ((= ch #\b) (pair (list 'anchor-word-boundary) (+ pos 1)))
      ((= ch #\B) (pair (list 'anchor-not-word-boundary) (+ pos 1)))
      (#t (pair (list 'lit ch) (+ pos 1))))))

; Parse character class [...] or [^...]
(def %regex-parse-class
  (fn (_ s pos end)
    (def negated (and (< pos end) (= (%str-ref s pos) #\^)))
    (def start (if negated (+ pos 1) pos))
    (def tag (if negated 'nclass 'class))
    (def %go
      (fn (self i acc)
        (if (>= i end) (pair (pair tag (%reverse acc)) i)
          (let ((ch (%char->integer (%str-ref s i))))
            (match
              ((= ch #\])
                (pair (pair tag (%reverse acc)) (+ i 1)))
              ; Escape inside class: \d \w \s etc. expand to ranges/literals
              ((= ch #\\)
                (if (>= (+ i 1) end) (self (+ i 1) (pair ch acc))
                  (let ((esc (%char->integer (%str-ref s (+ i 1)))))
                    (match
                      ((= esc #\d) (self (+ i 2) (pair (pair 48 57) acc)))
                      ((= esc #\w) (self (+ i 2) (pair 95 (pair (pair 97 122) (pair (pair 65 90) (pair (pair 48 57) acc))))))
                      ((= esc #\s) (self (+ i 2) (pair 13 (pair 10 (pair 9 (pair 32 acc))))))
                      (#t (self (+ i 2) (pair esc acc)))))))
              ; Range: a-z
              ((and (< (+ i 2) end) (= (%char->integer (%str-ref s (+ i 1))) #\-))
                (let ((hi (%char->integer (%str-ref s (+ i 2)))))
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
    (let ((ch (%str-ref s i)))
      (match
        ((= ch #\.)
          (pair (list 'any) (+ i 1)))
        ((= ch #\\)
          (if (>= (+ i 1) end) (pair (list 'lit ch) (+ i 1))
            (%regex-parse-escape s (+ i 1))))
        ((= ch #\[)
          (%regex-parse-class s (+ i 1) end))
        ((= ch #\()
          (let ((inner (%regex-parse-group s (+ i 1) end)))
            (pair (list 'group (first inner)) (rest inner))))
        (#t
          (pair (list 'lit ch) (+ i 1)))))))

(set! %regex-parse-group
  (fn (_ s pos end)
    (def content (%regex-parse-alt-full s pos end 1))
    (def nodes (first content))
    (def close-pos (rest content))
    (pair nodes (if (and (< close-pos end) (= (%str-ref s close-pos) #\)))
                  (+ close-pos 1) close-pos))))

(set! %regex-parse-alt-full
  (fn (_ s pos end depth)
    (def left (%regex-parse-seq s pos end depth))
    (def left-nodes (first left))
    (def left-pos (rest left))
    (if (and (< left-pos end) (= (%str-ref s left-pos) #\|))
      (let ((right (%regex-parse-alt-full s (+ left-pos 1) end depth)))
        (pair (list (list 'alt left-nodes (first right))) (rest right)))
      left)))

(set! %regex-parse-seq
  (fn (_ s pos end depth)
    (def %go
      (fn (self i acc)
        (if (>= i end) (pair (%reverse acc) i)
          (let ((ch (%str-ref s i)))
            (match
              ((and (= ch #\)) (> depth 0)) (pair (%reverse acc) i))
              ((= ch #\|) (pair (%reverse acc) i))
              ((= ch #\^) (self (+ i 1) (pair (list 'anchor-start) acc)))
              ((= ch #\$) (self (+ i 1) (pair (list 'anchor-end) acc)))
              (#t
                (let ((atom (%regex-parse-atom s i end)))
                  (def node (first atom))
                  (def next-i (rest atom))
                  (let ((q (%regex-wrap-quantifier s next-i end node)))
                    (self (rest q) (pair (first q) acc))))))))))
    (%go pos ())))

; Top-level parse: pattern string to AST node list
; Number the groups in OPEN order (1-based, the convention $N follows):
; the parser emits (group nodes); this pass rewrites to (group N nodes),
; walking group bodies, alt branches, and quantifier inners. A one-cell
; counter box threads the numbering (per-activation state rides params;
; the box keeps the walk purely top-down).
(def %regex-number-groups
  (fn (_ nodes)
    (def counter (pair 0 ()))
    (def walk-one ())
    (def walk-list
      (fn (self ns)
        (if (null? ns) ()
          (pair (walk-one (first ns)) (self (rest ns))))))
    (set! walk-one
      (fn (_ node)
        (def tag (first node))
        (match
          ((eq? tag 'group)
            (do (set-first! counter (+ (first counter) 1))
                (let ((n (first counter)))
                  (list 'group n (walk-list (first (rest node)))))))
          ((eq? tag 'alt)
            (list 'alt (walk-list (first (rest node)))
                       (walk-list (first (rest (rest node))))))
          ((eq? tag 'star) (list 'star (walk-one (first (rest node)))))
          ((eq? tag 'plus) (list 'plus (walk-one (first (rest node)))))
          ((eq? tag 'opt) (list 'opt (walk-one (first (rest node)))))
          ((eq? tag 'lazy-star) (list 'lazy-star (walk-one (first (rest node)))))
          ((eq? tag 'lazy-plus) (list 'lazy-plus (walk-one (first (rest node)))))
          ((eq? tag 'lazy-opt) (list 'lazy-opt (walk-one (first (rest node)))))
          ((eq? tag 'repeat)
            (list 'repeat (walk-one (first (rest node)))
                  (first (rest (rest node)))
                  (first (rest (rest (rest node))))))
          (#t node))))
    (walk-list nodes)))

(set! %regex-parse
  (fn (_ pattern)
    (def len (%str-length pattern))
    (def result (%regex-parse-alt-full pattern 0 len 0))
    (%regex-number-groups (first result))))

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
        'call
        (fn (_ self . args)
          (def input (first args))
          (def end (%str-length input))
          ; exec returns a STATE (pos . caps) since #23
          (def result (%regex-exec (first self) input 0 end ()))
          (if (and result (= (first result) end)) #t #f)))
      (pair
        'write
        (fn (_ self)
          (display "#/")
          (%regex-write (first self))
          (display "/")))
      (pair
        'analyse
        (fn (_ buffer score chr)
          (if (= chr #\#)
            (fn (_ buf sc c0)
              (if (= c0 #\/) %regex-scan-body ()))
            ())))
      (pair 'read
        (fn (_ . args)
          (def tok (%buffer-token (first args)))
          ; Strip #/ prefix and / suffix
          (def pattern (%substring tok 2 (- (%str-length tok) 1)))
          (%make-instance %regex (%regex-parse pattern)))))))

(set! %regex-read
  (fn (_ . args) (%make-instance %regex (first args))))

; --- Captures to texts (#23) ---
; A winning exec state's caps hold finished (N start end) triples,
; most recent first; a group under a quantifier appears once per
; iteration, head = last. Build ((0 . whole) (N . text) ...) keeping
; the FIRST entry seen per N, sorted by N.
(def %regex-caps->alist
  (fn (_ str start endpos caps)
    (def seen-add
      (fn (self cs acc)
        (if (null? cs) acc
          (let ((c (first cs)))
            (if (assoc-has? (first c) acc)
              (self (rest cs) acc)
              (self (rest cs)
                (pair (pair (first c)
                        (%substring str (first (rest c)) (first (rest (rest c)))))
                      acc)))))))
    ; insertion sort by group number (tiny lists)
    (def ins
      (fn (self e lst)
        (if (null? lst) (list e)
          (if (< (first e) (first (first lst)))
            (pair e lst)
            (pair (first lst) (self e (rest lst)))))))
    (def sort-by-n
      (fn (self lst acc)
        (if (null? lst) acc
          (self (rest lst) (ins (first lst) acc)))))
    (sort-by-n (seen-add caps ())
               (list (pair 0 (%substring str start endpos))))))

; First match at-or-after pos WITH captures:
; (start end ((0 . whole) (N . text) ...)) or ()
(def %regex-find-caps
  (fn (_ str pos rx)
    (def end (%str-length str))
    (def nodes (%rx-nodes rx))
    (def %try
      (fn (self i)
        (if (> i end) ()
          (let ((result (%regex-exec nodes str i end ())))
            (if result
              (list i (first result)
                    (%regex-caps->alist str i (first result) (rest result)))
              (self (+ i 1)))))))
    (%try pos)))

; Expand $N references in a string replacement against a groups alist:
; $0 = whole match, $1..$9 = groups (absent/unmatched -> ""), $$ = "$".
(def %regex-expand-rep
  (fn (_ rep groups)
    (def len (%str-length rep))
    (def %go
      (fn (self i acc)
        (if (>= i len) acc
          (let ((ch (%char->integer (%str-ref rep i))))
            (if (not (= ch 36))                       ; $
              (self (+ i 1) (%str-append acc (%substring rep i (+ i 1))))
              (if (>= (+ i 1) len)
                (%str-append acc "$")
                (let ((nx (%char->integer (%str-ref rep (+ i 1)))))
                  (match
                    ((= nx 36)                        ; $$
                      (self (+ i 2) (%str-append acc "$")))
                    ((if (>= nx 48) (<= nx 57) #f)    ; $N
                      (let ((hit (assoc-get (- nx 48) groups)))
                        (self (+ i 2) (%str-append acc (if (null? hit) "" hit)))))
                    (#t (self (+ i 1) (%str-append acc "$")))))))))))
    (%go 0 "")))

; A function replacement receives the matched text; a string replacement
; expands $N against the match's groups (#23).
(def %regex-get-replacement
  (fn (_ rep matched groups)
    (if (procedure? rep) (rep matched) (%regex-expand-rep rep groups))))

; The AST inside a compiled regex, with a type guard: handing the exec family
; a non-REGEX (e.g. the bare AST from (Regex parse) or a plain string) used to
; silently no-op -- (first non-regex) walked garbage that never matched.
(def %rx-nodes
  (fn (_ rx)
    (if (%type? rx %regex) (first rx)
      (Err raise 'type "Regex: expected a compiled regex -- use #/.../ or (Regex compile pattern)" ()))))

(def-class Regex ()
  (static
    (method regex? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a regex." (returns BOOL "True if x is a regex"))
      (%type? x %regex))
    ; Every exec method is subject-LAST (the regex is the final parameter):
    ; the class-call handler appends the dispatched value last, so value-calls
    ; like (#/,/ split "a,b") route to (Regex split "a,b" #/,/).
    (method match (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Test whether a regex matches an entire string." (returns BOOL "True if regex matches the entire string"))
      (def end (%str-length str))
      (def result (%regex-exec (%rx-nodes rx) str 0 end ()))
      (if (and result (= (first result) end)) #t #f))
    (method search (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Search for the first occurrence of a regex pattern in a string." (returns LIST "Pair (start end) of first match, or nil if not found"))
      (def end (%str-length str))
      (def %try
        (fn (self i)
          (if (> i end) ()
            (let ((result (%regex-exec (%rx-nodes rx) str i end ())))
              (if result (list i (first result))
                (self (+ i 1)))))))
      (%try 0))
    (method find-at (self (param str STRING "Input string") (param pos INT "Start position") (param rx REGEX "Compiled regex"))
      (doc "Search for regex starting from position pos." (returns LIST "Pair (start end) of match, or nil"))
      (def end (%str-length str))
      (def %try
        (fn (self i)
          (if (> i end) ()
            (let ((result (%regex-exec (%rx-nodes rx) str i end ())))
              (if result (list i (first result))
                (self (+ i 1)))))))
      (%try pos))
    (method find (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Find first match and return the matched substring." (returns STRING "Matched substring, or nil")
        (example "(Regex find \"abc123def\" #/[0-9]+/)" "\"123\""))
      (def m (Regex search str rx))
      (if (null? m) ()
        (%substring str (first m) (first (rest m)))))
    (method match-groups (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Capture-group texts of the FIRST match anywhere in str: an alist ((0 . whole-match) (N . group-text) ...) keyed by group number in ( ) OPEN order, sorted. A group that did not participate (unmatched alternative) is ABSENT -- presence door, not a sentinel; a group under a quantifier keeps its last iteration. nil when nothing matches."
        (returns ANY "Groups alist, or nil")
        (example "(assoc-get 2 (Regex match-groups \"2026-07-19\" #/([0-9]+)-([0-9]+)-([0-9]+)/))" "\"07\"")
        (example "(assoc-get 0 (Regex match-groups \"key=val\" #/(\\w+)=(\\w+)/))" "\"key=val\"")
        (example "(null? (Regex match-groups \"nope\" #/[0-9]+/))" "#t"))
      (def m (%regex-find-caps str 0 rx))
      (if (null? m) () (first (rest (rest m)))))
    (method find-all (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Find all non-overlapping matches as a list of substrings." (returns LIST "List of matched substrings")
        (example "(Regex find-all \"a1b22c333\" #/[0-9]+/)" "(\"1\" \"22\" \"333\")"))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at str pos rx))
          (if (null? m) (%reverse acc)
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair (%substring str start end) acc))))))
      (%go 0 ()))
    (method find-all-pos (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Find all non-overlapping match positions." (returns LIST "List of (start end) pairs"))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at str pos rx))
          (if (null? m) (%reverse acc)
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair m acc))))))
      (%go 0 ()))
    (method match-count (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Count the number of non-overlapping matches. (count elsewhere means total elements; this counts MATCHES.)" (returns INT "Number of non-overlapping matches")
        (example "(Regex match-count \"a1b22c333\" #/[0-9]+/)" "3"))
      (%length (Regex find-all-pos str rx)))
    (method replace (self (param str STRING "Input string") (param rep ANY "Replacement string or function") (param rx REGEX "Compiled regex"))
      (doc "Replace the first match. rep can be a string or a function that receives the matched text." (returns STRING "String with first match replaced")
        (example "(Regex replace \"abc123def\" \"N\" #/[0-9]+/)" "\"abcNdef\""))
      (def m (%regex-find-caps str 0 rx))
      (if (null? m) str
        (let ((groups (first (rest (rest m)))))
          (%str-append
            (%substring str 0 (first m))
            (%str-append
              (%regex-get-replacement rep (assoc-get 0 groups) groups)
              (%substring str (first (rest m)) (%str-length str)))))))
    (method replace-all (self (param str STRING "Input string") (param rep ANY "Replacement string or function") (param rx REGEX "Compiled regex"))
      (doc "Replace all matches. rep can be a string or a function that receives each matched text." (returns STRING "String with all matches replaced")
        (example "(Regex replace-all \"a1b22c333\" \"N\" #/[0-9]+/)" "\"aNbNcN\""))
      (def len (%str-length str))
      (def %go
        (fn (self pos acc)
          (def m (%regex-find-caps str pos rx))
          (if (null? m)
            (%str-append acc (%substring str pos len))
            (let ((start (first m)))
              (def end (first (rest m)))
              (def groups (first (rest (rest m))))
              (def next (if (= start end) (+ end 1) end))
              (self next
                (%str-append acc
                  (%str-append (%substring str pos start)
                    (%regex-get-replacement rep (assoc-get 0 groups) groups))))))))
      (%go 0 ""))
    (method split (self (param str STRING "Input string") (param rx REGEX "Compiled regex"))
      (doc "Split a string at regex matches." (returns LIST "List of substrings between matches")
        (example "(Regex split \"a,b,c\" #/,/)" "(\"a\" \"b\" \"c\")")
        (example "(#/,/ split \"a,b,c\")" "(\"a\" \"b\" \"c\")"))
      (def len (%str-length str))
      (def %go
        (fn (self pos acc)
          (def m (Regex find-at str pos rx))
          (if (null? m)
            (%reverse (pair (%substring str pos len) acc))
            (let ((start (first m)))
              (def end (first (rest m)))
              (def next (if (= start end) (+ end 1) end))
              (self next (pair (%substring str pos start) acc))))))
      (%go 0 ()))
    (method exec (self (param nodes LIST "List of AST nodes from a compiled regex")
                       (param str STRING "Input string to match against")
                       (param pos INT "Starting position in the string")
                       (param end INT "End position (string length)"))
      (doc "Execute a regex AST against a string from the given position."
        (returns INT "Final position after match, or nil on failure"))
      (let ((r (%regex-exec nodes str pos end ())))
        (if (null? r) () (first r))))
    (method parse (self (param pattern STRING "Regex pattern string"))
      (doc "Parse a regex pattern string into a bare AST node list. For a value the exec methods accept, use (Regex compile)." (returns LIST "AST node list"))
      (%regex-parse pattern))
    (method compile (self (param pattern STRING "Regex pattern string"))
      (doc "Compile a pattern string into a REGEX value -- the programmatic twin of the #/.../ literal, for patterns built at runtime."
        (returns REGEX "Compiled regex, usable with every exec method and as a value-call subject")
        (example "(Regex find \"abc123\" (Regex compile \"[0-9]+\"))" "\"123\""))
      (%make-instance %regex (%regex-parse pattern)))))

; Value dispatch over the existing match call handler: (rx match s) / (rx find s)
; dispatch to Regex methods; (rx "input") still runs the bare match.
(%bind-call-over! (Type of #/x/) Regex)

(doc (provide x/type/regex Regex)
  (note "Syntax: #/pattern/. Supports: . * + ? \\ [class] [^neg] (group) | alternation ^ $ anchors {n,m} repetition \\d \\w \\s.")
  (example "(Regex find \"abc123def\" #/[0-9]+/)" "\"123\"")
  (example "(Regex replace-all \"a1b2\" \"N\" #/[0-9]+/)" "\"aNbN\"")
  (example "(#/,/ split \"a,b,c\")" "(\"a\" \"b\" \"c\")")
  "Regular expressions with literal syntax; operations homed on the Regex class.")
