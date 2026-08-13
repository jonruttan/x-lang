; intrinsics.x -- Low-level intrinsics for tokenizer and profiling
;
; Buffer scoring helpers used by custom type analysers, and stderr output.
; Requires: data.x (first-int, set-first-int!)

; Write to stderr (swap fileout fd, display, restore)
(def %stderr
  (fn (_ msg)
    (def %files (rest (first (first (rest (first (%base)))))))
    (def %fo (first (rest %files)))
    (def %s (%cell-int %fo))
    (%set-cell-int! %fo (%cell-int (first (rest (rest %files)))))
    (display msg)
    (%set-cell-int! %fo %s)))

; Quick profile dump to stderr (alloc-count + heap object count).
; ns `heap` is de-registered (R5): fetch the prim from the catalog.


; Buffer length and unread for tokenizer scoring
(def %buffer-len
  (fn (_ buffer)
    (- (%cell-int (rest buffer)) (%cell-int buffer))))
(def %buffer-unread
  (fn (_ buffer)
    (%set-cell-int!
      (rest buffer)
      (- (%cell-int (rest buffer)) 1))))
(def %score-set
  (fn (_ score sign buffer)
    (%set-cell-int! score (* sign (%buffer-len buffer)))))


; Current source line number
(def %current-line
  (fn (_ )
    (%cell-int
      (first (first (rest (first (rest (first (%base))))))))))

(doc (provide x/reader/intrinsics)
  "Low-level tokenizer and profiling intrinsics: buffer scoring helpers and line tracking.")
