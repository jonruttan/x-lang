; tools/dev/cov-report.x -- x-lang library coverage report (entry script)
;
; Usage: cat lib/x-core.x [tests...] tools/dev/cov-report.x | ./x-profile
;
; Set %cov-tsv-mode to #t before loading for machine-readable TSV output.

(import x/tool/cov)

(unless (not (symbol? '%cov-tsv-mode))
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
      (do (display "=== x-lang Library Coverage ===\n\n")))
    ; One (name cov total) row -> tallies + printed line (non-tsv).
    ; Helpers defined BEFORE their users (a closure cannot see a later
    ; sibling def).  %seen dedups rows by name string: the env walk and
    ; the registry walk can both reach a bare top-frame fn.
    (def %seen (pair () ()))
    (def %seen?
      (fn (self s lst)
        (if (null? lst) #f
          (if (str=? s (first lst)) #t (self s (rest lst))))))
    (def %row-new?
      (fn (_ name)
        (let ((s (%cvt name %string)))
          (if (%seen? s (first %seen)) #f
            (do (%set-first! %seen (pair s (first %seen))) #t)))))
    (def %tally-row
      (fn (_ result)
        (if (if (null? result) #f (%row-new? (nth 0 result)))
          (if (not %cov-tsv-mode)
            (do
              (set! %cov-total (+ %cov-total 1))
              (def rname (nth 0 result))
              (def cov (nth 1 result))
              (def total (nth 2 result))
              (if (= cov total)
                (set! %cov-tested (+ %cov-tested 1))
                (if (= cov 0)
                  (do (set! %cov-untested (+ %cov-untested 1))
                      (display "    ") (write rname) (display " UNTESTED\n"))
                  (do (set! %cov-partial (+ %cov-partial 1))
                      (display "    ") (write rname) (display " " cov "/" total " ("
                                                             (%int/ (* cov 100) total)
                                                             "%)\n")))))))))
    (def %tally-rows
      (fn (self rows)
        (unless (null? rows)
          (do (%tally-row (first rows)) (self (rest rows))))))
    ; Walk with inline reporting.  Classes report their own methods
    ; (#408): post-"functions into classes" the library surface lives
    ; there, and a class entry used to be silently skipped.
    (def %report-walk
      (fn (_ al n)
        (unless (or (null? al) (> n 5000))
          (do
            (guard (_ ())
              (let ((name (first (first al)))
                    (val (rest (first al))))
                (if (symbol? name)
                  (if (procedure? val)
                    (%tally-row (cov-check-fn name val %cov-tsv-mode))
                    (if (class? val)
                      (%tally-rows (cov-check-class name val %cov-tsv-mode))
                      ()))
                  ())))
            (%report-walk (rest al) (+ n 1))))))
    ; Registry walk (#408): the top-frame env spine holds only ~72
    ; entries post-#47 -- classes and module fns resolve through nested
    ; frames the flat walk can never reach.  The include-list registry
    ; rows are (module-name . provided-names); evaluating each provided
    ; symbol IN e rides the engine's own frame-marked lookup, which is
    ; the one sound door to those bindings.  Stale provides error and
    ; are skipped by the guard.
    (def %provides-walk
      (fn (self syms)
        (unless (null? syms)
          (do
            (guard (_ ())
              (let ((sym (first syms)))
                (let ((val (eval sym e)))
                  (if (procedure? val)
                    (%tally-row (cov-check-fn sym val %cov-tsv-mode))
                    (if (class? val)
                      (%tally-rows (cov-check-class sym val %cov-tsv-mode))
                      ())))))
            (self (rest syms))))))
    (def %registry-walk
      (fn (self rows)
        (unless (null? rows)
          (do (guard (_ ()) (%provides-walk (rest (first rows))))
              (self (rest rows))))))
    (%report-walk alist 0)
    (guard (_ ())
      (%registry-walk (first (rest (eval (lit %include-list-cell) e)))))
    (if (not %cov-tsv-mode)
      (do (display "\n" "  Full:     " %cov-tested "/" %cov-total "\n"
                   "  Partial:  " %cov-partial "/" %cov-total "\n"
                   "  Untested: " %cov-untested "/" %cov-total "\n")))))

(%cov-report)
