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
          (#t (%pin-bad "unknown form")))))
    (%go forms)))

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
          ((symbol? (first (rest form))) (%pin-take-module (first (rest form))))
          (#t (%pin-bad "computed import name in closure"))))
      ((%pin-include-head? (first form))
        (let ((arg (first (rest form))))
          (match
            ((not (str? arg)) (%pin-bad "computed include path in closure"))
            ((Str8 starts? "./" arg)
              (%pin-take-rel dirs (Str8 sub 2 (- (Str8 length arg) 2) arg)))
            (#t (%pin-bad (Str8 append "unvendorable include path: " arg))))))
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
    (let ((rel (%path-join (first dirs) tail)))
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
          (do (%pin-copy-all! dest entries)
              (%pin-rels entries))))))))

; --- Load-time driver: a no-op unless the wrapper announced a manifest.
(def %pin-file-path (guard (_ ()) %pin-file))
(match
  ((null? %pin-file-path) ())
  (#t (%pin-arm!
        (%pin-interpret (%pin-forms (File slurp %pin-file-path))
                        (%path-dir %pin-file-path)))))

(provide x/tool/pin Pin)
