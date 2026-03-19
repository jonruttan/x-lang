; tools/cov-report.x -- x-lang library coverage report
;
; Usage: cat lib/x-core.x [tests...] tools/cov-report.x | ./x-profile

(def %cov-word-size
  (if (> (ptr->int (int->ptr 4294967296)) 0) 8 4))
(def %cov-flags-offset (* 2 %cov-word-size))

(def %cov-obj-flags
  (fn (obj)
    (if (null? obj) 0
      (ptr-ref-word (obj->ptr obj) %cov-flags-offset))))

(def %cov-covered?
  (fn (obj) (> (& (%cov-obj-flags obj) 2) 0)))

(def %cov-is-cons?
  (fn (x)
    (if (null? x) #f
      (let ((tn (type-name x)))
        (or (string=? tn "LIST") (string=? tn "PAIR"))))))

(def %cov-count-tree
  (fn (expr depth)
    (if (or (null? expr) (> depth 15))
      (list 0 0)
      (if (not (%cov-is-cons? expr))
        (list 0 0)
        (guard (err (list 0 0))
          (let ((left (%cov-count-tree (first expr) (+ depth 1)))
                (right (%cov-count-tree (rest expr) (+ depth 1)))
                (self (if (%cov-covered? expr) 1 0)))
            (list
              (+ self (+ (first left) (first right)))
              (+ 1 (+ (first (rest left)) (first (rest right)))))))))))

(def %cov-tested 0)
(def %cov-partial 0)
(def %cov-untested 0)
(def %cov-total 0)

(def %cov-check-fn
  (fn (name val)
    (if (not (string=? (type-name val) "PROCEDURE")) ()
      (let ((body (obj-ref val 1)))
        (let ((counts (%cov-count-tree body 0)))
          (let ((cov (first counts))
                (total (first (rest counts))))
            (if (> total 0)
              (do
                (set %cov-total (+ %cov-total 1))
                (if (= cov total)
                  (set %cov-tested (+ %cov-tested 1))
                  (if (= cov 0)
                    (do
                      (set %cov-untested (+ %cov-untested 1))
                      (display "    ")
                      (write name)
                      (display " UNTESTED")
                      (newline))
                    (do
                      (set %cov-partial (+ %cov-partial 1))
                      (display "    ")
                      (write name)
                      (display " ")
                      (display cov)
                      (display "/")
                      (display total)
                      (display " (")
                      (display (%int/ (* cov 100) total))
                      (display "%)")
                      (newline))))))))))))

(def %cov-walk
  (fn (alist n)
    (if (or (null? alist) (> n 5000)) ()
      (do
        (guard (err ())
          (let ((name (first (first alist)))
                (val (rest (first alist))))
            (if (and (symbol? name) (procedure? val) (not (null? val)))
              (%cov-check-fn name val))))
        (%cov-walk (rest alist) (+ n 1))))))

; Skip past test defs to the library boundary marker
(def %cov-skip-to-library
  (fn (alist)
    (if (null? alist) ()
      (if (and (symbol? (first (first alist)))
               (string=? (symbol->string (first (first alist)))
                          "%cov-library-end"))
        (rest alist)
        (%cov-skip-to-library (rest alist))))))

(def %cov-report
  (op () e
    (def lib-start (%cov-skip-to-library e))
    (display "=== x-lang Library Coverage ===")
    (newline)
    (newline)
    (%cov-walk (if (null? lib-start) e lib-start) 0)
    (newline)
    (display "  Full:     ")
    (display %cov-tested)
    (display "/")
    (display %cov-total)
    (newline)
    (display "  Partial:  ")
    (display %cov-partial)
    (display "/")
    (display %cov-total)
    (newline)
    (display "  Untested: ")
    (display %cov-untested)
    (display "/")
    (display %cov-total)
    (newline)))

(%cov-report)
