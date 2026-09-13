; run.x -- the fixture bundle's entry.  See lang.xon.
;
; Empty on purpose.  Everything the gate reads is emitted by the wrapper before
; this file (import-path! and %lang-root, from bundle_form), so an entry that
; does nothing is the right amount: what is under test is the wrapper's
; arrangement, not anything a bundle could do to help it.  The probe -f file
; runs after this and does the looking.
()
