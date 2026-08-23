; module.x -- Include-once and module system (bootstrap)
; lint-known: dirent-names
; (x/platform/dirent, imported at CALL time in %module-list-dir --
;  the same lazy-import pattern as the syscall table)
;
; Provides include-once, require-once, provide, import.
; Last bootstrap file — after this, normal modules can use provide/import.

; Extend base tree: add include-list cell under io-state
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))

; THE COMMITTED ROUTES, not a hand-walked chain.  Both of these used to spell
; their steps out -- (rest (first (rest (first (%base))))) and two more rests --
; which silently assumed x-engine-c's base layout.  On an engine that arranges
; its base differently the steps land on an unrelated cell, and the %set-rest!
; below then WRITES there: booting x-engine-rust turned #f truthy, because the
; extension scribbled past an object that had no room for it.
;
; Decision L1 says the layout travels with the engine and only the NAMES are the
; contract, so a literal walk is the one thing the library may not do.  Every
; route named here is one x-engine-c already declared -- the names existed all
; along; these three lines simply were not using them.
; %io-state itself is no longer read: it existed only as a waypoint on the way
; to the false cell, which is now resolved directly.
(def %false-stack (%reflect-base-cell (lit false)))
(%set-rest! %false-stack (pair () ()))
(def %include-list-cell (rest %false-stack))

(def %rewrite
  (fn (_ p a b) (%set-first! p a) (%set-rest! p b) p))
(def %expanded (pair () ()))

; --- Path resolution (for ./ and ../ relative includes) ---------------------
; `include` (wrapped just below) and the loaders built on it (include-once /
; require-once / import) resolve a path that begins with ./ or ../ against the
; directory of the file currently loading -- tracked in %include-dir-cell, a
; stack pushed around each load. Plain and absolute paths keep their cwd-relative
; meaning, so no existing call-site moves. The C primitive itself is untouched;
; see the set!-wrapper below for how the bare symbol is made relative-aware.
(def %slash-code (%char->integer (%str-ref "/" 0)))

(def %str-starts?
  (fn (_ s p)
    (def pl (%str-length p))
    (match
      ((< (%str-length s) pl) #f)
      (#t (str=? (%substring s 0 pl) p)))))

; Index of the last "/" in p, or -1 if there is none.
(def %last-slash
  (fn (_ p)
    (def n (%str-length p))
    (def %go
      (fn (self i last)
        (match
          ((= i n) last)
          ((= (%char->integer (%str-ref p i)) %slash-code) (self (+ i 1) i))
          (#t (self (+ i 1) last)))))
    (%go 0 -1)))

; Directory part of a path: everything before the last "/", or "." if none.
; BOOT-CONSTRAINED twins of (Path dirname)/(Path join) -- this file
; loads before the class layer, so it cannot ride x/type/path.  The
; SEMANTICS INTENTIONALLY DIVERGE and callers rely on it: %path-dir
; does not strip trailing slashes or special-case the root, and
; %path-join returns part UNCHANGED for dir "." or "" where (Path join)
; would emit "./part" -- rel paths built here key lockfiles and the
; module registry, so the bytes are the contract (#225).
(def %path-dir
  (fn (_ p)
    (def slash (%last-slash p))
    (match
      ((< slash 0) ".")
      (#t (%substring p 0 slash)))))

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
        (%path-join curdir (%substring input 2 (%str-length input))))
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
  (fn (_ dir) (%set-first! %include-dir-cell (pair dir (first %include-dir-cell)))))
(def %include-dir-pop!
  (fn (_) (%set-first! %include-dir-cell (rest (first %include-dir-cell)))))

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
          (%set-first! %include-list-cell
            (pair %io-path (first %include-list-cell)))
          (include %io-path))))))
(def require-once include-once)

; --- Module registry ---
(%set-rest! %include-list-cell (pair () ()))
(def %module-registry-cell (rest %include-list-cell))

; --- Documentation registry cell ---
(%set-rest! %module-registry-cell (pair () ()))
(def %doc-registry-cell (rest %module-registry-cell))

; --- Loaded-module registry (name-keyed) ---
; Module identity is the NAME (x/type/str), not the filesystem path it was
; loaded from: paths vary with the import root (repo "lib" vs an installed
; absolute root), names do not.  Path-keyed dedup left every boot module one
; import away from a silent double load in any tree whose root is not the
; literal "lib".  Symbols are interned per-base, so
; eq? membership is sound.
(%set-rest! %doc-registry-cell (pair () ()))
(def %module-loaded-cell (rest %doc-registry-cell))
; An entry is a bare NAME symbol (loaded by import -- the current line) or a
; (NAME . LINE) pair (loaded by import-version[-once] -- a pinned line).
; Both spell "one version per name per session"; the pair records WHICH.
; Lookup takes the FIRST match, so a raw import-version re-record shadows.
(def %module-loaded-line
  ; () = not loaded; the symbol `bare` = loaded without a line; N = line N
  (fn (_ name)
    (def %go
      (fn (self lst)
        (match
          ((eq? lst ()) ())
          ((eq? (first lst) name) (lit bare))
          ((pair? (first lst))
            (match
              ((eq? (first (first lst)) name) (rest (first lst)))
              (#t (self (rest lst)))))
          (#t (self (rest lst))))))
    (%go (first %module-loaded-cell))))
(def %module-loaded?
  (fn (_ name)
    (match
      ((eq? (%module-loaded-line name) ()) #f)
      (#t #t))))
(def %module-loaded!
  (fn (_ name)
    (%set-first! %module-loaded-cell (pair name (first %module-loaded-cell)))))
(def %module-loaded-at!
  (fn (_ name line)
    (%set-first! %module-loaded-cell
      (pair (pair name line) (first %module-loaded-cell)))))

(def %module-register!
  (fn (_ name exports)
    (%set-first! %module-registry-cell
      (pair (pair name exports)
            (first %module-registry-cell)))))
; Search roots for `import`. The default is just "lib", so resolution stays
; exactly "lib/<name>.x" and needs no filesystem check at boot (a single root
; short-circuits before %file-exists? is ever called -- Sys loads much later).
; Add roots post-boot with (import-path! "dir") to import modules outside lib/.
;
; The embedder may define %install-root -- the runtime tree root, no trailing
; slash, e.g. "/usr/local/share/x" -- BEFORE the library loads (the shell
; wrapper's installed mode emits one (def %install-root ...) form at the top
; of the pipe; def is a C prim, so no library is needed to evaluate it).
; When bound it REPLACES the cwd-relative default: an installed tree must
; resolve imports from ANY cwd.  Unbound -- the repo
; case -- the guard falls back to "lib" and nothing changes.
(def %import-roots-cell
  (pair (guard (_ (list "lib")) (list (%path-join %install-root "lib"))) ()))
(def %file-exists?
  (fn (_ path) (guard (_ #f) (Sys file-exists? path))))
(def import-path!
  (fn (_ dir)
    (%set-first! %import-roots-cell (pair dir (first %import-roots-cell)))
    (first %import-roots-cell)))
(def %module-resolve-file
  (fn (_ %file)
    (def %go
      (fn (self roots)
        (match
          ((eq? roots ()) (%str-append "lib/" %file))            ; ultimate fallback
          ((eq? (rest roots) ()) (%path-join (first roots) %file)) ; last root: no check
          ((%file-exists? (%path-join (first roots) %file))
            (%path-join (first roots) %file))
          (#t (self (rest roots))))))
    (%go (first %import-roots-cell))))
(def %module-resolve
  (fn (_ name)
    (%module-resolve-file (%str-append (symbol->str name) ".x"))))
; --- Version arithmetic (GH #214): dotted tuples, missing components 0 ---
; The digit render/parse is local and rides the INT prims directly --
; ambient / promotes to RATIONAL once the tower loads (the tower-division
; trap), and boot-layer code depends on nothing later than itself.
(def %int-div (prim-ref (lit int) (lit /)))
(def %int-mod (prim-ref (lit int) (lit %)))
(def %zero-code (%char->integer (%str-ref "0" 0)))
(def %dot-code (%char->integer (%str-ref "." 0)))
(def %module-int->str
  (fn (_ n)
    (def %digit
      (fn (_ d) (%substring "0123456789" d (+ d 1))))
    (def %go
      (fn (self n acc)
        (match
          ((= n 0) acc)
          (#t (self (%int-div n 10)
                    (%str-append (%digit (%int-mod n 10)) acc))))))
    (match
      ((= n 0) "0")
      (#t (%go n "")))))
; "3.1.4" -> (3 1 4); () on anything that is not dotted digits.
(def %module-parse-version
  (fn (_ s)
    (def n (%str-length s))
    (def %digit?
      (fn (_ c)
        (match
          ((< c %zero-code) #f)
          ((< (+ %zero-code 9) c) #f)
          (#t #t))))
    ; %go returns the tuple, or the symbol `bad` on a malformed spelling --
    ; nil cannot carry the failure, it is also the empty tail.
    (def %go
      (fn (self i acc seen)
        (match
          ((= i n)
            (match
              (seen (pair acc ()))
              (#t (lit bad))))
          ((= (%char->integer (%str-ref s i)) %dot-code)
            (match
              (seen
                (do
                  (def %tail (self (+ i 1) 0 #f))
                  (match
                    ((eq? %tail (lit bad)) (lit bad))
                    (#t (pair acc %tail)))))
              (#t (lit bad))))
          ((%digit? (%char->integer (%str-ref s i)))
            (self (+ i 1)
                  (+ (* acc 10) (- (%char->integer (%str-ref s i)) %zero-code))
                  #t))
          (#t (lit bad)))))
    (match
      ((= n 0) (lit bad))
      (#t (%go 0 0 #f)))))
(def %module-version-render
  (fn (self v)
    (match
      ((eq? v ()) "0")
      ((eq? (rest v) ()) (%module-int->str (first v)))
      (#t (%str-append (%module-int->str (first v))
            (%str-append "." (self (rest v))))))))
; Tuple compare with zero-padding: (3 1) vs (3 1 0) is equal; (3 10) > (3 9).
(def %module-version-cmp
  (fn (self a b)
    (match
      ((eq? a ())
        (match
          ((eq? b ()) 0)
          ((= (first b) 0) (self () (rest b)))
          (#t -1)))
      ((eq? b ())
        (match
          ((= (first a) 0) (self (rest a) ()))
          (#t 1)))
      ((< (first a) (first b)) -1)
      ((< (first b) (first a)) 1)
      (#t (self (rest a) (rest b))))))
; A spec string is one of:
;   "3.1.4"  exact (missing components 0)     -> (exact 3 1 4)
;   "*"      anything                          -> (star)
;   "3.1.*"  prefix                            -> (star 3 1)
;   "^3.1"   >= 3.1, below the next major      -> (caret 3 1)
; Unknown spellings are a loud error -- the closed-vocabulary rule.
(def %module-parse-spec
  (fn (_ who s)
    (def n (%str-length s))
    (def %bad
      (fn (_)
        (error (%str-append (symbol->str who)
                 (%str-append ": bad version spec \"" (%str-append s "\""))))))
    (def %vers
      (fn (_ part)
        (def %v (%module-parse-version part))
        (match
          ((eq? %v (lit bad)) (%bad))
          (#t %v))))
    (match
      ((= n 0) (%bad))
      ((str=? s "*") (pair (lit star) ()))
      ((%str-starts? s "^")
        (pair (lit caret) (%vers (%substring s 1 n))))
      ((match
         ((< n 2) #f)
         (#t (str=? (%substring s (- n 2) n) ".*")))
        (pair (lit star) (%vers (%substring s 0 (- n 2)))))
      (#t (pair (lit exact) (%vers s))))))
; Does version v satisfy the parsed spec?
(def %module-version-ok?
  (fn (_ spec v)
    (def %prefix?
      (fn (self p v)
        (match
          ((eq? p ()) #t)
          ((eq? v ())
            (match
              ((= (first p) 0) (self (rest p) ()))
              (#t #f)))
          ((= (first p) (first v)) (self (rest p) (rest v)))
          (#t #f))))
    (match
      ((eq? (first spec) (lit exact)) (= 0 (%module-version-cmp (rest spec) v)))
      ((eq? (first spec) (lit star)) (%prefix? (rest spec) v))
      (#t ; caret: >= base, same major
        (match
          ((< (%module-version-cmp v (rest spec)) 0) #f)
          ((eq? (rest spec) ()) #t)
          ((eq? v ()) (= (first (rest spec)) 0))
          (#t (= (first (rest spec)) (first v))))))))
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
    (match
      ((%module-loaded? name) ())
      (#t
        (do
          ; register BEFORE loading -- cycle safety, mirrors include-once
          (%module-loaded! name)
          (include (%module-resolve name)))))
    (match
      ((eq? syms ()) ())
      (#t
        (let ((%entry (%module-find name)))
          (match
            ((eq? %entry ()) ())
            (#t (%module-check-imports name syms (rest %entry)))))))))

; --- Versioned lines (GH #214) ---
; A module may exist in several versions at once, as sibling files:
; grid.x (version 0 -- every unversioned module), grid@1.x, grid@1.3.x,
; grid@1.3.1.x.  Files are append-only: a bug fix is a NEW patch file, and
; it reaches old importers through RESOLUTION -- their spec ("1.3", "^1",
; "1.3.*") selects the newest satisfying file next run.  The version is an
; ARGUMENT, never part of the module name: every version file provides the
; base name, and the registry keys it, so two versions of one module cannot
; meet in a session.
;
; Selection scans the module's directory per root ((File list-dir) -- per-OS
; dirent decoding, fetched at CALL time: versioned imports appear in user
; projects, never in boot files).  The FIRST root holding any satisfying
; candidate wins, even if a later root holds a higher version -- root order
; is precedence (the overlay shadows the platform), same as import.
(def %module-at-prefix?
  ; "grid@..." for base "grid" -> the version part, or the symbol `no`.
  (fn (_ entry base)
    (def bl (%str-length base))
    (def el (%str-length entry))
    (match
      ((< el (+ bl 3)) (lit no))                       ; needs "@" + v + ".x"
      ((not (str=? (%substring entry 0 bl) base)) (lit no))
      ((not (str=? (%substring entry bl (+ bl 1)) "@")) (lit no))
      ((not (str=? (%substring entry (- el 2) el) ".x")) (lit no))
      (#t (%substring entry (+ bl 1) (- el 2))))))
; Kernel-direct directory read: open / getdents64 (Linux) or
; getdirentries64 (Darwin) / close over the syscall prim, numbers and O_*
; flags from the platform table -- imported at CALL time (versioned imports
; appear in user projects, never in boot files), and the table layer itself
; is built to load mid-boot.  No class layer: boot code reads the kernel the
; same way sys/file.x does, without riding File/Err above it.
(def %str-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %str-make (prim-ref (lit str) (lit make)))
(def %module-mode
  ; O_* value by name out of the platform table, boot-style walk.
  (fn (_ name)
    (def %go
      (fn (self lst)
        (match
          ((eq? lst ()) 0)
          ((eq? (first (first lst)) name) (first (rest (first lst))))
          (#t (self (rest lst))))))
    (%go %file-modes)))
(def %module-list-dir
  ; Entry names in dir; a dir that cannot be opened is no entries (a
  ; DELIBERATE boot policy -- resolution probes absent roots), but a
  ; read error mid-scan is an ERROR: folding it into EOF silently
  ; changed which module version resolved (#228).  "." and ".." are
  ; rejected here, not in the decoder, mirroring file.x's split.
  (fn (_ dir)
    (import x/platform/syscall)
    (import x/platform/dirent)
        ; Three args always, like sys/file.x: the kernel ignores the perm
    ; unless O_CREAT is set, and the prim's call shape stays uniform.
    (def %fd (syscall (syscall-id (lit open)) dir (%module-mode (lit rdonly)) 420))
    (match
      ((< %fd 0) ())
      (#t
        (do
          (def %buf (%str-make 4096))
          (def %basep (%str-make 8))
        (def %go
          (fn (self acc)
            (def %n
              (match
                (os-darwin?
                  (syscall (syscall-id (lit getdirentries64)) %fd %buf 4096 %basep))
                (#t (syscall (syscall-id (lit getdents64)) %fd %buf 4096))))
            (match
              ((< %n 0)
                (do (syscall (syscall-id (lit close)) %fd)
                    (error (%str-append "module list-dir: directory read failed: " dir))))
              ((= %n 0) acc)
              (#t (self (dirent-names %buf %n acc))))))
          (def %names (%go ()))
          (syscall (syscall-id (lit close)) %fd)
          (def %keep
            (fn (self lst acc)
              (match
                ((eq? lst ()) acc)
                ((str=? (first lst) ".") (self (rest lst) acc))
                ((str=? (first lst) "..") (self (rest lst) acc))
                (#t (self (rest lst) (pair (first lst) acc))))))
          (%keep %names ()))))))
(def %module-scan-dir
  ; All (version-tuple . filename) candidates for base in dir, bare included
  ; as version ().  A missing or unreadable directory is no candidates.
  (fn (_ dir base)
    (def %entries (%module-list-dir dir))
    (def %go
      (fn (self lst acc)
        (match
          ((eq? lst ()) acc)
          (#t
            (do
              (def %vpart (%module-at-prefix? (first lst) base))
              (match
                ((eq? %vpart (lit no)) (self (rest lst) acc))
                (#t
                  (do
                    (def %v (%module-parse-version %vpart))
                    (match
                      ((eq? %v (lit bad)) (self (rest lst) acc))
                      (#t (self (rest lst)
                                (pair (pair %v (first lst)) acc))))))))))))
    (def %at (%go %entries ()))
    (match
      ((%file-exists? (%path-join dir (%str-append base ".x")))
        (pair (pair () (%str-append base ".x")) %at))
      (#t %at))))
(def %module-pick
  ; Newest candidate satisfying spec, or ().
  (fn (_ spec cands)
    (def %go
      (fn (self lst best)
        (match
          ((eq? lst ()) best)
          ((not (%module-version-ok? spec (first (first lst)))) (self (rest lst) best))
          ((eq? best ()) (self (rest lst) (first lst)))
          ((< (%module-version-cmp (first best) (first (first lst))) 0)
            (self (rest lst) (first lst)))
          (#t (self (rest lst) best)))))
    (%go cands ())))
; name + parsed spec -> (version-tuple . path), or a loud error.  Exact specs
; try the literal spelling first (no scan); either way equivalent spellings
; ("3.1" / "3.1.0") unify through the scan's numeric compare.
(def %module-resolve-version
  (fn (_ who name spec text)
    (def %relname (symbol->str name))
    (def %base
      (match
        ((< (%last-slash %relname) 0) %relname)
        (#t (%substring %relname (+ (%last-slash %relname) 1) (%str-length %relname)))))
    (def %reldir (%path-dir %relname))
    (def %exact-file
      (match
        ((eq? (first spec) (lit exact))
          (%str-append %relname
            (%str-append "@" (%str-append (%module-version-render (rest spec)) ".x"))))
        (#t ())))
    (def %go
      (fn (self roots)
        (match
          ((eq? roots ())
            (error (%str-append (symbol->str who)
                     (%str-append ": no version of "
                       (%str-append %relname
                         (%str-append " satisfies \"" (%str-append text "\"")))))))
          (#t
            (match
              ((match
                 ((eq? %exact-file ()) #f)
                 (#t (%file-exists? (%path-join (first roots) %exact-file))))
                (pair (rest spec) (%path-join (first roots) %exact-file)))
              (#t
                (do
                  (def %hit (%module-pick spec
                              (%module-scan-dir
                                (%path-join (first roots) %reldir) %base)))
                  (match
                    ((eq? %hit ())
                      (self (rest roots)))
                    (#t (pair (first %hit)
                              (%path-join (first roots)
                                (%path-join %reldir (rest %hit)))))))))))))
    (%go (first %import-roots-cell))))
; import-version-once is the everyday form.  Once-semantics with a contract:
; if the module is already loaded AND the loaded version satisfies the spec,
; no-op; loaded but NOT satisfying -- or loaded bare, version unknowable --
; is a LOUD error.  Import's silent first-wins would hand back some other
; version precisely when one was requested, which is the failure this form
; exists to prevent.  (A later bare (import name) still no-ops silently:
; that is import's own contract, unchanged.)
(def %module-spec-text!
  (fn (_ who spec)
    (match
      ((str? spec) ())
      (#t (error (%str-append (symbol->str who)
                   ": the version spec must be a string literal, e.g. \"3.1\" or \"^3\""))))))
(def %module-version-conflict!
  (fn (_ name have text)
    (error (%str-append "import-version: "
             (%str-append (symbol->str name)
               (%str-append " is already loaded as "
                 (%str-append
                   (match
                     ((eq? have (lit bare)) "the unversioned module")
                     (#t (%str-append "version " (%module-version-render have))))
                   (%str-append "; requested \"" (%str-append text "\"")))))))))
(def import-version-once
  (op (name text . syms) _
    (%module-spec-text! (lit import-version-once) text)
    (def %spec (%module-parse-spec (lit import-version-once) text))
    (def %have (%module-loaded-line name))
    (match
      ((eq? %have ())
        (do
          (def %hit (%module-resolve-version (lit import-version-once) name %spec text))
          ; register BEFORE loading -- cycle safety, mirrors import
          (%module-loaded-at! name (first %hit))
          (include (rest %hit))))
      ((eq? %have (lit bare)) (%module-version-conflict! name %have text))
      ((%module-version-ok? %spec %have) ())
      (#t (%module-version-conflict! name %have text)))
    (match
      ((eq? syms ()) ())
      (#t
        (let ((%entry (%module-find name)))
          (match
            ((eq? %entry ()) ())
            (#t (%module-check-imports name syms (rest %entry)))))))))
; The raw re-evaluating sibling, mirroring include vs include-once.  It
; re-records the version it loads; lookup takes the first match, so the new
; record shadows any prior one -- the registry reflects what is actually
; in the session.
(def import-version
  (op (name text . syms) _
    (%module-spec-text! (lit import-version) text)
    (def %spec (%module-parse-spec (lit import-version) text))
    (def %hit (%module-resolve-version (lit import-version) name %spec text))
    (%module-loaded-at! name (first %hit))
    (include (rest %hit))
    (match
      ((eq? syms ()) ())
      (#t
        (let ((%entry (%module-find name)))
          (match
            ((eq? %entry ()) ())
            (#t (%module-check-imports name syms (rest %entry)))))))))
