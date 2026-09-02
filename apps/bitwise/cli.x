; # x-lang -- Bitwise
;
; ## apps/bitwise/cli.x -- the command line: one project, or every project
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
;   x -l bitwise -- NAME [--fmt mark|avatar|banner] [--tagline TEXT]
;                        [--kind KIND] [-o FILE] [--png] [--json]
;   x -l bitwise -- --all [--root DIR] [--out DIR] [--png]
;
; --all discovers x-expr, x-lang, engines/* and languages/* under --root
; (default: the parent of the working directory, the x workspace), reads
; each tagline off the first paragraph of its README, and writes every
; format for every project plus index.json.  --png shells out to
; rsvg-convert when it is on PATH.
(import x/type/class)
(import bitwise/gen)
(import x/sys/proc)
(import x/codec/json)

(def-class BitwiseCli ()
  (doc "The command line over Bitwise: (BitwiseCli main args) draws one project or every project under a workspace root.")
  (static
    (%widths (list (list "mark" 512) (list "avatar" 512) (list "banner" 1280)))
    (%kinds (list (list "x-expr" "a C library") (list "x-lang" "the language")))
    (%subdirs (list (list "engines" "an x-lang engine") (list "languages" "a language on x-lang")))

    (method %width (self fmt)
      (first (rest (%find (fn (_ e) (str=? (first e) fmt)) (BitwiseCli %widths)))))

    ; The engine's own flags reach the program too; drop them, and a leading --.
    (method %engine-flag? (self s)
      (if (str=? s "--quiet") #t (if (str=? s "--batch") #t (if (str=? s "--no-color") #t (str=? s "--verbose")))))
    (method %argv (self raw)
      (def ops (List filter (fn (_ a) (not (BitwiseCli %engine-flag? a))) (if (pair? raw) (rest raw) ())))
      (if (if (pair? ops) (str=? (first ops) "--") #f) (rest ops) ops))

    ; index-of answers nil for absent; -1 is easier to compare.
    (method %idx (self sub s) (let ((i (Str8 index-of sub s))) (if (null? i) -1 i)))
    (method %ridx (self sub s) (let ((i (Str8 last-index-of sub s))) (if (null? i) -1 i)))

    (method %opts (self argv)
      (def o (Dict make))
      (o set! 'fmt "mark")
      (o set! 'tagline "")
      (o set! 'kind "")
      (o set! 'out #f)
      (o set! 'png #f)
      (o set! 'json #f)
      (o set! 'all #f)
      (o set! 'root "..")
      (o set! 'outdir "build/bitwise")
      (o set! 'name #f)
      (let go ((as argv))
        (unless (null? as)
          (let ((a (first as)) (more (rest as)))
            (match
              ((str=? a "--fmt") (do (o set! 'fmt (first more)) (go (rest more))))
              ((str=? a "--tagline") (do (o set! 'tagline (first more)) (go (rest more))))
              ((str=? a "--kind") (do (o set! 'kind (first more)) (go (rest more))))
              ((str=? a "-o") (do (o set! 'out (first more)) (go (rest more))))
              ((str=? a "--root") (do (o set! 'root (first more)) (go (rest more))))
              ((str=? a "--out") (do (o set! 'outdir (first more)) (go (rest more))))
              ((str=? a "--png") (do (o set! 'png #t) (go more)))
              ((str=? a "--json") (do (o set! 'json #t) (go more)))
              ((str=? a "--all") (do (o set! 'all #t) (go more)))
              (#t (do (o set! 'name a) (go more)))))))
      o)

    ; ---------------------------------------------------------------- projects

    (method %sort (self lst)
      (let ins ((xs lst) (acc ()))
        (if (null? xs) acc
          (ins (rest xs)
               (let put ((ys acc) (x (first xs)))
                 (if (null? ys) (list x)
                   (if (Str8 <? x (first ys)) (pair x ys) (pair (first ys) (put (rest ys) x)))))))))

    (method %discover (self root)
      (def found ())
      (List for-each
        (fn (_ e)
          (let ((d (%path-join root (first e))))
            (when (File exists? (%path-join d "README.md"))
              (set! found (pair (list (first e) d (first (rest e))) found)))))
        (BitwiseCli %kinds))
      (List for-each
        (fn (_ sub)
          (let ((base (%path-join root (first sub))))
            (when (File exists? base)
              (List for-each
                (fn (_ e)
                  (let ((d (%path-join base e)))
                    (when (if (Str8 starts? "." e) #f (File exists? (%path-join d "README.md")))
                      (set! found (pair (list e d (first (rest sub))) found)))))
                (BitwiseCli %sort (File list-dir base))))))
        (BitwiseCli %subdirs))
      (%reverse found))

    ; Markdown links to their text: [text](url) and [text][ref].
    (method %unlink (self t)
      (let go ((s t))
        (let ((j (self %idx "](" s)) (j2 (self %idx "][" s)))
          (let ((cut (if (< j 0) j2 (if (< j2 0) j (Num min j j2)))))
            (if (< cut 0) s
              (let ((i (self %ridx "[" (Str8 sub 0 cut s)))
                    (k (self %idx (if (= cut j) ")" "]") (Str8 sub (+ cut 2) (- (Str8 length s) (+ cut 2)) s))))
                (if (if (< i 0) #t (< k 0)) s
                  (go (%str-concat (list (Str8 sub 0 i s)
                                         (Str8 sub (+ i 1) (- cut (+ i 1)) s)
                                         (Str8 sub (+ cut 2 k 1) (- (Str8 length s) (+ cut 2 k 1)) s)))))))))))

    (method %earliest (self s seps)
      (let go ((ss seps) (best -1))
        (if (null? ss) best
          (let ((i (self %idx (first ss) s)))
            (go (rest ss) (if (< i 0) best (if (< best 0) i (Num min best i))))))))

    ; First prose paragraph after the H1, de-markdowned, cut to one sentence.
    (method %tagline (self readme)
      (def para
        (let go ((ls (File read-lines readme)) (seen #f) (fence #f) (acc ()))
          (if (null? ls) (%reverse acc)
            (let ((line (first ls)))
              (match
                ((Str8 starts? "```" line) (go (rest ls) seen (not fence) acc))
                (fence (go (rest ls) seen fence acc))
                ((Str8 starts? "# " line) (go (rest ls) #t fence acc))
                ((not seen) (go (rest ls) seen fence acc))
                ((str=? (Str8 trim line) "") (if (null? acc) (go (rest ls) seen fence acc) (%reverse acc)))
                ((if (Str8 starts? "[!" line) #t
                   (if (Str8 starts? "    " line) #t
                     (if (Str8 starts? "|" line) #t
                       (if (Str8 starts? "<" line) #t
                         (if (Str8 starts? "#" line) #t (Str8 includes? "{O,O}" line))))))
                 (go (rest ls) seen fence acc))
                (#t (go (rest ls) seen fence (pair (Str8 trim line) acc))))))))
      (def text0 (Str8 join " " (Bitwise %words (Str8 replace "`" "" (Str8 replace "_" "" (Str8 replace "*" "" (self %unlink (Str8 join " " para))))))))
      (def cut (self %earliest text0 (list ". " "; " " -- " " \xe2\x80\x94 ")))
      (def text1 (Bitwise %rstrip (if (< cut 0) text0 (Str8 sub 0 (+ cut 1) text0)) ".:;, "))
      (def po (self %idx "(" text1))
      (def text2
        (if (if (< po 0) #f (< (self %idx ")" (Str8 sub po (- (Str8 length text1) po) text1)) 0))
          (Bitwise %rstrip (Str8 sub 0 po text1) ",;: ")
          text1))
      (if (> (Bitwise %chars text2) 160)
        (let ((head (Bitwise %glyph-take text2 160)))
          (let ((sp (self %ridx " " head)))
            (%str-concat (list (Bitwise %rstrip (if (< sp 0) head (Str8 sub 0 sp head)) ",;: ") "\xe2\x80\xa6"))))
        text2))

    ; ---------------------------------------------------------------- output

    (method %png! (self svg-path fmt)
      (def png (%str-concat (list (Str8 sub 0 (- (Str8 length svg-path) 4) svg-path) ".png")))
      (Proc run! (list "rsvg-convert" "-w" (Io display-to-str (self %width fmt)) svg-path "-o" png))
      png)

    (method %run-all (self o)
      (def outdir (o get 'outdir))
      (unless (File exists? outdir) (File mkdir outdir))
      (def index
        (List map
          (fn (_ proj)
            (let ((name (first proj)) (dir (first (rest proj))) (kind (first (rest (rest proj)))))
              (let ((tag (BitwiseCli %tagline (%path-join dir "README.md"))))
                (let ((p (let go ((fs (list "mark" "avatar" "banner")) (last #f))
                           (if (null? fs) last
                             (let ((r (Bitwise render name (first fs) tag kind "o")))
                               (let ((path (%path-join outdir (%str-concat (list name "-" (first fs) ".svg")))))
                                 (File write-all path (first r))
                                 (when (o get 'png) (BitwiseCli %png! path (first fs)))
                                 (go (rest fs) (rest r))))))))
                  (display (%str-concat (list (Str8 pad-right 16 #\space name) (Str8 pad-right 6 #\space (p get 'opname))
                                              " bit " (Io display-to-str (p get 'bit)) "  n=" (Str8 pad-left 2 #\space (Io display-to-str (p get 'n)))
                                              "  hue " (Str8 pad-left 5 #\space (Bitwise %hue-str (p get 'hue10)))
                                              "  " (Str8 pad-right 24 #\space (p get 'costume)) " " (p get 'reference) "\n")))
                  (let ((d (Dict make)))
                    (d set! "name" name) (d set! "kind" kind) (d set! "tagline" tag)
                    (d set! "opname" (p get 'opname)) (d set! "formula" (p get 'formula))
                    (d set! "bit" (p get 'bit)) (d set! "n" (p get 'n)) (d set! "hue10" (p get 'hue10))
                    (d set! "lit" (p get 'lit)) (d set! "costume" (p get 'costume)) (d set! "reference" (p get 'reference))
                    d)))))
          (self %discover (o get 'root))))
      (File write-all (%path-join outdir "index.json") (Json emit index)))

    (method %run-one (self o)
      (def r (Bitwise render (o get 'name) (o get 'fmt) (o get 'tagline) (o get 'kind) "o"))
      (if (o get 'json)
        (display (%str-concat (list (Json emit (rest r)) "\n")))
        (if (o get 'out)
          (do (File write-all (o get 'out) (first r))
              (when (o get 'png) (display (%str-concat (list (self %png! (o get 'out) (o get 'fmt)) "\n")))))
          (display (%str-concat (list (first r) "\n"))))))

    (method main (self (param raw LIST "The program's arguments, argv[0] first, engine flags and a leading -- tolerated"))
      (doc "Run the command line: one project to stdout or a file, or --all under a workspace root."
        (returns ANY "nil")
        (example "(BitwiseCli main (list \"x\" \"--\" \"x-lang\" \"--json\"))" "..."))
      (def o (self %opts (self %argv raw)))
      (if (o get 'all) (self %run-all o)
        (if (o get 'name) (self %run-one o)
          (display (%str-concat (list "usage: x -l bitwise -- NAME [--fmt mark|avatar|banner] [--tagline TEXT] [--kind KIND] [-o FILE] [--png] [--json]\n"
                                      "       x -l bitwise -- --all [--root DIR] [--out DIR] [--png]\n"))))))))

(provide bitwise/cli BitwiseCli)
