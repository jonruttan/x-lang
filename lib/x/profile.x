; profile.x -- Profiling library
;
; Requires: lib/x-core.x (%stderr already defined there)

; Navigate base to profile list:
; (%base) -> (type-alist (files) (env) p-true line-number (a e t))
(def %profile (fn () (first (rest (rest (rest (rest (rest (first (%base))))))))))

; Read counters
(def alloc-count (fn () (first-int (first (%profile)))))
(def eval-count  (fn () (first-int (first (rest (%profile))))))
(def tco-count   (fn () (first-int (first (rest (rest (%profile)))))))

; Reset counters
(def profile-reset (fn ()
  (set-first-int (first (%profile)) 0)
  (set-first-int (first (rest (%profile))) 0)
  (set-first-int (first (rest (rest (%profile)))) 0)))

; --- Heap collection ---

; Save the atomic C primitive before we shadow it
(def %heap-collect-prim heap-collect)

(def %hc-last-allocs 0)
(def %hc-last-surviving 10000)

; Force full collection -- always runs atomic mark+sweep, returns freed count
; Uses op (dynamic scoping) so the caller's env is not saved/restored,
; avoiding GC freeing the saved env from the C stack.
(def heap-collect-force (op () %hcf-e
  (def %hcf-before (heap-count))
  (%heap-collect-prim)
  (def %hcf-after (heap-count))
  (set %hc-last-allocs (alloc-count))
  (set %hc-last-surviving %hcf-after)
  (- %hcf-before %hcf-after)))

; Smart collection -- skip if heap pressure is low
(def heap-collect (op () %hc-e
  (if (> (- (alloc-count) %hc-last-allocs) %hc-last-surviving)
    (heap-collect-force)
    0)))

; --- Output ---

; Dump all profile data to stderr
(def profile-dump (fn ()
  (%stderr "allocs=") (%stderr (alloc-count))
  (%stderr " evals=") (%stderr (eval-count))
  (%stderr " tco=") (%stderr (tco-count))
  (%stderr " heap=") (%stderr (heap-count))
  (%stderr "\n")))
