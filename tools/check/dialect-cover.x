; tools/check/dialect-cover.x -- the dialect coverage ratchet (#70).
;
; Every shipped entry point under lib/*.x must be exercised end-to-end by
; a `# @lib <file>` group in tests/x/specs/dialects/.  The dialects had
; ZERO such coverage until #70, which is how #49 shipped: both tower
; launchers crashed at the exact invocation the README documents, while
; every numeric spec passed against its own bespoke harness.
;
; The point is that a NEW dialect cannot ship untested -- add lib/x-foo.x
; and this fails until a smoke group exists for it.  The reverse
; direction: a group naming a dialect that no longer exists is stale
; coverage, and would otherwise sit green forever against nothing.
;
; Same shape as check-isa and the other contract ratchets: mechanical,
; not a habit anyone has to remember.
;
; Run: sh x.sh --no-pin -q -f tools/check/dialect-cover.x  (make check-dialect-cover)

(import x/tool/contract)

(Contract alloc-guard!)

(def %dc-byte-len (prim-ref 'str 'byte-len))
(def %dc-byte-ref (prim-ref 'str 'byte-ref))
(def %dc-byte-sub (prim-ref 'str 'byte-sub))   ; (v start LENGTH), unchecked

(def %spec-dir "tests/x/specs/dialects")

; Lines of text starting "# @lib ", their values in file order (the
; grep -hr | sed extraction).  Small corpus; open-coded byte walk.
(def %at-lib-values
  (fn (_ text acc)
    (def len (%dc-byte-len text))
    (def %line-end
      (fn (_ i)
        (let go ((j i))
          (if (>= j len) len
            (if (= 10 (%dc-byte-ref text j)) j (go (+ j 1)))))))
    (def %starts-at?
      (fn (_ pfx i)
        (def plen (%dc-byte-len pfx))
        (if (> (+ i plen) len) #f
          (let go ((j 0))
            (if (>= j plen) #t
              (if (= (%dc-byte-ref pfx j) (%dc-byte-ref text (+ i j)))
                (go (+ j 1)) #f))))))
    (let go ((i 0) (acc acc))
      (if (>= i len) (List reverse acc)
        (let ((e (%line-end i)))
          (go (+ e 1)
              (if (%starts-at? "# @lib " i)
                (pair (%dc-byte-sub text (+ i 7) (- e (+ i 7))) acc)
                acc)))))))

(def %covered
  (let go ((files (Contract walk %spec-dir (fn (_ p) #t))) (acc ()))
    (if (null? files) acc
      (go (rest files) (List append acc (%at-lib-values (File slurp (first files)) ()))))))

(def %dialects
  (Contract sort
    (let go ((names (File list-dir "lib")) (acc ()))
      (if (null? names) acc
        (go (rest names)
            (if (Str8 ends? ".x" (first names)) (pair (first names) acc) acc))))))


(def %contains-slash?
  (fn (_ s)
    (def len (%dc-byte-len s))
    (let go ((i 0))
      (if (>= i len) #f
        (if (= 47 (%dc-byte-ref s i)) #t (go (+ i 1)))))))

(def %bad (pair #f ()))

(let go ((names %dialects))
  (unless (null? names)
    (let ((name (first names)))
      (unless (%member-str? name %covered)
        (do (display "dialect-cover: FAIL lib/") (display name)
            (display " has no '# @lib ") (display name)
            (display "' group in ") (display %spec-dir) (display "/")
            (newline)
            (%set-first! %bad #t))))
    (go (rest names))))

; harness libs (e.g. ../tests/x/lib/float.x) carry a '/', not dialects
(let go ((gs %covered))
  (unless (null? gs)
    (let ((g (first gs)))
      (unless (or (%contains-slash? g) (File exists? (Str8 append "lib/" g)))
        (do (display "dialect-cover: FAIL ") (display %spec-dir)
            (display "/ covers lib/") (display g)
            (display ", which does not exist")
            (newline)
            (%set-first! %bad #t))))
    (go (rest gs))))

(if (first %bad) (Sys exit 1)
  (do (display "dialect-cover: ok") (newline)))
