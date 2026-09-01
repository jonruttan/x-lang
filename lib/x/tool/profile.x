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
  (fn (_ ) (%reflect-base-cell (lit profile))))

; --- Counter accessors ---

(doc (def alloc-count (fn (_ ) (%cell-int (first (first (%profile))))))
  (returns INT "Total heap allocations since last reset")
  "Return the number of heap objects allocated.")

(doc (def eval-count (fn (_ ) (%cell-int (first (first (rest (%profile)))))))
  (returns INT "Total eval calls since last reset")
  "Return the number of eval invocations.")

(doc (def tco-count
  (fn (_ ) (%cell-int (first (first (rest (rest (%profile))))))))
  (returns INT "Total tail-call optimizations since last reset")
  "Return the number of tail-call optimizations performed.")

(doc (def assoc-calls-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (%profile)))))))))
  (returns INT "Total alist lookup calls")
  "Return the number of association list lookup operations.")

(doc (def assoc-steps-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (%profile))))))))))
  (returns INT "Total alist walk steps")
  "Return the total steps walked during alist lookups.")

(doc (def sym-find-calls-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (%profile)))))))))))
  (returns INT "Total symbol-find calls")
  "Return the number of symbol lookup operations.")

(doc (def sym-find-steps-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))))))
  (returns INT "Total symbol-find steps")
  "Return the total steps walked during symbol lookups.")

(doc (def gc-runs-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))
  (returns INT "Total GC mark/sweep cycles")
  "Return the number of garbage collection runs.")

(doc (def bst-hits-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))))))
  (returns INT "BST cache hits")
  "Return the number of successful BST (binary search tree) lookups.")

(doc (def bst-misses-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))))
  (returns INT "BST cache misses")
  "Return the number of BST lookups that fell through to alist walk.")

; --- Reset ---

(doc (def profile-reset
  (fn (_ )
    (%set-cell-int! (first (first (%profile))) 0)
    (%set-cell-int! (first (first (rest (%profile)))) 0)
    (%set-cell-int! (first (first (rest (rest (%profile))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (%profile)))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (%profile))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (%profile)))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))) 0)))
  "Reset all performance counters to zero.")

; --- Heap collection ---

; ns `heap` is de-registered (R5): fetch the raw collector from the catalog.
; The instrumented heap-collect / heap-collect-force ops below are this
; tool's own exports, defined fresh (nothing bare to shadow anymore).
(def %heap-collect-prim (prim-ref (lit heap) (lit collect)))
(def %hc-last-allocs 0)
(def %hc-last-surviving 10000)

(doc (def heap-collect-force
  (op ()
    _
    (def %hcf-before (Heap count))
    (%heap-collect-prim)
    (def %hcf-after (Heap count))
    (set! %hc-last-allocs (alloc-count))
    (set! %hc-last-surviving %hcf-after)
    (- %hcf-before %hcf-after)))
  (returns INT "Number of objects freed")
  "Force a full GC mark/sweep cycle, returning the number of objects freed.")

(doc (def heap-collect
  (op ()
    _
    (if (> (- (alloc-count) %hc-last-allocs) %hc-last-surviving)
      (heap-collect-force)
      0)))
  (returns INT "Number of objects freed, or 0 if skipped")
  "Smart GC: only collect when allocations since last run exceed surviving objects.")

; --- Output ---

; READER-NEUTRAL ON PURPOSE.  A lang bundle imports this module through its
; OWN reader (x-sweet does), and $-interpolation is a he/xe reader feature:
; sweet's reader mangles the $-string silently, and the mangled body crashed
; the engine when evaluated (found live, 2026-09-01).  Plain prims and 2-arg
; appends read identically under every reader this module can arrive through.
; The helpers are BODY defs, not globals (the percent-globals budget holds
; this file at 4) -- dump runs once, so the defs-at-depth cost is nothing.
(doc (def profile-dump
  (fn (_ )
    (def %prof-sa (prim-ref (lit str) (lit append)))
    (def %prof-w (prim-ref (lit io) (lit write-to-str)))
    (def %prof-kv
      (fn (_ label value rest)
        (%prof-sa label (%prof-sa (%prof-w value) rest))))
    (%stderr
      (%prof-kv "allocs=" (alloc-count)
        (%prof-kv " evals=" (eval-count)
          (%prof-kv " tco=" (tco-count)
            (%prof-kv " assoc-calls=" (assoc-calls-count)
              (%prof-kv " assoc-steps=" (assoc-steps-count)
                (%prof-kv " sym-find-calls=" (sym-find-calls-count)
                  (%prof-kv " sym-find-steps=" (sym-find-steps-count)
                    (%prof-kv " gc-runs=" (gc-runs-count)
                      (%prof-kv " bst-hits=" (bst-hits-count)
                        (%prof-kv " bst-misses=" (bst-misses-count)
                          (%prof-kv " heap=" (Heap count) "\n"))))))))))))))
  "Dump all profile counters to stderr.")

(doc (provide x/tool/profile
  alloc-count eval-count tco-count
  assoc-calls-count assoc-steps-count
  sym-find-calls-count sym-find-steps-count
  gc-runs-count bst-hits-count bst-misses-count
  profile-reset profile-dump
  heap-collect heap-collect-force)
  "Performance profiling and smart garbage collection.")
