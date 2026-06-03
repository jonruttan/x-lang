; profile.x -- Performance profiling and smart garbage collection
;
; Reads the interpreter's internal performance counters from the base
; object's profile list. Each counter tracks a different aspect of
; evaluation: allocation, eval calls, tail-call optimizations, symbol
; lookups, and GC activity.
;
; Also provides a smart heap-collect that skips collection when heap
; pressure is low, and a forced variant that always collects.

(def %profile
  (fn (_ )
    (first (first (rest (rest (first (%base))))))))

; --- Counter accessors ---

(doc (def alloc-count (fn (_ ) (first-int (first (first (%profile))))))
  (returns INTEGER "Total heap allocations since last reset")
  "Return the number of heap objects allocated.")

(doc (def eval-count (fn (_ ) (first-int (first (first (rest (%profile)))))))
  (returns INTEGER "Total eval calls since last reset")
  "Return the number of eval invocations.")

(doc (def tco-count
  (fn (_ ) (first-int (first (first (rest (rest (%profile))))))))
  (returns INTEGER "Total tail-call optimizations since last reset")
  "Return the number of tail-call optimizations performed.")

(doc (def assoc-calls-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (%profile)))))))))
  (returns INTEGER "Total alist lookup calls")
  "Return the number of association list lookup operations.")

(doc (def assoc-steps-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (%profile))))))))))
  (returns INTEGER "Total alist walk steps")
  "Return the total steps walked during alist lookups.")

(doc (def sym-find-calls-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (rest (%profile)))))))))))
  (returns INTEGER "Total symbol-find calls")
  "Return the number of symbol lookup operations.")

(doc (def sym-find-steps-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))))))
  (returns INTEGER "Total symbol-find steps")
  "Return the total steps walked during symbol lookups.")

(doc (def gc-runs-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))
  (returns INTEGER "Total GC mark/sweep cycles")
  "Return the number of garbage collection runs.")

(doc (def bst-hits-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))))))
  (returns INTEGER "BST cache hits")
  "Return the number of successful BST (binary search tree) lookups.")

(doc (def bst-misses-count
  (fn (_ ) (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))))
  (returns INTEGER "BST cache misses")
  "Return the number of BST lookups that fell through to alist walk.")

; --- Reset ---

(doc (def profile-reset
  (fn (_ )
    (set-first-int! (first (first (%profile))) 0)
    (set-first-int! (first (first (rest (%profile)))) 0)
    (set-first-int! (first (first (rest (rest (%profile))))) 0)
    (set-first-int! (first (first (rest (rest (rest (%profile)))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (%profile))))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (rest (%profile)))))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))) 0)
    (set-first-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))) 0)))
  "Reset all performance counters to zero.")

; --- Heap collection ---

(def %heap-collect-prim heap-collect)
(def %hc-last-allocs 0)
(def %hc-last-surviving 10000)

(doc (def heap-collect-force
  (op ()
    _
    (def %hcf-before (heap-count))
    (%heap-collect-prim)
    (def %hcf-after (heap-count))
    (set! %hc-last-allocs (alloc-count))
    (set! %hc-last-surviving %hcf-after)
    (- %hcf-before %hcf-after)))
  (returns INTEGER "Number of objects freed")
  "Force a full GC mark/sweep cycle, returning the number of objects freed.")

(doc (def heap-collect
  (op ()
    _
    (if (> (- (alloc-count) %hc-last-allocs) %hc-last-surviving)
      (heap-collect-force)
      0)))
  (returns INTEGER "Number of objects freed, or 0 if skipped")
  "Smart GC: only collect when allocations since last run exceed surviving objects.")

; --- Output ---

(doc (def profile-dump
  (fn (_ )
    (%stderr "allocs=")    (%stderr (alloc-count))
    (%stderr " evals=")    (%stderr (eval-count))
    (%stderr " tco=")      (%stderr (tco-count))
    (%stderr " assoc-calls=") (%stderr (assoc-calls-count))
    (%stderr " assoc-steps=") (%stderr (assoc-steps-count))
    (%stderr " sym-find-calls=") (%stderr (sym-find-calls-count))
    (%stderr " sym-find-steps=") (%stderr (sym-find-steps-count))
    (%stderr " gc-runs=")  (%stderr (gc-runs-count))
    (%stderr " bst-hits=") (%stderr (bst-hits-count))
    (%stderr " bst-misses=") (%stderr (bst-misses-count))
    (%stderr " heap=")     (%stderr (heap-count))
    (%stderr "\n")))
  "Dump all profile counters to stderr.")

(doc (provide x/tool/profile
  alloc-count eval-count tco-count
  assoc-calls-count assoc-steps-count
  sym-find-calls-count sym-find-steps-count
  gc-runs-count bst-hits-count bst-misses-count
  profile-reset profile-dump
  heap-collect heap-collect-force)
  "Performance profiling and smart garbage collection.")
