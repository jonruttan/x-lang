; module.x -- Include-once and module system (bootstrap)
;
; Provides include-once, require-once, provide, import.
; Last bootstrap file — after this, normal modules can use provide/import.

; Extend base tree: add include-list cell under io-state
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))

(def %io-state (rest (first (rest (first (%base))))))
(def %false-stack (rest (rest %io-state)))
(set-rest! %false-stack (pair () ()))
(def %include-list-cell (rest %false-stack))

(def %rewrite
  (fn (_ p a b) (set-first! p a) (set-rest! p b) p))
(def %expanded (pair () ()))

; --- Path resolution (for ./ and ../ relative includes) ---------------------
; `include` (wrapped just below) and the loaders built on it (include-once /
; require-once / import) resolve a path that begins with ./ or ../ against the
; directory of the file currently loading -- tracked in %include-dir-cell, a
; stack pushed around each load. Plain and absolute paths keep their cwd-relative
; meaning, so no existing call-site moves. The C primitive itself is untouched;
; see the set!-wrapper below for how the bare symbol is made relative-aware.
(def %slash-code (%char->integer (str-ref "/" 0)))

(def %str-starts?
  (fn (_ s p)
    (def pl (str-length p))
    (match
      ((< (str-length s) pl) #f)
      (#t (str=? (substring s 0 pl) p)))))

; Index of the last "/" in p, or -1 if there is none.
(def %last-slash
  (fn (_ p)
    (def n (str-length p))
    (def %go
      (fn (self i last)
        (match
          ((= i n) last)
          ((= (%char->integer (str-ref p i)) %slash-code) (self (+ i 1) i))
          (#t (self (+ i 1) last)))))
    (%go 0 -1)))

; Directory part of a path: everything before the last "/", or "." if none.
(def %path-dir
  (fn (_ p)
    (def slash (%last-slash p))
    (match
      ((< slash 0) ".")
      (#t (substring p 0 slash)))))

; Join a directory with a relative remainder. No normalisation -- the OS
; collapses any "." / ".." segments when it opens the file.
(def %path-join
  (fn (_ dir part)
    (match
      ((str=? dir ".") part)
      ((str=? dir "") part)
      (#t (%str-append dir (%str-append "/" part))))))

; Resolve an include argument against the current directory:
;   /foo   -> absolute, used as-is
;   ./foo  -> sibling of the including file (the "./" is stripped)
;   ../foo -> relative to the including file (the ".." is kept for the OS)
;   foo    -> unchanged: cwd-relative, exactly as before
(def %resolve-include-path
  (fn (_ input curdir)
    (match
      ((%str-starts? input "/") input)
      ((%str-starts? input "./")
        (%path-join curdir (substring input 2 (str-length input))))
      ((%str-starts? input "../") (%path-join curdir input))
      (#t input))))

; Stack of the directories of the files currently being loaded (innermost
; first). Pushed/popped around each managed include below.
(def %include-dir-cell (pair () ()))
(def %include-curdir
  (fn (_)
    (match
      ((eq? (first %include-dir-cell) ()) ".")
      (#t (first (first %include-dir-cell))))))
(def %include-dir-push!
  (fn (_ dir) (set-first! %include-dir-cell (pair dir (first %include-dir-cell)))))
(def %include-dir-pop!
  (fn (_) (set-first! %include-dir-cell (rest (first %include-dir-cell)))))

; --- Relative-aware include (the C primitive is untouched) -----------------
; Make the bare `include` resolve ./ and ../ against the file currently loading
; WITHOUT changing the C primitive: capture it as %raw-include, then set! -- NOT
; def! -- the `include` binding to a wrapper. set! MUTATES the existing binding
; slot, so every resolution path sees the wrapper: the boot C-loop AND the
; REPL's eval!. A plain (def include ...) instead creates a shadowing variable
; that the REPL's operator lookup ignores in favour of the C callable, so the
; redefinition is bypassed at the prompt -- the one case that matters.
; A fn (not an op): applicative like the primitive it fronts, and it carries its
; own save-stack frame, so it does NOT add a no-save op layer that would corrupt
; provide/import's variadic bind. Only early-boot forms here (def/match, no
; `let`) -- this runs for every include from here on, before `let` is defined.
; x_eval_load still binds each loaded file's defs globally. Plain/absolute paths
; are unchanged, so no existing call-site moves.
(def %raw-include include)
(set! include
  (fn (_ path)
    (def %io-path (%resolve-include-path path (%include-curdir)))
    (%include-dir-push! (%path-dir %io-path))
    (def %result (%raw-include %io-path))
    (%include-dir-pop!)
    %result))

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
    ; Resolve ./ and ../ for the dedup key; the load itself -- and the dir-stack
    ; push/pop -- is handled by the relative-aware `include` above.
    (def %io-path (%resolve-include-path (eval path e) (%include-curdir)))
    (match
      ((%include-list-has? %io-path) ())
      (#t
        (do
          (set-first! %include-list-cell
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
; Search roots for `import`. The default is just "lib", so resolution stays
; exactly "lib/<name>.x" and needs no filesystem check at boot (a single root
; short-circuits before %file-exists? is ever called -- Sys loads much later).
; Add roots post-boot with (import-path! "dir") to import modules outside lib/.
(def %import-roots-cell (pair (list "lib") ()))
(def %file-exists?
  (fn (_ path) (guard (_ #f) (Sys file-exists? path))))
(def import-path!
  (fn (_ dir)
    (set-first! %import-roots-cell (pair dir (first %import-roots-cell)))
    (first %import-roots-cell)))
(def %module-resolve
  (fn (_ name)
    (def %file (%str-append (symbol->str name) ".x"))
    (def %go
      (fn (self roots)
        (match
          ((eq? roots ()) (%str-append "lib/" %file))            ; ultimate fallback
          ((eq? (rest roots) ()) (%path-join (first roots) %file)) ; last root: no check
          ((%file-exists? (%path-join (first roots) %file))
            (%path-join (first roots) %file))
          (#t (self (rest roots))))))
    (%go (first %import-roots-cell))))
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
            (let ((%sym (first remaining)))
              (let ((%found
                     (fn (self lst)
                       (match
                         ((eq? lst ()) #f)
                         ((eq? (first lst) %sym) #t)
                         (#t (self (rest lst)))))))
                (match
                  ((%found exports) (self (rest remaining)))
                  (#t (error (%str-append "import: symbol not exported by "
                        (%str-append (symbol->str name)
                          (%str-append ": " (symbol->str %sym)))))))))))))
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
