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

; Load-time driver: a no-op unless the wrapper announced a manifest.
(def %pin-file-path (guard (_ ()) %pin-file))
(match
  ((null? %pin-file-path) ())
  (#t (%pin-arm!
        (%pin-interpret (%pin-forms (File slurp %pin-file-path))
                        (%path-dir %pin-file-path)))))

(provide x/tool/pin)
