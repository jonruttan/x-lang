; gc.x -- Garbage collection hooks
;
; Provides heap-collect and GC hook registration.

; Ensure dependencies are loaded
(match
  ((guard (e ()) (eval (lit set-first!))) ())
  (#t (include "lib/x/boot/data.x")))

(def heap-collect (fn (_ ) (applicative heap-mark heap-sweep) ()))

; Navigate base tree to gc-hooks cells
(def %gc-hooks
  (rest (rest (rest (rest (rest (rest (rest (first (%base))))))))))
(def %gc-hooks-rest (rest %gc-hooks))

(def heap-mark-root!
  (fn (_ obj)
    (def %cell (rest %gc-hooks-rest))
    (set-first! %cell (pair obj (first %cell)))))
(def heap-mark-hook!
  (fn (_ hook)
    (def %cell (first %gc-hooks))
    (set-first! %cell (pair hook (first %cell)))))
(def heap-free-hook!
  (fn (_ hook)
    (def %cell (first %gc-hooks-rest))
    (set-first! %cell (pair hook (first %cell)))))
