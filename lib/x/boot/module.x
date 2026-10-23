; module.x -- Include-once and module system (bootstrap)
; lint-known: dirent-names %image-writing
; (x/platform/dirent, imported at CALL time in %module-list-dir --
;  the same lazy-import pattern as the syscall table)
; (%image-writing: bound by tools/dev/image-write.x in its child base alone,
;  read through a guard by include below)
;
; Provides include-once, require-once, provide, import.
; Last bootstrap file — after this, normal modules can use provide/import.

; Extend base tree: add include-list cell under io-state
; Fetch the string prims from the catalogue (ns `str` is de-registered, R5).
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
; RE-LOADABLE, and every guard in this file exists for one reason: including
; lib/x-core.x on an already-booted tower must not corrupt the loader.  It is
; the first two lines of anyone's personality extraction, and it used to
; SIGSEGV with nothing on stdout or stderr.
;
; The state lives in the CATALOGUE rather than in cells this file owns, because a
; `def` here is re-evaluated on a re-load -- so any flag this file keeps is
; reset exactly when it is needed.  The catalogue belongs to the base and
; survives.  There is no bound?/defined? predicate to test with either: this
; runs before `let`, let alone the type system, and prim-ref answering nil for
; an unregistered member is the test.
;
; This one is subtle: hanging the include-once list off the base's false cell
; already makes the OBJECT survive, but the (%set-rest! ...) beside it wiped it
; on every re-load, so include-once forgot every file it had loaded.
(def %false-stack (%reflect-base-cell (lit false)))
(match
  ((eq? (prim-ref (lit module) (lit include-list)) ())
    (do
      (%set-rest! %false-stack (pair () ()))
      (prim-reg! (lit module) (lit include-list) (rest %false-stack))))
  (#t ()))
(def %include-list-cell (prim-ref (lit module) (lit include-list)))

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
; THE ONE THAT SEGFAULTED.  A re-load happens INSIDE an include, so this stack
; has a frame pushed; recreating it empty made the matching pop walk off nil.
(match
  ((eq? (prim-ref (lit module) (lit include-dir)) ())
    (prim-reg! (lit module) (lit include-dir) (pair () ())))
  (#t ()))
(def %include-dir-cell (prim-ref (lit module) (lit include-dir)))
(def %include-curdir
  (fn (_)
    (match
      ((eq? (first %include-dir-cell) ()) ".")
      (#t (first (first %include-dir-cell))))))
(def %include-dir-push!
  (fn (_ dir) (%set-first! %include-dir-cell (pair dir (first %include-dir-cell)))))
; Popping an empty stack is a no-op rather than a walk off nil.  With the guard
; above this should be unreachable, which is the point: an underflow here is a
; loader bug, and it should report as nothing happening rather than as a crash
; three frames away.
(def %include-dir-pop!
  (fn (_)
    (match
      ((eq? (first %include-dir-cell) ()) ())
      (#t (%set-first! %include-dir-cell (rest (first %include-dir-cell)))))))

; --- Loading a file into an environment --------------------------------------
; An included file's forms are evaluated where the include stands, as if
; written there: in the root from an unscoped file, in the module from a
; scoped one.  The engine's `include` evaluates every form of a file at the
; top level, in the root, whatever environment called it -- which is the
; loader a module's own file needs, since `import` loads a module into the
; root and a header makes the module's environment itself.  A file included
; from inside a scoped module is loaded here instead, by the steps the engine
; takes, through the base cells the contract names (tools/contract/
; base-paths.x): open the file, push it onto the input, line and buffer
; stacks, register its id so an error can name it, read each form with the
; reader -- which stamps it with the file and line -- and evaluate it in the
; including environment, then pop and close.  A failure mid-file needs none
; of this undone: `guard` restores the three stacks and closes the file, as
; it does for the engine's own include.  The frames pushed are pairs and
; atoms the engine reads through the same slots as its own; the engine's EOF
; latch writes into the atom, so each is fresh.  Every door is in isa.x and
; base-paths.x; nothing here is a primitive.
;
; `include` resolves ./ and ../ against the file loading, marks the module
; the file may be headed with -- the name `import` asks for, or %module-any
; by path -- for the header to read, and loads into the caller's
; environment.  It is set! over the engine's binding, not shadowed: set!
; mutates the slot every resolution path reads, the boot loop's and the
; REPL's.  Installed ONCE: a second load of this file would capture the
; wrapper as the engine's include and loop; on a reload the flag is set and
; the whole form is skipped.  The flag is a plain pair, not a catalogue
; entry: the catalogue is the C surface isa.x describes.  Only early-boot
; forms here -- def, match, fn, op -- since `let` is not defined yet, and
; integer doors through the catalogue, since the operators are not either.
(match
  ((eq? (prim-ref (lit module) (lit include-wrapped)) ())
    (do
      (prim-reg! (lit module) (lit include-wrapped) (pair () ()))
      ; The engine's include, kept under the name the ISA manifest records
      ; for it (isa.x, %isa-aliases): the image writer binds it into its
      ; child and names its code.
      (def %raw-include include)
      (def %include-into
        ((fn (_)
           (def %open (prim-ref (lit sys) (lit open)))
           (def %close (prim-ref (lit sys) (lit close)))
           (def %buf-make (prim-ref (lit buf) (lit make)))
           (def %str-make (prim-ref (lit str) (lit make)))
           (def %obj-make (prim-ref (lit obj) (lit make)))
           (def %int+ (prim-ref (lit int) (lit +)))
           (def %int< (prim-ref (lit int) (lit <)))
           (def %atom-type ((prim-ref (lit type) (lit of)) 0))
           ; The node whose FIRST slot holds a stack: the path's parent, its
           ; last step `f`.  A stack is pushed by replacing that slot, as the
           ; engine replaces the field.
           (def %holder
             (fn (_ name)
               (def %steps (%reflect-path name %base-paths))
               (def %last (fn (self l) (match ((eq? (rest l) ()) (first l)) (#t (self (rest l))))))
               (match
                 ((eq? (%last %steps) (lit f)) (%reflect-step (%base) (%reflect-path-parent %steps)))
                 (#t (error (pair (lit include-stack-not-a-first-slot) name))))))
           (def %atom (fn (_ n) (%set-cell-int! (%obj-make %atom-type 1) n)))
           (def %push! (fn (_ node v) (%set-first! node (pair v (first node)))))
           (def %pop! (fn (_ node) (%set-first! node (rest (first node)))))
           (def %load
             (fn (_ env path)
               (def %fd (%open path 0))
               (match
                 ((%int< %fd 0) (error (%str-append "include: cannot open " path)))
                 (#t ()))
               (def %line (%holder (lit line)))
               (def %filein (%holder (lit filein)))
               (def %buffer (%holder (lit buffer)))
               (def %registry (%reflect-base-cell (lit file-registry)))
               (def %buf (%buf-make (%str-make 65536) %obj-flag-meta))
               ; ids grow monotonically; the head entry carries the highest
               (def %id
                 (match
                   ((eq? (first %registry) ()) 1)
                   (#t (%int+ (%cell-int (first (first (first %registry)))) 1))))
               (%set-first! %registry (pair (pair (%atom %id) path) (first %registry)))
               ; lines from 1, and the file id, for the reader's stamps
               (%reflect-meta-set! %buf 0 1)
               (%reflect-meta-set! %buf 1 %id)
               (%push! %line (%atom 1))
               (%push! %filein (%atom %fd))
               (%push! %buffer %buf)
               (def %result (%module-load-into env))
               (%pop! %filein)
               (%pop! %buffer)
               (%close %fd)
               (%pop! %line)
               %result))
           (fn (_ env path expected)
             (def %io-path (%resolve-include-path path (%include-curdir)))
             (%include-dir-push! (%path-dir %io-path))
             ; The mark is for THIS file, and reading it is the header's first
             ; act, so a file this one loads in turn sets its own: by then a
             ; header here has already read this one, and a file with no
             ; header never will.  An import's name must not reach the files
             ; its file loads -- x/boot/tower-compiled includes x/type/hash by
             ; path.
             (%set-first! %module-expected-cell expected)
             (def %result
               (match
                 ((%module-same? env (%module-root-env)) (%raw-include %io-path))
                 (#t (%load env %io-path))))
             (%set-first! %module-expected-cell ())
             (%include-dir-pop!)
             ; In a base the image writer is loading, each file's garbage is
             ; swept as the file ends.  Nowhere else: a module must not
             ; collect (the note at the end of x/boot/tower-compiled), and
             ; neither may the loader under an importer it cannot see -- a
             ; codec loads its JIT engine lazily with its caller's lists
             ; live.  The writer's child runs nothing but the load, and
             ; %image-writing is true there alone.  docs/state-images.md,
             ; "The child sweeps as it loads".
             (match
               ((guard (_ #f) %image-writing) ((prim-ref (lit heap) (lit collect))))
               (#t ()))
             %result))))
      ; A second argument names the module the file must be headed with,
      ; which is what `import` asks for.  With a path alone, the file is
      ; whatever module its header names, or none.
      (set! include
        (op (path . expected) e
          (%include-into e (eval path e)
            (match ((eq? expected ()) %module-any) (#t (eval (first expected) e))))))))
  (#t ()))

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
    ; push/pop -- is the loader's above, into the including environment.
    (def %io-path (%resolve-include-path (eval path e) (%include-curdir)))
    (match
      ((%include-list-has? %io-path) ())
      (#t
        (do
          (%set-first! %include-list-cell
            (pair %io-path (first %include-list-cell)))
          (%include-into e %io-path %module-any))))))
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

; --- Version files loading right now (x-lang#503) ---
; The next link of the registry chain holds a stack of (NAME . LINE) for
; version files whose bodies are mid-load.  It exists for one allowance:
; a version file may import a STRICTLY LOWER version of its own base name
; -- the object layer's (extends ...) wants the lower class as a value to
; build on.  The stack is how "its own" is known: outside a self-load the
; old contract holds, because loading an older version into a session
; that already handed out the newer one would rebind the exported names
; underneath every caller.  Accessed as (rest %module-loaded-cell), with
; op-local helpers -- boot has no class to home new %-defs in, and the
; percent-globals budget is a ratchet.
(%set-rest! %module-loaded-cell (pair () ()))

; --- Module environments and export owners (x-lang#719) ---
; Two more links on the chain.  A scoped module -- a file whose first form,
; after its comment banner, is (module NAME) -- is evaluated in an
; environment of its own, a child of the root, and this cell keeps
; ((NAME . ENV) ...) so a selective import can read an export from it and a
; reader can walk it.  The owner cell
; keeps ((SYM . NAME) ...): every name `provide` binds in the root has one
; owner, and a second module providing the same name is refused, naming
; both -- the one-owner rule of docs/modules.md.
(%set-rest! (rest %module-loaded-cell) (pair () ()))
(def %module-env-cell (rest (rest %module-loaded-cell)))
(%set-rest! %module-env-cell (pair () ()))
(def %module-owner-cell (rest %module-env-cell))
; The root environment, read through the contract each time rather than
; held in a global: it is the base's, and a global holding it would be one
; more reference for the image writer to explain.
(def %module-root-env
  (fn (_) (%reflect-base-cell (lit env-root))))
; Object identity, never eq?: eq? compares the operand word, and every
; closure carries the same call handler in that word, so eq? is #t for any
; two procedures.  A re-export and an import repeat compare values, which
; are usually closures, so they must ask same?.
(def %module-same? (prim-ref (lit obj) (lit same?)))
; The marker a guarded lookup answers for a name that is not bound: a
; fresh pair, so nothing a lookup could return is the same object.
(def %module-unbound (pair () ()))
(def %module-assoc
  (fn (self k l)
    (match
      ((eq? l ()) ())
      ((eq? (first (first l)) k) (first l))
      (#t (self k (rest l))))))
(def %module-env-of
  ; The environment a module's names live in: its own when scoped, the
  ; root when it was loaded by include.
  (fn (_ name)
    (def %e (%module-assoc name (first %module-env-cell)))
    (match
      ((eq? %e ()) (%module-root-env))
      (#t (rest %e)))))
(def %module-owner-of
  (fn (_ sym)
    (def %o (%module-assoc sym (first %module-owner-cell)))
    (match
      ((eq? %o ()) ())
      (#t (rest %o)))))

; The catalogue doors to the owner table and the module environments, for
; the Module class (x/type/module): it loads after the object system and
; reads the two tables through these, so this file's privates stay its own.
(prim-reg! (lit module) (lit owner) %module-owner-of)
(prim-reg! (lit module) (lit env) %module-env-of)

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
; A definition made in a given environment: (def SYM 'VALUE) evaluated
; there.  The value is quoted so `def` binds the object handed in rather
; than evaluating it a second time -- a symbol value would be looked up.
(def %module-define!
  (fn (_ env sym value)
    (eval (list (lit def) sym (list (lit lit) value)) env)))

; Export one name.  The value is read in the provider's own environment
; `e`: a scoped module's, or the root.  An export is recorded in the
; registry, which is where a selective `import` finds it; the registry entry
; is the module's namespace (docs/modules.md, "Module scope").
;
; Only some exports are also bound in the root.  In an unscoped module every
; definition is there already.  A scoped module binds there a class -- a
; value `class?` answers true for, which exists only once x/type/class has
; loaded -- and a name its provide marks (global NAME): the operatives and
; functions of the sanctioned bare set, tools/contract/bare-globals.x, which
; check-bare-globals holds the marks to.  Any other export of a scoped module
; stays its own and is reached with a selective import.
;
; A name bound in the root has one owner, and one owner per name means one
; definition per name.  A module that lists a name another module owns,
; bound to the very object the owner bound -- x/core re-exporting its
; submodules' predicates, a dialect toolbox listing what it gathers -- is a
; re-export: it binds nothing new, and the owner stays.  A different object
; is a second definition, and refused.  A module providing again is a
; reload and rebinds.
(def %module-export!
  (fn (_ name spec e)
    (def %global (pair? spec))
    (def sym (match (%global (first (rest spec))) (#t spec)))
    (match
      ((match (%global (match ((eq? (first spec) (lit global)) (symbol? sym)) (#t #f))) (#t (symbol? spec))) ())
      (#t (error (%str-append "provide: "
            (%str-append (symbol->str name)
              ": an export is a name or (global name)")))))
    (def %owner (%module-owner-of sym))
    ; The value, or the unbound marker.  An unscoped file may `provide` at
    ; its top, ahead of its definitions -- every lang bundle does -- and
    ; such a provide records the owner and binds nothing: `include` binds
    ; the definitions in the root when it reaches them, as it always has.
    ; A scoped module's provide follows its definitions, because the value
    ; is copied to the root here, so a name it has not defined is an error.
    (def %value (guard (_ %module-unbound) (eval sym e)))
    (match
      ((not (%module-same? %value %module-unbound)) ())
      ((%module-same? e (%module-root-env)) ())
      (#t (error (%str-append "provide: "
            (%str-append (symbol->str name)
              (%str-append " exports "
                (%str-append (symbol->str sym) ", which it does not define")))))))
    ; Whether the name is bound in the root (see above).  `class?` is
    ; unbound until x/type/class loads, and nothing is a class before then.
    (def %root
      (match
        ((%module-same? e (%module-root-env)) #t)
        (%global #t)
        (#t (guard (_ #f) (class? %value)))))
    (match
      ((not %root) ())
      ((eq? %owner ())
        (%set-first! %module-owner-cell
          (pair (pair sym name) (first %module-owner-cell))))
      ((eq? %owner name) ())
      ((%module-same? %value %module-unbound) ())
      ((%module-same? %value (eval sym (%module-root-env))) ())
      (#t (error (%str-append "provide: "
            (%str-append (symbol->str name)
              (%str-append " exports "
                (%str-append (symbol->str sym)
                  (%str-append ", owned by " (symbol->str %owner)))))))))
    ; An unscoped module's defs are already bound in the root by `include`,
    ; so `e` is the root and there is nothing to copy -- provide only
    ; records the owner.  A scoped module's value lives in its own
    ; environment and is copied to the root here when it goes there.
    (match
      ((%module-same? e (%module-root-env)) ())
      ((not %root) ())
      (#t (%module-define! (%module-root-env) sym %value)))))

(def provide
  (op (name . specs) e
    ; The registry records each export by its name, (global NAME) as NAME.
    (%module-register! name
      ((fn (self l)
         (match
           ((eq? l ()) ())
           ((pair? (first l)) (pair (first (rest (first l))) (self (rest l))))
           (#t (pair (first l) (self (rest l))))))
       specs))
    (def %go
      (fn (self l)
        (match
          ((eq? l ()) ())
          (#t (do (%module-export! name (first l) e) (self (rest l)))))))
    (%go specs)
    ()))

; --- The module header (x-lang#719) ---
; What the file now loading may be headed with, for its header to find: the
; name of the module `import` is including, %module-any while a file is
; loaded by path (a path names no module), or nil.  `include` sets it for
; the one file it loads and clears it afterwards, since an unscoped file
; never reads it.
(def %module-expected-cell (pair () ()))
(def %module-any (pair () ()))
; In an amalgam a spliced file is not loaded by `import` or `include-once`
; but read in place from the stream, so the amalgamator writes these two
; forms around a spliced scoped file: the first names the module for its
; header, and the header's reading stops at the second, since the end of
; the spliced text is not the end of the input.  Evaluated anywhere else,
; the second only clears what the first set.
(def %module-expecting!
  (fn (_ name) (%set-first! %module-expected-cell name)))
(def %module-end
  (fn (_) (%set-first! %module-expected-cell ())))
(def %module-load-into
  ; The rest of the input into ENV: every remaining form read and evaluated
  ; there, one at a time, until end of input or an amalgam's (%module-end).
  ; The reader reads one form from the head of the input -- while a file
  ; loads, that file -- stamps it with the file's id and line, and reads it
  ; after the forms before it have run; at end of input it answers the EOF
  ; sentinel, %token-eof, so a () in the file is read as the form it is.
  ; Answers ENV, which is what `include` then returns.  The loader above
  ; reads a whole file this way, and a header the rest of its file.
  (fn (_ env)
    (def %read (prim-ref (lit io) (lit read)))
    (def %go
      (fn (self)
        (def %form (%read))
        (match
          ((%module-same? %form %token-eof) env)
          ((match ((pair? %form) (eq? (first %form) (lit %module-end))) (#t #f)) env)
          (#t (do (eval %form env) (self))))))
    (%go)))

; The form that names a scoped module, and denotes it everywhere else.
;
; As the first form of a file that `import`, `include` or `include-once` is
; loading, after the file's comment banner, it is the header: the rest of
; the file is the module's.  A module not yet loaded gets an environment of
; its own, a child of the root, recorded before any form runs so the module
; can name itself; a module already loaded is joined, the rest of the file
; read into its environment -- so a module may be written in several files,
; its own file including the others, each headed with its name, and a file
; loaded again by path reloads in place.  A file already being read into
; its module, which is what its own file's include makes it, needs nothing
; of the header, and it does nothing.  Under `import` the header must name
; the module being imported: a header naming another is refused, naming
; both, since the file is not the module the import asked for.  Under
; `include` or `include-once` it names the module the file is, which is how
; the boot files, loaded by path, are scoped.
;
; As an expression anywhere else, inside code or at the prompt, it answers
; the named module's environment, so a reader can walk a module's names.  A
; module that is not loaded is an error.
(def module
  (op (name) e
    (def %expected (first %module-expected-cell))
    (def %entry (%module-assoc name (first %module-env-cell)))
    (match
      ((eq? %expected ())
        (match
          ((eq? %entry ()) (error (%str-append "module: not loaded: " (symbol->str name))))
          (#t (rest %entry))))
      ((match ((%module-same? %expected %module-any) #f) ((eq? %expected name) #f) (#t #t))
        (do
          (%set-first! %module-expected-cell ())
          (error (%str-append "import: "
            (%str-append (symbol->str %expected)
              (%str-append " is headed (module "
                (%str-append (symbol->str name) ")")))))))
      ((eq? %entry ())
        (do
          (def %env (pair () (%module-root-env)))
          (%set-first! %module-expected-cell ())
          (%set-first! %module-env-cell
            (pair (pair name %env) (first %module-env-cell)))
          (%module-load-into %env)))
      ((%module-same? e (rest %entry))
        (do (%set-first! %module-expected-cell ()) ()))
      (#t
        (do
          (%set-first! %module-expected-cell ())
          (%module-load-into (rest %entry)))))))

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

; A selective import copies an export into the importer's environment `e`,
; by the export's name or under an alias -- (import NAME sym (sym alias))
; -- so the importer holds the value: a later rebinding of the global does
; not reach it.  Whether `e` already binds the name is read from its own
; frame, (first e), not by a lookup: a lookup walks to the root, where a name
; every module can see is bound to the very object the import is about to
; copy, and the copy would never be made.  The root has no parent, so there
; the lookup is the frame.  One binding per name per environment: a name
; already bound in `e` to the same object (same?, never eq?, which is #t for
; any two closures) is a repeat and does nothing; bound to anything else,
; refused.
(def %module-import-one!
  (fn (_ name spec e)
    (def %sym (match ((pair? spec) (first spec)) (#t spec)))
    (def %alias (match ((pair? spec) (first (rest spec))) (#t spec)))
    (def %value (eval %sym (%module-env-of name)))
    (def %root? (%module-same? e (%module-root-env)))
    (def %own (match (%root? ()) (#t (%module-assoc %alias (first e)))))
    (def %have
      (match
        (%root? (guard (_ %module-unbound) (eval %alias e)))
        ((eq? %own ()) %module-unbound)
        (#t (rest %own))))
    (match
      ((%module-same? %have %module-unbound) (%module-define! e %alias %value))
      ((%module-same? %have %value) ())
      (#t
        (do
          (def %owner (%module-owner-of %alias))
          (error (%str-append "import: "
            (%str-append (symbol->str %alias)
              (%str-append " from "
                (%str-append (symbol->str name)
                  (%str-append " is already bound here"
                    (match
                      ((eq? %owner ()) "")
                      (#t (%str-append " by " (symbol->str %owner)))))))))))))))
(def %module-import-names!
  (fn (_ name syms e)
    (def %names
      ((fn (self l)                                   ; a (sym alias) pair's sym
         (match
           ((eq? l ()) ())
           ((pair? (first l)) (pair (first (first l)) (self (rest l))))
           (#t (pair (first l) (self (rest l))))))
       syms))
    (let ((%entry (%module-find name)))
      (match
        ((eq? %entry ()) ())
        (#t (%module-check-imports name %names (rest %entry)))))
    (def %go
      (fn (self l)
        (match
          ((eq? l ()) ())
          (#t (do (%module-import-one! name (first l) e) (self (rest l)))))))
    (%go syms)))

(def import
  (op (name . syms) e
    (match
      ((%module-loaded? name) ())
      (#t
        (do
          ; register BEFORE loading -- cycle safety, mirrors include-once
          (%module-loaded! name)
          (def %path (%module-resolve name))
          ; A module loads into the root, whoever imports it; its file's
          ; header, if it has one, makes the module's own environment.
          (%include-into (%module-root-env) %path name))))
    (match
      ((eq? syms ()) ())
      (#t (%module-import-names! name syms e)))))

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
  ; O_* value by name out of the platform table, boot-style walk.  The table
  ; is x/platform/syscall's export, imported here, when the walk runs: this
  ; file loads long before that one, and by the time a directory is listed
  ; the import is a lookup, not a load.
  (fn (_ name)
    (import x/platform/syscall file-modes)
    (def %go
      (fn (self lst)
        (match
          ((eq? lst ()) 0)
          ((eq? (first (first lst)) name) (first (rest (first lst))))
          (#t (self (rest lst))))))
    (%go file-modes)))
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
    ; unless O_CREAT is set, and the prim's calling convention stays uniform.  Through
    ; the door, because open is the one call here the generic table has no
    ; number for.
    (def %fd ((syscall-door (lit open)) dir (%module-mode (lit rdonly)) 420))
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
    (def %loading (rest %module-loaded-cell))
    (def %self-loading?
      (fn (self lst)
        (match
          ((eq? lst ()) #f)
          ((eq? (first (first lst)) name) #t)
          (#t (self (rest lst))))))
    (match
      ((eq? %have ())
        (do
          (def %hit (%module-resolve-version (lit import-version-once) name %spec text))
          ; register BEFORE loading -- cycle safety, mirrors import
          (%module-loaded-at! name (first %hit))
          (%set-first! %loading (pair (pair name (first %hit)) (first %loading)))
          (%include-into (%module-root-env) (rest %hit) %module-any)
          (%set-first! %loading (rest (first %loading)))))
      ((eq? %have (lit bare)) (%module-version-conflict! name %have text))
      ((%module-version-ok? %spec %have) ())
      ; a version file may reach DOWN to an earlier version of itself
      ; (#503): resolve, insist on strictly lower than the recorded line,
      ; and load by PATH, once -- the name's record stays on the outer
      ; version, and the lower file's bindings (and provide) are the
      ; higher file's to shadow.
      ((%self-loading? (first %loading))
        (do
          (def %hit (%module-resolve-version (lit import-version-once) name %spec text))
          (match
            ((< (%module-version-cmp (first %hit) %have) 0)
              (match
                ((%include-list-has? (rest %hit)) ())
                (#t
                  (do
                    (%set-first! %include-list-cell
                      (pair (rest %hit) (first %include-list-cell)))
                    (%include-into (%module-root-env) (rest %hit) %module-any)))))
            (#t (%module-version-conflict! name %have text)))))
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
    (def %loading (rest %module-loaded-cell))
    (%module-loaded-at! name (first %hit))
    (%set-first! %loading (pair (pair name (first %hit)) (first %loading)))
    (%include-into (%module-root-env) (rest %hit) %module-any)
    (%set-first! %loading (rest (first %loading)))
    (match
      ((eq? syms ()) ())
      (#t
        (let ((%entry (%module-find name)))
          (match
            ((eq? %entry ()) ())
            (#t (%module-check-imports name syms (rest %entry)))))))))
