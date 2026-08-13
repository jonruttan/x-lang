; doc-index.x -- Generate the master index for x-lang reference docs
;
; A pure filter: the docs/ref/x index Markdown on stdout.
;   sh x.sh --no-pin -q -f tools/dev/doc-index.x > docs/ref/x/index.md
;
; Scans the docs/ref/x/ directory structure directly rather than
; querying the module registry, so all generated docs appear.

(import x/tool/contract)
(import x/type/path)

(Contract alloc-guard!)

(def %di-byte-len (prim-ref 'str 'byte-len))
(def %di-byte-ref (prim-ref 'str 'byte-ref))
(def %di-byte-sub (prim-ref 'str 'byte-sub))   ; (v start LENGTH), unchecked

(def %doc-dir "docs/ref/x")

; Group labels in display order
(def %groups
  (list (pair "boot" "Bootstrap") (pair "core" "Core") (pair "type" "Types")
        (pair "sys" "System") (pair "num" "Numeric Tower")
        (pair "doc" "Documentation") (pair "tool" "Tools")
        (pair "platform" "Platform")))

; --- tiny line scanner over a slurped doc file ---------------------

; Lines of text as (start . end) offset pairs, first N only.
(def %title-and-desc
  (fn (_ text)
    (def len (%di-byte-len text))
    (def %line-end
      (fn (_ i)
        (let go ((j i))
          (if (>= j len) len
            (if (= 10 (%di-byte-ref text j)) j (go (+ j 1)))))))
    (def %starts-at?
      (fn (_ pfx i e)
        (def plen (%di-byte-len pfx))
        (if (> (+ i plen) e) #f
          (let go ((j 0))
            (if (>= j plen) #t
              (if (= (%di-byte-ref pfx j) (%di-byte-ref text (+ i j)))
                (go (+ j 1)) #f))))))
    ; title: first '# ' heading within the first 5 lines
    ; desc: first non-empty line after that heading not starting '#' or '['
    (let go ((i 0) (n 0) (title ()))
      (if (>= i len) (pair title ())
        (let ((e (%line-end i)))
          (match
            ((and (null? title) (>= n 5)) (pair () ()))
            ((and (null? title) (%starts-at? "# " i e))
              (go (+ e 1) (+ n 1) (%di-byte-sub text (+ i 2) (- e (+ i 2)))))
            ((null? title) (go (+ e 1) (+ n 1) ()))
            ; after the heading: skip blank lines and '#'/'[' lines...
            ((= i e) (go (+ e 1) (+ n 1) title))
            ((or (%starts-at? "#" i e) (%starts-at? "[" i e))
              (go (+ e 1) (+ n 1) title))
            ; ...the first ordinary line is the description
            (#t (pair title (%di-byte-sub text i (- e i))))))))))

(def %md-name?
  (fn (_ name)
    (and (Str8 ends? ".md" name) (not (str=? name "index.md")))))

; The typed strip replaces the hardcoded cut-3-bytes (#225).
(def %base-of (fn (_ name) (Path strip-ext name)))

(def %emit-entry
  (fn (_ path link fallback-title)
    (def td (%title-and-desc (File slurp path)))
    (def title (if (null? (first td)) fallback-title (first td)))
    (do (display "- [") (display title) (display "](") (display link) (display ")")
        (unless (null? (rest td))
          (do (display " — ") (display (rest td))))
        (newline))))

(display "# x-lang Reference") (newline) (newline)
(display "Generated from source by `make doc-x`.") (newline) (newline)

(let go ((groups %groups))
  (unless (null? groups)
    (let ((dir (first (first groups))) (label (rest (first groups))))
      (let ((dpath (Path join %doc-dir dir)))
        (when (File exists? dpath)
          (do (display "## ") (display label) (newline) (newline)
              (let each ((names (Contract sort (File list-dir dpath))))
                (unless (null? names)
                  (let ((name (first names)))
                    (when (%md-name? name)
                      (let ((base (%base-of name)))
                        (%emit-entry (Path join dpath name)
                                     (Path join dir name)
                                     (Path join "x" dir base)))))
                  (each (rest names))))
              (newline)))))
    (go (rest groups))))

; Top-level files (and.x, or.x, constructs.x, x-core.x)
(def %top-md
  (let go ((names (Contract sort (File list-dir %doc-dir))) (acc ()))
    (if (null? names) (List reverse acc)
      (go (rest names)
          (if (and (%md-name? (first names))
                   (File exists? (Path join %doc-dir (first names))))
            (pair (first names) acc) acc)))))

(unless (null? %top-md)
  (do (display "## Top-level") (newline) (newline)
      (let each ((names %top-md))
        (unless (null? names)
          (let ((name (first names)))
            (%emit-entry (Path join %doc-dir name)
                         name
                         (%base-of name)))
          (each (rest names))))
      (newline)))
