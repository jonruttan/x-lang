; intrinsics.x -- Low-level intrinsics for tokenizer and profiling
;
; Buffer scoring helpers used by custom type analysers, and stderr output.
; Requires: data.x (first-int, set-first-int!)

; Write to stderr (swap fileout fd, display, restore)
(def %stderr
  (fn (_ msg)
    (def %files (rest (first (first (rest (first (%base)))))))
    (def %fo (first (rest %files)))
    (def %s (%first-int %fo))
    (%set-first-int! %fo (%first-int (first (rest (rest %files)))))
    (display msg)
    (%set-first-int! %fo %s)))

; Quick profile dump to stderr (alloc-count + heap object count).
; ns `heap` is de-registered (R5): fetch the prim from the catalog.
(def %heap-count (prim-ref (lit heap) (lit count)))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read-char (prim-ref (lit io) (lit read-char)))

(def %profile-dump
  (fn (_ )
    (%stderr
      (%first-int
        (first (first (first (first (rest (rest (first (%base))))))))))
    (%stderr " ")
    (%stderr (%heap-count))
    (%stderr "\n")
    ()))

; Buffer length and unread for tokenizer scoring
(def buffer-len
  (fn (_ buffer)
    (- (%first-int (rest buffer)) (%first-int buffer))))
(def buffer-unread
  (fn (_ buffer)
    (%set-first-int!
      (rest buffer)
      (- (%first-int (rest buffer)) 1))))
(def score-set
  (fn (_ score sign buffer)
    (%set-first-int! score (* sign (buffer-len buffer)))))

; Peek at next character without consuming it
(def peek-char
  (fn (_ )
    (def %ch (%read-char))
    (if (null? %ch)
      ()
      (do
        (buffer-unread
          (first
            (first (rest (rest (rest (rest (first (%base)))))))))
        %ch))))

; Current source line number
(def current-line
  (fn (_ )
    (%first-int
      (first (first (rest (first (rest (first (%base))))))))))

(doc (provide x/reader/intrinsics
  buffer-len buffer-unread score-set peek-char current-line)
  "Low-level tokenizer and profiling intrinsics: buffer scoring helpers and line tracking.")
