; profile.x -- Profiling library
;
; Requires: lib/x-core.x (%stderr already defined there)
; Navigate base to profile list:
; (%base) -> (type-alist-stack (files) (env) true-stack false-stack line-stack (profile...) (hooks) save ...)
; Each counter is stack-wrapped: (atom(n) . nil)

(def %profile
  (fn ()
    (first (rest (rest (rest (rest (rest (rest (first (%base)))))))))))
; Read counters (extra first to unwrap stack)

(def alloc-count
  (fn () (first-int (first (first (%profile))))))

(def eval-count
  (fn () (first-int (first (first (rest (%profile)))))))

(def tco-count
  (fn ()
    (first-int (first (first (rest (rest (%profile))))))))

(def assoc-calls-count
  (fn ()
    (first-int (first (first (rest (rest (rest (%profile)))))))))

(def assoc-steps-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (%profile))))))))))

(def sym-find-calls-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (rest (%profile)))))))))))

(def sym-find-steps-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))))))

(def gc-runs-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))

(def bst-hits-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))))))

(def bst-misses-count
  (fn ()
    (first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))))

; Reset all counters

(def profile-reset
  (fn ()
    (set-first-int (first (first (%profile))) 0)
    (set-first-int (first (first (rest (%profile)))) 0)
    (set-first-int (first (first (rest (rest (%profile))))) 0)
    (set-first-int (first (first (rest (rest (rest (%profile)))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (%profile))))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (rest (%profile)))))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))) 0)
    (set-first-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))) 0)))

; --- Heap collection ---
; Save the atomic C primitive before we shadow it

(def %heap-collect-prim heap-collect)

(def %hc-last-allocs 0)

(def %hc-last-surviving 10000)
; Force full collection -- always runs atomic mark+sweep, returns freed count
; Uses op (dynamic scoping) so the caller's env is not saved/restored,
; avoiding GC freeing the saved env from the C stack.

(def heap-collect-force
  (op ()
    %hcf-e
    (def %hcf-before (heap-count))
    (%heap-collect-prim)
    (def %hcf-after (heap-count))
    (set %hc-last-allocs (alloc-count))
    (set %hc-last-surviving %hcf-after)
    (- %hcf-before %hcf-after)))
; Smart collection -- skip if heap pressure is low

(def heap-collect
  (op ()
    %hc-e
    (if (> (- (alloc-count) %hc-last-allocs) %hc-last-surviving)
      (heap-collect-force)
      0)))
; --- Output ---
; Dump all profile data to stderr

(def %profile-dump
  (fn ()
    (%stderr "allocs=")
    (%stderr (alloc-count))
    (%stderr " evals=")
    (%stderr (eval-count))
    (%stderr " tco=")
    (%stderr (tco-count))
    (%stderr " assoc-calls=")
    (%stderr (assoc-calls-count))
    (%stderr " assoc-steps=")
    (%stderr (assoc-steps-count))
    (%stderr " sym-find-calls=")
    (%stderr (sym-find-calls-count))
    (%stderr " sym-find-steps=")
    (%stderr (sym-find-steps-count))
    (%stderr " gc-runs=")
    (%stderr (gc-runs-count))
    (%stderr " bst-hits=")
    (%stderr (bst-hits-count))
    (%stderr " bst-misses=")
    (%stderr (bst-misses-count))
    (%stderr " heap=")
    (%stderr (heap-count))
    (%stderr "\n")))

(def profile-dump %profile-dump)
