; pin.x -- arm a project's overlay import roots from its pin.xon manifest
;
; Tier 2 of the pinning design (GH #115): a project vendors the modules it
; pins into a tree (e.g. deps/) and declares that tree in pin.xon; import
; then resolves pinned names against the overlay before the platform
; library.  The shell wrapper probes for pin.xon (walking up from the
; program's directory; the cwd for a REPL; --no-pin skips) and, when
; found, ANNOUNCES it as data -- (def %pin-file "<abs path>") ahead of
; the boot entry, (import x/tool/pin) after it -- so arming lands
; post-boot, before the first user form.
;
; The manifest is xon -- x object notation: a sequence of x-lang data
; forms read with the ordinary reader and NEVER evaluated.  This module
; interprets a CLOSED vocabulary over those forms; anything else is a
; loud error.  A hostile manifest can therefore only do what pinning
; does: redirect import resolution into its own project's files.
;
; Vocabulary:
;   (root "DIR")   overlay root; a relative DIR resolves against the
;                  manifest's own directory.  First root listed wins.
;   (boot "FILE")  boot entry (a pinned amalgam) -- consumed by the
;                  SHELL WRAPPER, which must choose the entry before
;                  the pipe exists; this loader only checks the shape.
;
; The pre-seeded boot set is unpinnable by construction: boot modules
; are already registered in %module-loaded-cell, so an import of them
; no-ops before any root is consulted.  Pinning the platform itself is
; tier 1 (amalgam pinning), not this file.

; Boot-floor snapshot -- MUST stay this module's first form, before its
; own imports below add to the registry.  At arming time (the wrapper's
; import lands before any user form) this is exactly the boot pre-seed:
; the unpinnable core.  The vendor walk skips these names, which is why
; vendor sessions are run fresh with this module imported FIRST.
(def %pin-floor (first %module-loaded-cell))

(import x/sys/file)
; Eager on purpose, both: sha256 (and posix, which fetch's curl runner
; rides) must resolve PLATFORM-side, before any overlay root is armed
; below -- a lazy import inside verify/fetch could be shadowed by the
; very overlay it is checking (the pin-the-pinner hole, closed the same
; way the wrapper closes it for this module itself).
(import x/sys/posix)
(import x/codec/sha256)

(def %pin-bad
  (fn (_ what) (error (Str8 append "pin: " what))))

; Read manifest text as forms, never evaluating.  Trailing space so the
; tokenizer closes the final token (read-str drops an unterminated tail
; -- the boot-order.x technique).
(def %pin-forms
  (fn (_ text) (Tok read-str (%base) (Str8 append text " "))))

; One (root "DIR") form -> the resolved root string.  %path-join is
; module.x's boot-level path helper (boot-adjacent accessors rule).
(def %pin-root
  (fn (_ form dir)
    (match
      ((not (pair? (rest form))) (%pin-bad "root needs one string argument"))
      ((not (null? (rest (rest form)))) (%pin-bad "root takes exactly one argument"))
      ((not (str? (first (rest form)))) (%pin-bad "root argument must be a string"))
      ((Str8 starts? "/" (first (rest form))) (first (rest form)))
      (#t (%path-join dir (first (rest form)))))))

; One (boot "FILE") form -> () -- wrapper-consumed (GH #139): the entry
; must be chosen before the pipe exists, so by the time this loader
; runs the pinned boot is already the running boot.  Shape-checked here
; so a malformed form stays a loud error under the closed vocabulary.
(def %pin-boot
  (fn (_ form)
    (match
      ((not (pair? (rest form))) (%pin-bad "boot needs one string argument"))
      ((not (null? (rest (rest form)))) (%pin-bad "boot takes exactly one argument"))
      ((not (str? (first (rest form)))) (%pin-bad "boot argument must be a string"))
      (#t ()))))

; One (src "DIR") form -> () -- tool-side, like boot.  It names where the
; PROJECT's own sources live, which is what lets sync and check derive the
; pin from the code that exists rather than a list written in advance: the
; imports ARE the dependency declaration.  Inert at load time; the loader
; arms roots, and a source directory is not a root.
(def %pin-src
  (fn (_ form)
    (match
      ((not (pair? (rest form))) (%pin-bad "src needs one string argument"))
      ((not (null? (rest (rest form)))) (%pin-bad "src takes exactly one argument"))
      ((not (str? (first (rest form)))) (%pin-bad "src argument must be a string"))
      (#t ()))))

; Manifest forms + manifest dir -> resolved roots, manifest order.
; Closed vocabulary: an unknown head is an error, not a skip.
(def %pin-interpret
  (fn (_ forms dir)
    (def %go
      (fn (self forms)
        (match
          ((null? forms) ())
          ((not (pair? (first forms))) (%pin-bad "form is not a list"))
          ((eq? (first (first forms)) 'root)
            (pair (%pin-root (first forms) dir) (self (rest forms))))
          ((eq? (first (first forms)) 'boot)
            (do (%pin-boot (first forms)) (self (rest forms))))
          ((eq? (first (first forms)) 'src)
            (do (%pin-src (first forms)) (self (rest forms))))
          (#t (%pin-bad "unknown form")))))
    (%go forms)))

; --- The manifest as the TOOL reads it -------------------------------
; The loader above turns (root ...) into armed import paths and discards
; the rest; the verbs need the VALUES, so read them back by head.  Path
; arguments resolve against the manifest's directory, exactly as (root
; ...) does, so a manifest means the same thing from any cwd.
(def %pin-manifest-name "pin.xon")

(def %pin-manifest-arg
  (fn (self head forms dir)
    (match
      ((null? forms) ())
      ((not (pair? (first forms))) (self head (rest forms) dir))
      ((not (eq? (first (first forms)) head)) (self head (rest forms) dir))
      ((not (pair? (rest (first forms)))) ())
      ((Str8 starts? "/" (first (rest (first forms)))) (first (rest (first forms))))
      (#t (%path-join dir (first (rest (first forms))))))))

; The same lookup WITHOUT resolution -- the manifest's own spelling.
; What the lock records has to be portable: "maze", not the absolute
; path this particular machine resolved it to.
(def %pin-manifest-raw
  (fn (self head forms)
    (match
      ((null? forms) ())
      ((not (pair? (first forms))) (self head (rest forms)))
      ((not (eq? (first (first forms)) head)) (self head (rest forms)))
      ((not (pair? (rest (first forms)))) ())
      (#t (first (rest (first forms)))))))

(def %pin-manifest-forms
  (fn (_ dir)
    (let ((p (%path-join dir %pin-manifest-name)))
      (match
        ((not (File exists? p)) (%pin-bad (Str8 append "no manifest: " p)))
        (#t (%pin-forms (File slurp p)))))))

; Arm: prepend each root via import-path!, last-listed first, so the
; manifest's FIRST root ends up with the highest precedence.  A missing
; root directory is a broken project -- fail loudly, never silently
; unarmed (File exists? is access(2), so it accepts directories).
(def %pin-arm!
  (fn (self roots)
    (match
      ((null? roots) ())
      (#t
        (do (self (rest roots))
            (match
              ((File exists? (first roots)) ())
              (#t (%pin-bad (Str8 append "root does not exist: " (first roots)))))
            (import-path! (first roots))
            ())))))

; --- Vendoring: the closure walk (GH #115 phase 3) --------------------
; Statically walk a module's source for (import NAME) EVERYWHERE in the
; tree -- including inside deferred fn/op/method bodies: a deferred
; import still needs its module at run time -- skipping only (lit ...)
; quoted data.  ./-relative include-once siblings ride along at the same
; relative offset (their run-time resolution is against the vendored
; file, so the offset is what preserves semantics).  Over-approximation
; is the safe direction: an extra vendored module is inert.  What cannot
; be resolved statically -- a computed include path, an absolute or
; root-relative literal (ratcheted out of runtime modules anyway) -- is
; a loud error, never a silently unvendored dependency.

(def %pin-memq
  (fn (self x lst)
    (match
      ((null? lst) #f)
      ((eq? x (first lst)) #t)
      (#t (self x (rest lst))))))

(def %pin-mem-str?
  (fn (self s lst)
    (match
      ((null? lst) #f)
      ((str=? (first lst) s) #t)
      (#t (self s (rest lst))))))

; --- Overlay-relative path normalisation ------------------------------
; %path-join deliberately does not normalise -- the OS collapses "." and
; ".." when it OPENS a file, which is all module.x needs.  An overlay rel
; is different: it is a lockfile KEY (compared with str=? against paths
; the tree walk builds by descent) and a copy TARGET under dest.  Left
; unnormalised, "acme/../shared.x" and the tree's "shared.x" name the
; same file and never compare equal, and enough ".." segments put the
; copy outside dest entirely.  So collapse here, and refuse a rel that
; climbs past the root -- neither absolute nor root-relative, so the
; guards above miss it, but just as unvendorable.

(def %pin-split-path                   ; "a/b/c" -> ("a" "b" "c")
  (fn (self p)
    (let ((i (Str8 index-of "/" p)))
      (match
        ((null? i) (list p))
        (#t (pair (Str8 sub 0 i p)
                  (self (Str8 sub (+ i 1) (- (Str8 length p) (+ i 1)) p))))))))

; Fold segments onto acc (reversed): "" and "." vanish, ".." pops.  An
; empty acc at a ".." means the path has climbed out of the overlay.
(def %pin-norm-segs
  (fn (self segs acc whole)
    (match
      ((null? segs) acc)
      ((str=? (first segs) "") (self (rest segs) acc whole))
      ((str=? (first segs) ".") (self (rest segs) acc whole))
      ((str=? (first segs) "..")
        (match
          ((null? acc)
            (%pin-bad (Str8 append "include path climbs out of the overlay: " whole)))
          (#t (self (rest segs) (rest acc) whole))))
      (#t (self (rest segs) (pair (first segs) acc) whole)))))

(def %pin-join-slash
  (fn (self segs)
    (match
      ((null? segs) "")
      ((null? (rest segs)) (first segs))
      (#t (Str8 append (first segs) (Str8 append "/" (self (rest segs))))))))

(def %pin-path-norm
  (fn (_ p)
    (%pin-join-slash (%reverse (%pin-norm-segs (%pin-split-path p) () p)))))

(def %pin-include-head?
  (fn (_ h)
    (or (eq? h 'include) (eq? h 'include-once) (eq? h 'require-once))))

; Walk state (reset per closure call; the tool is a single-session
; utility, mirroring boot-order.x's cell style).
(def %pin-visited-cell (pair () ()))  ; module names taken (symbols)
(def %pin-out-cell (pair () ()))      ; (root-relative . source-path), newest first
(def %pin-push!
  (fn (_ cell v) (%set-first! cell (pair v (first cell)))))

; Forward refs: the walk is mutually recursive (module -> file -> form).
(def %pin-take-module ())
(def %pin-take-version ())
(def %pin-walk-file ())

; One form.  dirs = (root-relative-dir . source-dir) of the file being
; scanned, so a ./ sibling lands at the same offset in the overlay.
(def %pin-scan-form
  (fn (self form dirs)
    (match
      ((not (pair? form)) ())
      ((eq? (first form) 'lit) ())
      ((eq? (first form) 'import)
        (match
          ; The argument check must come FIRST: (first (rest form)) on an
          ; argument-less form derefs nil, so reaching for it inside the
          ; guard that rejects it crashes instead of erroring.
          ((not (pair? (rest form))) (%pin-bad "import with no module name in closure"))
          ((symbol? (first (rest form))) (%pin-take-module (first (rest form))))
          (#t (%pin-bad "computed import name in closure"))))
      ((or (eq? (first form) 'import-version) (eq? (first form) 'import-version-once))
        (match
          ((not (pair? (rest form))) (%pin-bad "import-version with no module name in closure"))
          ((not (symbol? (first (rest form)))) (%pin-bad "computed import-version name in closure"))
          ((not (pair? (rest (rest form)))) (%pin-bad "import-version with no version spec in closure"))
          ((not (str? (first (rest (rest form))))) (%pin-bad "computed import-version spec in closure"))
          (#t (%pin-take-version (first form) (first (rest form))
                                 (first (rest (rest form)))))))
      ((%pin-include-head? (first form))
        (match
          ((not (pair? (rest form))) (%pin-bad "include with no path in closure"))
          (#t
            (let ((arg (first (rest form))))
              (match
                ((not (str? arg)) (%pin-bad "computed include path in closure"))
                ((Str8 starts? "./" arg)
                  (%pin-take-rel dirs (Str8 sub 2 (- (Str8 length arg) 2) arg)))
                (#t (%pin-bad (Str8 append "unvendorable include path: " arg))))))))
      (#t (do (self (first form) dirs)
              (self (rest form) dirs))))))

(def %pin-scan-list
  (fn (self forms dirs)
    (match
      ((pair? forms)
        (do (%pin-scan-form (first forms) dirs)
            (self (rest forms) dirs)))
      (#t ()))))

; A ./ sibling: same tail joined under both the overlay offset and the
; source dir; scanned like any file (it may import).
(def %pin-take-rel
  (fn (_ dirs tail)
    ; The overlay rel is normalised (it keys the lockfile and targets the
    ; copy); the SOURCE path keeps its ".." -- it is only ever opened, and
    ; the OS resolves it against the real tree.
    (let ((rel (%pin-path-norm (%path-join (first dirs) tail))))
      (match
        ((%pin-out-has? rel) ())
        (#t
          (do (%pin-push! %pin-out-cell (pair rel (%path-join (rest dirs) tail)))
              (%pin-walk-file rel (%path-join (rest dirs) tail))))))))

(def %pin-out-has?
  (fn (_ rel)
    (def %go
      (fn (self lst)
        (match
          ((null? lst) #f)
          ((str=? (first (first lst)) rel) #t)
          (#t (self (rest lst))))))
    (%go (first %pin-out-cell))))

(set! %pin-take-module
  (fn (_ name)
    (match
      ((%pin-memq name %pin-floor) ())  ; platform floor: inert if vendored
      ((%pin-memq name (first %pin-visited-cell)) ())
      (#t
        ; push BEFORE walking -- cycle safety, mirrors import itself
        (do (%pin-push! %pin-visited-cell name)
            (let ((rel (Str8 append (symbol->str name) ".x")))
              (let ((src (%module-resolve name)))
                (do (%pin-push! %pin-out-cell (pair rel src))
                    (%pin-walk-file rel src)))))))))

; A versioned import: resolve name+spec through the BOOT layer's own
; resolver (one resolver, two consumers -- the same boot-level-accessor
; pattern take-module already uses for %module-resolve), then vendor the
; CHOSEN file at its versioned rel.  Dedup is by rel: each version file is
; its own overlay entry, and a bare (import name) elsewhere in the closure
; vendors the bare file alongside -- coexistence is the point; whether a
; PROJECT mixes versions is the audit's question, not the walk's.
(set! %pin-take-version
  (fn (_ who name spec)
    (let ((hit (%module-resolve-version who name
                 (%module-parse-spec who spec) spec)))
      (let ((rel (%path-join (%path-dir (symbol->str name))
                             (%pin-basename (rest hit)))))
        (match
          ((%pin-out-has? rel) ())
          (#t
            (do (%pin-push! %pin-out-cell (pair rel (rest hit)))
                (%pin-walk-file rel (rest hit)))))))))

(set! %pin-walk-file
  (fn (_ rel src)
    (%pin-scan-list (%pin-forms (File slurp src))
                    (pair (%path-dir rel) (%path-dir src)))))

; Closure of NAME: (root-relative . source) pairs, discovery order.  A
; floor seed is the caller's error to reject; here it just yields ().
(def %pin-closure-of
  (fn (_ name)
    (do (%set-first! %pin-visited-cell ())
        (%set-first! %pin-out-cell ())
        (%pin-take-module name)
        (%reverse (first %pin-out-cell)))))

; mkdir -p: ensure every prefix of dir exists.  EEXIST races are settled
; by the guard; a real failure surfaces at the spit that follows.
(def %pin-mkdirs
  (fn (self dir)
    (match
      ((str=? dir ".") ())
      ((str=? dir "") ())
      ((File exists? dir) ())
      (#t
        (do (self (%path-dir dir))
            (guard (_ ()) (File mkdir dir))
            ())))))

(def %pin-copy!
  (fn (_ dest entry)
    (let ((target (%path-join dest (first entry))))
      (do (%pin-mkdirs (%path-dir target))
          (File spit target (File slurp (rest entry)))
          ()))))

(def %pin-rels
  (fn (_ entries)
    (def %go
      (fn (self lst)
        (match
          ((null? lst) ())
          (#t (pair (first (first lst)) (self (rest lst)))))))
    (%go entries)))

(def %pin-copy-all!
  (fn (self dest lst)
    (match
      ((null? lst) ())
      (#t (do (%pin-copy! dest (first lst))
              (self dest (rest lst)))))))

; --- The lockfile (GH #115 phase 4): the overlay's integrity record ---
; <dest>/pin.lock.xon, generated by vendor; xon like the manifest, with
; a closed vocabulary of (file "REL" "sha256:HEX") forms.  verify
; recomputes every digest AND walks the tree, so a modified file, a
; missing file, or an UNLISTED file (a rogue shadow ready to win root
; precedence) is a loud error -- the overlay must be exactly the lock.
;
; PROVENANCE (GH #147): one overlay legitimately holds several vendors --
; the tutorial's "repeated vendors into one overlay merge cleanly" -- so
; the file list alone cannot say which vendor put a file there.  Without
; that, re-vendoring a seed whose upstream DROPPED a dependency left the
; orphan in the tree AND in the lock, still shadowing the platform, with
; verify calling the pair clean because both had gone stale together.
; So each vendor also records what it claimed:
;   (seed "NAME" "rel" ...)   NAME = a module name, or "project:DIR"
; Re-vendoring a seed replaces that seed's claim; a rel no other seed
; claims leaves the lock and is reported.  Entries predating this record
; are unattributed and kept as-is, so an old overlay keeps verifying.
(def %pin-lock-name "pin.lock.xon")

(def %pin-digest
  (fn (_ path) (Str8 append "sha256:" (Sha256 hex (File slurp path)))))

; The closed vocabulary is (file ...) | (seed ...); each reader takes the
; forms it owns and ignores -- never rejects -- the other's.
(def %pin-lock-parse
  (fn (_ forms)
    (def %go
      (fn (self forms)
        (match
          ((null? forms) ())
          ((not (pair? (first forms))) (%pin-bad "lockfile form is not a list"))
          ((eq? (first (first forms)) 'seed) (self (rest forms)))
          ; The platform half -- (release ...) (isa ...) (boot ...), written
          ; by the boot verb.  Same rule the seed forms already follow: a
          ; reader takes the forms it owns and ignores the other's, so the
          ; vocabulary stays closed without either half rejecting the other.
          ((%pin-member? (first (first forms)) %pin-platform-heads) (self (rest forms)))
          ((not (eq? (first (first forms)) 'file)) (%pin-bad "unknown lockfile form"))
          ((not (str? (first (rest (first forms)))))
            (%pin-bad "lockfile entry needs a path string"))
          ((not (str? (first (rest (rest (first forms))))))
            (%pin-bad "lockfile entry needs a digest string"))
          (#t (pair (pair (first (rest (first forms)))
                          (first (rest (rest (first forms)))))
                    (self (rest forms)))))))
    (%go forms)))

; (seed "NAME" "rel" ...) -> (NAME . (rel ...)) pairs, file order.
(def %pin-lock-parse-seeds
  (fn (_ forms)
    (def %rels
      (fn (self lst)
        (match
          ((null? lst) ())
          ((not (str? (first lst))) (%pin-bad "seed entry needs path strings"))
          (#t (pair (first lst) (self (rest lst)))))))
    (def %go
      (fn (self forms)
        (match
          ((null? forms) ())
          ((not (pair? (first forms))) (%pin-bad "lockfile form is not a list"))
          ((not (eq? (first (first forms)) 'seed)) (self (rest forms)))
          ((not (str? (first (rest (first forms)))))
            (%pin-bad "seed entry needs a name string"))
          (#t (pair (pair (first (rest (first forms)))
                          (%rels (rest (rest (first forms)))))
                    (self (rest forms)))))))
    (%go forms)))

; Final path segment.  Used for the lock's name, and by the boot verb to
; take its amalgam name from the manifest's (boot "boot/he.x") -- so the
; file name is data the project already stated, with no dialect symbol to
; repeat at the call site.
(def %pin-basename
  (fn (_ p)
    (let ((d (%path-dir p)))
      (match
        ((str=? d ".") p)
        (#t (%substring p (+ 1 (%str-length d)) (%str-length p)))))))

; The lock sits BESIDE the overlay root and is NAMED FOR IT -- deps/ is
; locked by deps.lock.xon.  Two reasons, and the second is the one that
; bites: an integrity record kept inside the tree it describes reads as
; part of the payload (vendor writes that tree, verify may condemn it),
; and a fixed name in the parent would make two overlays sharing a parent
; share one lock and silently clobber each other -- which is exactly what
; the spec suite does, vendoring build/pin-spec/prov and .../partial.
(def %pin-lock-path
  (fn (_ dest)
    (%path-join (%path-dir dest)
                (Str8 append (%pin-basename dest) ".lock.xon"))))

(def %pin-lock-forms
  (fn (_ dest)
    (let ((p (%pin-lock-path dest)))
      (match
        ((File exists? p) (%pin-forms (File slurp p)))
        (#t ())))))

; The platform half of the lock -- (release ...) (isa ...) (boot ...),
; written by `boot`.  relock rewrites the whole file from the overlay's
; forms, so these must survive a sync that knows nothing about them.
(def %pin-member?
  (fn (self x lst)
    (match
      ((null? lst) #f)
      ((eq? (first lst) x) #t)
      (#t (self x (rest lst))))))

(def %pin-str->sym (prim-ref (lit str) (lit ->sym)))

(def %pin-platform-heads (list 'release 'isa 'boot))

(def %pin-platform-forms
  (fn (self forms)
    (match
      ((null? forms) ())
      ((not (pair? (first forms))) (self (rest forms)))
      ((%pin-member? (first (first forms)) %pin-platform-heads)
        (pair (first forms) (self (rest forms))))
      (#t (self (rest forms))))))

(def %pin-platform-render
  (fn (self forms)
    (match
      ((null? forms) "")
      (#t (Str8 append (%pin-form-render (first forms))
                       (self (rest forms)))))))

; One (head "a" "b" ...) form back to a line of xon.
(def %pin-form-render
  (fn (_ form)
    (Str8 append "(" (Str8 append (symbol->str (first form))
                                  (Str8 append (%pin-args-render (rest form)) ")\n")))))

(def %pin-args-render
  (fn (self args)
    (match
      ((null? args) "")
      (#t (Str8 append " \"" (Str8 append (first args)
                                          (Str8 append "\"" (self (rest args)))))))))

(def %pin-lock-read
  (fn (_ dest) (%pin-lock-parse (%pin-lock-forms dest))))

(def %pin-lock-read-seeds
  (fn (_ dest) (%pin-lock-parse-seeds (%pin-lock-forms dest))))

(def %pin-lock-render
  (fn (_ entries)
    (def %go
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          (#t (self (rest lst)
                (Str8 append acc
                  (Str8 append "(file \""
                    (Str8 append (first (first lst))
                      (Str8 append "\" \""
                        (Str8 append (rest (first lst)) "\")\n"))))))))))
    ; No header here: both writers emit %pin-lock-header first, so that a
    ; lock carrying platform lines does not end up with its own banner
    ; stranded in the middle of the file.
    (%go entries "")))

(def %pin-lock-header "; pin.lock.xon -- generated; do not edit\n")

(def %pin-seed-render
  (fn (_ seeds)
    (def %rels
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          (#t (self (rest lst)
                (Str8 append acc (Str8 append " \"" (Str8 append (first lst) "\""))))))))
    (def %go
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          (#t (self (rest lst)
                (Str8 append acc
                  (Str8 append "(seed \""
                    (Str8 append (first (first lst))
                      (Str8 append "\""
                        (Str8 append (%rels (rest (first lst)) "") ")\n"))))))))))
    (%go seeds "")))

; Order-preserving upsert of one seed's claim.
(def %pin-seed-put
  (fn (self seeds name rels)
    (match
      ((null? seeds) (pair (pair name rels) ()))
      ((str=? (first (first seeds)) name) (pair (pair name rels) (rest seeds)))
      (#t (pair (first seeds) (self (rest seeds) name rels))))))

(def %pin-append-new                   ; acc ++ (lst minus what acc holds)
  (fn (self acc lst)
    (match
      ((null? lst) acc)
      ((%pin-mem-str? (first lst) acc) (self acc (rest lst)))
      (#t (self (%pin-concat acc (list (first lst))) (rest lst))))))

(def %pin-seed-claims                  ; every rel any seed claims
  (fn (self seeds acc)
    (match
      ((null? seeds) acc)
      (#t (self (rest seeds) (%pin-append-new acc (rest (first seeds))))))))

(def %pin-not-in                       ; rels absent from lst
  (fn (self rels lst)
    (match
      ((null? rels) ())
      ((%pin-mem-str? (first rels) lst) (self (rest rels) lst))
      (#t (pair (first rels) (self (rest rels) lst))))))

; Rewrite the lock with SEED now claiming RELS.  The file list becomes
; every rel still claimed, plus entries no seed ever claimed (written
; before provenance existed -- kept, never silently dropped).  Returns
; the rels that left the lock: files this seed used to pull in and no
; longer does, which now shadow the platform for nothing.
(def %pin-lock-entries                 ; rels -> (rel . digest), digests fresh
  (fn (self dest rels)
    (match
      ((null? rels) ())
      (#t (pair (pair (first rels) (%pin-digest (%path-join dest (first rels))))
                (self dest (rest rels)))))))

(def %pin-lock-relock!
  (fn (_ dest seed rels)
    (let ((old-rels (%pin-rels (%pin-lock-read dest)))
          (was-seeds (%pin-lock-read-seeds dest)))
      (let ((seeds (%pin-seed-put was-seeds seed rels))
            ; Unattributed: in the file list, claimed by no seed -- an
            ; overlay locked before provenance existed.  Keep them.
            (loose (%pin-not-in old-rels (%pin-seed-claims was-seeds ()))))
        (let ((live (%pin-append-new (%pin-seed-claims seeds ()) loose)))
          (do
            ; The platform lines ride through untouched: a sync re-derives
            ; the overlay from source and must not silently unpin the
            ; language underneath it.
            (File spit (%pin-lock-path dest)
              (Str8 append %pin-lock-header
                (Str8 append (%pin-platform-render (%pin-platform-forms (%pin-lock-forms dest)))
                  (Str8 append (%pin-lock-render (%pin-lock-entries dest live))
                               (%pin-seed-render seeds)))))
            (%pin-not-in old-rels live)))))))

; A dropped file is not deleted -- vendor writes into a tree the project
; owns, and removing files there is the user's call.  It is named, and
; verify will flag it as unlisted until it goes.
(def %pin-report-dropped
  (fn (_ dest dropped)
    (match
      ((null? dropped) ())
      (#t (do (display "pin: ")
              (display (%pin-length dropped))
              (display " file(s) no longer in the closure, still in ")
              (display dest)
              (display " (delete them; verify flags them as unlisted):")
              (newline)
              (display (%pin-join-lines dropped))
              ())))))

; Every file under root, as root-relative paths.  list-dir raises on a
; non-directory; the guard's 'file fallback is how a leaf announces
; itself (an empty directory yields the empty list and contributes
; nothing, which is also right).  Module-level mutual recursion (the
; set! forward-ref pattern, as the closure walk above): an inner def
; referenced across a closure boundary dies with its TCO'd frame.
(def %pin-tf-walk ())
(def %pin-tf-each ())
(set! %pin-tf-walk
  (fn (_ path rel acc)
    (def %names (guard (_ 'file) (File list-dir path)))
    (match
      ((eq? %names 'file) (pair rel acc))
      (#t (%pin-tf-each path rel %names acc)))))
(set! %pin-tf-each
  (fn (self path rel lst acc)
    (match
      ((null? lst) acc)
      (#t (self path rel (rest lst)
            (%pin-tf-walk (%path-join path (first lst))
                          (%path-join rel (first lst)) acc))))))
(def %pin-tree-files
  (fn (_ root) (%pin-tf-walk root "" ())))

(def %pin-verify-fails
  (fn (_ dest lock)
    (def %entry-fails
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          ((not (File exists? (%path-join dest (first (first lst)))))
            (self (rest lst) (pair (Str8 append "missing: " (first (first lst))) acc)))
          ((str=? (%pin-digest (%path-join dest (first (first lst)))) (rest (first lst)))
            (self (rest lst) acc))
          (#t (self (rest lst) (pair (Str8 append "modified: " (first (first lst))) acc))))))
    (def %lock-has?
      (fn (self rel lst)
        (match
          ((null? lst) #f)
          ((str=? (first (first lst)) rel) #t)
          (#t (self rel (rest lst))))))
    (def %tree-fails
      (fn (self files acc)
        (match
          ((null? files) acc)
          ((str=? (first files) %pin-lock-name) (self (rest files) acc))
          ((%lock-has? (first files) lock) (self (rest files) acc))
          (#t (self (rest files) (pair (Str8 append "unlisted: " (first files)) acc))))))
    (%tree-fails (%pin-tree-files dest) (%entry-fails lock ()))))

(def %pin-join-lines
  (fn (self lst)
    (match
      ((null? lst) "")
      (#t (Str8 append (first lst) (Str8 append "\n" (self (rest lst))))))))

(def %pin-length
  (fn (self lst)
    (match
      ((null? lst) 0)
      (#t (+ 1 (self (rest lst)))))))

; --- Fetch (GH #115 phase 6): released amalgams, always verified ------
; A release tag's artifacts (release.yml) are plain HTTPS files:
;   <base>/<tag>/pin.release.xon       the manifest (xon)
;   <base>/<tag>/<entry>.x             the amalgams
; fetch downloads via curl when present (fork/execvp/wait -- no shell),
; and otherwise prints the URLs and stops: transport is optional,
; verification is not.  Every downloaded amalgam is digested with
; Sha256 against the manifest before fetch will call it good -- the
; JIT engine when the host proves it (it must agree with the pure-x
; digest before adoption), the pure-x reference otherwise.

; The canonical release home; a trailing optional on fetch overrides it
; (a mirror, or file:// in the smoke).
(def %pin-release-base "https://github.com/jonruttan/x-lang/releases/download")
(def %pin-release-name "pin.release.xon")

(def %pin-url
  (fn (_ base tag file)
    (Str8 append base (Str8 append "/" (Str8 append tag (Str8 append "/" file))))))

; Run argv ("curl" ...) via fork/execvp/wait; 127 = exec never happened
; (the command is absent).  The child must die on exec failure or a
; second interpreter continues this very program.
(def %pin-run!
  (fn (_ argv)
    (let ((pid (Sys fork)))
      (match
        ((= pid 0)
          (do (Sys exec (first argv) (rest argv))
              (Sys exit 127)))
        (#t (Sys wait pid))))))

(def %pin-download!
  (fn (_ url target)
    ; -f: HTTP errors fail the exit status; -L: release downloads
    ; redirect; -sS: quiet but errors still print
    (let ((status (%pin-run! (list "curl" "-fsSL" "-o" target url))))
      (match
        ((= status 0) ())
        ((= status 127)
          (%pin-bad (Str8 append "curl not found -- download manually and re-run against the files:\n  " url)))
        (#t (%pin-bad (Str8 append "download failed: " url)))))))

; pin.release.xon -> ((release . TAG) (isa . DIGEST) (files . ALIST)),
; closed vocabulary: release | isa | (file NAME DIGEST).
(def %pin-release-parse
  (fn (_ forms)
    (def %go
      (fn (self forms tag isa files)
        (match
          ((null? forms)
            (match
              ((null? tag) (%pin-bad "release manifest has no (release ...)"))
              (#t (list (pair 'release tag) (pair 'isa isa) (pair 'files files)))))
          ((not (pair? (first forms))) (%pin-bad "release-manifest form is not a list"))
          ((eq? (first (first forms)) 'release)
            (match
              ((str? (first (rest (first forms))))
                (self (rest forms) (first (rest (first forms))) isa files))
              (#t (%pin-bad "release needs a tag string"))))
          ((eq? (first (first forms)) 'isa)
            (match
              ((str? (first (rest (first forms))))
                (self (rest forms) tag (first (rest (first forms))) files))
              (#t (%pin-bad "isa needs a digest string"))))
          ((eq? (first (first forms)) 'file)
            (match
              ((not (str? (first (rest (first forms)))))
                (%pin-bad "release file needs a name string"))
              ((not (str? (first (rest (rest (first forms))))))
                (%pin-bad "release file needs a digest string"))
              (#t (self (rest forms) tag isa
                    (pair (pair (first (rest (first forms)))
                                (first (rest (rest (first forms)))))
                          files)))))
          (#t (%pin-bad "unknown release-manifest form")))))
    (%go forms () () ())))

(def %pin-release-file
  (fn (self name files)
    (match
      ((null? files) (%pin-bad (Str8 append "not in the release manifest: " name)))
      ((str=? (first (first files)) name) (rest (first files)))
      (#t (self name (rest files))))))

(def %pin-assoc
  (fn (self key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (self key (rest alist))))))

; --- Project-wide vendoring / audit (GH #132, #133) -------------------
; closure/vendor act on ONE module; a project imports many.  These scan a
; project's own *.x sources for every (import NAME) and drive the same
; closure walk over the union -- the tool a retrofit needs in place of a
; grep + one vendor per import (and the gap that makes a silent half-pin
; easy to ship).  Project-local ./ includes are the project's own files,
; not dependencies, so only (import NAME) is followed here.  Run unarmed
; (like vendor) so names resolve to the platform being vendored FROM.

(def %pin-concat                       ; two lists, a ++ b
  (fn (self a b)
    (match
      ((null? a) b)
      (#t (pair (first a) (self (rest a) b))))))

(def %pin-kind                         ; path -> 'file | 'dir | ... (File stat's kind)
  (fn (_ path) (%pin-assoc 'kind (File stat path))))

(def %pin-ends-x?                      ; does name end in ".x"?
  (fn (_ name)
    (let ((n (Str8 length name)))
      (match
        ((< n 2) #f)
        (#t (str=? ".x" (Str8 sub (- n 2) 2 name)))))))

(def %pin-x-files                      ; dir -> every *.x path under dir, recursive
  (fn (self dir)
    (def %go
      (fn (go names)
        (match
          ((null? names) ())
          (#t
            (let ((p (%path-join dir (first names))))
              (%pin-concat
                (match
                  ((eq? (%pin-kind p) 'dir) (self p))
                  ((%pin-ends-x? (first names)) (list p))
                  (#t ()))
                (go (rest names))))))))
    (%go (File list-dir dir))))

; Like %pin-scan-form, but for a project's OWN source: follow (import
; NAME) into the library closure; ignore project-local ./ includes.
(def %pin-scan-project-form
  (fn (self form)
    (match
      ((not (pair? form)) ())
      ((eq? (first form) 'lit) ())
      ((eq? (first form) 'import)
        (match
          ; Same nil-deref guard as %pin-scan-form, and it matters more
          ; here: this walk reads arbitrary project sources, where a
          ; half-typed (import) is an ordinary typo, not a library bug.
          ((not (pair? (rest form))) (%pin-bad "import with no module name in project scan"))
          ((symbol? (first (rest form))) (%pin-take-module (first (rest form))))
          (#t (%pin-bad "computed import name in project scan"))))
      ((or (eq? (first form) 'import-version) (eq? (first form) 'import-version-once))
        (match
          ((not (pair? (rest form))) (%pin-bad "import-version with no module name in project scan"))
          ((not (symbol? (first (rest form)))) (%pin-bad "computed import-version name in project scan"))
          ((not (pair? (rest (rest form)))) (%pin-bad "import-version with no version spec in project scan"))
          ((not (str? (first (rest (rest form))))) (%pin-bad "computed import-version spec in project scan"))
          (#t (%pin-take-version (first form) (first (rest form))
                                 (first (rest (rest form)))))))
      (#t (do (self (first form))
              (self (rest form)))))))

(def %pin-scan-project-list
  (fn (self forms)
    (match
      ((pair? forms)
        (do (%pin-scan-project-form (first forms))
            (self (rest forms))))
      (#t ()))))

(def %pin-scan-project-files
  (fn (self paths)
    (match
      ((null? paths) ())
      (#t (do (%pin-scan-project-list (%pin-forms (File slurp (first paths))))
              (self (rest paths)))))))

; srcdir -> (rel . src) entries: the union closure of every import the
; project's sources reference, discovery order (dedup via the walk's
; visited set).
(def %pin-project-closure
  (fn (_ srcdir)
    (do (%set-first! %pin-visited-cell ())
        (%set-first! %pin-out-cell ())
        (%pin-scan-project-files (%pin-x-files srcdir))
        (%reverse (first %pin-out-cell)))))

; Required rels absent from dest: each such import silently resolves to
; the platform, not the overlay (a half-pin).
(def %pin-audit-missing
  (fn (self dest rels)
    (match
      ((null? rels) ())
      ((File exists? (%path-join dest (first rels))) (self dest (rest rels)))
      (#t (pair (first rels) (self dest (rest rels)))))))

; Vendor a whole source tree's union closure into dest.  Shared by the
; vendor-project method (explicit paths) and by sync (paths from the
; manifest) so both do exactly the same thing -- one mechanism, two doors.
; label is what the lock RECORDS as the seed; srcdir is what gets
; scanned.  They differ for sync, which scans a path resolved against
; the manifest's directory but must record the manifest's own spelling:
; a resolved path can be absolute, and an absolute path in a committed
; lockfile is both meaningless on another machine and a quiet leak of
; wherever the author happened to keep the project.
(def %pin-vendor-project!
  (fn (_ dest srcdir label)
    (let ((entries (%pin-project-closure srcdir)))
      (let ((rels (%pin-rels entries)))
        ; A project whose imports are all boot floor yields an empty
        ; closure, and dest must still exist for the lockfile.  The seed
        ; is the SOURCE DIR, not a module: the claim is "what this
        ; project's sources need", replaced wholesale on each scan.
        (do (%pin-mkdirs dest)
            (%pin-copy-all! dest entries)
            (%pin-report-dropped dest
              (%pin-lock-relock! dest (Str8 append "project:" label) rels))
            rels)))))

; Drop a trailing ".x": the manifest names a FILE, the release names an
; ENTRY, and this is the one place the two spellings meet.
(def %pin-entry-of
  (fn (_ file)
    (%pin-str->sym (%substring file 0 (- (%str-length file) 2)))))

; Replace the lock's platform lines, keeping the overlay's untouched.
; The inverse of the passthrough in relock: `boot` owns these three forms,
; `sync` owns the rest, and neither may clobber the other's half.
(def %pin-lock-set-platform!
  (fn (_ dest forms)
    (let ((old (%pin-lock-forms dest)))
      (File spit (%pin-lock-path dest)
        (Str8 append %pin-lock-header
          (Str8 append (%pin-platform-render forms)
                       (%pin-nonplatform-render old)))))))

(def %pin-nonplatform-render
  (fn (self forms)
    (match
      ((null? forms) "")
      ((not (pair? (first forms))) (self (rest forms)))
      ((%pin-member? (first (first forms)) %pin-platform-heads) (self (rest forms)))
      (#t (Str8 append (%pin-form-render (first forms)) (self (rest forms)))))))

; The default project directory for the verbs: "." unless given.
(def %pin-dir-or-dot
  (fn (_ dir) (match ((null? dir) ".") (#t (first dir)))))

; root/src out of a manifest, with the message a project hits when the
; form it needs is simply not there -- naming the form, not the failure.
(def %pin-need
  (fn (_ head forms dir)
    (let ((v (%pin-manifest-arg head forms dir)))
      (match
        ((null? v) (%pin-bad (Str8 append "manifest has no ("
                                          (Str8 append (symbol->str head)
                                                       " \"...\") form"))))
        (#t v)))))

; Distinct module-name strings out of a closure's entries.
(def %pin-closure-names
  (fn (_ entries)
    (def %go
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          (#t
            (let ((nm (%pin-rel-name (first (first lst)))))
              (match
                ((%pin-name-member? nm acc) (self (rest lst) acc))
                (#t (self (rest lst) (pair nm acc)))))))))
    (%go entries ())))
(def %pin-selected-paths
  (fn (_ entries)
    (def %go
      (fn (self lst acc)
        (match
          ((null? lst) acc)
          (#t (self (rest lst)
                    (pair (%pin-path-norm (rest (first lst))) acc))))))
    (%go entries ())))
(def %pin-unselected
  (fn (_ names selected)
    (def %per-name
      (fn (self names acc)
        (match
          ((null? names) acc)
          (#t
            (self (rest names)
              (%pin-append-new acc
                (%pin-not-in (%pin-name-candidates (first names)) selected)))))))
    (%per-name names ())))

; --- Version observability (GH #214 follow-up) -----------------------
; rel "maze/grid@1.3.1.x" or "maze/grid.x" -> the module name string.
(def %pin-rel-name
  (fn (_ rel)
    (let ((at (Str8 index-of "@" rel)))
      (match
        ((null? at) (Str8 sub 0 (- (Str8 length rel) 2) rel))
        (#t (Str8 sub 0 at rel))))))
(def %pin-name-member?
  (fn (self x lst)
    (match
      ((null? lst) #f)
      ((str=? (first lst) x) #t)
      (#t (self x (rest lst))))))
; Every candidate file for a module name string, across ALL import roots:
; the version files the kernel-direct scan sees, plus the bare file where
; present.  Full normalised paths.
(def %pin-name-candidates
  (fn (_ namestr)
    (let ((reldir (%path-dir namestr))
          (base (%pin-basename namestr)))
      (def %per-root
        (fn (self roots acc)
          (match
            ((null? roots) acc)
            (#t
              (let ((dir (%path-join (first roots) reldir)))
                (self (rest roots)
                  (%pin-append-new acc
                    (%pin-cand-paths dir (%module-scan-dir dir base)))))))))
      (%per-root (first %import-roots-cell) ()))))
(def %pin-cand-paths
  (fn (self dir cands)
    (match
      ((null? cands) ())
      (#t (pair (%pin-path-norm (%path-join dir (rest (first cands))))
                (self dir (rest cands)))))))

(def-class Pin ()
  (static
    (method closure (self (param name SYMBOL "Module name, e.g. x/type/dict"))
    (doc "The module's vendorable import closure: root-relative file paths (the module, its transitive imports, and any ./-relative include siblings), discovery order. Boot-floor modules -- pre-seeded under the running dialect, so inert in an overlay -- are excluded. Loud error on any path the static walk cannot resolve."
      (returns LIST "Root-relative file path strings")
      (sample "(Pin closure 'x/type/dict)" "(\"x/type/dict.x\" ...)"))
    (%pin-rels (%pin-closure-of name)))
    (method vendor (self (param dest STRING "Overlay root directory, e.g. \"deps\"")
                         (param name SYMBOL "Module name to pin"))
    (doc "Copy the module's import closure into dest, preserving the root-relative layout (dest/x/type/dict.x pins x/type/dict). Run from a fresh session with x/tool/pin imported FIRST, so the boot floor is exact. A boot-floor seed is refused: it is unpinnable under this dialect (the pin boundary). Returns the copied paths."
      (returns LIST "Root-relative file path strings copied")
      (sample "(Pin vendor \"deps\" 'x/type/dict)" "(\"x/type/dict.x\" ...)"))
    (match
      ((%pin-memq name %pin-floor)
        (%pin-bad (Str8 append "unpinnable (boot floor): " (symbol->str name))))
      (#t
        (let ((entries (%pin-closure-of name)))
          (let ((rels (%pin-rels entries)))
            ; dest otherwise only ever appears as a side effect of copying
            ; a file into it, so an EMPTY closure left the lockfile spit
            ; writing into a directory that was never created.
            (do (%pin-mkdirs dest)
                (%pin-copy-all! dest entries)
                (%pin-report-dropped dest
                  (%pin-lock-relock! dest (symbol->str name) rels))
                rels))))))
    (method vendor-project (self (param dest STRING "Overlay root directory, e.g. \"deps\"")
                                 (param srcdir STRING "Project source dir to scan, e.g. \"src\""))
    (doc "Vendor a whole project's import closure in one call: scan srcdir's *.x sources for every (import NAME), take the union of their closures, and copy it into dest with the lockfile updated -- the multi-import vendor. Run from a fresh session with x/tool/pin imported FIRST (unarmed), so names resolve to the platform being vendored FROM and the boot floor is exact; boot-floor seeds are skipped. Returns the copied paths."
      (returns LIST "Root-relative file path strings copied")
      (sample "(Pin vendor-project \"deps\" \"src\")" "(\"x/type/dict.x\" ...)"))
    (%pin-vendor-project! dest srcdir srcdir))
    (method verify (self (param dest STRING "Overlay root directory"))
      (doc "Verify dest against its pin.lock.xon: every entry's digest must match, and every file in the tree must be listed -- an unlisted file is a rogue shadow ready to win root precedence. A missing lockfile, missing file, digest mismatch, or unlisted file is a loud error naming each offender. Returns the number of files verified."
        (returns INT "Files verified")
        (sample "(Pin verify \"deps\")" "5"))
      (match
        ((not (File exists? (%pin-lock-path dest)))
          (%pin-bad (Str8 append "no lockfile: " (%pin-lock-path dest))))
        (#t
          (let ((lock (%pin-lock-read dest)))
            (let ((fails (%pin-verify-fails dest lock)))
              (match
                ((null? fails) (%pin-length lock))
                (#t (%pin-bad (Str8 append "verify failed\n" (%pin-join-lines fails))))))))))
    (method audit (self (param dest STRING "Overlay root directory")
                        . (param srcdir STRING "Project source dir to scan; default \".\""))
    (doc "Cross-check an overlay against the project's real imports: scan srcdir's *.x sources for their union import closure and report every required file MISSING from dest. Each missing file is an import that silently falls through to the live platform -- a half-pin. Returns the missing root-relative paths (empty = complete) and prints a notice when non-empty; guard CI with (if (null? (Pin audit ...)) ok (error ...)). Run unarmed, like vendor-project."
      (returns LIST "Missing root-relative file paths (empty = complete pin)")
      (sample "(Pin audit \"deps\" \"src\")" "()"))
    (let ((src (match ((null? srcdir) ".") (#t (first srcdir)))))
      (let ((missing (%pin-audit-missing dest (%pin-rels (%pin-project-closure src)))))
        (do (match
              ((null? missing) ())
              (#t (do (display "pin: audit -- ")
                      (display (%pin-length missing))
                      (display " import(s) fall through to the platform (absent from ")
                      (display dest)
                      (display "):")
                      (newline)
                      (display (%pin-join-lines missing))
                      (newline))))
            missing))))
    ; --- The front door (root/src/boot come from the manifest) --------
    ; sync/check exist because the older pair (vendor-project + audit)
    ; makes the CALLER carry what the manifest already says, and because
    ; hand-vendoring module by module forces a project to declare its
    ; libraries before writing the code that uses them.  It is backwards:
    ; the imports ARE the declaration.  These read pin.xon and work from
    ; the code that exists today, so a project that grows a new import
    ; re-syncs instead of being re-planned.
    (method sync (self . (param dir STRING "Project directory holding pin.xon; default \".\""))
      (doc "Bring the overlay in line with the project's code: read pin.xon, scan its (src ...) tree for every import, and vendor the union closure into its (root ...), rewriting the lockfile. Idempotent, and the whole update after a source file gains an import -- no module list to maintain by hand. Run unarmed (--no-pin), so names resolve to the platform being vendored FROM. Returns the vendored root-relative paths."
        (returns LIST "Root-relative file path strings now pinned")
        (sample "(Pin sync)" "(\"x/type/dict.x\" ...)"))
      (let ((d (%pin-dir-or-dot dir)))
        (let ((forms (%pin-manifest-forms d)))
          (%pin-vendor-project! (%pin-need 'root forms d)
                                (%pin-need 'src forms d)
                                (%pin-manifest-raw 'src forms)))))
    (method check (self . (param dir STRING "Project directory holding pin.xon; default \".\""))
      (doc "The whole integrity question in one call, for CI: the overlay must match its lockfile byte for byte (nothing edited, nothing unlisted), AND no import in the (src ...) tree may fall through to the live platform. A digest mismatch or unlisted file is a loud error; a fallen-through import is reported and returned. Returns the missing root-relative paths -- empty means the pin is complete and intact."
        (returns LIST "Imports absent from the overlay (empty = complete)")
        (sample "(Pin check)" "()"))
      (let ((d (%pin-dir-or-dot dir)))
        (let ((forms (%pin-manifest-forms d)))
          (let ((root (%pin-need 'root forms d))
                (src (%pin-need 'src forms d)))
            ; Verify first: it raises. An audit answer computed against an
            ; overlay whose bytes are already wrong would describe a tree
            ; that does not exist.
            (do (Pin verify root)
                (Pin audit root src))))))
    (method boot (self (param tag STRING "Release tag to pin the language to, e.g. \"v0.3.1-rc6\"")
                       . (param dir STRING "Project directory holding pin.xon; default \".\""))
      (doc "Pin the language itself to a release, in one step: read the manifest's (boot ...) path, fetch and verify that release's amalgam into place, and record the release tag, its ISA fingerprint and the amalgam's digest in the lockfile beside pin.xon. The release manifest is consumed, not kept -- its three facts live in the lock, so nothing generated is left in the boot directory. Returns the amalgam's path."
        (returns STRING "Path of the verified amalgam")
        (sample "(Pin boot \"v0.3.1-rc6\")" "\"boot/he.x\""))
      (let ((d (%pin-dir-or-dot dir)))
        (let ((forms (%pin-manifest-forms d)))
          (let ((bootpath (%pin-need 'boot forms d))
                (root (%pin-need 'root forms d)))
            (let ((bootdir (%path-dir bootpath))
                  (file (%pin-basename (%pin-need 'boot forms d))))
              (do
                (Pin fetch bootdir tag (%pin-entry-of file))
                ; Lift the release's facts into the lock, then remove the
                ; downloaded manifest: two records of the same thing drift.
                (let ((rel (%path-join bootdir %pin-release-name)))
                  (let ((m (%pin-release-parse (%pin-forms (File slurp rel)))))
                    (do
                      (%pin-lock-set-platform! root
                        (list (list 'release tag)
                              (list 'isa (%pin-assoc 'isa m))
                              (list 'boot file (%pin-digest bootpath))))
                      (File unlink rel))))
                bootpath))))))
    (method resolve (self (param name SYMBOL "Module name, e.g. maze/grid")
                          (param spec STRING "Version spec, e.g. \"1.3.*\" or \"^1\""))
      (doc "The file an (import-version-once NAME \"SPEC\") would load, resolved against the CURRENT import roots without loading anything -- the dry run of a versioned import, as closure is of vendor. Run it where your program runs (armed, the overlay answers; unarmed, the platform does). A spec nothing satisfies is the same loud error the import raises."
        (returns STRING "Path of the file the spec selects")
        (sample "(Pin resolve 'maze/grid \"1.3.*\")" "\"maze/grid@1.3.1.x\""))
      (rest (%module-resolve-version (lit resolve) name
              (%module-parse-spec (lit resolve) spec) spec)))
    (method unused (self . (param srcdir STRING "Project source dir to scan; default \".\""))
      (doc "Version files no import in srcdir's sources selects -- the safe-removal list. Provably neutral: resolution takes the newest satisfying candidate per root, so a file this returns cannot change any scanned import's outcome by being removed (had it been able to win for some spec, it would already be selected). The answer is relative to the sources scanned: an external consumer's specs are invisible here. Run unarmed, like audit; prints a notice when non-empty."
        (returns LIST "Full paths of version files nothing scanned selects")
        (sample "(Pin unused \"maze\")" "(\"maze/grid@0.9.x\")"))
      (let ((src (%pin-dir-or-dot srcdir)))
        (let ((entries (%pin-project-closure src)))
          (let ((selected (%pin-selected-paths entries))
                (names (%pin-closure-names entries)))
            (let ((unused (%pin-unselected names selected)))
              (do (match
                    ((null? unused) ())
                    (#t (do (display "pin: unused -- ")
                            (display (%pin-length unused))
                            (display " version file(s) no scanned import selects (safe to remove):")
                            (newline)
                            (display (%pin-join-lines unused))
                            (newline))))
                  unused))))))
    (method fetch (self (param dest STRING "Directory to fetch into")
                        (param tag STRING "Release tag, e.g. \"v0.4.0\"")
                        (param entry SYMBOL "Boot entry to fetch, e.g. 'xe")
                        . (param base STRING "Base URL; default the project's releases"))
      (doc "Fetch a released amalgam, verified or nothing: downloads the tag's pin.release.xon and <entry>.x (curl via fork/execvp -- absent curl prints the URLs and stops), checks the manifest names the tag, digests the amalgam with Sha256 -- the differentially-verified JIT engine where the host supports it (seconds), pure-x elsewhere (minutes for an amalgam; either way announced), and errors on any mismatch, naming the offending file (left in place for inspection; do not boot it). Reports whether the release's ISA fingerprint matches this tree's tools/contract/isa.x when present -- drift is information, not an error: a pinned platform pairs with its own engine. Returns the amalgam's path."
        (returns STRING "Path of the verified amalgam")
        (sample "(Pin fetch \"boot\" \"v0.4.0\" 'xe)" "\"boot/xe.x\""))
      (let ((b (match ((null? base) %pin-release-base) (#t (first base)))))
        (let ((file (Str8 append (symbol->str entry) ".x")))
          (do
            (%pin-mkdirs dest)
            (%pin-download! (%pin-url b tag %pin-release-name)
                            (%path-join dest %pin-release-name))
            (let ((m (%pin-release-parse
                       (%pin-forms (File slurp (%path-join dest %pin-release-name))))))
              (do
                (match
                  ((str=? (%pin-assoc 'release m) tag) ())
                  (#t (%pin-bad (Str8 append "manifest names another release: "
                                            (%pin-assoc 'release m)))))
                (let ((want (%pin-release-file file (%pin-assoc 'files m)))
                      (target (%path-join dest file)))
                  (do
                    (%pin-download! (%pin-url b tag file) target)
                    (display "pin: verifying ")
                    (display target)
                    (display (if (Sha256 jit!)
                                 " (jit sha256)"
                                 " (pure x-lang sha256; an amalgam takes minutes)"))
                    (newline)
                    (match
                      ((str=? (%pin-digest target) want) ())
                      (#t (%pin-bad (Str8 append "digest mismatch: " target))))
                    (match
                      ((File exists? "tools/contract/isa.x")
                        (do (display (match
                                       ; A manifest may carry no (isa ...) at all --
                                       ; %pin-release-parse requires only the tag, so
                                       ; %pin-assoc hands back nil, and str=? on nil
                                       ; would die AFTER the amalgam verified clean.
                                       ; Drift is information, not an error (docstring),
                                       ; and so is an absent fingerprint.
                                       ((null? (%pin-assoc 'isa m))
                                         "pin: the release manifest carries no isa fingerprint -- engine pairing unchecked")
                                       ((str=? (%pin-digest "tools/contract/isa.x") (%pin-assoc 'isa m))
                                         "pin: isa fingerprint matches this tree")
                                       (#t "pin: isa fingerprint DIFFERS from this tree -- pair the amalgam with its release's engine")))
                            (newline)))
                      ; No local ISA manifest -- the reader case: an
                      ; unpacked tarball has no source checkout, so the
                      ; check above cannot run.  SAY so.  Silence here
                      ; reads as "pairing verified" to someone who just
                      ; watched the digest verify, and the pairing is
                      ; precisely what a platform pin is for.  Absent
                      ; information is information, the same ruling the
                      ; absent-fingerprint branch above already makes.
                      (#t
                        (do
                          (display "pin: no isa manifest here -- engine pairing unchecked (run from a source checkout to compare)")
                          (newline))))
                    target))))))))))

; --- Load-time driver: a no-op unless the wrapper announced a manifest.
(def %pin-file-path (guard (_ ()) %pin-file))
(match
  ((null? %pin-file-path) ())
  (#t (%pin-arm!
        (%pin-interpret (%pin-forms (File slurp %pin-file-path))
                        (%path-dir %pin-file-path)))))

(provide x/tool/pin Pin)
