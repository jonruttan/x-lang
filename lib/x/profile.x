; profile.x -- Profiling library (requires X_PROFILE build)

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

; Write to stderr (swap fileout fd, display, restore)
(def %fileout (fn () (rest (first (rest (first (%base)))))))
(def stderr (fn (msg)
  (do
    (def %saved (first-int (%fileout)))
    (set-first-int (%fileout) (first-int (rest (rest (first (rest (first (%base))))))))
    (display msg)
    (set-first-int (%fileout) %saved))))

; Full GC: mark + sweep, composed from heap primitives
(def gc (fn ()
  (def before (heap-count))
  (heap-mark)
  (heap-sweep)
  (- before (heap-count))))

; Dump all profile data to stderr
(def profile-dump (fn ()
  (stderr "allocs=") (stderr (alloc-count))
  (stderr " evals=") (stderr (eval-count))
  (stderr " tco=") (stderr (tco-count))
  (stderr " heap=") (stderr (heap-count))
  (stderr "\n")))
