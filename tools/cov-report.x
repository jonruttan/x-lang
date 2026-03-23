; tools/cov-report.x -- x-lang library coverage report (entry script)
;
; Usage: cat lib/x-core.x [tests...] tools/cov-report.x | ./x-profile
;
; Set %cov-tsv-mode to #t before loading for machine-readable TSV output.

(import x/tool/cov)

(if (not (symbol? (lit %cov-tsv-mode)))
  ()
  (if (null? %cov-tsv-mode)
    (def %cov-tsv-mode #f)))
(def %cov-tested 0)
(def %cov-partial 0)
(def %cov-untested 0)
(def %cov-total 0)

(def %cov-report
  (op (_ ) e
    (def lib-start (cov-skip-to-library e))
    (def alist (if (null? lib-start) e lib-start))
    (if (not %cov-tsv-mode)
      (do (display "=== x-lang Library Coverage ===") (newline) (newline)))
    ; Walk with inline reporting
    (def %report-walk
      (fn (_ al n)
        (if (or (null? al) (> n 5000)) ()
          (do
            (guard (err ())
              (let ((name (first (first al)))
                    (val (rest (first al))))
                (if (and (symbol? name) (procedure? val) (not (null? val)))
                  (do
                    (def result (cov-check-fn name val %cov-tsv-mode))
                    (if (not (null? result))
                      (if (not %cov-tsv-mode)
                        (do
                          (set! %cov-total (+ %cov-total 1))
                          (def cov (nth 1 result))
                          (def total (nth 2 result))
                          (if (= cov total)
                            (set! %cov-tested (+ %cov-tested 1))
                            (if (= cov 0)
                              (do (set! %cov-untested (+ %cov-untested 1))
                                  (display "    ") (write name) (display " UNTESTED") (newline))
                              (do (set! %cov-partial (+ %cov-partial 1))
                                  (display "    ") (write name) (display " ")
                                  (display cov) (display "/") (display total)
                                  (display " (") (display (%int/ (* cov 100) total))
                                  (display "%)") (newline)))))))))))
            (%report-walk (rest al) (+ n 1))))))
    (%report-walk alist 0)
    (if (not %cov-tsv-mode)
      (do (newline)
          (display "  Full:     ") (display %cov-tested) (display "/") (display %cov-total) (newline)
          (display "  Partial:  ") (display %cov-partial) (display "/") (display %cov-total) (newline)
          (display "  Untested: ") (display %cov-untested) (display "/") (display %cov-total) (newline)))))

(%cov-report)
