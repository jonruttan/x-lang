; module.x -- Include-once and module system (bootstrap)
;
; Provides include-once, require-once, provide, import.
; Last bootstrap file — after this, normal modules can use provide/import.

; Extend base tree: add include-list cell under io-state
(def %io-state (rest (first (rest (first (%base))))))
(def %false-stack (rest (rest %io-state)))
(set-rest! %false-stack (pair () ()))
(def %include-list-cell (rest %false-stack))

(def %rewrite
  (fn (_ p a b) (set-first! p a) (set-rest! p b) p))
(def %expanded (pair () ()))

; --- Include-once / require-once ---
(def %include-list-has?
  (fn (_ path)
    (def %go
      (fn (self lst)
        (match
          ((eq? lst ()) #f)
          ((str=? (first lst) path) #t)
          (#t (self (rest lst))))))
    (%go (first %include-list-cell))))
(def include-once
  (op (path) e
    (def %io-path (eval path e))
    (match
      ((%include-list-has? %io-path) ())
      (#t
        (do (set-first! %include-list-cell
              (pair %io-path (first %include-list-cell)))
            (include %io-path))))))
(def require-once include-once)

; --- Module registry ---
(set-rest! %include-list-cell (pair () ()))
(def %module-registry-cell (rest %include-list-cell))

; --- Documentation registry cell ---
(set-rest! %module-registry-cell (pair () ()))
(def %doc-registry-cell (rest %module-registry-cell))

(def %module-register!
  (fn (_ name exports)
    (set-first! %module-registry-cell
      (pair (pair name exports)
            (first %module-registry-cell)))))
(def %module-resolve
  (fn (_ name)
    (str-append "lib/"
      (str-append (symbol->str name) ".x"))))
(def provide
  (op (name . syms) _
    (%module-register! name syms)
    ()))

; Look up a module entry in the registry by name
(def %module-find
  (fn (self name)
    (def %go
      (fn (self lst)
        (match
          ((eq? lst ()) ())
          ((eq? (first (first lst)) name) (first lst))
          (#t (self (rest lst))))))
    (%go (first %module-registry-cell))))

; Check that every symbol in syms appears in the module's export list
(def %module-check-imports
  (fn (_ name syms exports)
    (def %check
      (fn (self remaining)
        (match
          ((eq? remaining ()) ())
          (#t
            (let* ((%sym (first remaining))
                   (%found
                    (fn (self lst)
                      (match
                        ((eq? lst ()) #f)
                        ((eq? (first lst) %sym) #t)
                        (#t (self (rest lst)))))))
              (match
                ((%found exports) (self (rest remaining)))
                (#t (error (str-append "import: symbol not exported by "
                      (str-append (symbol->str name)
                        (str-append ": " (symbol->str %sym))))))))))))
    (%check syms)))

(def import
  (op (name . syms) _
    (include-once (%module-resolve name))
    (match
      ((eq? syms ()) ())
      (#t
        (let ((%entry (%module-find name)))
          (match
            ((eq? %entry ()) ())
            (#t (%module-check-imports name syms (rest %entry)))))))))
