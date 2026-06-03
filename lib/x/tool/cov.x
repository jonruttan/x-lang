; cov.x -- Library coverage report
;
; Walks the env-alist, inspects procedure bodies for coverage flags
; (X_OBJ_FLAG_2 set by x-profile), and reports covered/total nodes.

; --- Platform detection ---

(def %cov-word-size
  (if (> (convert (convert 4294967296 %ptr) %int) 0) 8 4))
(def %cov-flags-offset (* 2 %cov-word-size))

; --- Object flag inspection ---

(def %cov-obj-flags
  (fn (_ obj)
    (if (null? obj) 0
      (ptr-ref-word (convert obj %ptr) %cov-flags-offset))))

(doc (def cov-covered?
  (fn (_ obj) (> (& (%cov-obj-flags obj) 2) 0)))
  (param obj ANY "Object to check")
  (returns BOOLEAN "True if object was evaluated (FLAG_2 set)")
  "Test whether an object was marked as evaluated by x-profile.")

(def %cov-is-cons?
  (fn (_ x)
    (if (null? x) #f
      (let ((tn (type-name x)))
        (or (str=? tn "LIST") (str=? tn "PAIR"))))))

; --- AST coverage counting ---

(doc (def cov-count-tree
  (fn (self expr depth)
    (if (or (null? expr) (> depth 15))
      (list 0 0)
      (if (not (%cov-is-cons? expr))
        (list 0 0)
        (guard (_ (list 0 0))
          (let ((left (self (first expr) (+ depth 1)))
                (right (self (rest expr) (+ depth 1)))
                (cov (if (cov-covered? expr) 1 0)))
            (list
              (+ cov (+ (first left) (first right)))
              (+ 1 (+ (first (rest left)) (first (rest right)))))))))))
  (param expr ANY "AST node to walk")
  (param depth INTEGER "Current recursion depth (limit 15)")
  (returns LIST "(covered total) pair")
  "Count covered and total AST nodes in a tree.")

; --- Per-function check ---

(doc (def cov-check-fn
  (fn (_ name val tsv-mode)
    (if (not (str=? (type-name val) "PROCEDURE")) ()
      (let ((body (obj-ref val 1)))
        (let ((counts (cov-count-tree body 0)))
          (let ((cov (first counts))
                (total (first (rest counts))))
            (if (> total 0)
              (if tsv-mode
                (do (display "COV\t") (write name) (display "\t")
                  (display cov) (display "\t")
                  (display total) (newline))
                (list name cov total)))))))))
  (param name SYMBOL "Function name")
  (param val ANY "Function value to inspect")
  (param tsv-mode BOOLEAN "Output TSV format if true")
  (returns LIST "(name covered total) or nil")
  "Check coverage for a single function.")

; --- Env-alist walker ---

(doc (def cov-walk
  (fn (self alist n tsv-mode)
    (if (or (null? alist) (> n 5000)) ()
      (do
        (guard (_ ())
          (let ((name (first (first alist)))
                (val (rest (first alist))))
            (if (and (symbol? name) (procedure? val) (not (null? val)))
              (cov-check-fn name val tsv-mode))))
        (self (rest alist) (+ n 1) tsv-mode)))))
  (param alist LIST "Environment alist to walk")
  (param n INTEGER "Counter (limit 5000)")
  (param tsv-mode BOOLEAN "Output TSV format if true")
  "Walk an environment alist checking coverage on each procedure.")

; --- Library boundary ---

(doc (def cov-skip-to-library
  (fn (self alist)
    (if (null? alist) ()
      (if (and (symbol? (first (first alist)))
               (str=? (convert (first (first alist)) %string)
                          "%cov-library-end"))
        (rest alist)
        (self (rest alist))))))
  (param alist LIST "Environment alist")
  (returns LIST "Alist from library boundary marker onward")
  "Skip past test definitions to the library boundary marker.")

(doc (provide x/tool/cov
  cov-covered? cov-count-tree cov-check-fn cov-walk cov-skip-to-library)
  "Library coverage analysis for x-profile instrumented code.")
