; path.x -- Path: pure-string pathname manipulation (#22).
;
; No filesystem access here -- Path never stats anything (that's File's
; job); every method is a total string function.  Byte-level '/' scanning
; via Str8 (paths are byte strings to the syscall layer anyway).

(import x/protocol/str/str8)
(import x/type/class)

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
    (let ((n (%str-length s)))
      (let go ((e n))
        (match
          ((<= e 1) (Str8 sub 0 e s))
          ((Char =? (Str8 ref (- e 1) s) #\/) (go (- e 1)))
          (#t (Str8 sub 0 e s)))))))

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
        (example "(Path join \"a\" \"\" \"b\")" "\"a/b\""))
      (%fold
        (fn (_ acc part)
          (match
            ((str=? part "") acc)
            ((str=? acc "") part)
            (#t (Str8 append (%path-strip-trailing acc)
                  (if (Char =? (Str8 ref 0 part) #\/) part
                    (Str8 append "/" part))))))
        "" parts))

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
            (if (< i 0) s (Str8 sub (+ i 1) (- (%str-length s) (+ i 1)) s))))))

    (method ext (self (param p STRING "Path"))
      (doc "The extension of the basename, without its dot -- or nil when there is none (a leading-dot name like \".bashrc\" has no extension; absence is nil, never a sentinel)."
        (returns ANY "Extension string, or nil")
        (example "(Path ext \"a/b.tar.gz\")" "\"gz\"")
        (example "(null? (Path ext \"Makefile\"))" "#t")
        (example "(null? (Path ext \".bashrc\"))" "#t"))
      (let ((b (Path basename p)))
        (let ((n (%str-length b)))
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

    (method absolute? (self (param p STRING "Path"))
      (doc "Does p start at the root?"
        (returns BOOL "True when p begins with '/'")
        (example "(Path absolute? \"/etc\")" "#t")
        (example "(Path absolute? \"etc\")" "#f"))
      (if (= (%str-length p) 0) #f (Char =? (Str8 ref 0 p) #\/)))))

(doc (provide x/type/path Path)
  "Pure-string pathname manipulation on the Path class.")
