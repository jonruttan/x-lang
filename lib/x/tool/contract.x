; contract.x -- Contract: shared scaffold for the in-language gate ratchets.
;
; The tools/check/*.x gates share three needs: a sorted recursive file walk
; (the `find | sort` replacement), sorted-list set operations for the
; manifest-vs-source diffs, and entry-script plumbing (the tool's own argv
; behind the x.sh engine prefix, the allocation guard).  Homed here so each
; gate stays a short entry script; the shell policy that put them in the
; language is tools/README.md.
;
; Gates run from the repo root (make provides the cwd); walk paths are
; therefore repo-relative by construction.

(import x/sys/posix)
(import x/sys/file)
(import x/type/list)
(import x/type/path)

; Fetch the byte prims from the catalog: the walk and the gates' line
; matchers are hot loops, and class dispatch costs hundreds of objects per
; call (the #123 lesson).
(def %ct-byte-len (prim-ref 'str 'byte-len))
(def %ct-byte-ref (prim-ref 'str 'byte-ref))
(def %ct-mem-cmp (prim-ref 'mem 'cmp))

; Byte-order string compare on the C memcmp door: (Str8 <?) walks the
; bytes in interpreted x through protocol dispatch (~6K heap objects per
; comparison, measured -- a 4K-name sort OOMed the 300M guard on it).
(def %ct-str<?
  (fn (_ a b)
    (def la (%ct-byte-len a))
    (def lb (%ct-byte-len b))
    (def c (%ct-mem-cmp a b (if (< la lb) la lb)))
    (if (= c 0) (< la lb) (< c 0))))

(def-class Contract ()
  (doc "Shared scaffold for the in-language contract gates (tools/check/*.x): sorted file walks, sorted-list set difference, and entry-script argv/allocation plumbing.")
  (static

  (method walk (self (param dir STRING "Directory to walk")
                     (param keep? CALLABLE "Path predicate: keep files answering truthy"))
    (doc "Every file under dir (recursive) whose repo-relative path satisfies keep?, sorted by byte order -- the `find DIR | sort` replacement."
      (returns LIST "Sorted path strings"))
    (def %go
      (fn (self path acc)
        (match
          ((eq? 'dir (Assoc get 'kind (File stat path)))
            (let ents ((names (File list-dir path)) (acc acc))
              (if (null? names) acc
                (ents (rest names)
                      (self (Path join path (first names))
                            acc)))))
          ((keep? path) (pair path acc))
          (#t acc))))
    (Contract sort (%go dir ())))

  (method sort (self (param xs LIST "String list"))
    (doc "xs sorted ascending by byte order.  Deliberately locale-free: shell `sort` output depends on the host locale, byte order does not."
      (returns LIST "Sorted list"))
    (List sort %ct-str<? xs))

  (method uniq (self (param xs LIST "SORTED string list"))
    (doc "Adjacent duplicates removed (with sort, `sort -u`)."
      (returns LIST "Deduplicated list"))
    (let go ((xs xs) (acc ()))
      (match
        ((null? xs) (List reverse acc))
        ((and (pair? acc) (str=? (first xs) (first acc))) (go (rest xs) acc))
        (#t (go (rest xs) (pair (first xs) acc))))))

  (method only (self (param as LIST "SORTED deduplicated string list")
                     (param bs LIST "SORTED deduplicated string list"))
    (doc "Members of as absent from bs, in order (merge walk; both inputs sorted and deduplicated)."
      (returns LIST "as minus bs"))
    (let go ((as as) (bs bs) (acc ()))
      (match
        ((null? as) (List reverse acc))
        ((null? bs) (List append (List reverse acc) as))
        ((str=? (first as) (first bs)) (go (rest as) (rest bs) acc))
        ((%ct-str<? (first as) (first bs)) (go (rest as) bs (pair (first as) acc)))
        (#t (go as (rest bs) acc)))))

  (method argv (self)
    (doc "The tool's own arguments: `args` minus the engine path and the engine flags x.sh -f prepends (--batch/--quiet/--no-color).  Tool flags after x.sh's `--` survive untouched."
      (returns LIST "Argument strings"))
    (let go ((xs (rest args)))
      (match
        ((null? xs) ())
        ((or (str=? (first xs) "--batch")
             (str=? (first xs) "--quiet")
             (str=? (first xs) "--no-color"))
          (go (rest xs)))
        (#t xs))))

  (method alloc-guard! (self)
    (doc "Arm alloc-limit! from X_ALLOC_LIMIT_OBJS -- default 300000000, non-numeric values fall OPEN to the default: the same contract as the spec harness and the shell gates it replaces.")
    (def %digits
      (fn (_ s)
        ; the numeric value, or nil unless s is one or more digit bytes
        (def len (%ct-byte-len s))
        (if (= len 0) ()
          (let go ((i 0) (n 0))
            (match
              ((>= i len) n)
              (#t
                (let ((b (%ct-byte-ref s i)))
                  (if (and (>= b 48) (<= b 57))
                    (go (+ i 1) (+ (* n 10) (- b 48)))
                    ()))))))))
    (def %env (Sys getenv "X_ALLOC_LIMIT_OBJS"))
    (def %n (if (null? %env) () (%digits %env)))
    (alloc-limit! (if (null? %n) 300000000 %n)))))

(doc (provide x/tool/contract Contract)
  (note "Gates run from the repo root (make provides the cwd), so walk paths are repo-relative by construction; the shell policy that homed the gates in the language is tools/README.md.")
  "Shared scaffold for the in-language gate ratchets, on the Contract class: the sorted recursive walk, sorted-list set ops (sort/uniq/only), the tool's own argv behind the engine prefix, and the allocation guard.")
