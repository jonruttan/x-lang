; tools/cov-report.x -- x-lang library coverage report
;
; Usage: cat lib/x-core.x [tests...] tools/cov-report.x | ./x-profile
;
; Walks the env alist, finds PROCEDURE closures, checks which
; body expression nodes have the X_COV flag (bit 2) set by eval.
; Reports functions with less than 100% node coverage.

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

; Count covered/total pair nodes in an expression tree
(def %cov-count-tree
  (fn (expr depth)
    (if (or (null? expr) (> depth 15)) (list 0 0)
      (if (not (%cov-is-cons? expr)) (list 0 0)
        (let ((left (%cov-count-tree (first expr) (+ depth 1)))
              (right (%cov-count-tree (rest expr) (+ depth 1)))
              (self (if (%cov-covered? expr) 1 0)))
          (list (+ self (+ (first left) (first right)))
                (+ 1 (+ (first (rest left)) (first (rest right))))))))))

(def %cov-tc 0)
(def %cov-ta 0)
(def %cov-uf 0)
(def %cov-tf 0)
(def %cov-full 0)

(def %cov-report
  (op () e
    (def %walk
      (fn (a n)
        (if (or (null? a) (> n 5000)) ()
          (do
            (guard (err ())
              (let ((name (first (first a)))
                    (val (rest (first a))))
                (if (and (symbol? name) (procedure? val) (not (null? val))
                         (string=? (type-name val) "PROCEDURE"))
                  (let ((body (obj-ref val 1)))
                    (let ((counts (%cov-count-tree body 0)))
                      (let ((cov (first counts))
                            (total (first (rest counts))))
                        (if (> total 0)
                          (do
                            (set %cov-tf (+ %cov-tf 1))
                            (set %cov-tc (+ %cov-tc cov))
                            (set %cov-ta (+ %cov-ta total))
                            (if (< cov total)
                              (do
                                (set %cov-uf (+ %cov-uf 1))
                                (display "  ")
                                (write name)
                                (display ": ")
                                (display cov)
                                (display "/")
                                (display total)
                                (if (= cov 0)
                                  (display " UNTESTED")
                                  (do
                                    (display " (")
                                    (display (/ (* cov 100) total))
                                    (display "%)")))
                                (newline))
                              (set %cov-full (+ %cov-full 1)))))))))))
            (%walk (rest a) (+ n 1))))))
    (display "=== x-lang Library Coverage Report ===")
    (newline)
    (newline)
    (%walk e 0)
    (newline)
    (display "  Nodes: ")
    (display %cov-tc)
    (display "/")
    (display %cov-ta)
    (display " (")
    (display (/ (* %cov-tc 100) (if (= %cov-ta 0) 1 %cov-ta)))
    (display "%)")
    (newline)
    (display "  Full coverage: ")
    (display %cov-full)
    (display "/")
    (display %cov-tf)
    (newline)
    (display "  Gaps: ")
    (display %cov-uf)
    (display "/")
    (display %cov-tf)
    (newline)))

(%cov-report)
