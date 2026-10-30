; path.x -- Path: pure-string pathname manipulation (#22).
;
; No filesystem access here -- Path never stats anything (that's File's
; job); every method is a total string function.  Byte-level '/' scanning
; via Str8 (paths are byte strings to the syscall layer anyway).

(module x/type/path)
(import x/protocol/str/str8)
(import x/type/class)
(import x/type/list)   ; relpath/match? segment work (reject/repeat/append/fold)

; Index of the last '/' in s, or -1 (internal sentinel only; the public
; door is (Str8 last-index-of), which misses with nil -- #25 delivered).
(def %path-last-slash
  (fn (_ s)
    (let ((i (Str8 last-index-of "/" s)))
      (if (null? i) -1 i))))

; s with trailing slashes stripped -- except a bare "/" (the root), which
; keeps its one slash.
(def %path-strip-trailing
  (fn (_ s)
    (let ((n (Str8 length s)))
      (let go ((e n))
        (match
          ((<= e 1) (Str8 sub 0 e s))
          ((Char =? (Str8 ref (- e 1) s) #\/) (go (- e 1)))
          (#t (Str8 sub 0 e s)))))))

; The join seam on the byte doors (0-1 objects a call each; the tower
; operators and a Str8 send cost ~100 and ~170).  A directory walker
; pays a seam for every entry, so this is the hot step of du, find and
; ls -R: the old fold of str=?, (Str8 ref) and (Char =?) sends cost
; ~6,300 objects a two-part join, a bare concat ~1.
(import x/core/doors char->int int+ int- str-append str-byte-len str-byte-ref str-byte-sub type-of)
(def %path-str-type (type-of ""))
(def %path-slash (char->int (str-byte-ref "/" 0)))

; The byte doors read unchecked, so a non-string part is refused here, as
; Str8 append refuses one, instead of reading memory.
(def %path-part
  (fn (_ v)
    (match
      ((if (eq? v ()) #f (eq? (type-of v) %path-str-type)) v)
      (#t (Err raise (lit type) "Path join: not a string" ())))))

; End of s without its trailing slashes: the index of the last byte that
; is not '/', plus one; 0 when s is empty or all slashes.
(def %path-trim-end
  (fn (self s e)
    (match
      ((eq? e 0) 0)
      ((eq? (char->int (str-byte-ref s (int- e 1))) %path-slash)
        (self s (int- e 1)))
      (#t e))))

; Start of s past its leading slashes; n when s is all slashes.
(def %path-trim-start
  (fn (self s i n)
    (match
      ((eq? i n) n)
      ((eq? (char->int (str-byte-ref s i)) %path-slash)
        (self s (int+ i 1) n))
      (#t i))))

; acc and part around one '/': acc's trailing and part's leading slashes
; collapse into it.  Two concats; the slices only when a slash is cut.
(def %path-seam
  (fn (_ acc part)
    (def alen (str-byte-len acc))
    (def e (%path-trim-end acc alen))
    (def plen (str-byte-len part))
    (def i (%path-trim-start part 0 plen))
    (str-append
      (str-append (match ((eq? e alen) acc) (#t (str-byte-sub acc 0 e))) "/")
      (match ((eq? i 0) part) (#t (str-byte-sub part i (int- plen i)))))))

; The join loop: an empty part vanishes, the first part stands as given
; (its own leading slashes are the root), every later one is a seam.
(def %path-join-go
  (fn (self acc parts)
    (match
      ((eq? parts ()) acc)
      ((eq? (str-byte-len (%path-part (first parts))) 0) (self acc (rest parts)))
      ((eq? (str-byte-len acc) 0) (self (first parts) (rest parts)))
      (#t (self (%path-seam acc (first parts)) (rest parts))))))

(def-class Path ()
  (doc "Pure-string pathname manipulation: join, dirname, basename, ext, split, absolute?."
    (note "No filesystem access -- every method is a total string function; pair with the File class for stat/exists?.")
    (example "(Path join \"lib\" \"x\" \"core\")" "\"lib/x/core\"")
    (example "(Path basename \"/a/b/c.txt\")" "\"c.txt\""))
  (static
    (method join (self . (param parts STRING "Path components"))
      (doc "Join components with exactly one '/' at each seam (a component's own leading/trailing slashes collapse into the seam). Empty components vanish."
        (returns STRING "The joined path")
        (example "(Path join \"a\" \"b/c\")" "\"a/b/c\"")
        (example "(Path join \"a/\" \"/b\")" "\"a/b\"")
        (example "(Path join \"/root\" \"etc\")" "\"/root/etc\"")
        (example "(Path join \"/\" \"etc\")" "\"/etc\"")
        (example "(Path join \"a\" \"\" \"b\")" "\"a/b\""))
      (%path-join-go "" parts))

    (method dirname (self (param p STRING "Path"))
      (doc "The directory part: everything before the last '/' (after trailing slashes are stripped). No slash at all answers \".\"; a root-level entry answers \"/\"."
        (returns STRING "The directory part")
        (example "(Path dirname \"/a/b/c.txt\")" "\"/a/b\"")
        (example "(Path dirname \"c.txt\")" "\".\"")
        (example "(Path dirname \"/etc\")" "\"/\""))
      (let ((s (%path-strip-trailing p)))
        (let ((i (%path-last-slash s)))
          (match
            ((< i 0) ".")
            ((= i 0) "/")
            (#t (Str8 sub 0 i s))))))

    (method basename (self (param p STRING "Path"))
      (doc "The final component: everything after the last '/' (after trailing slashes are stripped)."
        (returns STRING "The final path component")
        (example "(Path basename \"/a/b/c.txt\")" "\"c.txt\"")
        (example "(Path basename \"c.txt\")" "\"c.txt\"")
        (example "(Path basename \"/a/b/\")" "\"b\""))
      (let ((s (%path-strip-trailing p)))
        (if (str=? s "/") "/"
          (let ((i (%path-last-slash s)))
            (if (< i 0) s (Str8 sub (+ i 1) (- (Str8 length s) (+ i 1)) s))))))

    (method ext (self (param p STRING "Path"))
      (doc "The extension of the basename, without its dot -- or nil when there is none (a leading-dot name like \".bashrc\" has no extension; absence is nil, never a sentinel)."
        (returns ANY "Extension string, or nil")
        (example "(Path ext \"a/b.tar.gz\")" "\"gz\"")
        (example "(null? (Path ext \"Makefile\"))" "#t")
        (example "(null? (Path ext \".bashrc\"))" "#t"))
      (let ((b (Path basename p)))
        (let ((n (Str8 length b)))
          (let go ((i (- n 1)))
            (match
              ((<= i 0) ())
              ((Char =? (Str8 ref i b) #\.)
                (if (= i (- n 1)) () (Str8 sub (+ i 1) (- n (+ i 1)) b)))
              (#t (go (- i 1))))))))

    (method split (self (param p STRING "Path"))
      (doc "The path's components as a list of strings; empty components (doubled or leading/trailing slashes) are dropped. Pair with absolute? to keep the root bit."
        (returns LIST "Component strings")
        (example "(Path split \"/a/b/c\")" "(\"a\" \"b\" \"c\")")
        (example "(Path split \"a//b/\")" "(\"a\" \"b\")"))
      (List reject (fn (_ c) (str=? c "")) (Str8 split "/" p)))

    (method norm (self (param p STRING "Path"))
      (doc "Lexically normalize: '.' and empty components drop, '..' consumes the component before it. Leading '..'s survive (nothing to consume -- the CALLER decides whether climbing out is an error), and an absolute path never climbs above '/'. Purely lexical: no symlink is consulted."
        (returns STRING "The normalized path")
        (example "(Path norm \"a/./b//c\")" "\"a/b/c\"")
        (example "(Path norm \"a/b/../c\")" "\"a/c\"")
        (example "(Path norm \"../a\")" "\"../a\"")
        (example "(Path norm \"a/..\")" "\".\"")
        (example "(Path norm \"/a/../..\")" "\"/\""))
      (def %resolve
        (fn (self segs acc)
          (match
            ((null? segs) (%reverse acc))
            ((str=? (first segs) ".") (self (rest segs) acc))
            ((str=? (first segs) "..")
              (match
                ((if (null? acc) #f (not (str=? (first acc) ".."))) (self (rest segs) (rest acc)))
                ((Path absolute? p) (self (rest segs) acc))
                (#t (self (rest segs) (pair ".." acc)))))
            (#t (self (rest segs) (pair (first segs) acc))))))
      (let ((segs (%resolve (Path split p) ())))
        ; join is one-pass since #333; the fold re-copied per segment.
        (let ((body (match ((null? segs) "") (#t (Str8 join "/" segs)))))
          (match
            ((Path absolute? p) (Str8 append "/" body))
            ((str=? body "") ".")
            (#t body)))))

    (method strip-ext (self (param p STRING "Path"))
      (doc "p without the basename's extension and its dot; unchanged when ext is nil. The whole path keeps its directory part -- this is the typed door for the byte-arithmetic suffix strips the tools hand-rolled."
        (returns STRING "The path minus its extension")
        (example "(Path strip-ext \"a/b.x\")" "\"a/b\"")
        (example "(Path strip-ext \"a.tar.gz\")" "\"a.tar\"")
        (example "(Path strip-ext \"Makefile\")" "\"Makefile\""))
      (let ((e (Path ext p)))
        (match
          ((null? e) p)
          ; guard: only cut when the dotted extension really is p's tail
          ; (a slash-terminated path keeps its bytes)
          ((Str8 ends? (Str8 append "." e) p)
            (Str8 sub 0 (- (Str8 length p) (+ 1 (Str8 length e))) p))
          (#t p))))

    (method absolute? (self (param p STRING "Path"))
      (doc "Does p start at the root?"
        (returns BOOL "True when p begins with '/'")
        (example "(Path absolute? \"/etc\")" "#t")
        (example "(Path absolute? \"etc\")" "#f"))
      (if (= (Str8 length p) 0) #f (Char =? (Str8 ref 0 p) #\/)))

    (method relpath (self (param start STRING "The path to be relative FROM")
                          (param p STRING "The path to express relative to start"))
      (doc "Express p relative to start, lexically (#364): both are normalized, the common prefix drops, and each remaining start segment becomes '..'. Both must be absolute or both relative -- mixing raises a label 'value (relating them needs a working directory, which this pure-string class refuses to consult); a relative start that still climbs ('..' after norm) raises for the same reason."
        (returns STRING "p relative to start ('.' when they coincide)")
        (example "(Path relpath \"/a/b\" \"/a/c/d\")" "\"../c/d\"")
        (example "(Path relpath \"a/b\" \"a/b\")" "\".\"")
        (example "(Path relpath \"/a\" \"/a/b\")" "\"b\""))
      (def ns (Path norm start))
      (def np (Path norm p))
      (unless (eq? (Path absolute? ns) (Path absolute? np))
        (Err raise 'value "Path relpath: mixing absolute and relative paths needs a working directory" (list start p)))
      (def %segs (fn (_ q)
        (List reject (fn (_ s) (str=? s ""))
          (Str8 split "/" q))))
      (def ss (%segs ns))
      (when (List includes? ".." ss)
        (Err raise 'value "Path relpath: start climbs out of the common root" start))
      (def ps (%segs np))
      (let strip ((a ss) (b ps))
        (match
          ((if (pair? a) (if (pair? b) (str=? (first a) (first b)) #f) #f)
            (strip (rest a) (rest b)))
          (#t
            (let ((ups (List repeat (List length a) "..")))
              (let ((all (List append ups b)))
                (if (null? all) "." (List fold (fn (_ acc s) (Str8 append acc "/" s)) (first all) (rest all)))))))))

    (method match? (self (param pattern STRING "Glob pattern: ? one char, * a run, ** a whole-segment wildcard crossing '/'")
                         (param p STRING "Path to test"))
      (doc "Glob-match p against pattern, segment-aware (#364): '?' matches one non-'/' character, '*' a non-'/' run, and '**' AS A FULL SEGMENT matches zero or more whole segments. No character classes (the [...] form) -- purely lexical, no filesystem access."
        (returns BOOL "True when the whole of p matches the whole pattern")
        (example "(Path match? \"*.x\" \"file.x\")" "#t")
        (example "(Path match? \"lib/*.x\" \"lib/a/b.x\")" "#f")
        (example "(Path match? \"lib/**/*.x\" \"lib/a/b.x\")" "#t")
        (example "(Path match? \"lib/**\" \"lib\")" "#t"))
      ; one segment against one glob segment, byte-recursive
      (def %seg? (fn (loop pat s pi si)
        (def pn (str-byte-len pat))
        (def sn (str-byte-len s))
        (match
          ((= pi pn) (= si sn))
          ((= (char->int (str-byte-ref pat pi)) 42)                       ; *
            (if (loop pat s (+ pi 1) si) #t
              (if (< si sn) (loop pat s pi (+ si 1)) #f)))
          ((= si sn) #f)
          ((= (char->int (str-byte-ref pat pi)) 63)                       ; ?
            (loop pat s (+ pi 1) (+ si 1)))
          ((= (char->int (str-byte-ref pat pi)) (char->int (str-byte-ref s si)))
            (loop pat s (+ pi 1) (+ si 1)))
          (#t #f))))
      (def %segs (fn (_ q)
        (List reject (fn (_ s) (str=? s "")) (Str8 split "/" q))))
      (let go ((pats (%segs pattern)) (segs (%segs p)))
        (match
          ((null? pats) (null? segs))
          ((str=? (first pats) "**")
            (if (go (rest pats) segs) #t                       ; ** takes zero segments
              (if (pair? segs) (go pats (rest segs)) #f)))     ; or eats one and stays
          ((null? segs) #f)
          ((%seg? (first pats) (first segs) 0 0)
            (go (rest pats) (rest segs)))
          (#t #f))))))

(doc (provide x/type/path Path)
  "Pure-string pathname manipulation on the Path class.")
