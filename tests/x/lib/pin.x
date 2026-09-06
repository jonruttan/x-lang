; Test harness for the pin specs: x-core, the assert module, and the pin
; tool itself -- which brings File and Proc with it.  One library so the
; specs can be many files: tools/pin.spec.md was one 25-second job, and
; every section after its first two relied on an import a test in those
; two had made.  Imaged like every declared library (make images).
(include "lib/x-core.x")
(import x/test/assert)
(import x/tool/pin)

; THE SHARED FIXTURE TREES, made on demand.  Every pin spec file's first
; case calls this, so a file needs no other file to have run: `lib0` is the
; acme library the closure walk, the lockfile and the vendoring cases read
; -- acme/one imports acme/two (which imports the boot-floor x/core/list),
; pulls a ./-relative sibling (which imports acme/four), and hides an import
; of acme/three inside a deferred fn body -- and `vfix` holds acme/vd in
; three versions for the constraint-import cases.  Idempotent: mkdir is
; guarded, write-all overwrites, and import-path! is a set.
(def %pin-fixture!
  (fn (_)
    (guard (_ ()) (File mkdir "build"))
    (guard (_ ()) (File mkdir "build/pin-spec"))
    (guard (_ ()) (File mkdir "build/pin-spec/lib0"))
    (guard (_ ()) (File mkdir "build/pin-spec/lib0/acme"))
    (File write-all "build/pin-spec/lib0/acme/one.x"
      "(import acme/two)\n(include-once \"./one-extra.x\")\n(def %acme-deferred (fn (_) (import acme/three)))\n(provide acme/one)\n")
    (File write-all "build/pin-spec/lib0/acme/one-extra.x" "(import acme/four)\n")
    (File write-all "build/pin-spec/lib0/acme/two.x"
      "(import x/core/list)\n(provide acme/two)\n")
    (File write-all "build/pin-spec/lib0/acme/three.x" "(provide acme/three)\n")
    (File write-all "build/pin-spec/lib0/acme/four.x" "(provide acme/four)\n")
    (File write-all "build/pin-spec/lib0/acme/bad.x" "(include-once (computed))\n")
    (import-path! "build/pin-spec/lib0")
    (guard (_ ()) (File mkdir "build/pin-spec/vfix"))
    (guard (_ ()) (File mkdir "build/pin-spec/vfix/acme"))
    (File write-all "build/pin-spec/vfix/acme/vd.x" "(provide acme/vd)\n")
    (File write-all "build/pin-spec/vfix/acme/vd@1.3.x" "(provide acme/vd)\n")
    (File write-all "build/pin-spec/vfix/acme/vd@1.3.1.x" "(provide acme/vd)\n")
    (import-path! "build/pin-spec/vfix")
    "ready"))
